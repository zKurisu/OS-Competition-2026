## 修复 ktracepoint

`os/StarryOS/kernel/src/tracepoint/mod.rs` 中

```rust
fn trace_pipe_push_raw_record(buf: &[u8]) {
        // log::debug!("trace_pipe_push_raw_record: {}", record.len());
        TRACE_STATE.raw_pipe.lock().push_record( // <- lock()
            monotonic_time_nanos(),
            this_cpu_id() as _,
            buf.to_vec(),
        );
        TRACE_STATE.pipe_notify.notify_irq();
    }

    fn trace_cmdline_push(pid: u32) {
        let curr = current();
        let proc_data = &curr.as_thread().proc_data;
        let exe_path = proc_data.exe_path.read();
        let pname = exe_path
            .split(' ')
            .next()
            .unwrap_or("unknown")
            .split('/')
            .next_back()
            .unwrap_or("unknown");
        TRACE_STATE.cmdline_cache.lock().insert(pid, pname); // <- lock
    }
```

两个 lock 使用的是 `Mutex` 锁，该锁是睡眠锁，可能导致上下文切换，因此会做 `might_sleep()` 判断

```rust
#[track_caller]
pub fn might_sleep() {
    let snapshot = AtomicContextSnapshot::capture();
    if snapshot.is_atomic() {
        panic_atomic_sleep(snapshot, core::panic::Location::caller()); // <- panic in atomic context
    }
}
```

以trace_cvi_camera_ioctl 为例，tracepoint 的调用流程是

```
trace_cvi_camera_ioctl()
  → ext_tp.lock()               ← SpinNoPreempt（关抢占，preempt_count++）
    → trace_pipe_push_raw_record()
      → raw_pipe.lock()         ← ax_sync::Mutex（睡眠锁！）
        → lock_plain()
          → might_sleep()
            → is_atomic() 检测 preempt_count != 0
            → panic → 系统挂死
```

然后内核 panic

因此将 tracepoint 中的 `raw_pipe` 和 `cmdline_cache` 改为 `SpinNoPreempt<T>`

## 添加 tracepoint

ktracepoint 库可以很方便地添加 tracepoint

```rust
// 定义一个 trace_cvi_camera_ioctl(cmd, us, ok)
ktracepoint::define_event_trace!(
    cvi_camera_ioctl,
    TP_kops(crate::tracepoint::KernelTraceAux),
    TP_system(camera),
    TP_PROTO(cmd: u32, elapsed_us: u64, ok: bool),
    TP_STRUCT__entry{
        cmd: u32,
        elapsed_us: u64,
        ok: u8,
    },
    TP_fast_assign{
        cmd: cmd,
        elapsed_us: elapsed_us,
        ok: ok as u8,
    },
    TP_ident(__entry),
    TP_printk({
        let name = match __entry.cmd {
            CVI_CAMERA_IOCTL_INIT => "INIT",
            CVI_CAMERA_IOCTL_GET_INFO => "GET_INFO",
            CVI_CAMERA_IOCTL_GET_FRAME => "GET_FRAME",
            CVI_CAMERA_IOCTL_GET_YUV_FRAME => "GET_YUV_FRAME",
            CVI_CAMERA_IOCTL_HARD_RESET => "HARD_RESET",
            _ => "?",
        };
        alloc::format!(
            "{} (cmd={}) elapsed={}us ok={}",
            name, __entry.cmd, __entry.elapsed_us, __entry.ok != 0
        )
    })
);
```
在 `os/StarryOS/kernel/src/pseudofs/dev/cvi_usb_camera.rs` 的 `ioctl` 的最后添加

```rust
...
trace_cvi_camera_ioctl(cmd, elapsed_us, result.is_ok());
...
```

以显示调用时使用的命令，耗时和是否成功

## 使用

ktracepoint 挂载了一个虚拟文件系统，在 tgoskits 中是 `/sys/kernel/debug/tracing`

向相应的 tracer 目录下的 `enable` 文件写入 1 表示开启 trace
向相应的 tracer 目录下的 `enable` 文件写入 0 表示关闭 trace

```bash
echo 1 > /sys/kernel/debug/tracing/events/camera/cvi_camera_ioctl/enable
```

然后可以通过读取 `/sys/kernel/debug/tracing/trace` 文件得到 tracer 打印的日志

```bash
cat /sys/kernel/debug/tracing/trace
# tracer: nop
#
# entries-in-buffer/entries-written: 123/123   #P:32
#
#
#                                _-----=> irqs-off/BH-disabled
#                               / _----=> need-resched
#                              | / _---=> hardirq/softirq
#                              || / _--=> preempt-depth
#                              ||| / _-=> migrate-disable
#                              |||| /     delay
#           TASK-PID     CPU#  |||||  TIMESTAMP  FUNCTION
#              | |         |   |||||     |         |
```

## 补丁

[ktracepoint_patch](./patch/ktracepoint-fix_2026-07-26_1bba09815.md)
