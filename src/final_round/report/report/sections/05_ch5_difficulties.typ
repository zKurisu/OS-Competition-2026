#import "_prelude.typ": *

= 实现难点说明

本章记录"改动之前发生了什么"：每一处优化都是先被数据指出来的，而这些定位过程本身
就是本项目在方法上的主要产出。写成难点而不是流水账，还有一重作用——它解释了方案为什么
长成现在这样，也让后续接手的人不必重复同样的排除工作。按应用层视觉链路、系统层内核、
实时小核、板级 I/O 四条线分别展开；其中被数据否掉的假设与尚未完成的工作也一并列出，
因为"不做什么"与"做什么"同样需要证据。

#include "jqj/05_ch5_difficulties.typ"

#include "kernel_opt/05_ch5_difficulties.typ"

#include "c906l/05_ch5_difficulties.typ"

#include "board_io/05_ch5_difficulties.typ"
