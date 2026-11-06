# 架构与边界

> **一句话**：本仓只做「开通一条密钥登录的 SSH 通道」这件事 —— 会改目标机哪些状态、
> 不会做什么、怎么加固、怎么撤销，全在这一篇。

---

## 1. 三个角色

| 角色 | 是什么 | 本仓对它做什么 |
|---|---|---|
| 操作机 | 你坐着敲命令的那台机器（Windows / Linux / macOS） | 只放 `tools/` 的只读验证脚本与 `host/host.conf` |
| 目标机 | 要被远程运维的那台 Windows | `host/bootstrap-openssh.ps1` 在这里跑一次，之后靠 `sshd` 接受连接 |
| 通道 | 局域网内的 TCP 22 | 不代理、不转发、不做隧道 —— 直连 |

**为什么不做隧道**：目标机与操作机在同一个局域网里，直连 22 最简单也最容易审计。
需要跨网段时是另一件事（VPN / 端口转发），本仓明确不覆盖，见 §3。

## 2. 会改什么

`host/bootstrap-openssh.ps1` 是唯一会动手的脚本。它做的每一件事：

| 动作 | 具体改了什么 | 幂等 | 撤销 |
|---|---|---|---|
| 安装可选功能 | `OpenSSH.Server~~~~0.0.1.0` | ✅ 已装则跳过 | `Remove-WindowsCapability` |
| 服务启动类型 | `sshd` → `Automatic` | ✅ | `Set-Service -StartupType Disabled` |
| 启动服务 | `sshd` 开始监听 22 | ✅ | `Stop-Service sshd` |
| 防火墙规则 | `OpenSSH-Server-In-TCP` 存在则强制 `Enabled=True, Profile=Any, Action=Allow`，不存在则新建（TCP 22） | ✅ | `Remove-NetFirewallRule` |
| 公钥 | 追加一行到 `administrators_authorized_keys`（管理员账户）或 `~/.ssh/authorized_keys`（普通账户） | ✅ 已有同一把则不重复追加 | 删掉那一行 |
| ACL | 对 `administrators_authorized_keys` 断继承，只留 `Administrators` + `SYSTEM` | ✅ | 无（默认就是收紧状态） |
| `sshd_config` | **默认不动**。只有显式加 `-DisablePasswordAuth` 才把 `PasswordAuthentication` 与 `KbdInteractiveAuthentication` 都改成 `no` 并重启 `sshd` | ✅ | 改回 `yes` 并重启 |

> 公钥写哪个文件取决于**登录账户是不是管理员**。这是最常见的失败原因，
> 见 [PITFALLS.md](PITFALLS.md) P1。

## 3. 不会做什么

这些是设计约束，不是还没做：

- ❌ 不做端口转发、不碰路由器 NAT、不把 22 暴露到公网
- ❌ 不做反向隧道（chisel / frp 这类）—— 局域网直连用不上，跨网段是另一件事
- ❌ 不安装第三方远程控制软件（RustDesk / MeshCentral 等）
- ❌ 不接管图形界面 —— 要 GUI 请自行使用 RDP，本仓不包装它
- ❌ 不改 UAC、不改组策略、不创建账户、不动用户密码
- ❌ 不改默认 shell（想换成 PowerShell 是个人偏好，见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md) T6）

## 4. 加固

开通之后建议按顺序做这三步：

1. **确认密钥登录可用**：`python tools/verify-host.py --conf host/host.conf` 四项全绿。
2. **关掉密码认证**：确认第 1 步没问题之后再执行
   `host/bootstrap-openssh.ps1 -PublicKeyFile <你的.pub> -DisablePasswordAuth`。
   它会同时写 `PasswordAuthentication no` 与 `KbdInteractiveAuthentication no`
   —— 只关前者在 Windows 上不管用，密码仍能从 keyboard-interactive 进来
   （[PITFALLS.md](PITFALLS.md) P11），并用 `Restart-Service sshd -Force` 重载（P12）。
   顺序不能反 —— 先关密码再验密钥，一旦密钥有问题你就把自己锁在外面了。
   关完用这条确认服务只认密钥：
   `ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive -o NumberOfPasswordPrompts=0 <HOST-USER>@<HOST-IP> hostname`
   应返回 `Permission denied (publickey).`。
3. **限定监听地址**（可选）：`sshd_config` 里加 `ListenAddress <HOST-IP>`，只在这个网卡上监听。

> **关于网络位置**：如果目标机的 WiFi 被判为「公用」（Public），入站默认更严。
> 本仓的脚本**不改网络位置**，而是把防火墙规则的作用域写成 `Profile=Any` —— 这样
> 不管网络位置怎么变，22 都按规则放行，也不会连带打开网络发现之类的共享项。
> 想改网络位置属于 OS 级设置，自己按需做（需要管理员权限）：
> `Set-NetConnectionProfile -Name '<SSID>' -NetworkCategory Private`。

私钥的管理口径见 [SECRETS.md](SECRETS.md)。

## 5. 撤销

在目标机的管理员 PowerShell 里：

```powershell
Stop-Service sshd
Set-Service sshd -StartupType Disabled
Remove-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
Remove-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
# 公钥那一行：删掉 administrators_authorized_keys 里对应的那行（或整个文件）
```

撤完用 `Get-NetTCPConnection -LocalPort 22 -State Listen` 确认没有残留监听。

## 6. 配置怎么读

`tools/verify-host.py` 的取值顺序：**命令行参数 → `host/host.conf`**；`host` / `user` 缺失或仍是占位符直接报 T8、退出码 2；仅 `port` 默认 22、`identity` 默认交给 ssh 自己找。

`host/host.conf` 用 `key=value` 行格式，只认这几个键：

```ini
host=<HOST-IP>          # 目标机地址
user=<HOST-USER>        # 登录用户名
port=22                 # 可选，默认 22
identity=~/.ssh/id_ed25519   # 可选，默认按 ssh 自己的规则找
```

该文件**不入库**（`.gitignore` 已排除）。样例见 `host/host.conf.example`。
