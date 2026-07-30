# 驱动编写
这里说明为 TGOSKits 环境编写驱动的流程. 会以为一个假的块设备编写驱动为例, 总的变更的代码文件如下, 略看一眼即可, 然后再看后续记录:

- OS 无关驱动实现, 可以在裸机上运行:
    - `tgoskits/drivers/blk/fakedisk/`, 新建的目录
    - `tgoskits/drivers/blk/fakedisk/Cargo.toml`, crate 基本信息
    - `tgoskits/drivers/blk/fakedisk/src/lib.rs`, 驱动具体实现
- `ax-driver` OS 粘合层, 把驱动实例放到 `rdrive` 管理的一个表内, OS 拿到这张表就能取出所有的驱动实例:
    - `drivers/ax-driver/src/block/fakedisk.rs`, 注册驱动的实现 (就是把驱动插入表)
    - `drivers/ax-driver/src/block/mod.rs`, 导出 `fakedisk` 的注册函数
    - `drivers/ax-driver/Cargo.toml`, 添加 `fakedisk` feature 便于条件编译
- Runtime 驱动调用, OS 的入口, 在这里实际使用驱动:
    - `os/arceos/modules/axruntime/src/lib.rs`, 增加 `fakedisk` 的实际注册调用
    - `os/arceos/modules/axruntime/Cargo.toml`, 同样增加 `fakedisk` feature 以条件编译
    - `os/StarryOS/kernel/Cargo.toml`, 增加 `fakedisk` 的依赖和 feature
    - `os/StarryOS/configs/board/qemu-riscv64.toml`, 增加 `fakedisk` 的 feature

先想想自己要为哪类硬件编写驱动, 在 `tgoskits/drivers/interface/` 目录下有 `rdif-*` (Rust Driver Interface) 的子目录, 以这里的类别为例子:
- base, 基础 `trait`. 比如 `DriverGeneric` trait 是所有设备驱动 `trait` 的超类, 不代表一个独立的驱动硬件
- def (define), 公共定义. 通用类型和宏 (`KError`, `CpuId`, `IrqId`, `KResult`), 含所有 `rdif crate` 共享的基础定义
- clk (clock), 时钟控制器. 管理 SoC 上各种外设的时钟开/关/降频, 驱动不直接给用户提供接口, 而是用作其他驱动的基础设施
- block, 块设备. 为磁盘, SSD, SD 卡等按固定大小扇区读写的存储设备
- display, 显示设备. GPU, framebuffer, 管理显存和显示模式
- eth (ethernet), 以太网卡. 有线/无线网卡, 管理 MAC 地址, TX/RX 队列, DMA 缓冲区
- input, 输入设备. 键盘, 鼠标, 触摸屏, 手柄等产生输入事件的设备
- intc (Interrupt Controller), 中断控制器. PLIC, GIC 等, 管理硬件中断的使能, 路由, 优先级
- pcie, PCIe 总线. PCIe 控制器, 枚举总线上的设备, 配置 BAR 空间, 是其他 PCIe 驱动的基础设施
- pinctrl (Pin Control), 引脚控制器. 管理 SoC 引脚的复用功能 (GPIO/UART/SPI 等模式切换)
- power, 电源管理. SoC 电源域控制, 休眠唤醒, 基础设施类
- pwm, PWM 控制器. 脉宽调制输出, 用于控制舵机, LED 亮度, 风扇转速等
- serial, 串口/UART. 串行通信接口, 用于调试输出, 终端控制台, 外设通信等
- systick, 系统滴答定时器. 产生固定周期的时钟中断 (如 `10ms`), 给调度器提供时钟
- timer, 通用定时器. 高精度硬件定时器, 用于延时, 超时, 周期性任务
- vsock (Virtual Socket), 虚拟机套接字. VM 和宿主机之间的 socket 通信通道

比如我现在想编写块设备驱动, 就需要定义一个 Rust 类型代表块设备, 然后为其实现一些函数作为驱动的具体操作. 但这并不是说任意编写几个接口函数就好, 而是得实现几个规定好的 `trait`:
- `tgoskits/drivers/interface/rdif-base/src/lib.rs` 中定义的 `DriverGeneric`, 这个是每个驱动类型都必须要实现的
- `tgoskits/drivers/interface/rdif-block/src/interface.rs` 中定义的 `Interface`, 说明了一个块设备具有的行为

