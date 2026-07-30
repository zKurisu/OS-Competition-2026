# dmesg 查看日志

## 问题

原本的 `dmesg` 命令无法查看系统日志，`info!()` 等日志输出不进入 `dmesg` 缓冲区

```
info!() → ax_log → LogIfImpl::console_write_str → ax_hal::console → UART 串口

dmesg   → sys_syslog syscall → SYSLOG_STATE (HeapRb ring buffer) /只有一条初始信息
```

系统启动信息仅在开机时能看到，后续日志可能走其他串口设备输出，运行 shell 的串口没有混杂输出

因此需要桥接 `dmesg`

## 修改

1. axruntime/src/lib.rs

实现注册与调用 logger 的函数

2. syscall/sys.rs

`dmesg` 通过 `sys_syslog` 这个 syscall 读取 日志的 ring buffer，修改前没有代码写入 `SYSLOG_STATE` 这个 ring buffer，于是增加一个其中添加内容的函数

另外需要更换锁

因为 `info!()` 等日志可能在任何时候出现，也可能在原子操作时出现，因此不能使用睡眠锁

睡眠锁获取失败时会导致让出 CPU ，切换任务上下文，但是原子操作的意义就是避免切换上下文，因此在睡眠锁获取时会进行检测

```rust
// ax_sync::Mutex

fn lock(&self) {
    might_sleep();                          // ← 检查：当前是否在原子上下文中？
    let current_id = current().id().as_u64();
    // CAS 获取锁，失败时阻塞当前任务（让出 CPU）
}
```

`might_sleep` 的检查逻辑

```rust
fn might_sleep() {
    if AtomicContextSnapshot::capture().is_atomic() {
        panic!("sleeping not allowed in atomic context");  // ← 直接 panic
    }
}
```

因此使用睡眠锁会导致 panic

使用自旋锁则没有这个问题，因为自旋锁只会 CAS 循环并关抢占，上下文不切换

而且写日志的操作很迅速，只需进行向 ring buffer 中写入字符串，即进行内存复制，速度非常快，因此也不存在性能问题

于是做出修改

```diff
 -static SYSLOG_STATE: spin::LazyLock<Mutex<SyslogState>> =
 -    spin::LazyLock::new(|| Mutex::new(SyslogState::new()));
 +static SYSLOG_STATE: spin::LazyLock<SpinNoPreempt<SyslogState>> =
 +    spin::LazyLock::new(|| SpinNoPreempt::new(SyslogState::new()));
```

3. entry.rs

注册 `log_writer` ，后续日志都会从 `log_writer` 再走一遍

## 补丁

见 [dmesg-patch](../../tree/tgos-patches/dmesg_2026-07-25_1bba09815.md)
