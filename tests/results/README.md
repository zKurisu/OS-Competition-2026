# 结果目录

`scripts/run_suite.sh` 与手工实验的输出都落在这里，命名约定：

```
<YYYY-MM-DD-HHMMSS>-harness-<starry|linux>.log     # 一键套件输出（HS_*/HL_* 行）
<YYYY-MM-DD>-<主题>.txt                            # 手工实验记录（数字 + 结论 + 现象）
```

日志本身应当自证：包含运行日期、内核版本/FIT 名、板卡侧别、以及关键数字。
原始日志被 `.gitignore` 忽略（`*.log`/`*.txt`），但结论性的实验记录建议另存一份
到仓库外的 `final_round/side_workspace/results/`，与交接文档放在一起。

## 当前已归档的结论（摘要）

| 主题 | 结论 |
|---|---|
| 视觉端到端 | StarryOS 53.0 ms vs Linux 54.2 ms（640×480 网球检测） |
| TPU 移植 | 时钟/复位生命周期 + TDMA 定时补偿后，推理 41.3 ms vs Linux 39.7 ms |
| 相机链路 | 异步取流/NV12/ION（ioctl 6..13）全部上板验证通过 |
| cmdqu 合并 | `port/main-sg2002-fixes-cmdqu-merge` 上板验证通过 |
| 详细数据 | 见 `final_round/workspace/SG2002_EVAL_MEASUREMENTS.md` 与 `final_round/side_workspace/` |
