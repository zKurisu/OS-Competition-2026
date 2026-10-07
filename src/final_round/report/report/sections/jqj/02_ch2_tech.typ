// 本文件由 jqj.typ 拆分而来，仅承载技术理论章中的视觉链路内容。
// 系统调用、内存、存储、网络等技术路线由本章其他文件继续补充。

本节首先介绍机器人视觉推理这一工作线的技术路线。它是项目技术体系的一部分，用于说明摄像头、图像加速器、TPU与运动控制之间的协同关系；本章其余小节仍可继续接入系统调用、内存管理、存储与网络等系统层工作。

== 视觉推理与运动控制链路
本系统面向 SG2002 平台构建了一条由硬件加速器协同完成的网球视觉推理链路，整体采用“异步采集---硬件解码---硬件预处理---神经网络推理---检测后处理---运动控制”的处理流程。摄像头通过通用串行总线（Universal Serial Bus，USB）视频设备类协议（USB Video Class，UVC）输出分辨率为 640×480 的码流；该码流由JPEG压缩图像连续组成，格式称为MJPEG（Motion JPEG）。StarryOS 内核中的后台采集任务持续接收并组装 UVC 数据包，使用单调递增的帧序号发布最新完整帧。前台视觉线程只获取序号更新的图像；当图像采集速度高于推理速度时，系统允许旧帧被新帧覆盖，从而避免历史图像在队列中积压，保证机器人使用尽可能接近当前环境状态的图像进行闭环控制。

#figure(
  image("../../../figures/jqj/1.png", width: 72%),
  caption: [网球视觉推理与运动控制链路],
)

=== JPU硬件解码
获得最新 MJPEG 帧后，系统使用 JPEG 处理单元（JPEG Processing Unit，JPU）完成硬件解码。当前摄像头的 JPEG 图像采用 4:2:2 色度采样，因此 JPU 将其解码为 640×480 的亮度---色度 4:2:2 平面格式（YUV 4:2:2 Planar，YUV422P），并通过直接存储器访问（Direct Memory Access，DMA）将亮度 Y、色度 Cb 和色度 Cr 三个平面直接写入 ION 内存分配器提供的共享缓冲区；ION 是该分配器的专有名称。该缓冲区同时具有中央处理器（Central Processing Unit，CPU）虚拟地址和硬件可访问的物理地址，可被后续视频处理模块直接使用，避免将整幅 YUV 图像复制到普通用户态临时内存。针对摄像头偶发的损坏 JPEG，驱动还实现了异常帧恢复机制；当 JPU 出现码流耗尽、超时或输出长度异常时，系统会丢弃当前帧、复位解码器并等待更新帧，而不会因单帧错误导致视觉线程永久阻塞。

=== VPSS几何转换
JPU 解码完成后，YUV422P 图像被送入视频处理子系统（Video Processing Subsystem，VPSS）执行硬件预处理。VPSS 在一次离线任务中完成颜色空间转换（Color Space Conversion，CSC）、等比例几何变换、letterbox 填充以及红绿蓝（Red, Green, Blue，RGB）三平面排布。对于 640×480 的摄像头图像和 640×640 的模型输入，原始 4:3 图像保持纵横比并置于 640×640 画布中央，上下区域使用填充值补齐，从而避免直接拉伸造成网球外观畸变。处理结果以 8 位无符号整数（Unsigned 8-bit Integer，UINT8）形式存放在目标 ION 缓冲区中，并按照批次、通道、高度、宽度（Number, Channel, Height, Width，NCHW）布局组织为 `1×3×640×640` 的 RGB planar 数据。由于 VPSS 输出格式与模型输入契约一致，系统无需再由 CPU 执行逐像素 YUV 到 RGB 转换、图像缩放、通道重排或浮点归一化。

