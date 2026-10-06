# pseudofs 架构文档

## 概述

`pseudofs` 是 StarryOS 内核的伪文件系统层，为 procfs、sysfs、devfs、debugfs、cgroup2fs 等合成文件系统提供统一的构建块。所有的伪文件系统共享同一个 `SimpleFs` 超级块机制，通过组合 trait 构建目录和文件节点。

## 核心类型别名

| 别名 | 定义 | 作用 |
|------|------|------|
| `DirMaker` | `Arc<dyn Fn(WeakDirEntry) -> Arc<dyn DirNodeOps> + Send + Sync>` | 延迟构造目录的回调，是目录树构建的核心胶水 |
| `NodeOpsMux` | `enum { Dir(DirMaker), File(Arc<dyn FileNodeOps>) }` | 目录或文件节点的多路复用枚举，作为 `lookup_child` 的返回值 |

`NodeOpsMux` 实现了 `From<DirMaker>` 和 `From<Arc<T: FileNodeOps>>`，允许从 `lookup_child` 直接返回 `DirMaker` 或 `Arc<T>` 而无须显式包装。

## Trait 体系

所有 trait 都是独立的（无继承关系），通过组合模式构建文件系统节点：

```
SimpleFileContent    ──── 文件内容为字节

SimpleFileOps       ──── "读取全量/写入全量" 语义
└─ RwFile<F>            —— 读写组合包装器

DirectRwFsFileOps   ──── "按偏移读写" 语义（实时/大数据文件）
└─ SeqObject             —— 带缓存的顺序读取

SimpleDirOps        ──── 目录操作
└─ DirMapping            —— BTreeMap 驱动的静态目录
└─ ChainedDirOps<A, B>   —— chain() 合并两个目录

DeviceOps           ──── 设备操作
└─ (27 个具体设备实现)

TtyRead / TtyWrite  ──── tty读写
```

每个 trait 对应一个 struct 作为适配器，将该 trait 桥接到 VFS 层的 `NodeOps` / `FileNodeOps` / `DirNodeOps`：

| Trait | 适配器 Struct | 桥接到的 VFS trait |
|-------|--------------|-------------------|
| `SimpleFileOps` | `SimpleFile` | `NodeOps` + `FileNodeOps` + `FsPollable` |
| `DirectRwFsFileOps` | `SpecialFsFile<T>` | `NodeOps` + `FileNodeOps` + `FsPollable` |
| `SimpleDirOps` | `SimpleDir<O>` | `NodeOps` + `DirNodeOps` |
| `DeviceOps` | `Device` | `NodeOps` + `FileNodeOps` + `FsPollable` |

---

## 1. 文件相关 Trait

### 1.1 `SimpleFileContent` (`file.rs:69`)

将内容转换为字节的抽象。

```rust
pub trait SimpleFileContent {
    fn into_content(self) -> Cow<'static, [u8]>;
}
```

### 1.2 `SimpleFileOps` (`file.rs:23`)

**"读取全量/写入全量"** 语义。适用于内容较小的合成文件（procfs/sysfs 的状态报告文件、控制文件等）。

```rust
pub trait SimpleFileOps: Send + Sync + 'static {
    fn read_all(&self) -> VfsResult<Cow<'_, [u8]>>;
    fn write_all(&self, _data: &[u8]) -> VfsResult<()> {
        Err(VfsError::BadFileDescriptor)
    }
}
```

- **自动实现 1**: 任何 `Fn() -> VfsResult<R> + Send + Sync + 'static` 闭包（其中 `R: SimpleFileContent`）自动实现 `SimpleFileOps`。这是最常用的模式：
  ```rust
  SimpleFile::new_regular(fs, move || Ok(format!("{}\n", value)))
  ```

- **自动实现 2**: `RwFile<F>` 包装器，将读/写统一到一个闭包中，适用于需要同时支持读写的控制文件：
  ```rust
  RwFile::new(move |req| match req {
      SimpleFileOperation::Read => Ok(Some(some_data)),
      SimpleFileOperation::Write(data) => { handle_write(data); Ok(None) }
  })
  ```

