# 证据采集与分享指南

## 闪退后立即记录

1. 系统时间（精确到秒）；
2. 是否为冷启动后的第一局；
3. 是否自动停止录制，还是手动按键停止；
4. 洲洲时刻、NVIDIA 覆盖层、游戏滤镜的状态；
5. 捕获模式与编码器；
6. 是否冻结、冻结大约多久；
7. 视频是否生成、是否黑屏、是否有声音。

## 使用采集器

默认只生成脱敏文本和 Dump 元数据：

```powershell
.\tools\Collect-Evidence.ps1 -GameRoot 'D:\Games\DeltaForce\DeltaForce'
```

需要 iCreate 日志尾部时增加：

```powershell
-IncludeLogTails
```

需要本机 WinDbg 分析时增加：

```powershell
-IncludeDumps
```

`-IncludeDumps` 输出只应用于本地分析或与可信厂商私下交换，不应直接附到公开 GitHub issue。

## 公开 issue 可提交

- `summary.txt`；
- `system-info.txt`；
- `application-events.txt`；
- `display-events.txt`；
- `classification.txt`；
- 已人工复核的 `*.redacted.txt`；
- A/B 表格和时间线。

## 公开前仍需人工检查

自动脱敏不是数据泄露的绝对保证。检查：

- 账号 ID、QQ/手机号、邮箱；
- 计算机名、Windows 用户名；
- `C:\Users\<USER>\...` 等个人路径；
- 游戏聊天、好友名、录音与画面；
- 启动参数中的令牌或会话字段；
- Dump、视频与完整原始日志。

## 时间线模板

```text
HH:mm:ss.fff  Match/GameEnd
HH:mm:ss.fff  StopRecorder
HH:mm:ss.fff  DestroySources / capture stopped
HH:mm:ss.fff  overlay window=3 / record_success.png
HH:mm:ss.fff  nvlddmkm Event ID 153
HH:mm:ss.fff  CrashSight fatal report
HH:mm:ss.fff  RHIThread DXGI_ERROR_DEVICE_HUNG
```

不要只比较“同一分钟”；停止录制与 TDR 的毫秒级先后关系才有诊断价值。
