# 文档规则

> **一句话**：docs/ 下的文档怎么分类、怎么互相引用、怎么脱敏、改动时连带改哪些 ——
> 本篇只管「怎么写、怎么保持一致」，不承载任何具体技术规则。

---

## 1. 分类与定位

docs/ 分四类（索引见 [README.md](README.md)）：

| 类别 | 收什么 | 现有成员 |
|---|---|---|
| 架构与机制 | 边界、会改什么、怎么接入 | ARCHITECTURE、RECON-WINDOWS-SSH |
| 工具专项 | 脚本清单、踩坑、排错 | TOOLS、PITFALLS、TROUBLESHOOTING |
| 流程与规范 | 版本、凭据、文档规则 | VERSIONING、SECRETS、DOC-RULES |
| 参考资料 | Release 说明 | release-notes/ |

每篇文档开头必须有一个 **「一句话」引言块**（`> **一句话**：…` 或一行定位语），
让读者不用往下翻就知道这篇管什么。新文档没有它不算写完。
**例外**：根 `README.md`（面向用户的门面）与 `docs/release-notes/` 下的正文。

### 文件命名：全大写 + 连字符

`docs/` 下的 `.md` 一律 **全大写 + 连字符**：`MAINTENANCE.md`、`DOC-RULES.md`、`RECON-WINDOWS-SSH.md`。
混用驼峰或下划线（`ReconWindowsSsh.md` / `recon_windows_ssh.md`）会让索引排序和全仓搜索都跟着散。

改名三步（顺序别乱）：

1. **`git mv` 改名** —— 保住 Git 的重命名识别；用 `mv` 出来的是一套「删一篇 + 加一篇」；
2. **全仓 grep 旧文件名**，把引用方一并改掉 —— 含 `CHANGELOG.md` / `PROGRESS.md` 里指向**现役文档**的链接；
   纯历史记录里的旧文件名保留原样，那是当时的事实（口径同 §5）；
3. **跑 `python tools/check-docs.py` 收尾** —— 断链 / 失效锚点 / 索引漏项 / 孤儿一次查完。

例外：**`docs/release-notes/` 下的文件名是版本号本身**（`0.1.0.md`），**不带 `v`** ——
`v` 前缀只属于发版 tag。规则正本见 [VERSIONING.md](VERSIONING.md)。

## 2. 脱敏纪律（本仓红线）

**文档里不出现任何具体主机的身份信息。** 这条比格式规则优先级高 —— 格式错了能改，
泄漏出去了改不回来。

| 不许出现 | 写成 |
|---|---|
| 局域网 IP / IPv6 / DDNS 名 | `<HOST-IP>` |
| 计算机名 / MAC / WiFi SSID | `<HOST-NAME>` / `<REDACTED-MAC>` |
| 登录用户名 / 域 / 工作组 | `<HOST-USER>` |
| 私钥、口令、passphrase | `<REDACTED-KEY>` |
| 本机绝对路径（`C:\Users\<你>`） | 相对路径或 `~` 推导 |
| 真机探测原始输出 | 只放 `.work/`（不入库） |

示例与模板文件只允许占位符。提交前跑 `python tools/check-secrets.py --all` —— 这是红线的可执行版本。
判断标准：**这段文字贴到公开 Issue 里，会不会暴露某台具体机器的身份或入口？**

## 3. 单一正本原则

**每条规则只在一篇文档里定义；其余位置只允许一句话概述 + 指向正本的链接。**
两处都写全文，迟早各改各的。

| 规则 | 正本 |
|---|---|
| 会改目标机哪些状态、加固与回退 | [ARCHITECTURE.md](ARCHITECTURE.md) |
| 每个脚本干什么、怎么调 | [TOOLS.md](TOOLS.md) |
| 踩过的坑与「下次怎么避」 | [PITFALLS.md](PITFALLS.md) |
| 按现象排查 | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
| 凭据与主机配置的位置（只写位置不写值） | [SECRETS.md](SECRETS.md) |
| 版本晋升、不发版不动版本号 | [VERSIONING.md](VERSIONING.md) |
| 接入方案的取舍与实测依据 | [RECON-WINDOWS-SSH.md](RECON-WINDOWS-SSH.md) |

## 4. 链接纪律

- 统一用**相对链接 + 锚点**（示例写成行内代码 `` `[标题](文档名.md#锚点)` ``；示例串不是真实链接），不用绝对路径。
- **改动 / 删除 / 合并文档后必须双向点验**：
  - 出链：新文档里指向别处的链接目标还存在、锚点没变；
  - 入链：全仓搜旧文件名，把指向它的链接改成新位置 —— **禁止只删文档不改引用方**。
- 历史记录里的旧文件名（如 CHANGELOG 历史条目）可保留原样 —— 那是当时的事实；
  但**正文中指向现役文档的链接**必须始终指向现役文档。

## 5. 变更触发矩阵

改了什么，就必须连带改什么：

| 变更 | 必须同步 |
|---|---|
| **修一个缺陷**（行为变化 / 判据修正 / 安全加固） | [PITFALLS.md](PITFALLS.md) 补一条 **现象 → 根因 → 怎么避**；形成新判据时同步 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)；CHANGELOG 只是变更记录，**不算补文档** |
| 新增 / 删除脚本 | [TOOLS.md](TOOLS.md) 工具表与目录树、[ARCHITECTURE.md](ARCHITECTURE.md) 的「会改什么」表 |
| 改接入方案或默认参数 | [RECON-WINDOWS-SSH.md](RECON-WINDOWS-SSH.md) 与 [ARCHITECTURE.md](ARCHITECTURE.md) |
| 发版 | 根目录 CHANGELOG.md、`docs/release-notes/<版本>.md`（写法正本：[release-notes/README.md](release-notes/README.md)） |
| 改名 / 新增 / 删除文档 | [README.md](README.md) 索引（见 §7）+ 全仓 grep 旧文件名同步引用 |

## 6. 体量预算与样例时效

- **单篇 ≤ 800 行。** 超了就按「正文档 + 踩坑史」拆：正文档留结论与约束，
  历史 / 根因分析移到 HISTORY 篇。
- **样例时效**：带版本标注的样例（如「Windows 11 23H2 实测」）可容忍过时 —— 它们是历史记录；
  但**工具清单、会改什么**这类内容必须随脚本变更同步，不允许停留在旧版本状态。

## 7. 索引维护与孤儿零容忍

- [README.md](README.md) 是 docs/ 的唯一索引，**新增 / 删除 / 改名文档必须同步更新**。
- **孤儿文档零容忍**：任何新文档必须至少被一处既有文档引用（或进索引并有明确入口），
  否则等于没写。