- **适配器**: `SimpleFile` struct 持有 `Arc<dyn SimpleFileOps>`，实现 `FileNodeOps`（`read_at`/`write_at`/`append`/`set_len`/`set_symlink`）。

**适用场景**: 内容可以完整装入内存的小文件，如 `/proc/version`, `/sys/class/pwm/pwmchip0/npwm`。

### 1.3 `DirectRwFsFileOps` (`file.rs:233`)

**"按偏移读写"** 语义。不缓存内容，每次 `read_at`/`write_at` 直接反映实时数据。适用于数据量可能很大或需要实时反映状态的 procfs/debugfs 文件。

```rust
pub trait DirectRwFsFileOps: Send + Sync + 'static {
    fn read_at(&self, buf: &mut [u8], offset: u64) -> VfsResult<usize>;
    fn write_at(&self, _buf: &[u8], _offset: u64) -> VfsResult<usize> {
        Err(VfsError::InvalidInput)
    }
}
```

- **`SeqObject`**: `DirectRwFsFileOps` 的实现者，内部使用 `Mutex<Option<Vec<u8>>>` 缓存第一次读取的内容，后续读取从缓存返回。适用于内容生成后不变的 seq_file（如 `/proc/filesystems`）。

- **适配器**: `SpecialFsFile<T>` struct 持有 `Arc<T: DirectRwFsFileOps>`，实现 `FileNodeOps`。通过 `SpecialFsFile::new_regular_with_perm(fs, obj, perm)` 创建。

**适用场景**: trace_pipe、dyn_debug controls、cgroup 控制文件、proc 下需要零偏移写入的接口。

### 1.4 选择指南

| 场景 | 使用 |
|------|------|
| 只读小文件（状态/信息） | `SimpleFileOps` = 闭包 `\|\| Ok(format!(...))` |
| 可读写控制文件 | `SimpleFileOps` via `RwFile` |
| 实时数据 / 大数据文件 | `DirectRwFsFileOps`（直接实现或 `SpecialFsFile`） |
| 生成后不变的大文件 | `SeqObject`（包装 `SimpleFileOps`，缓存首次生成结果） |

---

## 2. 目录相关 Trait

### 2.1 `SimpleDirOps` (`dir.rs:21`)

构建合成文件系统目录层次的核心 trait。

```rust
pub trait SimpleDirOps: Send + Sync + 'static {
    fn child_names<'a>(&'a self) -> Box<dyn Iterator<Item = Cow<'a, str>> + 'a>;
    fn lookup_child(&self, name: &str) -> VfsResult<NodeOpsMux>;
    fn is_cacheable(&self) -> bool { true }
    fn chain<N: SimpleDirOps>(self, other: N) -> ChainedDirOps<Self, N>
    where Self: Sized { ChainedDirOps(self, other) }
}
```

- **`child_names()`**: 返回目录中所有条目的名称。对动态目录（如 procfs 进程目录），迭代器从实时状态生成。对静态目录（`DirMapping`），直接从 `BTreeMap` 的 key 迭代。
- **`lookup_child()`**: 按名称查找，返回 `NodeOpsMux::Dir(DirMaker)` 或 `NodeOpsMux::File(Arc<T>)`。
- **`is_cacheable()`**: 目录条目是否可以被 VFS 缓存。动态目录（proc 进程目录、sysfs 设备目录）应返回 `false`。
- **`chain()`**: 组合器模式，将两个目录合并（先查 A，A 上 `NotFound` 再查 B）。

### 2.2 `DirMapping` (`dir.rs:64`)

`SimpleDirOps` 的最常用实现。基于 `BTreeMap<String, NodeOpsMuxTy>` 的静态目录映射。

```rust
pub struct DirMapping {
    map: BTreeMap<String, NodeOpsMuxTy>,
    cacheable: bool,
}
```

