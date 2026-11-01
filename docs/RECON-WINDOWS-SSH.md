# 接入方案踩点：局域网 Windows 主机

> **一句话**：一台「ping 得通、端口全关」的 Windows 主机能不能被远程接管、四条路各有什么代价、
> 为什么不该先去 GitHub 找项目 —— 本文是这条结论的实测依据与决策记录。

- 日期：2026-10-26
- 状态：结论已定，真机待验证

---

## 1. 结论

**可行。用 Windows 自带的 OpenSSH Server，不需要第三方远程控制项目。**

一开始的设想是「从 GitHub 拉一个远程控制项目，装到操作机上，就能操控目标机」。这条路走不通，
原因是位置错了：

- 仓库下载下来只存在于**操作机**上；
- 目标机上没有任何可被连入的服务（实测 25 个常见端口全关，见 §3）；
- 操作机没有通道把任何东西推过去。

所以顺序必须反过来：**先在目标机上做一次性开通，之后才谈工具选型**。而开通之后，
Windows 已经内置了能提供「远程 shell + 文件传输」的全部能力，不需要第三方仓库。

> 唯一需要 GitHub 的场景是**可选功能装不上**（精简版 / LTSC），此时才装
> [PowerShell/Win32-OpenSSH](https://github.com/PowerShell/Win32-OpenSSH) 的 MSI。见 §5 方案 D。

## 2. 判据：怎么从网络侧认出一台封闭主机

以下六步按「代价从低到高」排，全部只读、不触碰目标机。后续遇到同类问题可直接复用。

| 步骤 | 命令（操作机上执行） | 看什么 |
|---|---|---|
| 1. 是否在线 | `ping <HOST-IP>` | 有回包即有主机；看 **TTL** 粗判系统 |
| 2. 有哪些服务 | `for p in 22 80 443 445 3389 5985 5986 8080 ...; do (echo > /dev/tcp/<HOST-IP>/$p) 2>/dev/null && echo "OPEN $p"; done` | 开放端口清单 |
| 3. NetBIOS 名称 | `nbtstat -A <HOST-IP>` | 有名字 → 大概率 Windows；无响应 → 名称服务被关或不是 Windows |
| 4. DHCP 租约 | 路由器上 `cat /tmp/dhcp.leases` | 租约里**没有主机名**说明设备没上报 hostname（手机、隐私设置、或被关） |
| 5. 有线还是无线 | 路由器上 `bridge fdb show br-lan`、`iw dev <wlan> station dump` | 出现在 station dump 里 → WiFi 客户端；只在 fdb 里 → 接网线 |
| 6. 设备发现 | SSDP `M-SEARCH` 到 `239.255.255.250:1900`；mDNS 到 `224.0.0.251:5353` | 有响应可拿到 `SERVER` / `ST` 字段；全静默说明设备不播报 |

**TTL 的局限**：TTL 只在没有中间设备改写时可信。Windows 默认 128、Linux/Android/iOS 默认 64，
但这台机实测回 **64** 却是 Windows —— 说明中间有改写（虚拟网卡 / VPN / 第三方协议栈）。
**所以 TTL 只能当线索，不能当结论**，最终以用户确认为准。这条已记进 [PITFALLS.md](PITFALLS.md) P4。

## 3. 实测结果

目标机记为 `<HOST>`，标识值一律脱敏（真值见 `.work/`，不入库）。

| 探测项 | 结果 |
|---|---|
| ICMP | 通，3 包 0 丢，**TTL=64** |
| TCP 端口 | 25 个常见端口**全部关闭**：`22 80 443 139 445 3389 5985 5986 5555 62078 8009 8080 8443 5000 5001 9000 32400 1883 9100 5357 7681 3000 8123 8888 62080` |
| NetBIOS 名称查询 | 无响应 |
| DHCP 租约主机名 | 无（设备未上报） |
| 路由器桥接表 | WiFi 客户端，5GHz，80MHz / HE-MCS11 / 双流，协商 1200 Mbps |
| SSDP 发现 | 全网无响应 |
| MAC | `<REDACTED-MAC>`（本地管理位=1，**随机化 MAC**） |

## 4. 判读

**ICMP 通 + 全部 TCP 关闭**这个组合，在 Windows 上有唯一自然的解释：

- Windows 防火墙默认**拒绝所有入站连接**；
- 但网络位置为「专用」时，「文件和打印机共享（回显请求）」规则默认放行 ICMPv4；
- 于是这台机**能被 ping 通、但没有任何服务在监听**。

这与「刚装好、没开任何共享服务」的 Windows 完全一致。**不是故障，是默认状态。**

另两条辅助证据：

- **随机化 MAC** + **无 DHCP 主机名** + **SSDP 静默** → 现代 Windows 11 的默认隐私行为
  （随机硬件地址、关闭网络发现）；
- **WiFi 客户端**而非有线 → 是笔记本或带无线网卡的台式机，不是服务器。

> 结论：这是一台**默认配置、没有对外开放任何服务**的 Windows。要远程接管，必须先主动开通一个入口。

## 5. 四条路

| 方案 | 做法 | 优点 | 缺点 | 结论 |
|---|---|---|---|---|
| **A. 系统自带 OpenSSH Server** | 装可选功能 + 起服务 + 放行 22 + 写公钥 | 无第三方依赖；shell + 文件传输齐全；可密钥登录；可审计 | 需要管理员权限跑一次 | ✅ **推荐** |
| B. WinRM | `Enable-PSRemoting -Force`，操作机用 `winrs` | 也是系统自带 | 工作组环境要配 `TrustedHosts`，还要处理 Negotiate/Basic 认证；没有 `scp` 式传输 | 次选 |
| C. RDP + 图形化操作 | 开远程桌面，操作机上驱动远程桌面窗口 | 能点图形界面 | **家庭版不能做服务端**；慢、占屏、易点偏；无法脚本化 | 只在必须 GUI 时用 |
| D. Win32-OpenSSH MSI | 装 GitHub 上的官方 MSI | 适用于可选功能缺失的精简版 | 需要先确认 A 真的不可用 | 回退 |

### 方案 A 为什么是默认选择

1. **零新增信任面**：不引入第三方常驻进程，SSH 是 Windows 官方组件。
2. **能力足够**：`ssh` 执行命令、`scp` / `sftp` 传文件、`ssh -L` 做临时端口转发 —— 部署类工作全覆盖。
3. **可收回**：一条 `Remove-WindowsCapability` 就能回到原状，见 [ARCHITECTURE.md](ARCHITECTURE.md) §5。
4. **可审计**：`sshd` 的登录日志进 Windows 事件日志，谁在什么时候进来有记录。

### 为什么先不考虑第三方远程控制项目

RustDesk、MeshCentral 这类工具解决的是「**图形界面接管 + 跨公网**」，代价是要在目标机装常驻代理、
要维护一个中继/服务端、还要处理它自己的账号体系。在**同一个局域网、只需要 shell** 的场景里，
这些代价全是净损失。等真的需要 GUI 了再单独评估，不要一上来就上重型方案。

## 6. 改动清单

### 6.1 目标机（一次性，约 2 分钟，需管理员）

1. 启用 `OpenSSH.Server` 可选功能
2. `sshd` 设为自启并启动
3. 放行 TCP 22（能力安装通常自动建规则，脚本带兜底）
4. 把操作机公钥写入正确的授权文件，并收紧 ACL

由 `host/bootstrap-openssh.ps1` 一把做完，逐项细节见 [ARCHITECTURE.md](ARCHITECTURE.md) §2。

### 6.2 操作机

- 无需安装任何东西：`ssh` 客户端与密钥已就绪。
- 复制 `host/host.conf.example` → `host/host.conf`，填目标机地址与用户名（不入库）。

### 6.3 明确不做

- 不往仓库里加第三方仓库或二进制
- 不在路由器上做 WAN 端口转发
- 不改目标机的默认 shell、UAC、组策略

## 7. 风险与回退

| 风险 | 说明与对策 |
|---|---|
| 暴露 22 端口 | 只在局域网监听；不做 WAN 转发；可加 `ListenAddress <HOST-IP>` 限定网卡 |
| 弱口令爆破 | 开通后**关闭密码认证**（`-DisablePasswordAuth`），只留密钥；顺序见 [ARCHITECTURE.md](ARCHITECTURE.md) §4 |
| 密钥文件权限过宽 | `administrators_authorized_keys` 必须断继承只留 `Administrators` + `SYSTEM`，否则 `sshd` 静默忽略该文件并退回密码认证（[PITFALLS.md](PITFALLS.md) P1） |
| 把自己锁在外面 | **先验证密钥登录可用，再关密码认证**。顺序反了就得去机器前面操作 |
| 需要撤销 | 见 [ARCHITECTURE.md](ARCHITECTURE.md) §5 |

## 8. 验收

三项全过才算开通成功：

1. `ssh <HOST-USER>@<HOST-IP> hostname` 返回目标机主机名，**且不提示输入密码**
2. 一个临时文件传到目标机、在那边算哈希比对、再删除（双向传输可用）
3. 能执行 PowerShell 而不只是 cmd（`$PSVersionTable.PSVersion` 有输出）

`python tools/verify-host.py --conf host/host.conf` 就是把这三项做成可执行版本。

## 9. 待确认项

1. **目标机的登录用户名 + 是否管理员账户** —— 决定公钥写 `administrators_authorized_keys`
   还是 `C:\Users\<HOST-USER>\.ssh\authorized_keys`。不知道就在目标机跑 `whoami`
   和 `net localgroup administrators`。
2. **走哪条路** —— 推荐方案 A。除非是家庭版且明确需要 GUI（才考虑 C），或可选功能缺失（才考虑 D）。
3. **要部署什么** —— 决定开通之后是否需要额外准备服务托管工具：
   - 常驻后台服务 → 需要 [WinSW](https://github.com/winsw/winsw) 这类服务包装器（**这时才值得拉仓库**）
   - Python / Node 应用 → 一般不需要
   - 容器 → 需要 Docker Desktop，是另一套流程
   - 只是装软件 / 改配置 → 什么都不用拉
