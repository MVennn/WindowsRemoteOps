# 排错手册

> **一句话**：排错手册（**正本**）：按「现象 → 排查步骤 → 原因 / 解法」组织，标题即检索词。

`tools/verify-host.py` 失败时会打印对应的条目号（`T1`…`T8`）。

---

## T1 `Connection refused`（连接被拒绝）

**排查**：

```powershell
# 在目标机上
Get-Service sshd | Select-Object Status,StartType
Get-NetTCPConnection -LocalPort 22 -State Listen
```

**原因 / 解法**：服务没起或没在监听。`Start-Service sshd`；
若 `StartType` 是 `Manual` 就改成 `Automatic`（[PITFALLS.md](PITFALLS.md) P3）。
服务起不来时看事件日志：`Get-WinEvent -LogName 'OpenSSH/Operational' -MaxEvents 20`。

## T2 连接超时（无任何响应）

**排查**：

```powershell
# 在目标机上
Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' | Select-Object Enabled,Direction,Action
Get-NetConnectionProfile | Select-Object Name,NetworkCategory
```

**原因 / 解法**：防火墙没放行，或网络位置是「公用」导致规则不匹配。
补规则或把网络改为「专用」（[PITFALLS.md](PITFALLS.md) P5）。
先从操作机 `ping <HOST-IP>` 确认链路本身通。

## T3 一直提示输入密码 / `Permission denied (publickey)`

**排查**：

```sh
ssh -v -o PreferredAuthentications=publickey -o PasswordAuthentication=no <HOST-USER>@<HOST-IP> hostname
```

看 `debug1: Offering public key` 之后有没有 `Server accepts key`。

**原因 / 解法**：这是最典型的一组失败，按顺序查：

1. 公钥写错文件（管理员 vs 普通账户）→ [PITFALLS.md](PITFALLS.md) P2
2. `administrators_authorized_keys` 权限过宽 → [PITFALLS.md](PITFALLS.md) P1
3. 公钥内容被换行/截断 —— 用 `Get-Content` 看是不是完整的一行 `ssh-ed25519 AAAA...`
4. 操作机没带对私钥 —— 显式加 `-i ~/.ssh/id_ed25519`

## T4 登录成功但立刻断开

**排查**：`ssh -v ... ` 看断开前最后几行；目标机上看 `Get-WinEvent -LogName 'OpenSSH/Operational'`。

**原因 / 解法**：常见于 `sshd_config` 被改过（`ForceCommand`、`Subsystem` 损坏）、
或账户被策略限制。先确认 `C:\ProgramData\ssh\sshd_config` 是不是原样（`sshd -T` 可校验）。

## T5 `scp` / `sftp` 失败，但 `ssh` 正常

**排查**：目标机上 `Get-Service sshd` 正常时，检查
`C:\Windows\System32\OpenSSH\sftp-server.exe` 是否存在。

**原因 / 解法**：部分精简镜像缺 `sftp-server`，或 `sshd_config` 里 `Subsystem sftp` 那行被注释。
Windows 上更省事的替代是 `scp -O`（走传统 SCP 协议，不依赖 sftp-server）。

## T6 登录后是 cmd，想用 PowerShell

**原因 / 解法**：默认 shell 由注册表决定，改它是**个人偏好**，不是本仓的默认行为。
确认要用的话：

```powershell
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell `
  -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
```

改完重连生效。不改也能用：`ssh <HOST-USER>@<HOST-IP> powershell -NoProfile -Command "..."`。

## T7 昨天能用，今天连不上

**排查**：`Get-Service sshd`、`Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'`、
目标机 IP 是否变了（DHCP 重新分配）。

**原因 / 解法**：按可能性排序 —— ① 服务启动类型被重置（[PITFALLS.md](PITFALLS.md) P3）；
② 目标机换了 IP，`host/host.conf` 里的地址失效；③ 系统更新后可选功能被移除。
第 ② 条建议在路由器上给这台机做静态租约。

## T8 `verify-host.py` 报配置缺失

**现象**：`退出码 2`，提示读不到 `host/host.conf`。

**原因 / 解法**：样例文件是 `host/host.conf.example`，必须先复制成 `host/host.conf` 再填值。
该文件被 `.gitignore` 排除，`git clone` 之后不存在是正常的。字段说明见
[ARCHITECTURE.md](ARCHITECTURE.md) §6。