关键方法:
- `new()` / `new()` + `set_cacheable(false)` 用于动态目录
- `add(name, ops)` — 添加静态条目
- `add_dynamic(name, maker)` — 添加按需创建的条目（工厂函数在首次访问时才执行）

**适配器**: `SimpleDir<O>` struct 持有 `Arc<O: SimpleDirOps>`，通过 `SimpleDir::new_maker(fs, ops)` 创建 `DirMaker`，后者在实际需要时构造 `Arc<SimpleDir<O>>`。

### 2.3 `ChainedDirOps<A, B>` (`dir.rs:107`)

由 `SimpleDirOps::chain()` 生成。`child_names()` 合并两个迭代器，`lookup_child()` 先查 A 再查 B（仅在 A 返回 `NotFound` 时 fallback）。

典型用法：procfs 的 `ProcFsHandler` 通过 `chain(root)` 将静态根目录与动态进程目录合并为统一的 `/proc` 树。

---

## 3. 设备相关 Trait

### 3.1 `DeviceOps` (`device.rs:56`)

字符设备和块设备的操作接口。

```rust
pub trait DeviceOps: Send + Sync {
    fn read_at(&self, buf: &mut [u8], offset: u64) -> VfsResult<usize>;
    fn write_at(&self, buf: &[u8], offset: u64) -> VfsResult<usize>;
    fn ioctl(&self, _cmd: u32, _arg: usize) -> VfsResult<usize> { Err(VfsError::NotATty) }
    fn as_any(&self) -> &dyn Any;
    fn as_pollable(&self) -> Option<&dyn Pollable> { None }
    fn mmap(&self, _offset: u64, _length: u64) -> DeviceMmap { DeviceMmap::None }
    fn flags(&self) -> NodeFlags { NodeFlags::empty() }
    fn open(&self, _exclusive: bool) -> VfsResult<()> { Ok(()) }
    fn close(&self, _exclusive: bool) {}
}
```

| 方法 | 是否必须实现 | 说明 |
|------|-------------|------|
| `read_at` | 是 | 从指定偏移读数据 |
| `write_at` | 是 | 向指定偏移写数据 |
| `ioctl` | 否 | 设备控制命令，默认 `ENOTTY` |
| `as_any` | 是 | 类型擦除后自身恢复 |
| `as_pollable` | 否 | epoll 支持，默认不支持 |
| `mmap` | 否 | 内存映射，默认不支持 |
| `flags` | 否 | 节点标志（如 `NON_CACHEABLE`） |
| `open` | 否 | 设备打开时的回调 |
| `close` | 否 | 设备关闭时的回调 |

**适配器**: `Device` struct 持有 `Arc<dyn DeviceOps>`，注册到 `/dev` 时指定 `NodeType`（`CharacterDevice` 或 `BlockDevice`）和 `DeviceId`（major, minor）。

### 3.2 典型设备实现模式

参考 `pinmux.rs` 和 `gpio.rs` 的模式：

**文本接口** (`write_at`):
```rust
fn write_at(&self, buf: &[u8], _offset: u64) -> VfsResult<usize> {
    let input = str::from_utf8(buf)?;
    let mut parts = input.split_whitespace();
    // 解析 "ARG1 ARG2 ARG3" 格式
    // ...
    Ok(buf.len())
}
```

**二进制接口** (`ioctl`):
```rust
#[repr(C)]
#[derive(Clone, Copy, AnyBitPattern)]
struct Op {
    field1: u32,
    field2: u32,
}

fn ioctl(&self, cmd: u32, arg: usize) -> VfsResult<usize> {
    match cmd {
        CMD_CONSTANT => {
            let op: Op = (arg as *const Op).vm_read()?;  // 从用户空间读取
            // 处理 op...
            Ok(0)
        }
        _ => Err(AxError::InvalidInput),
    }
}
```