另外, block 设备需要借助 IO Queue 来处理请求, 因此还需要定义一个队列, 并且实现下面 `trait`:
- `tgoskits/drivers/interface/rdif-block/src/interface.rs` 中定义的 `IQueue` trait

为块设备编写的驱动,  需要放在 `tgoskits/drivers/blk` 目录下. 假如具体设备型号是 `fakedisk` (假磁盘), 那么就创建 `tgoskits/drivers/blk/fakedisk` 目录:
```sh
tree tgoskits/drivers/blk/fakedisk
.
├── Cargo.toml
└── src
    └── lib.rs
```

## fakedisk Driver Core
这部分是 OS 无关的. 因此编写的代码可以单独测试.

### Cargo.toml
需要在 `Cargo.toml` 中添加 `rdif-block` 的依赖:
```toml
[package]
name = "fakedisk"
version = "0.1.0"
edition.workspace = true

[dependencies]
rdif-block = { workspace = true }
```
- 需要用到 `rdif-block` (Rust Driver Interface, Block) 中定义的 `trait` 和通用类型

### lib.rs 导入的外部内容
`lib.rs` 同样是在 `no_std` 环境下编写, 先导入一些必要的接口:
```rust
#![no_std]
extern crate alloc;

use alloc::boxed::Box;
use rdif_block::{
    BlkError, DeviceInfo, DriverGeneric, IQueue, Interface, QueueInfo, QueueLimits,
    Request, RequestId, RequestOp, RequestStatus, validate_request,
};
```
- `alloc` crate 是构建在 `core` 之上的, 提供堆上分配的能力 (`Box`, `Vec`, `Arc` 等), 且不依赖操作系统. `alloc::boxed::Box` 是堆分配的智能指针
- 核心的 `trait` 有 3 个:
    - `DriverGeneric`, 所有的驱动都必须实现的 `trait`
    - `Interface`, 定义了一个块设备必须暴露的信息, 类型需要先实现 `DriverGeneric`
    - `IQueue`, IO 队列 trait, 负责处理读写请求. 是一个 `unsafe trait`, 因为请求数据需要通过裸指针传递
- 信息描述相关的类型有 3 个:
    - `DeviceInfo`, 包含设备的基本信息, 是 `device_info()` 的返回值类型
    - `QueueLimits`, 描述 IO 队列的参数限制, 是 `queue_limits()` 的返回值类型
    - `QueueInfo`, 队列状态快照, 是 `IQueue::info()` 的返回值类型
- 请求相关的类型有 6 个:
    - `Request`, 表示一次 IO 请求, 用作 `submit_request` 的输入参数
    - `RequestOp`, 请求的操作类型, 在 `match request.op` 时用到
    - `RequestId`, 请求编号, 是 `submit_request` 的返回值, 可以用 `poll_request` 来查询状态
    - `RequestStatus`, 请求完成状态, 是 `poll_request` 的返回值
    - `BlkError`, 块设备错误类型, 所有可能出错的地方都用它
- 一个校验函数 `validate_request`, 对请求做边界检查, LBA 是否越界, 段长度是否匹配对齐块大小, 读写的段是否合法等

下面部分同样在 `lib.rs` 中编写.
### fakedisk 结构体
之后定义代表 `fakedisk` 本身硬件的结构体, 读这个设备时返回 `0`, 写的时候直接丢弃, 因此不需要存储任何实际数据, 用 `block_size` 和 `num_blocks` 两个元数据就能描述 (`block_size x num_blocks` 就是总的字节数):
```rust
const FAKEDISK_NAME: &str = "fakedisk";

pub struct FakeDisk {
    block_size: usize,
    num_blocks: usize,
}

impl FakeDisk {
    pub fn new(block_size: usize, num_blocks: usize) -> Self {
        Self { block_size, num_blocks }
    }
}
```

