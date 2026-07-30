# strace 功能修复

## 问题原因

1. syscall/task/ptrace.rs

strace 使用系统调用

```c
ptrace(PTRACE_SEIZE, pid, 0, PTRACE_O_TRACESYSGOOD | PTRACE_O_TRACEEXEC)
```

在 starryos 中，传入 `sys_ptrace` 的 `data` 参数包含选项，也就是 `PTRACE_O_TRACESYSGOOD | PTRACE_O_TRACEEXEC`

但是 `ptrace` 的实现有问题

```rust
PTRACE_SEIZE => ptrace_seize(pid, addr) // 这里传入了 addr
```
应该修改为

```rust
PTRACE_SEIZE => ptrace_seize(pid, data)
```
由于 `PTRACE_O_TRACESYSGOOD` 从来没有被设置，tracee 的系统调用停止信号是原始 `SIGTRAP(5)` 而不是 `SIGTRAP` | `0x80(0x85)`。`strace` 收到后把系统调用停止错误归类为信号投递停止（而非系统调用停止），所以：

- 它注入 `SIGTRAP` 回 tracee（而不是调用 `get_scno()` 读寄存器）
- 它永远不进入 `trace_syscall()` 路径
- 没有系统调用输出

2. task/signal.rs: `wait_ptrace_resume(...)`

原代码在被 `task.interrupt()` 打断时调用 `clear_ptrace_stop()` 清空 `exec-stop` 记录，导致 tracer 永远收不到 `SIGTRAP`。退出和 `SIGKILL` 路径已通过独立机制唤醒，不需要 `interruptible`。

```rust
if wait_result.is_err() {
    clear_ptrace_stop() // 清除了记录
}
```

3. task/signal.rs: `check_signals(...)`

tracer 注入相同信号（如 `PTRACE_SYSCALL(data=SIGSTOP)`）后，原代码继续执行 `do_job_stop`，把 tracee 卡在 job-control stop，而 tracer 的 `waitpid(WALL)` 检测不到（需要 `WUNTRACED`），形成死锁。修复后信号被标记为已消费。


3. task/user.rs

`new_user_task(...)` 中检查顺序有误

```diff
- syscall exit trace 检查
- exec-stop 检查
+ exec-stop 检查            // 先检查
+ syscall exit trace 检查   // 后检查
```
符合 Linux 语义：exec-stop 应当替代（supersede）syscall exit stop，而非在其之后发生。

## 补丁

见 [strace-fix-patch](./patch/strace-fix_2026-07-24_1bba09815.md)
