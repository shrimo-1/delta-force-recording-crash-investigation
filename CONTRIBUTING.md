# Contributing

欢迎提交可复现、已脱敏的改进。

## Issue 最小信息

- Windows 版本与 GPU/驱动版本；
- 游戏与录制组件版本（若能确认）；
- 捕获模式、编码器、覆盖层状态；
- 冷启动/局次/停止方式；
- 毫秒级故障时间线；
- 新 Dump 的模块、异常代码和相对偏移；
- 是否伴随 Event ID 153 或 WATCHDOG `0x141`。

不要公开上传原始 Dump、视频、完整日志、账号 ID、手机号或个人路径。

## Pull request

运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1
```

提交应保持只读取证、安全默认值和“未知签名不误报为已确认根因”的边界。