### `DriverGeneric` trait 实现
`DriverGeneric` trait 的定义如下:
```rust
pub trait DriverGeneric: Send + Any {
    fn name(&self) -> &str; // 该设备驱动的名字

    /// Subtype casting support, returns subtype as `&dyn Any`
    fn raw_any(&self) -> Option<&dyn Any> {
        None
    }
    /// Subtype casting support, returns subtype as `&mut dyn Any`
    fn raw_any_mut(&mut self) -> Option<&mut dyn Any> {
        None
    }
}
``` 
- 要求标记 `Send` trait, 意味着这个驱动能够被多核同时访问
- 实现 `Any`, 意味着类型在包裹在 `Box<dyn xxx>` 中后, 能够通过 `downcast_ref::<T>()` 函数回到原来的类型
- 这里提供了 `raw_any` 和 `raw_any_mut` 的默认实现, 返回 `None`, 如果想使用 `Any` 的能力, 则需要返回 `Some(xxx)`

具体实现 `DriverGeneric` trait 如下:
```rust
impl DriverGeneric for FakeDisk {
    fn name(&self) -> &str { FAKEDISK_NAME }
    fn raw_any(&self) -> Option<&dyn core::any::Any> { Some(self) }
    fn raw_any_mut(&mut self) -> Option<&mut dyn core::any::Any> { Some(self) }
}
```

这里解释下为什么返回 `Some(self)` 可行, 因为 `self` 是 `FakeDisk` 类型, 定义如下:

```rust
pub struct FakeDisk {
    block_size: usize,
    num_blocks: usize,
}
```
两个字段 `block_size` 和 `num_blocks` 都是 `usize` 类型, 天然是 `'static` 生命周期的, 而 `core` 自动为所有的 `'static` 实现了 `Any`, 因此可以返回 `Some(self)`.

### Interface trait
`tgoskits` 中的一个 block driver 需要能够提供这些接口:
```rust
pub trait Interface: DriverGeneric {
    fn device_info(&self) -> DeviceInfo;

    fn queue_limits(&self) -> QueueLimits;

    fn create_queue(&mut self) -> Option<BQueue>;

    fn create_owned_queue(&mut self) -> Option<QueueHandle> {
        None
    }

    fn enable_irq(&self) {}

    fn disable_irq(&self) {}

    fn is_irq_enabled(&self) -> bool {
        false
    }

    fn irq_sources(&self) -> IrqSourceList {
        Vec::new()
    }

    fn take_irq_handler(&mut self, _source_id: usize) -> Option<BIrqHandler> {
        None
    }
}
```
注意只有 `device_info`, `queue_limits`, `create_queue` 是没有默认实现的. 因此简单起见, 这里就只实现这三个.

```rust
impl Interface for FakeDisk {
    fn device_info(&self) -> DeviceInfo {
        DeviceInfo {
            name: Some(FAKEDISK_NAME),
            ..DeviceInfo::new(self.num_blocks as u64, self.block_size)
        }
    }

    fn queue_limits(&self) -> QueueLimits {
        QueueLimits::simple(self.block_size, u64::MAX)
    }

    fn create_queue(&mut self) -> Option<Box<dyn IQueue>> {
        Some(Box::new(FakeQueue {
            id: 0,
            device: self.device_info(),
            limits: self.queue_limits(),
            next_id: 0,
        }))
    }
}
```

这里列一下几个类型的实现 (注意这些类型是从别的 crate 导入的, 不需要写在 `lib.rs` 中):
```rust
#[derive(Debug, Clone, Copy)]
pub struct DeviceInfo {
    pub num_blocks: u64,
    pub logical_block_size: usize,
    pub read_only: bool,
    pub name: Option<&'static str>,
    pub vendor: Option<&'static str>,
    pub model: Option<&'static str>,
}

impl DeviceInfo {
    pub const fn new(num_blocks: u64, logical_block_size: usize) -> Self {
        Self {
            num_blocks,
            logical_block_size,
            read_only: false,
            name: None,
            vendor: None,
            model: None,
        }
    }
}
```
在上面 `device_info()` 的实现中, 相当于只设置了 `name`, `num_blocks` 和 `logical_block_size`, 其他的取默认值.