=== TDMA数据传输
模型推理阶段使用YOLOv8网球检测模型。VPSS 生成的 RGB planar 物理缓冲区首先通过张量直接存储器访问（Tensor Direct Memory Access，TDMA）导入模型输入张量，随后由 CVITEK/SOPHGO 神经网络运行时调用 `CVI_NN_Forward()` 执行前向推理。运行时将模型编译生成的 TDMA 和张量指令单元（Tensor Instruction Unit，TIU）命令提交给张量处理器（Tensor Processing Unit，TPU）驱动：TDMA 负责输入、权重、特征图和中间张量的数据传输，TIU 负责卷积、激活及其他张量运算。当前 TPU 工作频率为 700 MHz，片上互连域频率为 900 MHz。任务触发后，提交线程进入等待状态，并由中断请求（Interrupt Request，IRQ）在硬件执行完成时唤醒；驱动同时保留内存映射输入/输出（Memory-Mapped Input/Output，MMIO）轮询作为异常情况下的兜底机制。经过调度优化后，推理任务由提交线程直接串行执行，消除了旧实现中提交线程、TPU 工作线程和完成等待线程之间的多次调度交接。内核分段测试表明，当前约 39～41 ms 的 TPU 推理耗时主要来自指令触发至硬件中断之间的真实网络执行，而不是软件排队延迟。

=== TPU硬件推理
TPU 前向计算完成后，用户态直接解析运行时管理的 32 位浮点数（32-bit Floating Point，FP32）输出张量。程序按照 YOLOv8 的通道优先布局读取每个候选框的中心坐标、宽度、高度和网球类别置信度，并首先依据置信度阈值剔除低质量候选框；当前默认阈值为 0.5。随后采用非极大值抑制（Non-Maximum Suppression，NMS）处理重叠候选框：程序按置信度降序排列候选框，并利用交并比（Intersection over Union，IoU）判断不同候选框的空间重叠程度，当 IoU 大于 0.5 时抑制置信度较低的重复框。由于模型输入图像经过 letterbox 处理，NMS 后还需要根据缩放比例和上下填充量执行坐标逆映射，将预测框从 640×640 模型坐标系恢复到 640×480 摄像头坐标系，为后续运动决策提供真实图像位置。

=== 运动控制追球
运动控制层从经过阈值过滤和 NMS 的检测结果中选择面积最大的网球框作为当前追踪目标，以降低远处小目标对近距离抓取任务的干扰。系统使用检测框水平中心坐标表示网球相对于夹爪中心线的方向偏差，并以检测框面积占整幅图像面积的比例近似描述网球距离。当未检测到网球时，机器人执行原地旋转搜索；检测到远距离网球后，根据目标位于期望中心的左侧、右侧或中心区域，分别执行左转、右转或直行接近。目标接近抓取区域后，系统扩大中心容差并缩短转向脉冲，减少离散视觉反馈造成的左右过冲。当检测框面积比例达到 0.55、目标中心进入夹爪有效区域且连续两帧确认成立时，底盘停止并触发原有机械臂抓取序列。若网球面积比例达到 0.85，系统将其判定为距离过近，先执行轻微后退再开始抓取。由此，系统实现了从图像采集、硬件推理、空间位置估计到车辆转向、接近和机械臂抓取的完整视觉闭环。

#figure(
  image("../../../figures/jqj/4.5.png", width: 72%),
  caption: [网球追踪、接近与抓取控制流程],
)

== 正式链路的函数级调用过程
=== 初始化阶段
```text
main()
  ├─ 解析模型、摄像头、VPSS、电机和机械臂参数
  ├─ YoloModel::open(model_path)
  │    ├─ CVI_NN_RegisterModel()
  │    ├─ CVI_NN_GetInputOutputTensors()
  │    ├─ 检查输入 shape/format/pixel_format/aligned/quantization
  │    └─ 输出 AKARS_TPU_INPUT 契约
  ├─ VpssRgbPipeline::open(output_width=640, output_height=640)
  │    ├─ IonAllocation::allocate(source=2 MiB)
  │    ├─ IonAllocation::allocate(destination=3×640×640)
  │    ├─ open(/dev/cvi-usb-camera0)
  │    ├─ open(/dev/cvi-vpss0)
  │    ├─ CVI_CAMERA_IOCTL_INIT
  │    ├─ CVI_CAMERA_IOCTL_RESET_CAPTURE_STATS
  │    └─ CVI_CAMERA_IOCTL_START_ASYNC
  ├─ 打开 /dev/ttyS1 底盘电机
  ├─ 打开 /dev/ttyS2 机械臂控制器
  └─ run_tennis_hunter()
```

=== 后台 UVC 采集阶段
```text
async_capture_worker()
  ├─ 等待一帧在途背压条件满足
  ├─ capture_frame()
  │    ├─ uvc_capture_one_frame_profiled()
  │    │    ├─ USB/UVC 包接收
  │    │    ├─ FID/EOF 组帧
  │    │    └─ 返回 JPEG 与采集 profile
  │    ├─ 检查 SOI/EOI/最小长度
  │    ├─ 错误时复位 FID 连续性并有限重试
  │    └─ 更新 CaptureStats
  ├─ 写入非活动 latest-frame 缓冲
  ├─ 发布宽高、长度、时间戳与 sequence+1
  └─ 唤醒等待新序号的消费者
```

