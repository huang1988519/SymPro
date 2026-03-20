# 崩溃格式对照表（SymPro 内部）

> 用途：记录「平台导出 / 样本文件 / 当前解析路径」，便于兼容新平台与回归测试。  
> 样本路径多为本机路径，**勿提交真实用户日志**；可只写文件名或脱敏路径。

## 1. 格式分类（内部枚举建议）

| `sourceKind`（建议） | 说明 | SymPro 当前处理 |
|---------------------|------|----------------|
| `apple_ips` | 标准 `.ips`：首行 metadata JSON + 余下 report JSON，`bug_type=309` | `CrashLogParser.parseIPS` → `CrashReportModel.fromIPS` |
| `apple_hybrid` | 前文 `Translated Report` + 文末 `Full Report` 双 JSON | `extractIPSPayload` 全文扫顶层 JSON 配对 |
| `apple_crash_text` | 传统文本：Process、Thread、Binary Images 等 | `extractProcessName` / `extractUUIDs` / `extractBinaryImages` |
| `volcengine_json_wrapped_text` | 外层 JSON（业务字段）+ `data` 为内嵌文本 crash | `extractEmbeddedCrashText` + `normalizeCrashText` + 文本解析 |

## 2. 平台 ↔ 格式 ↔ 样本（请随样本补充）

| 平台 / 产品 | 常见导出形态 | 内层是否 Apple 原生 | 已知样本（文件名/说明） | 备注 |
|-------------|--------------|---------------------|-------------------------|------|
| **Apple（Xcode / 设备 / 模拟器）** | `.ips` 或 `.crash` | 是 | `ios-crash-log.txt`（混合格式示例） | hybrid 需全文提 JSON |
| **字节 / 火山 DataFinder 等** | 单文件 JSON，`data` 为长字符串（`\n` 或真实换行） | 内层多为 **类 Apple 文本**，非 `.ips` | `火山 crash.txt`、`火山data.txt` | `@Process:`、`<uuid>` 镜像行 |
| **Firebase Crashlytics** | 控制台 + SDK；导出视控制台而定 | 多为平台加工视图 | _待补充：导出文件名_ | 符号化依赖 dSYM |
| **Sentry** | 事件 JSON；也可上传 `.crash`/`.ips` 做符号化 | 混合 | _待补充_ | 文档支持 `.crash`/`.ips` + dSYM |
| **Microsoft App Center** | API/SDK JSON 结构 | 非 Apple 原始文件 | _待补充_ | 见官方 Upload Crashes API |
| **Instabug** | CSV 等导出 | 一般非原始 Apple 文件 | _待补充_ | |
| **腾讯 Bugly** | 控制台/SDK | 多为自有结构 | _待补充_ | |

## 3. 代码入口（维护时改这里）

| 能力 | 文件 |
|------|------|
| 总入口 | `SymPro/Models/CrashLogParser.swift` |
| IPS 模型 | `SymPro/Models/CrashReportModel.swift` |
| 符号化（依赖 IPS JSON） | `SymPro/Services/SymbolicationService.swift` |

## 4. 回归样本清单（建议放 `Fixtures/CrashSamples/`，仅本地或私有仓）

在仓库中**不要**提交含隐私的完整日志。可：

- 脱敏（替换路径、用户 ID、设备标识）；或  
- 仅保留「前 200 行 + Binary Images 段 + 一段 Thread」的最小复现片段。

| 用例 ID | 描述 | 期望 `sourceKind` | 期望行为 |
|---------|------|-------------------|----------|
| FIX-001 | 标准 `.ips` 双 JSON | `apple_ips` | 有 `model`，可符号化 |
| FIX-002 | Translated + Full Report | `apple_hybrid` | 有 `model`，可符号化 |
| FIX-003 | 火山 JSON + `data` 文本 | `volcengine_json_wrapped_text` | `uuidList`/镜像可解析；符号化视是否具备 IPS 结构 |
| FIX-004 | 纯文本 `.crash` | `apple_crash_text` | UUID/镜像；符号化当前可能受限（见 `SymbolicationService`） |

## 5. 待办（你来填）

- [ ] 为 `CrashLog` 增加 `sourceKind` 字段并在 UI 显示（便于确认走哪条解析路径）
- [ ] 收集 Bugly / Sentry / Crashlytics **脱敏**导出各 1 份，补全上表「样本」列
- [ ] 建立 `Fixtures` 最小片段 + 单测或快照测试

---

*文档版本：与 `CrashLogParser` 当前实现同步维护。*