`QueueLimits` 也只设置了两个字段, 其他的取默认值:
```rust
#[derive(Debug, Clone, Copy)]
pub struct QueueLimits {
    pub dma_mask: u64,
    pub dma_domain: DmaDomainId,
    pub dma_alignment: usize,
    pub max_inflight: usize,
    pub max_blocks_per_request: u32,
    pub max_segments: usize,
    pub max_segment_size: usize,
    pub supported_flags: RequestFlags,
    pub supports_flush: bool,
    pub supports_discard: bool,
    pub supports_write_zeroes: bool,
}

impl QueueLimits {
    pub const fn simple(logical_block_size: usize, dma_mask: u64) -> Self {
        Self {
            dma_mask,
            dma_domain: DmaDomainId::legacy_global(),
            dma_alignment: logical_block_size,
            max_inflight: 1,
            max_blocks_per_request: 1,
            max_segments: 1,
            max_segment_size: logical_block_size,
            supported_flags: RequestFlags::NONE,
            supports_flush: false,
            supports_discard: false,
            supports_write_zeroes: false,
        }
    }
}
```

最后的 `FakeQueue` 在下面章节实现.

### IQueue trait
```rust
pub unsafe trait IQueue: Send + 'static {
    fn id(&self) -> usize;

    fn info(&self) -> QueueInfo;

    fn submit_request(&mut self, request: Request<'_>) -> Result<RequestId, BlkError>;

    fn poll_request(&mut self, request: RequestId) -> Result<RequestStatus, BlkError>;

    /// Poll a set of in-flight requests and report observed terminal results.
    ///
    /// Implementers must report per-request completion or failure through
    /// `sink.complete`. The return value describes the batch query itself:
    /// `Err` means this poll attempt did not reliably observe request states
    /// and must not be interpreted as terminal status for any request that was
    /// not reported to the sink.
    ///
    /// `BlkError::Retry` is submit-side backpressure only. `poll_request` and
    /// `poll_completions` must not return `Retry`; pending requests are
    /// represented by omitting them from the sink in this method.
    fn poll_completions(
        &mut self,
        requests: &[RequestId],
        sink: &mut dyn CompletionSink,
    ) -> Result<(), BlkError> {
        for &request in requests {
            match self.poll_request(request) {
                Ok(RequestStatus::Pending) => {}
                Ok(RequestStatus::Complete) => sink.complete(request, Ok(())),
                Err(err) => sink.complete(request, Err(err)),
            }
        }
        Ok(())
    }
}
```
同样在这里实现没有默认实现的几个函数.

```rust
struct FakeQueue {
    id: usize,
    device: DeviceInfo,
    limits: QueueLimits,
    next_id: usize,
}

unsafe impl IQueue for FakeQueue {
    fn id(&self) -> usize { self.id }

    fn info(&self) -> QueueInfo {
        QueueInfo { id: self.id, device: self.device, limits: self.limits }
    }

    fn submit_request(&mut self, request: Request<'_>) -> Result<RequestId, BlkError> {
        validate_request(self.info(), &request)?;
        let req_id = RequestId::new(self.next_id);
        self.next_id += 1;

        match request.op {
            RequestOp::Read => {
                for seg in request.segments.iter() {
                    unsafe { core::ptr::write_bytes(seg.virt, 0, seg.len); }
                }
            }
            RequestOp::Write | RequestOp::Flush => {}
            _ => return Err(BlkError::NotSupported),
        }
        Ok(req_id)
    }

    fn poll_request(&mut self, _: RequestId) -> Result<RequestStatus, BlkError> {
        Ok(RequestStatus::Complete)
    }
}
```

`QueueInfo` 的实现为 (导入的):
```rust
#[derive(Debug, Clone, Copy)]
pub struct QueueInfo {
    pub id: usize,
    pub device: DeviceInfo,
    pub limits: QueueLimits,
}

```

