    .section .text
    .global _start
_start:
    la sp, _stack_top
    call rust_main
    
    .section .bss.stack
    .global _stack_base
_stack_base:
    .space 4096 * 16 
    .global _stack_top
_stack_top:

