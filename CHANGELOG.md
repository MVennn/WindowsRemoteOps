# 更新日志

> **一句话**：本仓的开发者记录 —— 每个版本改了什么、为什么、怎么验。
> 顶部的版本命名规则是**摘要**，**正本见 [docs/VERSIONING.md](docs/VERSIONING.md)**。

版本号形如 `vX.Y.Z`。**有功能更新进次版本（+0.1.0，补丁归零）；没有功能更新进补丁版本（+0.0.1）。**

---

## [未发布] — 2026-10-26

### 建仓入库（2026-11-01）

- 本地建仓 —— `git init -b main`，首个提交导入脱敏后的脚本、文档、门面资源与 CI 配置。
- 全量普查（169 个文件 / 约 13M）：`.work/`（真机实测产物与日志）与 `host/host.conf`
  （真机地址与用户名）经 `.gitignore` 排除，不入库；逐文件复查 IP / 用户名 / 本机路径 /
  凭据形态，二进制资源抽查 strings。
- 脱敏整理 —— `PROGRESS.md` 真机地址占位化（`<HOST-IP>`）、本机盘符路径改写为相对表述；
  `tools/` 三个脚本注释里的兄弟仓别名改为泛化表述（对外发布口径）。
- 自检 —— `tools/check-docs.py`、`tools/check-secrets.py --all` 全绿；PowerShell 纯 ASCII
  与解析、Python 语法、Issue 表单 YAML 复验通过。

### 建仓（2026-10-26）

- 新增 `docs/RECON-WINDOWS-SSH.md` —— 局域网 Windows 主机接入踩点：网络侧怎么判断
  一台「ping 得通但端口全关」的主机状态、四个接入方案的取舍、为什么不该先去
  GitHub 找远程控制项目、风险与回退、验收口径。**主机标识已全部脱敏**（`<HOST-IP>` 占位）。
- 新增 `host/bootstrap-openssh.ps1` —— 目标机侧一次性开通脚本：装 `OpenSSH.Server`、
  设自启并启动、放行 22、写 `administrators_authorized_keys` 并收紧 ACL；
  `-DisablePasswordAuth` 为可选加固开关，默认不动 `sshd_config`。
- 新增 `tools/verify-host.py` —— 操作机侧四项验证（密钥登录 / 命令执行 / 文件传输 /
  PowerShell 可用），`--dry-run` 只做只读探测。
- 新增 `host/host.conf.example` —— 主机配置模板，只含 `<HOST-IP>` / `<HOST-USER>` 占位符；
  真值写 `host/host.conf`，不入库。
- 新增 `docs/` 全套 —— ARCHITECTURE（会改什么 / 边界 / 加固）、TOOLS（工具清单正本）、
  PITFALLS（踩坑总汇）、TROUBLESHOOTING（按现象查）、SECRETS（凭据位置索引）、
  VERSIONING、DOC-RULES、release-notes 模板。
- 新增 `tools/check-docs.py` / `tools/check-secrets.py` —— 文档自检与脱敏扫描，
  口径与系列仓一致。
- 新增 `.github/` —— Issue 表单（Bug / 功能建议 / config）与 CI（Python 语法、
  文档自检、脱敏扫描、PowerShell 解析）。

### 修复（2026-10-26）

- 修复 `host/bootstrap-openssh.ps1` —— 标准账户的授权文件路径原本按
  `C:\Users\<账户名>\.ssh\authorized_keys` 拼，账户被改过名时（SAM 名与 profile 目录名不一致）
  会写进一个新建的空目录、`sshd` 永远读不到。改为从注册表
  `ProfileList\<SID>\ProfileImagePath` 取真实家目录。管理员账户不受影响。
  现象与识别信号见 [docs/PITFALLS.md](docs/PITFALLS.md) P10。
- 修复 `tools/verify-host.py` —— 命令行同时给了 `--host` 与 `--user` 时仍强制要求
  `host/host.conf` 存在，退出码 2。改为两者齐备即不需要配置文件。

### 真机开通与加固（2026-10-26）

- 新增 真机实测 —— 在目标 Windows 主机上完成开通：`OpenSSH.Server` 能力安装、
  `sshd` 设自启并启动、22 放行、公钥写入 `administrators_authorized_keys`；
  `tools/verify-host.py` 四项全通过（`OpenSSH_for_Windows_9.5` / PowerShell 5.1.26100）。
- 修复 `host/bootstrap-openssh.ps1` 防火墙逻辑 —— 能力自建的 `OpenSSH-Server-In-TCP`
  规则作用域是 `Profile=Private`；网络被判为 `Public` 时一条都不匹配，但规则仍显示
  `Enabled=True`，原逻辑据此判定「已启用，跳过」，等于什么都没修。改为始终执行
  `Set-NetFirewallRule -Enabled True -Profile Any -Action Allow`；不再用
  `New-NetFirewallRule` 当兜底（同名规则已存在，错误会被 `-ErrorAction SilentlyContinue` 吞掉）。
  见 [docs/PITFALLS.md](docs/PITFALLS.md) P5。
- 修复 `host/bootstrap-openssh.ps1 -DisablePasswordAuth` —— 只关 `PasswordAuthentication`
  在 Windows 上无效，密码仍能从 keyboard-interactive 进入；改为同时关
  `KbdInteractiveAuthentication`，并把 `Restart-Service sshd` 改成 `-Force`
  （否则报 `ServiceHasDependentServices`、配置不重载）。见 PITFALLS P11 / P12。
- 加固 —— 目标机现在只接受 publickey：`Permission denied (publickey).`，
  `password` 与 `keyboard-interactive` 都已从服务支持的认证方法列表中消失。

### 待办

- 待办 仓库已完成本地建仓（2026-11-01），远端未建；README 的 CI 徽章与 GitHub 绝对链接
  在推送后生效，logo 暂用相对路径 `assets/logo.png`。
