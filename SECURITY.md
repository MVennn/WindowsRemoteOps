# 安全策略

> **一句话**：发现安全问题怎么报、**这些脚本会改目标机的哪些状态**、边界在哪。

## 支持的版本

| 分支 | 收修 |
|---|---|
| `main` | ✅ 修 bug 与安全问题 |

## 怎么报告

**请不要开公开 Issue 报告安全问题。** 用 GitHub 的
「Security → Report a vulnerability」提私有报告：
<https://github.com/MVennn/WindowsRemoteOps/security/advisories/new>

报告里请写清：受影响的文件 / 触发条件 / 影响面（谁能做什么）/ 你建议的修法。

## 这个仓会改你的机器

**这是本仓与一般工具库最大的不同** —— 下面这些操作**会动手**：

| 操作 | 会改什么 | 触发方式 |
| --- | --- | --- |
| `host/bootstrap-openssh.ps1` | 安装 `OpenSSH.Server` 可选功能、把 `sshd` 设为自启并启动、加防火墙规则、写 `administrators_authorized_keys` 并收紧其 ACL | 手动（管理员 PowerShell） |
| 同上的 `-DisablePasswordAuth` 开关 | 改 `sshd_config` 的 `PasswordAuthentication` 并重启 `sshd` | 手动，需显式加开关 |
| `tools/verify-host.py` | **什么都不改**，只做只读探测与一次临时文件往返 | 手动 |

它**不会**做的事（这是设计约束，不是巧合）：

- ❌ 不改你的用户密码、不创建新账户
- ❌ 不动 UAC 设置、不改组策略
- ❌ 不做端口转发、不把 22 暴露到公网
- ❌ 不安装第三方远程控制软件
- ❌ 不接管图形界面（要 GUI 请自行使用 RDP；**家庭版不能做 RDP 服务端**，取舍见 [docs/RECON-WINDOWS-SSH.md](docs/RECON-WINDOWS-SSH.md) 的方案 C）

装之前请先看 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) 的「会改什么」一节。

## 凭据

**本仓不存放任何凭据。** SSH 私钥留在你自己的 `~/.ssh/`，
passphrase 留在密码管理器里。位置索引见 [docs/SECRETS.md](docs/SECRETS.md)。

同样地，**主机地址、计算机名、MAC、登录用户名也不该出现在本仓** ——
它们放 `host/host.conf`（不入库），文档与示例只用 `<HOST-IP>` / `<HOST-USER>` 占位符。

## 脱敏红线

开通 SSH 之后，这台机器就有了一个远程入口。任何能拿到**私钥 + 主机地址 + 用户名**的人
都能进去。因此：

- 真机探测输出（含 IP、MAC、计算机名、DHCP 租约）**只放 `.work/`**，不入库；
- 提交前跑 `python tools/check-secrets.py --all`；
- 如果你在任何地方看到明文凭据或主机标识（包括历史记录、示例配置、日志），
  请当作缺陷报上来 —— **不要在公开 Issue 里贴出凭据本身**。