### 测试
在 `tgoskits/drivers/blk/fakedisk/src/lib.rs` 中继续追加测试逻辑验证上述代码的正确性, 比如:
```rust
#[cfg(test)]
mod tests {
    use super::*;

    // ── Basic device properties ──

    #[test]
    fn device_has_correct_size() {
        let disk = FakeDisk::new(512, 32768);
        let info = disk.device_info();
        assert_eq!(info.num_blocks, 32768);
        assert_eq!(info.logical_block_size, 512);
    }

    #[test]
    fn device_has_correct_name() {
        let disk = FakeDisk::new(512, 1);
        assert_eq!(disk.name(), "fakedisk");
        assert_eq!(disk.device_info().name, Some("fakedisk"));
    }
}
```
(其他逻辑可以自己添加测试, 这里简化)

然后在 `tgoskits/Cargo.toml` 中注册该模块:
```toml
[workspace.dependencies]
fakedisk = { path = "drivers/blk/fakedisk" }
```

之后就能测试:
```sh
cargo test -p fakedisk
```

## OS Glue
OS 需要与很多驱动打交道, 为了方便, 需要把所有驱动集合在一张表里统一管理, 而负责维护这个表的就是 `rdrive`, 其定义在 `tgoskits/drivers/rdrive` 中, 主要负责管理 `BTreeMap<DeviceId, DriverInstance>` 的映射关系, 可以用:
- `register` 来向 `BTreeMap` 插入一个 `DeviceId` 和 `DriverInstance` 的映射
- `get_list`, `get_one` 来查询

OS 会在启动的时候调用 `rdrive::init()` 来初始化这个全局表, 之后可以通过它来注册和查找设备. `rdrive` 查找到设备时, 会将其注册信息放在 `PlatformDevice` 内:
```rust
pub struct PlatformDevice {
    pub descriptor: Descriptor,  // 设备身份证
}

pub struct Descriptor {
    pub(crate) device_id: DeviceId,   // 全局唯一 ID，自增 u64
    pub name: &'static str,           // 设备名称
    pub irq_parent: Option<DeviceId>, // 中断控制器是谁
}

impl PlatformDevice {
    pub fn register<T: DriverGeneric>(self, driver: T) {
        // ...存入 BTreeMap
    }
}
```

通过调用 `PlatformDevice.register(driver)` 来将一个驱动对象放入全局表中.

OS 在 `rdirve` 之上会做额外的封装, 会把一类 driver 包裹在一个类型中, 比如对于 `FakeDisk` 和 `VirtBlk` 的驱动实例, 包裹在 `PlatformBlockDevice` 内:
```rust
pub struct PlatformBlockDevice {
    name: String,
    interface: Option<Box<dyn Interface>>,
    info: BindingInfo,
}

PlatformDevice::new("fakedisk", Some(Box::new(xxx)), xxx);
```
(这里类似伪代码, 实际上并不是这样调用的, 会复杂很多)

这样就能通过 `rdrive` 查询直接得到这类 driver 的所有实例:
```rust
let devs = rdrive::get_list::<PlatformBlockDevice>();
// devs.len() == 2
// devs[0].lock().name()  → "fakedisk"
// devs[1].lock().name()  → "virtio-blk"
```

OS 把 `FakeDisk` 和 `VirtBlk` 包裹在 `PlatformBlockDevice` 的工作是实现在 `ax-driver` 中的, 如果要包裹并注册 `FakeDisk`, 则需要变更下面文件:
- `drivers/ax-driver/src/block/fakedisk.rs`, 定义核心的 `register()` 函数, 用于将 FakeDisk 注册到 `rdrive` 中
- `drivers/ax-driver/src/block/mod.rs`, 添加 `pub mod fakedisk` 声明, 导出该模块内容
- `drivers/ax-driver/Cargo.toml`, 添加 `feature gate` "fakedisk" 和可选的依赖

### 核心 register
`drivers/ax-driver/src/block/fakedisk.rs` 的内容为:

