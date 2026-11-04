# 踩坑总汇

> **一句话**：踩坑总汇（**正本**）：每条写清「现象 → 根因 → 怎么避」，现象那一行即搜索词。

按现象搜索本文，或先看 [TROUBLESHOOTING.md](TROUBLESHOOTING.md) 的排查树。

---

## P1 `administrators_authorized_keys` 权限过宽 → 密钥被静默忽略

**现象**：公钥明明写进了 `C:\ProgramData\ssh\administrators_authorized_keys`，`ssh` 还是提示输密码；
`sshd` 日志里只有 `Failed password`，没有任何「key rejected」字样。

**根因**：`sshd` 对管理员账户的授权文件有**额外的权限要求** —— 文件不能被 `Administrators` 与 `SYSTEM`
之外的任何人写入，也不能继承父目录的可写 ACE。不满足时它**不报错、直接跳过这个文件**，
然后退回密码认证。这是本仓最容易踩的坑。

**怎么避**：写完公钥立刻断继承：

```powershell
icacls "$env:ProgramData\ssh\administrators_authorized_keys" /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"
```

> 非英文系统上组名可能是本地化的，`Administrators` 解析不到。用 SID 写法最稳：
> `/grant "*S-1-5-32-544:F" /grant "*S-1-5-18:F"`（544 = Administrators，18 = SYSTEM）。
> `host/bootstrap-openssh.ps1` 用的是 SID 形式。

`host/bootstrap-openssh.ps1` 已内置这一步。排查时用 `icacls <文件>` 看有没有多余的 `(I)` 继承项。

## P2 公钥写错文件：管理员 vs 普通账户

**现象**：P1 的 ACL 已经收紧了，还是连不上；或者换一个账户登录就能用。

**根因**：默认 `sshd_config` 末尾有一段

```text
Match Group administrators
       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
```

**属于管理员组的账户只认** `administrators_authorized_keys`；**普通账户只认**
`C:\Users\<HOST-USER>\.ssh\authorized_keys`。写错地方就等于没写。

**怎么避**：先用 `whoami` 与 `net localgroup administrators` 确认账户身份，再决定写哪个文件。
脚本的 `-User` 参数就是干这个的。

## P3 装完能力没设自启 → 重启后连不上

**现象**：开通当天一切正常，第二天开机后 `Connection refused`。

**根因**：`Add-WindowsCapability` 只安装不启服务，`sshd` 的启动类型默认是**手动**。
重启后服务不会自己起来。

**怎么避**：`Set-Service sshd -StartupType Automatic`。脚本已做。事后核对：
`Get-Service sshd | Select-Object Status,StartType` 应为 `Running / Automatic`。

## P4 用 TTL 判断对端系统不可靠

**现象**：`ping` 回 `TTL=64`，据此判定对方是 Linux/Android，结果一问是 Windows。

**根因**：TTL 只在没有中间设备改写时可信。虚拟网卡、VPN、第三方协议栈、部分安全软件都会改写它。
Windows 默认 128，但被改写后可能显示 64。

**怎么避**：TTL 只当线索。判断系统用多条证据交叉（NetBIOS 名称、SMB 端口、DHCP 租约主机名、
用户确认），别单点下结论。这条是本次踩点实际踩到的。

## P5 能力装完了、规则显示 Enabled，22 端口还是不通

**现象**：`Get-Service sshd` 是 `Running`，本机 `Test-NetConnection 127.0.0.1 -Port 22` 返回 `True`，
但从另一台机器连是**超时**（不是拒绝）。目标机 `ping` 得通。

**根因（2026-10-26 真机确认）**：`OpenSSH.Server` 能力安装时自动创建的
`OpenSSH-Server-In-TCP` 规则**作用域是 `Profile=Private`**。如果这台机的网络位置被 Windows
判为 `Public`（连陌生 WiFi 时的默认），这条规则**一条都不匹配** —— 端口照旧关着，
但 `Get-NetFirewallRule` 会告诉你 `Enabled : True`，非常容易误判成「已经放行了」。

