#import "_prelude.typ": *

= 总 结

本项目的总结按四条线给出：应用层视觉推理与运动控制链路、系统层内核优化、实时小核、
以及板级 I/O 与上板工作流。四条线共用同一块板、同一份用户态 ELF 与同一套评测口径，
因此它们的结论可以放在一起读：应用层把端到端帧到指令延迟压到与 Linux 相当，内核层把
每次操作的固定成本从落后一到两个数量级收敛到同一量级，实时小核补上了单核平台无法承诺
的实时性与故障兜底，板级 I/O 则让这些结论能在真机上被反复测出来。

#include "jqj/06_ch6_summary.typ"

#include "kernel_opt/06_ch6_summary.typ"

#include "c906l/06_ch6_summary.typ"

#include "board_io/06_ch6_summary.typ"
