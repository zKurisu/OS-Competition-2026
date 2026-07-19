# 交叉编译 SG2002 (RISC-V 64) GPIO 测试程序
#
# 使用方法:
#   make                     # 交叉编译
#   make CROSS_COMPILE=xxx   # 指定交叉编译器前缀
#   make clean               # 清理

CROSS_COMPILE ?= riscv64-linux-musl-
CC            = $(CROSS_COMPILE)gcc
CFLAGS        = -Wall -Wextra -O2 -static
LDFLAGS       = -static

TARGET = gpio_mmap

.PHONY: all clean

all: $(TARGET)

$(TARGET): gpio_mmap.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)
	@echo "✓ 编译完成: $(TARGET)"
	@file $(TARGET)

clean:
	rm -f $(TARGET)