所有 `/dev` 下的设备都实现了 `DeviceOps`（共 27 个），包括：
- 标准设备: `Null`, `Zero`, `Full`, `Random`, `Urandom`
- 块设备: `RootBlk`, `LoopDevice`
- 显示: `FrameBuffer`, `Card0`, `Card1`
- 输入: `EventDev`
- 硬件加速器: `DmaHeap`, `MppService`, `KpuDevice`, `TpuDevice`
- SoC 设备: `GPIODev`, `PinmuxDev`, `CviCamera`, `IonDevice`
- 内存: `MemDev`, `MemTrack`
- 终端: `CurrentTty`, `Ptmx`
- 其他: `Kmsg`, `Rtc`, `CpuDmaLatency`, `UsbDeviceOps`

---

## 4. TTY 层 (`dev/tty/terminal/ldisc.rs`)

### 4.1 `TtyRead`

```rust
pub trait TtyRead: Send + Sync + 'static {
    fn read(&mut self, buf: &mut [u8]) -> usize;
    fn closed(&self) -> bool { false }
}
```

用于行规程从物理串口/PTY 对端读取原始字节。

### 4.2 `TtyWrite`

```rust
pub trait TtyWrite: Send + Sync + 'static {
    fn open(&self) -> AxResult<()> { Ok(()) }
    fn close(&self) {}
    fn write(&self, buf: &[u8]);
    fn try_write(&self, buf: &[u8]) -> usize { self.write(buf); buf.len() }
    fn flush_echo_before_input(&self) -> bool { false }
    fn max_sync_echo_bytes(&self) -> usize { ... }
    fn drain(&self) -> AxResult<()> { Ok(()) }
    fn termios_changed(&self, _old: &Termios2, _new: &Termios2) {}
}
```

用于行规程向物理串口/PTY 对端写入处理后的字节（经过回显、行规程转换等）。

`TtyRead` + `TtyWrite` 的组合被 `LineDiscipline<R, W>` 消费，后者处理规范模式、回显、信号、termios 配置等终端核心逻辑。

具体实现：
- `SerialReader` / `SerialWriter` — 物理串口（`SerialTtyDriver = Tty<SerialReader, SerialWriter>`）
- `PtyReader` / `PtyWriter` — 伪终端（`PtyDriver = Tty<PtyReader, PtyWriter>`）
- `UsbSerialReader` / `UsbSerialWriter` — USB 串口

---

## 5. 文件系统创建流程

### 5.1 devfs 创建示例

```rust
fn builder(fs: Arc<SimpleFs>) -> DirMaker {
    let mut root = DirMapping::new();

    // 注册设备节点
    root.add("null", Device::new(fs.clone(), NodeType::CharacterDevice,
        DeviceId::new(1, 3), Arc::new(Null)));

    // 注册子目录
    root.add("dri", SimpleDir::new_maker(fs.clone(), Arc::new(dri_dir)));

    SimpleDir::new_maker(fs, Arc::new(root))   // 返回 DirMaker
}
```

### 5.2 动态目录示例（procfs 进程目录）

```rust
struct ProcessTaskDir { ... }

impl SimpleDirOps for ProcessTaskDir {
    fn child_names(&self) -> Box<dyn Iterator<Item = Cow<str>> + 'a> {
        // 从实时进程表生成子项名称
        Box::new(active_pids().map(|p| Cow::Owned(format!("{p}"))))
    }

    fn lookup_child(&self, name: &str) -> VfsResult<NodeOpsMux> {
        let pid = name.parse::<u32>()?;
        Ok(NodeOpsMux::Dir(SimpleDir::new_maker(
            self.fs.clone(),
            Arc::new(ThreadDir::new(pid)),
        )))
    }

    fn is_cacheable(&self) -> bool { false }  // 动态目录不可缓存
}
```

### 5.3 控制文件示例（PWM export）

```rust
impl SimpleDirOps for PwmChipDir {
    fn lookup_child(&self, name: &str) -> VfsResult<NodeOpsMux> {
        match name {
            "export" => Ok(pwm_attr_file(self.fs.clone(),
                RwFile::new(move |req| match req {
                    SimpleFileOperation::Read => Ok(Some(Vec::new())),
                    SimpleFileOperation::Write(data) => {
                        let channel = parse_u8(data)?;
                        export_pwm_channel(chip_index, channel)?;
                        Ok(None)
                    }
                }),
            ).into()),
            "npwm" => Ok(SimpleFile::new_regular(self.fs.clone(),
                move || Ok(format!("{count}\n"))
            ).into()),
            _ => Err(VfsError::NotFound),
        }
    }
}
```

### 5.4 PWM 属性文件（SpecialFsFile + RwFile 组合）

`PwmAttrFile` 实现 `DirectRwFsFileOps`，内部持有 `Arc<dyn SimpleFileOps>`（即 `RwFile` 闭包）：
```rust
struct PwmAttrFile { ops: Arc<dyn SimpleFileOps> }

impl DirectRwFsFileOps for PwmAttrFile {
    fn read_at(&self, buf: &mut [u8], offset: u64) -> VfsResult<usize> {
        let data = self.ops.read_all()?;
        // 按 offset 切片返回
    }
    fn write_at(&self, buf: &[u8], offset: u64) -> VfsResult<usize> {
        if offset != 0 { return Err(VfsError::InvalidInput); }
        self.ops.write_all(buf)?;  // sysfs 属性写入替换整个值
        Ok(buf.len())
    }
}
```

这允许 sysfs 属性文件使用 `RwFile` 的便利写法（读/写统一闭包），同时享受 `SpecialFsFile` 的 VFS 适配。

---

## 6. 架构分层

```
┌─────────────────────────────────────────────────────┐
│  VFS 层 (axfs-ng)                                    │
│  NodeOps / FileNodeOps / DirNodeOps / FsPollable     │
├─────────────────────────────────────────────────────┤
│  适配器层                                            │
│  SimpleFile     SpecialFsFile<T>    SimpleDir<O>     │
│  (SimpleFileOps) (DirectRwFsFileOps) (SimpleDirOps)  │
│                                                     │
│  Device                                          │
│  (DeviceOps)                                      │
├─────────────────────────────────────────────────────┤
│  域 Trait 层 （用户实现）                             │
│  SimpleFileOps / DirectRwFsFileOps / SimpleDirOps    │
│  DeviceOps / TtyRead / TtyWrite                     │
├─────────────────────────────────────────────────────┤
│  底层文件系统                                        │
│  SimpleFs (基于 slab 的 inode 分配)                   │
│  MemoryFs (tmpfs)                                    │
│  OverlayFs (读写层/只读层合并)                        │
└─────────────────────────────────────────────────────┘
```

用户只需实现域 trait（`SimpleFileOps`、`SimpleDirOps`、`DeviceOps`），适配器层负责将其桥接到 VFS，无需关心 `NodeOps`/`DirNodeOps`/`FileNodeOps` 的细节。

---

## 7. 关键文件索引

| 文件 | 内容 |
|------|------|
| `mod.rs` | 模块入口，`DirMaker`/`NodeOpsMux` 定义，`mount_all()` 挂载所有伪文件系统 |
| `file.rs` | `SimpleFileContent`, `SimpleFileOps`, `SimpleFileOperation`, `RwFile`, `SimpleFile`, `DirectRwFsFileOps`, `SpecialFsFile`, `SeqObject` |
| `dir.rs` | `SimpleDirOps`, `DirMapping`, `ChainedDirOps`, `SimpleDir` |
| `device.rs` | `DeviceOps`, `Device`, `DeviceMmap` |
| `fs.rs` | `SimpleFs`, `SimpleFsNode` |
| `tmp.rs` | `MemoryFs` — 内存文件系统（tmpfs） |
| `dev/mod.rs` | `/dev` 设备节点注册（`builder` 函数） |
| `dev/tty/terminal/ldisc.rs` | `TtyRead`, `TtyWrite` |
| `proc.rs` | `/proc` 文件系统 |
| `sysfs.rs` | `/sys` 文件系统 |
| `debug.rs` | `/sys/kernel/debug` 入口 |
| `cgroup.rs` | cgroup v2 文件系统 |
| `overlay.rs` | overlay 文件系统 |