```rust
use crate::block::PlatformDeviceBlock;

/// Called explicitly from axruntime after `fs::init()` to avoid confusing
/// the root-device auto-detection (which needs exactly 1 raw block device).
pub fn register(plat_dev: rdrive::PlatformDevice) {
    let disk = fakedisk::FakeDisk::new(512, 32768); // 16 MiB
    plat_dev.register_block(disk);
    log::info!("registered fakedisk: 32768 blocks x 512 bytes = 16 MiB");
}
```
- `plat_dev` 携带 FakeDisk 的注册信息, 比如 `device_id`, `name` 等
- `disk` 就是一个 FakeDisk 驱动的实例
- `ax-driver` 构建了 `PlatformDeviceBlock` (区分前面的 `PlatformBlockDevice` 类型) trait, 携带 `register_block` 方法. 其为 `PlatformDevice` 实现了这个 `trait`, 用于将 `disk` 包裹在 `PlatformBlockDevice` 中后注册

这个函数的调用后面会说明.

### 导出 FakeDisk 的注册模块
`drivers/ax-driver/src/block/mod.rs` 内添加:
```rust
#[cfg(feature = "fakedisk")]
pub mod fakedisk;
```

### 添加编译选项
在 `drivers/ax-driver/Cargo.toml` 文件中添加:
```rust
[features]
fakedisk = ["block", "dep:fakedisk"]

[dependencies]
fakedisk = { workspace = true, optional = true }
```

## Runtime 集成
Runtime 集成, 其实就是指调用上面的 `register` 函数, 这里涉及 4 个文件:
- `os/arceos/modules/axruntime/src/lib.rs`, 真正调用 `register()` 的地方
- `os/arceos/modules/axruntime/Cargo.toml`
- `os/StarryOS/configs/board/qemu-riscv64.toml`, 声明该开发板依赖于哪些硬件 crate
- `os/StarryOS/kernel/Cargo.toml`, 给 StarryOS 添加 `fakedisk` 模块的依赖 

### 调用 FakeDisk 注册
`os/arceos/modules/axruntime/src/lib.rs` 文件内添加下面内容, 直接在 `rust_main` 内调用注册函数:
```rust
pub fn rust_main(xxx) {
    ...

    #[cfg(feature = "fakedisk")]
    ax_driver::block::fakedisk::register(rdrive::PlatformDevice {
        descriptor: rdrive::Descriptor::new(),
    });

    ...
}
```
- `rdrive::Descriptor::new()` 创建新的实例时, 内部会自动将 `ID` 自增

也就是说, 目前操作系统只不过是调用了 `fakedisk` 的 `register` 函数, 除了注册到 `BTreeMap` 以外, 就只会打印一个日志信息.

### 增加 fakedisk feature
在 `os/arceos/modules/axruntime/Cargo.toml` 文件添加上述代码中要启用的 `feature`:
```toml
[features]
fakedisk = ["ax-driver/fakedisk"]
```

### 板级依赖
`os/StarryOS/configs/board/qemu-riscv64.toml` 的文件内容为:
```toml
features = [
  "ax-feat/display",
  "ax-feat/rtc",
  "ax-driver/serial",
  "ax-driver/fakedisk",
  "ax-driver/virtio-blk",
  "ax-driver/virtio-net",
  "ax-driver/virtio-gpu",
  "ax-driver/virtio-input",
  "ax-driver/virtio-socket",
  "starry-kernel/input",
  "starry-kernel/vsock",
]
log = "Info"
target = "riscv64gc-unknown-none-elf"
```

`axbuild` 会读取这个文件, 将其中的 `features` 传给 `cargo build --features "..."`.

`cargo build` 的 `--features` 选项用于在编译时临时启用当前 crate 的某些 `features`. 基本用法为:
```sh
# 启用单个 feature
cargo build --features json

# 启用多个 feature（用空格或逗号分隔）
cargo build --features "json random"

# 结合 --no-default-features：禁用默认 features，只启用指定的
cargo build --no-default-features --features json
```

### 为 StarryOS 添加依赖
```toml
[dependencies]
ax-driver = { workspace = true, features = ["fakedisk"] }
ax-runtime = { workspace = true, features = ["fakedisk"] }
```

## 测试
```sh
cargo starry qemu
```

启动后能看到:
```
[  0.358340 ax_driver::block::fakedisk:8] registered fakedisk: 32768 blocks x 512 bytes = 16 MiB
```

的日志, 说明注册成功了.