叠加的第二个坑：如果这时用 `New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' ... -ErrorAction SilentlyContinue`
去补规则，会因为**同名规则已存在**而失败，错误又被 `SilentlyContinue` 吞掉 ——
看起来执行成功，实际什么都没改。

**怎么避**：

1. 不要判断「规则存在且 Enabled 就跳过」，而是**强制写一遍作用域**：
   ```powershell
   Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Enabled True -Profile Any -Action Allow
   ```
2. 检查网络位置：`Get-NetConnectionProfile | Select-Object Name,NetworkCategory`。
   `Public` 就是嫌疑对象（也可以把它改成 `Private`，但那会连带打开网络发现等）。
3. 判断「服务通不通」用 `127.0.0.1` 自测，判断「防火墙通不通」必须**从另一台机器**测 ——
   这两个结论分开才定位得到。本机通、远端超时 = 防火墙。
4. 别用 `New-NetFirewallRule` 当兜底，用 `Get` + `Set`。

`host/bootstrap-openssh.ps1` 已按第 1、4 条改写。


## P6 先关密码认证再验密钥 → 把自己锁在外面

**现象**：为了安全，开通时直接加了「禁用密码认证」，结果密钥那一步有问题，现在怎么都进不去。

**根因**：顺序反了。密钥链路涉及「写对文件 + ACL 正确 + 账户类型匹配」三个条件，
任何一条不满足都会静默失败；此时再关掉密码就彻底没有入口。

**怎么避**：**永远先验证密钥登录成功，再关密码认证**。验证用
`ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no <HOST-USER>@<HOST-IP> hostname`，
能返回主机名才算密钥链路通。脚本把 `-DisablePasswordAuth` 做成显式开关也是这个原因。

## P7 `host/*.ps1` 用 UTF-8 无 BOM 写中文 → 乱码或解析失败

**现象**：脚本在别人的机器上跑，报 `字符串缺少终止符` 之类的语法错误，或者注释全变问号。

**根因**：Windows PowerShell 5.1 在读取**无 BOM** 的文件时按系统 ANSI 代码页解码，
UTF-8 的中文字节会被拆成非法字符，落到字符串或括号上就会破坏语法。

**怎么避**：`host/` 下的脚本**一律纯 ASCII**（注释用英文）。这条已写进 [AGENTS.md](../AGENTS.md)
与 [CONTRIBUTING.md](../CONTRIBUTING.md)。

## P8 靠 DHCP 租约找主机 —— 随机化 MAC 让租约认不出设备

**现象**：在路由器租约表里想找出「那台 Windows」，看到一堆没有主机名的条目，MAC 也对不上任何厂商。

**根因**：Windows 11 默认开启「随机硬件地址」，每次连 WiFi 可能换一个 MAC；
再加上设备没上报 hostname，租约里只剩一个匿名条目。OUI 查厂商因此完全失效。

**怎么避**：不要用租约表定位设备。改用「有线/无线」（路由器 station dump）、
用户自己确认、或在目标机上执行 `hostname` / `ipconfig` 后告知。

## P9 以为「把项目拉到操作机」就能控制目标机

**现象**：在操作机上克隆了一个远程控制项目，装好客户端，目标机依然连不上。

**根因**：架构误解。目标机没有开放任何入口时，操作机上的任何软件都**没有通道**去触达它。
远程控制工具的「服务端/代理」必须跑在**目标机**上，而把它装上去这个动作本身就需要通道 —— 循环依赖。

**怎么避**：先解决「一次性物理/本地开通」（本仓方案 A 就是这件事），再谈工具。
这条是本次踩点的出发点，详见 [RECON-WINDOWS-SSH.md](RECON-WINDOWS-SSH.md) §1。

## P10 账户名与用户目录名不一致 → 公钥写进了不存在的目录

**现象**：给标准用户写公钥，按 `C:\Users\<账户名>\.ssh\authorized_keys` 拼路径，
文件确实建出来了（目录也被 `New-Item` 创建了），但登录仍然提示输密码。

**根因**：账户被改过名（`net user <旧名> <新名>`），或者用户目录是从旧机器迁移来的。
这时 **SAM 账户名 ≠ profile 目录名**：`whoami` 返回的是账户名，而家目录可能是另一个名字
（形如 `C:\Users\<另一段名字>`）。
`sshd` 解析家目录用的是 `GetUserProfileDirectory`（读注册表），不是你拼出来的字符串。
于是公钥落在了一个新造的空目录里，`sshd` 根本不会去看。

