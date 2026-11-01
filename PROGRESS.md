# WindowsRemoteOps 建仓

> **一句话**：本仓唯一的进度台账 —— 当前在做什么、做到哪、卡在哪；接手时先读这里。

状态: 已完成（建仓 + 入库）

## 任务目标

按系列仓规范（基准仓的门面骨架 + 系列仓的 docs 四分类约定）
新建 `WindowsRemoteOps`，承载「局域网 Windows 主机远程接入与运维」这条线。
全程遵守脱敏红线：仓库内零设备标识，真机实测值只放 `.work/` 与不入库的 `host/host.conf`。

## 批次 2：建仓入库（2026-11-01）

- [x] 全量普查（169 个文件 / 13M，其中 `.work/` 约 13M 不入库）
- [x] 逐文件敏感信息复查（IP / 用户名 / 本机路径 / 主机名 / 凭据形态 / 二进制 strings）
- [x] 脱敏：本台账两处真机地址占位化（`<HOST-IP>`）、本机盘符路径改写为相对表述、
      私有规范文档名与兄弟仓别名改为泛化表述
- [x] `.gitignore` / `.gitattributes` / `.editorconfig` 核对，守卫 `tools/check-secrets.py` 跑通
- [x] CHANGELOG 补 2026-11-01 建仓条目
- [x] `git init -b main` + 首个提交（脱敏后的脚本与文档）
- [ ] 建 GitHub 远端并推送（等用户操作；推送后 README 徽章与绝对链接生效）

## 批次 1：门面与脚本（2026-10-26）

## 步骤清单
- [x] 建目录与基础配置：`.gitignore` / `.gitattributes` / `.editorconfig` / `LICENSE` / `NOTICE`
- [x] 根文档：`README.md` / `AGENTS.md` / `CONTRIBUTING.md` / `SECURITY.md` / `CHANGELOG.md`
- [x] docs/ 全套（9 篇 + release-notes 模板）：DOC-RULES / README 索引 / ARCHITECTURE / TOOLS /
      RECON-WINDOWS-SSH / PITFALLS / TROUBLESHOOTING / SECRETS / VERSIONING
- [x] host/：`bootstrap-openssh.ps1`（纯 ASCII）+ `host.conf.example`（占位符）+ `host.conf`（本地，不入库）
- [x] tools/：`verify-host.py` + `check-docs.py` / `check-secrets.py` / `make_social_preview.py`
- [x] .github/：Issue 表单三件 + `ci.yml`（Python 语法 / PS 纯 ASCII / PS 解析 / YAML / 文档 / 脱敏）
- [x] assets/：`icon.svg` 并渲染 `logo.png`（512×512）与 `social-preview.png`（1280×640）
- [x] 自检全绿（见下）
- [x] 清理：删除工作区根目录下未脱敏的临时踩点文件

## 自检结果（2026-10-26）

| 检查 | 命令 | 结果 |
|---|---|---|
| 文档自检 | `python tools/check-docs.py` | ✓ 16 篇全部通过（链接 / 锚点 / 引言块 / 孤儿） |
| 脱敏扫描 | `python tools/check-secrets.py --all` | ✓ 34 个文件，无命中 |
| PowerShell 纯 ASCII | 逐字节检查 `host/*.ps1` | ✓ 无非 ASCII 字节 |
| PowerShell 语法 | Windows PowerShell 5.1 `Parser::ParseFile` | ✓ 解析通过 |
| Python 语法 | `ast.parse` 全仓 | ✓ |
| Issue 表单 YAML | `yaml.safe_load` 三份 | ✓ |
| `verify-host.py` 冒烟 | `--host <HOST-IP> --user test --dry-run` | ✓ 正确报 T2 并返回 1 |

## 待解决的问题

- **目标机身份已确认（2026-10-26）**：登录账户在 Administrators 组内 → 公钥写
  `administrators_authorized_keys`（账户名见不入库的 `host/host.conf`）。注意该账户被改过名：
  `whoami` 返回的名字与 profile 目录名不一致（见 PITFALLS P10）。
- **开通已完成（2026-10-26）**：`sshd` Running/Automatic，监听 0.0.0.0:22；
  `verify-host.py` 四项全通过。随后已关闭密码认证与 keyboard-interactive，
  服务现在只接受 `publickey`（`Permission denied (publickey).`）。
- **网络位置已调整（2026-10-26）**：目标机与操作机的 WiFi 网络位置均从 `Public`
  改为 `Private`（同一张网）。本机改这个需要提权，当前 Bash 会话非管理员，
  走 `Start-Process -Verb RunAs` 弹 UAC 执行。改完通道四项复验仍全通过 ——
  防火墙规则已是 `Profile=Any`，不依赖网络位置。
- **待确认**：要部署什么（决定是否需要 WinSW 之类的服务托管工具）。
  见 `docs/RECON-WINDOWS-SSH.md` §9 第 3 条。
- **仓库已 `git init`（2026-11-01，`main` 分支，首个提交为脱敏后的脚本与文档）；
  尚未建远端**：等用户操作。建远端后需要
  ① 把 README 的 logo 从相对路径换成 `raw.githubusercontent.com` 绝对地址
  ② CI 徽章才会生效。

## 脱敏口径（本轮已执行）

| 内容 | 位置 | 是否入库 |
|---|---|---|
| 文档、脚本、示例、Issue 表单 | 仓库内 | ✅ 入库，**零设备标识**，只有 `<HOST-IP>` / `<HOST-USER>` / `<REDACTED-...>` |
| 目标机地址、用户名 | `host/host.conf` | ❌ `.gitignore` 排除 |
| 真机探测原始记录（IP / MAC / IPv6 / 信号） | `.work/`（文件名含真值，整个目录不入库） | ❌ `.gitignore` 排除 |