## 暴露给用户态
`os/StarryOS/kernel/src/pseudofs/dev/`  目录下的文件用于将一个设备暴露在文件系统中的 `/dev/` 目录下. 

对于简单设备, 直接内嵌在 `os/StarryOS/kernel/src/pseudofs/dev/mod.rs` 内即可, 比如:
- `struct Null`, 对应 `/dev/null`, 读返回 `EOF`, 写直接丢弃
- `struct Zero`, 对应 `/dev/zero`, 读返回 `0`, 写直接丢弃
- 等

如果是复杂设备, 则放在独立文件中, 比如:
- `loop.rs`, 对应 `/dev/loop0~15`, 块回环设备, 用于 `LOOP_SET_FD` ioctl 绑定文件
- `kpu.rs`, 对应 `/dev/kpu0`, K230 NPU 加速器
- 等

这里 fakedisk 的逻辑很简单, 读返回 `0`, 写直接丢弃, 跟 `Zero` 几乎一样, 因此直接在 `mod.rs` 中加一个结构体, 然后内嵌暴露的逻辑就行.

StarryOS 还是秉持 UNIX 的一切皆文件哲学, 将一个设备也视为文件, 就需要为它实现 VFS 的接口, 这里对应 `tgoskits/os/StarryOS/kernel/src/pseudofs/device.rs` 中定义的 `DeviceOps` trait:

```rust
pub trait DeviceOps: Send + Sync {
    fn read_at(&self, buf: &mut [u8], offset: u64) -> VfsResult<usize>;
    fn write_at(&self, buf: &[u8], offset: u64) -> VfsResult<usize>;
    fn as_any(&self) -> &dyn Any;

    fn ioctl(&self, cmd: u32, arg: usize) -> VfsResult<usize> { ... }
    fn mmap(&self, offset: u64, length: u64) -> DeviceMmap { ... }
    fn open(&self, exclusive: bool) -> VfsResult<()> { ... }
    fn close(&self, exclusive: bool) { }
    fn flags(&self) -> NodeFlags { ... }
}
```

这里只有 `read_at`, `write_at` 和 `as_any` 没有默认实现. `DeviceOps` 是如何起作用的, 这里也先暂时跳过, 只是感受下流程. 了解下如何挂载设备到文件系统中, 因此也不使用前面的 `fakedisk` 驱动, 直接用简单逻辑替代.

在 `os/StarryOS/kernel/src/pseudofs/dev/mod.rs` 文件里加入:
```rust
struct FakeDiskDev;

impl DeviceOps for FakeDiskDev {
    fn read_at(&self, buf: &mut [u8], _offset: u64) -> VfsResult<usize> {
        buf.fill(0);   // fakedisk 读永远返回零
        Ok(buf.len())
    }

    fn write_at(&self, buf: &[u8], _offset: u64) -> VfsResult<usize> {
        Ok(buf.len())  // 写永远成功（空操作）
    }

    fn as_any(&self) -> &dyn Any { self }

    fn flags(&self) -> NodeFlags {
        NodeFlags::NON_CACHEABLE
    }
}
```
如果要用之前的 `fakedisk` 驱动, 其实就是用驱动提供的接口来实现 `read_at` 和 `write_at`.

然后在 `builder()` 函数里面加入:
```rust
root.add(
    "fakedisk0",
    Device::new(
        fs.clone(),
        NodeType::BlockDevice,
        DeviceId::new(253, 0),  // major 253 是 Linux 的 local/experimental 区域
        Arc::new(FakeDiskDev),
    ),
);
```

之后测试就能看到了:
```sh
$ cargo starry qemu
root@starry:/root # ls /dev
bus              loop1            loop5            shm
console          loop10           loop6            tty
cpu_dma_latency  loop11           loop7            ttyS0
dri              loop12           loop8            ttyUSB0
fakedisk0        loop13           loop9            urandom
full             loop14           null             vda
input            loop15           ptmx             zero
kmsg             loop2            pts
log              loop3            random
loop0            loop4            rtc0
```

如果想测试对 `/dev/fakedisk0` 的操作, 还需要在宿主机编写好程序, 编译后嵌入到 `rootfs` 内, 这里暂时不列出.