=== 前台摄像头与 JPU 阶段
```text
VpssRgbPipeline::next_inner()
  ├─ 构造 CameraIonFrameRequest(abi=2, last_sequence, source_ion_fd)
  ├─ ioctl(CVI_CAMERA_IOCTL_GET_LATEST_YUV_ION)
  │    └─ CviUsbCamera::latest_yuv_to_ion()
  │         ├─ wait_for_sequence(last_sequence)
  │         ├─ 解析并验证 source ION
  │         ├─ 复制小尺寸压缩 JPEG，释放 latest-frame 锁
  │         ├─ JpuDecoder::decode_planar_into()
  │         │    ├─ 复制 JPEG 到 JPU 位流缓冲
  │         │    ├─ 清零 1,024 字节尾部余量
  │         │    ├─ 编程 BBC/DPB/采样格式寄存器
  │         │    ├─ 启动并等待 JPU 完成
  │         │    └─ 输出 Y/Cb/Cr 到 source ION
  │         ├─ 失败时丢弃 sequence、复位并等待更新帧
  │         ├─ 返回三平面偏移/长度/步长、jpu_decode_us
  │         └─ mark_consumed(sequence)
  └─ 用户态校验 format=YUV422P、640×480 和平面范围
```

=== VPSS 阶段
```text
VpssRgbPipeline::next_inner(execute_vpss=true)
  ├─ 构造 VpssRunYuv422pRgb(abi=1)
  │    ├─ source fd + Y/Cb/Cr offsets/strides
  │    ├─ crop=(0,0,640,480)
  │    ├─ content=(0,80,640,480)
  │    ├─ destination fd + R/G/B offsets/strides
  │    └─ border + timeout=100 ms
  ├─ ioctl(CVI_VPSS_IOCTL_RUN_YUV422P_RGB)
  │    ├─ 解析 ION 并校验范围
  │    ├─ 配置 YUV422P 输入地址、采样与步长
  │    ├─ 配置 BT.601 CSC、SC_V1 scaler、letterbox
  │    ├─ 配置 RGB planar ODMA
  │    ├─ 启动任务并记录 hardware_start
  │    ├─ 3 ms 有界完成观察 / IRQ 等待
  │    ├─ 记录 hardware_done 和调试状态
  │    └─ 返回 status/IRQ/timestamps
  ├─ split_vpss_timing()
  └─ 返回 destination physical address 与 RGB planar 视图
```

=== TPU 输入与模型前向阶段
```text
YoloModel::infer_vpss_rgb_timed()
  ├─ 验证 destination 物理区间和张量契约
  ├─ CVI_NN_SetTensorWithAlignedFrames()
  │    ├─ libcviruntime 构造 TDMA-only 命令
  │    ├─ ioctl 提交 / TPU direct execution
  │    ├─ run_one(prepare → fire → IRQ → finish)
  │    └─ 将外部 RGB planar 导入模型输入
  ├─ CVI_NN_Forward()
  │    ├─ 提交 compute 命令流
  │    ├─ TDMA 搬运权重/特征图
  │    ├─ TIU 执行卷积、激活和检测头
  │    ├─ IRQ 唤醒提交线程
  │    └─ 返回输出张量
  └─ 分别记录 preprocess_us 与 forward_us
```

=== 后处理与控制阶段
```text
YoloModel::get_detections()
  ├─ CVI_NN_TensorPtr(output)
  ├─ FP32 直接只读切片
  ├─ parse_yolov8_output()
  │    ├─ 按通道读取 cx/cy/w/h/score
  │    ├─ 置信度阈值优先过滤
  │    └─ 构造少量有效 Detection
  ├─ nms(iou=0.5)
  └─ correct_yolo_boxes(640×640 → 640×480)

Robot::handle_detections()
  ├─ 选择最大面积网球框
  ├─ 计算 cx 和 area_ratio
  ├─ 搜索 / 左转 / 右转 / 前进 / 近球微调
  ├─ 连续两帧确认抓取条件
  └─ 进入机械臂抓取与持球状态
```
