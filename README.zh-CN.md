# Delta Force × iCreate 录制崩溃调查

[English](README.md) | 中文

一个面向 Windows 版《三角洲行动》、腾讯“洲洲时刻”与 D3D12/NVIDIA 录制冲突的**非官方、证据驱动**调查项目。

本仓库整理了一次真实故障调查中可公开复用的部分：崩溃链、证据分级、安全只读取证工具、保留录制功能的规避流程，以及厂商侧修复建议。仓库不包含游戏文件、腾讯组件、原始 Dump、原始日志或用户身份信息。

## 结论摘要

在已分析的样本中，最深可证实链路为：

1. 对局结束触发 `StopRecorder` / 捕获资源销毁；
2. 同一时间窗口，录制成功提示浮层上传 `record_success.png`；
3. Windows 记录 `nvlddmkm` Event ID 153，并产生 GPU WATCHDOG `0x141`；
4. 游戏随后观察到 `DXGI_ERROR_DEVICE_REMOVED`，移除原因是 `DXGI_ERROR_DEVICE_HUNG`；
5. 腾讯 `graphics-hook64.dll 1.8.0.0` 的 D3D12 图片上传路径未检查对象创建结果，在 `+0x1AB42` 或 `+0x1AB89` 解引用空的 command list / command queue；
6. 同一路径还存在无限 fence 等待，因此用户体验可能是“先冻结，再退回桌面”。

确定无疑的是：**未检查失败结果并解引用空 COM 指针属于录制浮层组件缺陷。** 现有公开样本不足以唯一证明最先导致 GPU 超时的是哪一个 command list、共享资源或跨队列同步点，因此上游竞态仍应表述为“最可信、但需 DRED/厂商符号最终确认”。

完整证据边界见 [`docs/root-cause.md`](docs/root-cause.md)。

## 不关闭“洲洲时刻”的处理顺序

### 用户侧最小变量

保持：

- 洲洲时刻开启；
- 进程捕获；
- NVENC；
- 其余游戏画质与 BIOS 设置不变。

只关闭：

- NVIDIA App 游戏内覆盖；
- NVIDIA 游戏滤镜；
- 其他会注入 Present/D3D12 的覆盖层。

然后执行三次“完整退出 WeGame → 冷启动游戏 → 完成第一局 → 停留到结算”的复测。这样可以区分“腾讯钩子自身缺陷”和“腾讯、NVIDIA 双覆盖层共同触发”。窗口捕获在本次调查中产生过黑屏，切换编码器也无法修复浮层上传路径，因此不作为首选变量。

### 厂商侧无损规避

调查确认录制与游戏内提示浮层受不同配置控制。向腾讯申请：

```text
enableSDK=true
enableRecord=true
overlayEnable=false
```

目标是保留自动录制、NVENC、音频与剪辑，只停止把录制提示图片注入游戏进程。详见 [`docs/mitigation.md`](docs/mitigation.md)。

## 安全取证工具

### 默认运行

```powershell
$env:DELTA_FORCE_ROOT = 'D:\Games\DeltaForce\DeltaForce'
.\tools\Collect-Evidence.ps1
```

也可双击 `collect-evidence.bat`，或显式传入路径：

```powershell
.\tools\Collect-Evidence.ps1 -GameRoot 'D:\Games\DeltaForce\DeltaForce' -LookbackHours 168
```

默认行为：

- 只读查询系统、事件日志、相关进程与 Dump 元数据；
- 输出仅写入仓库下的 `evidence\<时间>`；
- 对文本中的计算机名、用户名、用户目录和疑似长账号 ID 脱敏；
- **不复制原始 Dump，不复制原始日志。**

显式增加脱敏日志尾部：

```powershell
.\tools\Collect-Evidence.ps1 -GameRoot 'D:\Games\DeltaForce\DeltaForce' -IncludeLogTails
```

只有在准备本地 WinDbg 分析时才使用：

```powershell
.\tools\Collect-Evidence.ps1 -GameRoot 'D:\Games\DeltaForce\DeltaForce' -IncludeDumps
```

原始 Dump 可能含私人数据，提交 issue 前不要直接上传。详见 [`docs/evidence-guide.md`](docs/evidence-guide.md)。

## 测试

Windows PowerShell 5.1 或 PowerShell 7：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1
```

测试覆盖：

- 崩溃时间相关日志不会被“只取最新 N 份”遗漏；
- 已知 `graphics-hook64` 签名识别；
- 未知签名不会被误报为已确认根因；
- 文本隐私脱敏；
- 仓库中无常见令牌、手机号、长账号 ID、真实用户目录或原始证据文件。

## 仓库结构

```text
.
├─ docs/                 调查结论、规避方案、证据指南、厂商修复建议
├─ src/                  可复用的 PowerShell 取证函数
├─ tools/                只读取证入口
├─ tests/                无第三方依赖的行为与发布安全检查
└─ collect-evidence.bat  Windows 快捷入口
```

## 证据优先原则

- API 报错点不一定是上游根因；`ID3D12Resource::Map` 只是观察到设备已挂起的位置。
- 压力测试不覆盖“注入捕获 + 共享纹理 + 编码 + 停止销毁 + 同帧浮层上传”。
- 不把相关性写成唯一因果；缺少 DRED、厂商 PDB 或失败 HRESULT 时明确保留边界。
- 每轮 A/B 只改变一个变量，并记录冷启动、局次、结算时间和生成文件。

## 商标与关联

《三角洲行动》、WeGame、“洲洲时刻”、NVIDIA、OBS 等名称归其各自权利人所有。本项目与腾讯、NVIDIA、OBS Project 无隶属或背书关系。

## 许可证

[MIT](LICENSE)
