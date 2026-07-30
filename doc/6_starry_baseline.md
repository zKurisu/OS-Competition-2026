# Starry_baseline用户态程序技术报告
> SG2002 RISC-V 嵌入式平台 | 2026 年 7 月

---

## 摘要

该用户态程序运行在 Sophgo SG2002 (CV181x) RISC-V SoC 上， 主要功能是自主网球收集。通过 USB 摄像头和 TPU 神经网络实现网球的实时检测与定位，控制双轮差速底盘和 3 自由度舵机臂完成自主导航、接近和抓取任务。

本文档记录了从原始版本到当前优化版本的全部技术改进，涵盖摄像头采集管道重构、机器人行为模型重设计、机械臂抓取序列校准、Web 远程监控系统搭建、以及多个辅助测试工具的开发。核心成果是将系统帧率从 **0.3 FPS 提升至 3–5 FPS**（约 15 倍），并实现完整的自主抓取闭环。

---

## 目录

1. [系统架构](#1-系统架构)
2. [摄像头采集管道优化](#2-摄像头采集管道优化)
3. [图像预处理优化](#3-图像预处理优化)
4. [机器人行为模型](#4-机器人行为模型)
5. [机械臂抓取序列](#5-机械臂抓取序列)
6. [Web 远程监控系统](#6-web-远程监控系统)
7. [调试与可观测性](#7-调试与可观测性)
8. [配置参数参考](#8-配置参数参考)
9. [工具程序](#9-工具程序)
10. [性能基准](#10-性能基准)
11. [鲁棒性增强](#11-鲁棒性增强)
12. [文件变更清单](#12-文件变更清单)

---

## 1. 系统架构

### 1.1 硬件平台

| 组件 | 型号/接口 | 说明 |
|------|----------|------|
| 主控 | SG2002 (CV181x) | RISC-V C906 核心，集成 TPU |
| 摄像头 | USB UVC MJPEG | 640×480，通过 `/dev/cvi-usb-camera0` 访问 |
| 底盘 | ESP32 双轮差速 | UART `/dev/ttyS1`，二进制帧协议 |
| 机械臂 | ZP10S 3 舵机 | UART `/dev/ttyS2`，文本指令协议 |
| 舵机 0 | 底座旋转 | 度数减小→上抬，度数增大→下摆 |
| 舵机 1 | 肩部升降 | 度数增大→上抬，度数减小→下压 |
| 舵机 2 | 夹爪开合 | 度数增大→张开，度数减小→夹紧 |

### 1.2 软件栈

```
┌─────────────────────────────────────────┐
│  main.rs  — CLI (hunt / serve / detect) │
├─────────────────────────────────────────┤
│  robot.rs — 自主行为状态机              │
├──────────────┬──────────────────────────┤
│  camera.rs   │  arm.rs  — 舵机控制器     │
│  (USB UVC)   │  motor.rs — 电机控制器    │
├──────────────┤  serial.rs — 串口抽象    │
│  tpu.rs      │  linux.rs — 内核 FFI     │
│  (TPU 推理)  │  pinmux.rs — 引脚复用    │
├──────────────┤                          │
│  detector.rs │                          │
│  (YOLO 后处理)│                         │
├──────────────┤                          │
│  image_bridge.rs                        │
│  (YUV→RGB 预处理)                       │
├─────────────────────────────────────────┤
│  web.rs  — Axum HTTP 控制面板           │
└─────────────────────────────────────────┘
```

### 1.3 数据管道

```
USB 摄像头 (MJPEG)
    │
    ▼  内核 JPU 硬件解码
YUV422 planar (640×480, 614KB)
    │
    ▼  yuv422p_to_rgb_planar()
RGB planar tensor (640×640×3)
    │
    ▼  CVI_NN_Forward()
YOLOv8 检测框 (8400 proposals)
    │
    ▼  parse + NMS + correct_boxes
Vec<Detection> → handle_detections()
    │
    ▼  状态机决策
电机/舵机串口指令
```

---

## 2. 摄像头采集管道优化

### 2.1 问题诊断

原始版本每帧 `camera capture` 耗时约 **2845ms**，占总帧时间的 92%。通过新增的 `diagnose_timing()` 诊断函数，在启动时分别测试两种采集模式：

```
cmd3 (raw MJPEG):  33.7 ms  ← 帧等待 + USB 传输
cmd4 (YUV via JPU): 56.1 ms  ← 帧等待 + USB 传输 + JPU 硬件解码
JPU decode overhead: 22.4 ms
```

诊断结果表明传感器和 JPU 硬件本身的性能是健康的（~56ms/帧），瓶颈在采集管道的外部控制逻辑。

### 2.2 根因分析

通过阅读 StarryOS 内核驱动源码 (`cvi_usb_camera.rs`)，确定了根因：

1. UVC 摄像头使用同步传输 + FID（Frame ID）状态机进行帧同步
2. 摄像头启动后需要 AE/AWB 自动收敛（~3 秒），期间产生大量不完整帧（JPEG SOI 有但 EOI 缺失）
3. 不完整帧被状态机检测并丢弃，触发 `WaitFirstSwitch` 重置
4. 原始版本的 `get_frame()` 每次捕获后调用 `INIT` ioctl 重新初始化管道
5. 下次 `GET_FRAME` 时管道已空闲，触发 AE/AWB 重新收敛 → 每帧都等 ~3 秒

### 2.3 解决方案

将 `INIT` ioctl 从 `get_frame()` 末尾移到开头：

```rust
// 旧：捕获后 INIT（管道空闲 → 下次需要重新收敛）
get_frame() → ioctl(GET_FRAME) → ioctl(INIT) → return
//                                        ↑ 这里断开管道

// 新：INIT 紧接 GET_FRAME（管道持续活跃）
get_frame() → ioctl(INIT) → ioctl(GET_FRAME) → return
//            ↑ 零间隙
```

### 2.4 效果

| 指标 | 旧 | 新 | 改善 |
|------|----|----|------|
| camera capture | ~2845ms | ~60ms | **47×** |
| 每帧总时间 | ~3100ms | ~190ms | **16×** |
| FPS | 0.32 | 3–5 | **10–15×** |

### 2.5 数据管道升级

原始版本使用 cmd3（原始 MJPEG），用户态进行 JPEG 解码。当前版本升级为 cmd4（内核 JPU 硬件解码为 YUV422），消除了用户态 JPEG 解码开销：

| 项目 | 旧版 | 新版 |
|------|------|------|
| ioctl 命令 | cmd3 | cmd4 |
| 输出格式 | JPEG 字节 | YUV422 planar |
| 缓冲大小 | 2MB/帧 | 614KB/帧 |
| JPEG 解码 | 用户态软件 | 内核 JPU 硬件 |
| 错误恢复 | 无 | 3 级（re_init / reopen / hard_reset） |
| 帧缓冲 | per-frame 分配 | 预分配复用 |

---

## 3. 图像预处理优化

### 3.1 处理管道简化

**旧版管道**：
```
MJPEG → zune-jpeg 软件解码 (或 DC 快速路径)
      → 双线性缩放
      → RGB planar packing
      → 写入 TPU tensor
```

**新版管道**：
```
YUV422 → BT.601 逐像素转换 + 最近邻缩放 (单遍遍历)
       → 直接写入 TPU tensor (零中间 buffer)
```

### 3.2 Letterbox 填充优化

4:3 摄像头画面（640×480）送入正方形模型输入（640×640）时，只在上下有黑边。利用这一几何特性，仅清零填充带而非整个输出 buffer：

```
旧：dst[0..640×640×3].fill(0)       // memset 1,228,800 字节
新：dst[0..80×640×3].fill(0)        // 顶边
   + dst[(80+480)×640×3..].fill(0)  // 底边
                                     // memset 307,200 字节（节省 75%）
```

### 3.3 帧缓冲预分配

`UsbCamera` 结构体持有一个 614KB 预分配 `Vec<u8>`，跨帧复用。每帧仅 clone 出数据给调用方，内部 buffer 原地清空重用，实现零 per-frame 堆分配，避免嵌入式系统上的内存碎片。

### 3.4 dc_jpeg.rs 移除

原始版本包含一个约 600 行的自定义 DC-only JPEG 解码器 (`dc_jpeg.rs`)，用于快速下采样场景。由于新版改用内核 JPU 硬件完成 MJPEG→YUV 解码，该模块已移除。这简化了预处理管道并消除了一条代码维护路径。

---

## 4. 机器人行为模型

### 4.1 状态机设计

```
                    ┌──────────┐
        无检测      │           │  检测到球
    ┌─────────────→│ ChaseTennis │←─────────────┐
    │  连续顺时针转  │           │ 渐进减速靠近    │
    │              └─────┬─────┘               │
    │                    │ 面积 ≥ 55% 且居中    │
    │                    ▼                     │
    │              ┌──────────┐   确认 2 帧     │
    │   球消失+后退 │           │──────────────→│
    └─────────────│ GrabTennis │  执行 5 步抓取  │
                  │           │←──────────────│
                  └──────────┘   抓完回到搜索    │
```

### 4.2 追击速度曲线

采用二次减速曲线替代原始版本的硬阈值：

```
speed(area) = CHASE_SPEED × (1 − area/GRAB_AREA)²

CHASE_SPEED = 45
GRAB_AREA   = 0.55

面积比 0.03 → speed = 38   (刚发现，温和靠近)
面积比 0.20 → speed = 17   (中场，明显减速)
面积比 0.40 → speed = 6    (靠近中，蠕行)
面积比 0.55 → speed = 0    (就位，停止)
```

**设计考量**：使用二次而非线性曲线，确保远距离保持较高速度，近距离急剧降速，防止冲过头。原始线性曲线在面积 40% 时仍有 speed=18，导致低速 FPS 下一帧跳过抓取区间。

### 4.3 抓取决策

```
条件：area ≥ GRAB_AREA (0.55) AND |ball_cx − target_center| ≤ CENTER_MARGIN (35px)

确认：连续 2 帧满足条件
     → 执行 arm.grab()

特例：area ≥ GRAB_AREA_MAX (0.85) → 先轻微后退 40ms
     area ≥ 30% 且球突然消失 → 后退 640ms 再搜索（遮挡恢复）
```

### 4.4 居中位置微调

`GRAB_CENTER_OFFSET = 8` 将判定"居中"的目标位置从画面正中心（x=320）向右偏移 8 像素（x=328）。这允许机械臂在偏右位置抓取，补偿了摄像头与机械臂之间的物理安装偏移。

### 4.5 搜索行为

无检测时，小车执行**连续顺时针旋转**（`IDLE_SPEED=12`），不停止等待。相比原始版本每帧仅转 100ms（有效转动占比 3.3%），当前实现了 100% 转动利用率。检测到目标后，下一帧的 align/forward 指令自然覆盖转向命令。

### 4.6 参数演进

| 参数 | 原始值 | 最终值 | 调整原因 |
|------|--------|--------|---------|
| `CHASE_SPEED` | 56 | 45 | 近距离冲太快 |
| `GRAB_AREA` | 0.40 | 0.55 | 球上下占满画面时距离合适 |
| `GRAB_AREA_MAX` | 0.55 | 0.85 | 只在极端靠近时才后退 |
| `GRAB_CONFIRM_THRESHOLD` | 5 | 2 | FPS 提升后 5 帧确认太慢 |
| `IDLE_SPEED` | 10 | 12 | 搜索转速微调 |
| `BACKWARD_PULSE_US` | 200ms | 80ms | 后退距离减小，遮挡时 ×8 |
| `TURN_SPEED` | 18 | 10 | 对齐转速降低 |
| `TURN_PULSE_MIN` | 75ms | 25ms | 最小对齐脉冲缩短 |
| `TURN_PULSE_MAX` | 500ms | 120ms | 最大对齐脉冲缩短 |

---

## 5. 机械臂抓取序列

### 5.1 5 步序列

| 步骤 | 舵机 0 (底座) | 舵机 1 (肩部) | 舵机 2 (夹爪) | 动作描述 | 耗时 |
|------|:-----------:|:-----------:|:-----------:|---------|------|
| 1. 就绪 | 150° | 140° | 120° | 臂抬起，夹爪半闭 | — |
| 2. 下探 | **200°** | **100°** | — | 底座下摆，肩部把球往车身推 | ~1.8s |
| 3. 张开 | — | **90°** | **180°** | 夹爪张开，肩部继续下压 | ~1.8s |
| 4. 夹取 | — | — | **80°** | 夹爪闭合抓住球 | ~1.5s |
| 5. 抬起 | **150°** | **140°** | — | 底座和肩部回到就绪 | ~1.8s |
| **总计** | | | | | **~8.6s** |

### 5.2 舵机方向规则

经实际测试确定各舵机的角度-运动映射：

| 舵机 | 增大度数 | 减小度数 |
|------|---------|---------|
| 0 底座旋转 | 下摆 (arm swings down) | 上抬 (arm swings up) |
| 1 肩部升降 | 上抬 (shoulder lifts up) | 下压 (shoulder pushes down) |
| 2 夹爪 | 张开 (gripper opens) | 夹紧 (gripper closes) |

### 5.3 指令可靠性

原始版本中多舵机指令连续发送无间隔（`set_angle(0) → set_angle(1) → set_angle(2)`），导致 ZP10S 控制器丢指令，舵机 1 和 2 时常无响应。修复方案：所有连续 `set_angle()` 调用间加入 50–300ms 延迟。

```rust
// 修复前
self.set_angle(0, S0_REACH, 1000);  // 立即发送
self.set_angle(1, S1_PUSH, 1000);   // 立即发送（可能被丢弃）

// 修复后
self.set_angle(0, S0_REACH, 1000);
sleep_ms(300);                       // 等待控制器处理
self.set_angle(1, S1_PUSH, 1000);   // 可靠发送
```

### 5.4 角度校准对照

| 功能 | 原始值 | 校准值 | 舵机 |
|------|--------|--------|------|
| 底座就绪 | 150° | 150° | 0 |
| 底座下探 | 225° | **200°** | 0 |
| 肩部就绪 | 100° | **140°** | 1 |
| 肩部推球 | 60° | **100°** | 1 |
| 肩部继续 | — | **90°** | 1 |
| 夹爪张开 | 110° | **180°** | 2 |
| 夹爪闭合 | 50° | **80°** | 2 |
| 夹爪就绪 | — | **120°** | 2 |

---

## 6. Web 远程监控系统

### 6.1 控制面板

`akars serve` 提供基于 Axum + Tokio 的 Web 控制面板（`http://<ip>:8080`）：

| 端点 | 方法 | 功能 |
|------|------|------|
| `/` | GET | 单页控制面板 |
| `/api/status` | GET | 硬件状态快照 (JSON) |
| `/api/control` | GET | 查询参数驱动 |
| `/api/drive` | POST | JSON 底盘控制 |
| `/api/arm/action` | POST | JSON 手臂控制 |
| `/api/reconnect` | POST | 重连硬件 |

### 6.2 摄像头实时流

`serve --camera /dev/cvi-usb-camera0` 启用摄像头预览：

```
新增端点: /camera.jpg (GET)
帧编码:   YUV422 → yuv422p_to_jpeg_bytes(quality=75) → JPEG 字节流
前端:     <img> 每 200ms 轮询刷新 (cache-bust 加时间戳)
实现:     后台 std::thread 持续采集+编码，共享 Arc<Mutex<Vec<u8>>>
```

### 6.3 独立 Web 控制程序

`cam_web` 是一个完全独立的二进制，提供摄像头预览 + 基础控制（前/后/左/右/夹取/释放/就绪），不依赖 `serve` 或 `hunt`。

---

## 7. 调试与可观测性

### 7.1 逐帧时间线

```
[time] cap=63 pre=56(dec=0 rsz=56) fwd=44 post=14 handle=10 total=191ms
        ↑       ↑                    ↑     ↑     ↑         ↑
        采集    预处理 (YUV→RGB)      TPU   后处理 电机控制   总计
```

### 7.2 状态追踪

```
[FPS] 5.23 avg=4.96 (191ms) status=ChaseTennis area=0.184 cx=316 confirm=0
       ↑     ↑       ↑         ↑               ↑         ↑      ↑
      瞬时   平均    帧时间    当前状态        球面积     球x坐标  确认计数
```

### 7.3 启动配置

```
[cfg] GRAB_AREA=0.550 GRAB_AREA_MAX=0.850 CHASE_SPEED=45 CONFIRM=2
      IDLE=12 CENTER=35±8 TURN_PULSE=[25000..120000]us
```

### 7.4 摄像头诊断

启动时自动运行 `diagnose_timing()`，捕获 cmd3（raw MJPEG）和 cmd4（YUV via JPU）各一帧并对比耗时，分离帧等待与 JPU 解码开销。

---

## 8. 配置参数参考

### 8.1 行为参数 (`src/robot.rs`)

| 常量 | 值 | 说明 |
|------|-----|------|
| `GRAB_AREA` | 0.55 | 触发抓取的球面积占比 |
| `GRAB_AREA_MAX` | 0.85 | 太近需后退的阈值 |
| `GRAB_CONFIRM_THRESHOLD` | 2 | 抓取确认帧数 |
| `CHASE_SPEED` | 45 | 追击最高速度 |
| `TURN_SPEED` | 10 | 对齐转向速度 |
| `IDLE_SPEED` | 12 | 搜索顺时针转速 |
| `BACKWARD_SPEED` | 16 | 后退速度 |
| `BACKWARD_PULSE_US` | 80,000 | 后退脉冲（遮挡时 ×8) |
| `CENTER_MARGIN` | 35 | 居中判定容忍（像素） |
| `GRAB_CENTER_OFFSET` | 8 | 抓取中心右偏移（像素） |
| `TURN_PULSE_MIN_US` | 25,000 | 对齐最小脉冲 |
| `TURN_PULSE_MAX_US` | 120,000 | 对齐最大脉冲 |

### 8.2 舵机角度 (`src/arm.rs`)

| 常量 | 值 | 舵机 | 用途 |
|------|-----|------|------|
| `S0_READY` | 150° | 0 | 底座就绪 |
| `S0_REACH` | 200° | 0 | 底座下探 |
| `S1_READY` | 140° | 1 | 肩部就绪 |
| `S1_PUSH` | 100° | 1 | 肩部推球 |
| `S1_CONTINUE` | 90° | 1 | 肩部持续下压 |
| `S2_READY` | 120° | 2 | 夹爪就绪 |
| `S2_OPEN` | 180° | 2 | 夹爪张开 |
| `S2_CLOSE` | 80° | 2 | 夹爪闭合 |

### 8.3 CLI 参数

```bash
# Hunt 模式
akars <model.cvimodel> \
  --camera /dev/cvi-usb-camera0 \
  --motor /dev/ttyS1 \
  --arm /dev/ttyS2 \
  [--frames N] [--classes N] [--conf X] [--iou X]

# Web 控制面板 + 摄像头流
akars serve \
  --camera /dev/cvi-usb-camera0 \
  [--listen 0.0.0.0:8080] [--motor DEV] [--arm DEV]

# 摄像头 Web 快速预览
cam_web [--camera DEV] [--motor DEV] [--arm DEV] [--port 8080]
```

---

## 9. 工具程序

| 程序 | 功能 |
|------|------|
| `test_servo0_lift` | 舵机 0 就绪角度测试（默认 150°） |
| `test_servo0_prepare` | 舵机 0 下探角度测试（默认 200°） |
| `test_servo1_lift` | 舵机 1 就绪角度测试（默认 140°） |
| `test_servo1_prepare` | 舵机 1 推球角度测试（默认 100°） |
| `test_servo2_approach` | 舵机 2 张开角度测试（默认 180°） |
| `test_servo2_grab` | 舵机 2 抓取中角度测试（默认 150°） |
| `test_servo2_lift` | 舵机 2 抬起角度测试（默认 120°） |
| `test_servo2_prepare` | 舵机 2 闭合角度测试（默认 80°） |
| `red_cloth_follow` | 红色布料 YUV 色域检测跟随 |
| `cam_web` | 独立摄像头 Web 控制面板 |

所有舵机测试程序支持 `--angle` 命令行覆盖和 `--arm` 设备指定。

---

## 10. 性能基准

### 10.1 逐帧耗时分解（当前版本）

| 阶段 | 耗时 | 占比 | 实现方式 |
|------|------|------|---------|
| camera capture | ~63ms | 33% | ioctl GET_FRAME (cmd4) |
| YUV→RGB 预处理 | ~56ms | 29% | CPU 逐像素 BT.601 + 最近邻 |
| TPU 推理 | ~44ms | 23% | CVI_NN_Forward (硬件) |
| NMS + 后处理 | ~14ms | 7% | CPU |
| 电机控制 | 9–140ms | 5–42% | 串口 UART |
| **总计** | **~190ms** | | **3–5 FPS** |

### 10.2 优化前后对比

| 指标 | 优化前 | 优化后 | 改善 |
|------|--------|--------|------|
| camera capture | ~2860ms | ~63ms | 45× |
| 预处理 | ~60ms | ~56ms | 1.1× |
| 推理 | ~45ms | ~44ms | — |
| 每帧总计 | ~3100ms | ~190ms | **16×** |
| FPS | 0.3 | 3–5 | **12–16×** |
| JPEG 软件解码 | 20–50ms | 0ms | 已消除 |
| memset 开销 | 1.2MB/帧 | 0.3MB/帧 | 4× |
| per-frame 堆分配 | 2MB | 0 | 已消除 |
| 搜索有效转动占比 | 3.3% | 100% | 30× |

---


## 11. 鲁棒性增强

### 11.1 摄像头错误恢复

原始版本无任何错误恢复机制。当前实现三级递进恢复策略：

| 级别 | 触发条件 | 恢复操作 | 耗时 |
|------|---------|---------|------|
| Tier 1 | 连续 3 帧失败 | `re_init()` — ioctl INIT 重置会话 | ~0ms |
| Tier 2 | Tier 1 失败后连续 3 帧再失败 | `reopen()` — 关闭 fd + 重新打开 + INIT | ~10ms |
| Tier 3 | Tier 2 失败后连续 3 帧再失败 | `hard_reset()` — GPIO 断电 + 重新上电 | ~2.5s |

恢复成功则清零计数器，恢复到正常采集。

### 11.2 抓取后摄像头恢复

机械臂抓取序列耗时约 8.6 秒，期间不采集帧。长时间空闲可能导致 UVC 管道超时。每次抓取完成后调用 `camera.re_init()` 重置管道，防止后续 `GET_FRAME` 返回 EIO。

### 11.3 串口指令可靠性

**舵机控制器**：ZP10S 控制器处理指令需要时间。原始版本多舵机指令连续发送无间隔，导致后续指令被丢弃。修复：所有连续 `set_angle()` 间加 50–300ms `sleep_ms`，指令末尾追加 `\r\n` 确保帧边界。

**电机控制器**：ESP32 协议帧包含 `SOF0(0xAA) + SOF1(0x55)` 帧同步头和 XOR 校验和。发送后等待 ACK 响应（超时 500ms）。`write_all_drain()` 确保 `tcdrain` 刷出后再返回。

### 11.4 信号处理

`SIGINT` 和 `SIGTERM` 处理器通过 `AtomicBool` 通知主循环退出。退出时执行 `motor.standby()` 确保电机关闭。

### 11.5 帧缓冲复用

`UsbCamera` 持有一个 614KB 预分配 `Vec<u8>`，跨帧 `fill(0)` 复用。每帧仅 `self.buffer[..].to_vec()` clone 输出给调用方。实现零 per-frame 堆分配，避免嵌入式系统内存碎片化。



---

## 12. 文件变更清单

| 文件 | 类型 | 说明 |
|------|------|------|
| `src/camera.rs` | 修改 | 帧采集管道重构（INIT 位置）、diagnose_timing()、cmd3 支持、3 级错误恢复 |
| `src/robot.rs` | 大幅修改 | 二次速度曲线、抓取状态机重设计、调试输出增强、遮挡后退恢复、抓取后 camera re-init |
| `src/arm.rs` | 重写 | 5 步校准抓取序列、指令间延迟（防丢指令）、`\r\n` 帧终止、角度常量全部重定义 |
| `src/image_bridge.rs` | 修改 | yuv422p_to_jpeg_bytes()、letterbox memset 优化 |
| `src/web.rs` | 修改 | /camera.jpg 端点、后台采集线程、HTML 摄像头区域 |
| `src/main.rs` | 修改 | serve 新增 --camera 选项 |
| `src/dc_jpeg.rs` | **移除** | 自定义 DC JPEG 解码器不再需要 |
| `src/bin/test_servo0_lift.rs` | **新增** | 舵机 0 就绪角度测试 |
| `src/bin/test_servo0_prepare.rs` | **新增** | 舵机 0 下探角度测试 |
| `src/bin/test_servo1_lift.rs` | **新增** | 舵机 1 就绪角度测试 |
| `src/bin/test_servo1_prepare.rs` | **新增** | 舵机 1 推球角度测试 |
| `src/bin/test_servo2_approach.rs` | **新增** | 舵机 2 张开角度测试 |
| `src/bin/test_servo2_grab.rs` | **新增** | 舵机 2 抓取中角度测试 |
| `src/bin/test_servo2_lift.rs` | **新增** | 舵机 2 抬起角度测试 |
| `src/bin/test_servo2_prepare.rs` | **新增** | 舵机 2 闭合角度测试 |
| `src/bin/red_cloth_follow.rs` | **新增** | YUV 色域红布检测跟随 |
| `src/bin/cam_web.rs` | **新增** | 独立摄像头 Web 控制面板 |
| `Cargo.toml` | 修改 | 新增 11 个 [[bin]] 目标 |