**识别信号**：`whoami` 返回的名字，和命令行提示符里 `C:\Users\<目录>` 的那一段对不上。

**怎么避**：从注册表取真实路径，不要按账户名拼：

```powershell
$sid = (Get-LocalUser -Name $User).SID
(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid").ProfileImagePath
```

`host/bootstrap-openssh.ps1` 已按这个方式解析。**管理员账户不受影响** ——
它们走 `administrators_authorized_keys`，与 profile 路径无关。

## P11 关了 `PasswordAuthentication`，密码照样能登进去

**现象**：`sshd_config` 里已经写了 `PasswordAuthentication no`，重启后从另一台机器连，
仍然弹密码框、输对了还能进。

**根因（2026-10-26 真机确认）**：Windows 的 sshd 还开着 **keyboard-interactive** 认证
（`KbdInteractiveAuthentication` 默认 `yes`），客户端会走这条路径把密码送进去。
`ssh -v` 里能看到 `Authentications that can continue: publickey,keyboard-interactive` ——
`password` 已经没了，但 `keyboard-interactive` 是等价的入口。

**怎么避**：两条一起关：

```text
PasswordAuthentication no
KbdInteractiveAuthentication no
```

**验证方式**（不要看配置文件，要看服务实际接受什么）：

```sh
ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive \
    -o NumberOfPasswordPrompts=0 <HOST-USER>@<HOST-IP> hostname
```

返回 `Permission denied (publickey).` —— 括号里**只剩 publickey** 才算真关干净。
如果还列着 `keyboard-interactive`，就是这条没做。

`host/bootstrap-openssh.ps1 -DisablePasswordAuth` 已同时写这两条。

## P12 `Restart-Service sshd` 报 `ServiceHasDependentServices` → 配置根本没重载

**现象**：改完 `sshd_config`，执行 `Restart-Service sshd` 抛
`ServiceHasDependentServices`，然后再连，行为跟改之前一模一样。

**根因**：sshd 有依赖服务，不带 `-Force` 时 `Restart-Service` 直接拒绝。错误只在控制台
闪一下，`Get-Service sshd` 依然是 `Running` —— 看起来「服务好好的」，实际跑的还是旧配置。

**怎么避**：用 `Restart-Service sshd -Force`。而且**重启后必须做行为验证**
（见 P11 的那条 `ssh -o PubkeyAuthentication=no ...`），
不要只看服务状态 —— 服务在跑和配置生效是两件事。



## P13 门禁脚本用 `✓` / `✗` 打结论，GBK 控制台下把自己判成失败 【通用】

- **现象**：Windows 中文控制台（cp936）跑 `python -I tools/check-docs.py`，最后一行
  `print(f"✓ …")` 抛 `UnicodeEncodeError: 'gbk' codec can't encode character '\u2713'`，
  脚本以**退出码 1** 结束 —— 检查其实全过，门禁却报红。CI 是 UTF-8，看不到，能长期潜伏。
- **根因**：`✓` U+2713 / `✗` U+2717 / `⚠` U+26A0 不在 cp936 码表，`sys.stdout` 在这个环境里
  就是 `gbk`；`python -I` 会把 `PYTHONIOENCODING` / `PYTHONUTF8` 一起忽略，所以「设个环境变量」
  不是解法 —— 必须改脚本。
- **解法**：结论行只用 ASCII（`[OK]` / `[FAIL]` / `[!]`）；入口再加
  `if hasattr(sys.stdout, "reconfigure"): sys.stdout.reconfigure(errors="replace")`，
  非 GBK 字符降级成 `?` 而不是抛异常。同一问题首次记录见 ZcodeAIModels 仓「踩坑总汇」第 36 节（跨仓引用，非本仓路径）。
- **验证**：`python -I tools/check-docs.py` → `[OK] …`、退出码 0；反证：把 `✓` 改回原样，
  同一命令退出码 1 并抛 `UnicodeEncodeError`。
