<div align="center">

<img src="assets/logo.png" width="128" alt="WindowsRemoteOps">

# WindowsRemoteOps

**把局域网里的 Windows 主机变成可远程运维的节点**

能用系统自带的就别装第三方，要改的只做最小化改动。

![CI](https://github.com/MVennn/WindowsRemoteOps/actions/workflows/ci.yml/badge.svg) ![源码仓库](https://img.shields.io/badge/源码仓库-GitHub-181717?logo=github&logoColor=white) ![问题反馈](https://img.shields.io/badge/问题反馈-Issues-181717?logo=github&logoColor=white) ![Windows](https://img.shields.io/badge/Windows-10%201809%2B%20%2F%2011-0078D4?logo=windows&logoColor=white) ![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white) ![License](https://img.shields.io/badge/License-MIT-blue)

</div>

---

## 这是什么

一台刚装好的 Windows，默认防火墙把入站全关了 —— 你能 ping 通它，但连不进去，也传不了文件。本仓解决的就是这一步：**用 Windows 自带的 OpenSSH Server 打通一条密钥登录的通道**，之后从局域网另一台机器就能执行命令、传文件、跑部署。

分三块。

**开通与验证**（`host/`、`tools/`）：`host/bootstrap-openssh.ps1` 在目标机上一把做完「装能力、设自启、放行端口、写公钥、收紧 ACL」；`tools/verify-host.py` 在操作机上验连通、验密钥、验文件传输、验 PowerShell 能跑。

**踩点结论**（`docs/RECON-WINDOWS-SSH.md`）：从网络侧怎么判断一台封闭主机的状态（端口全关但 ping 通意味着什么）、四个接入方案的对比与取舍、为什么不该先去 GitHub 找一个远程控制项目。

**排错与踩坑**（`docs/PITFALLS.md`、`docs/TROUBLESHOOTING.md`）：`administrators_authorized_keys` 的 ACL、默认 shell 不是 PowerShell、家庭版没有 RDP、随机化 MAC 让 DHCP 租约认不出主机 —— 每条都写清「为什么错」和「下次怎么避」。

边界是：**只做开通与运维通道，不做图形界面接管**。要 GUI 请用 RDP，本仓不包装它。会改目标机哪些状态见 [docs/ARCHITECTURE.md](https://github.com/MVennn/WindowsRemoteOps/blob/main/docs/ARCHITECTURE.md)，每个脚本干什么见 [docs/TOOLS.md](https://github.com/MVennn/WindowsRemoteOps/blob/main/docs/TOOLS.md)。

## 环境要求

| 项 | 要求 |
|---|---|
| 目标机 | Windows 10 1809+ 或 Windows 11；**管理员权限**（装可选功能要） |
| 操作机 | 任意带 `ssh` 客户端的系统（Windows 10+ 自带 OpenSSH Client）；`tools/verify-host.py` 需 Python 3.8+ |
| 网络 | 操作机能直连目标机的 22 端口（同一局域网即可，不需要端口转发） |
| 目标机能力 | `OpenSSH.Server` 可选功能；缺失时走 [docs/RECON-WINDOWS-SSH.md](https://github.com/MVennn/WindowsRemoteOps/blob/main/docs/RECON-WINDOWS-SSH.md) 的方案 D |

## 使用

1. 克隆仓库（`git clone https://github.com/MVennn/WindowsRemoteOps.git`），把主机配置复制成你自己的：`cp host/host.conf.example host/host.conf`，填上目标机地址、用户名、端口。
2. 把 `host/bootstrap-openssh.ps1` 和你的公钥带到目标机上，在**管理员 PowerShell**里跑：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\bootstrap-openssh.ps1 -PublicKeyFile .\id_ed25519.pub
   ```

   脚本默认只做「装能力 + 起服务 + 放行 22 + 写公钥 + 收紧 ACL」，不改默认 shell、不改 `sshd_config` 的其他项。每一项都会打印它做了什么。
3. 回操作机验证：

   ```sh
   python tools/verify-host.py --conf host/host.conf
   ```

   四项全绿才算通：密钥登录、命令执行、文件传输、PowerShell 可用。任何一项失败，按输出的提示查 [docs/TROUBLESHOOTING.md](https://github.com/MVennn/WindowsRemoteOps/blob/main/docs/TROUBLESHOOTING.md)。
4. 确认能用之后，建议关掉密码认证只留密钥 —— 步骤见 [docs/ARCHITECTURE.md](https://github.com/MVennn/WindowsRemoteOps/blob/main/docs/ARCHITECTURE.md) 的「加固」一节。

## 反馈

脚本在你的机器上跑不通、验证项对不上、想要新的运维能力，到 [Issues](https://github.com/MVennn/WindowsRemoteOps/issues) 反馈。请带上：

- 目标机的 Windows 版本（`winver`）
- 执行的完整命令与参数
- 报错原文（贴之前先抹掉主机名、用户名与公钥内容）

踩过的坑见 [docs/PITFALLS.md](https://github.com/MVennn/WindowsRemoteOps/blob/main/docs/PITFALLS.md)，按现象查见 [docs/TROUBLESHOOTING.md](https://github.com/MVennn/WindowsRemoteOps/blob/main/docs/TROUBLESHOOTING.md)。想参与贡献见 [CONTRIBUTING](https://github.com/MVennn/WindowsRemoteOps/blob/main/CONTRIBUTING.md)，安全问题按 [SECURITY](https://github.com/MVennn/WindowsRemoteOps/blob/main/SECURITY.md) 报告。

## 免责声明

本项目仅供学习与个人运维使用。

- `host/bootstrap-openssh.ps1` **会改目标机的系统状态**（安装可选功能、改服务启动类型、加防火墙规则、写 `administrators_authorized_keys`）。执行前先看清楚它会改什么，最好先备份相关文件。
- 开通 SSH 等于给这台机器开了一个远程入口。**只在你自己的机器、自己的局域网里用**，不要把 22 端口映射到公网；确认可用后立刻关掉密码认证。
- 本仓库**不保存任何凭据** —— 私钥留在你自己的 `~/.ssh/`，主机名与用户名放 `host/host.conf`（不入库），位置见 [docs/SECRETS.md](https://github.com/MVennn/WindowsRemoteOps/blob/main/docs/SECRETS.md)。
- 所有结论都是在特定 Windows 版本与网络环境下实测的，换环境后**必须重新验证**。
- 使用本项目造成的任何后果由使用者自行承担。

「Windows」「PowerShell」「OpenSSH」等名称与标识的权利均归其各自权利人所有。本项目与之不存在任何隶属、合作、授权、认可或支持关系。

## 开源鸣谢

本仓库建立在这些开源项目之上（详见 [NOTICE](https://github.com/MVennn/WindowsRemoteOps/blob/main/NOTICE)）：

| 项目 | 用途 |
|---|---|
| [**OpenSSH**](https://www.openssh.com/) | 全部远程操作的传输层；Windows 上以 `OpenSSH.Server` 可选功能形式提供 |
| [**OpenSSH for Windows**](https://github.com/PowerShell/Win32-OpenSSH) | 可选功能不可用时的 MSI 回退方案（本仓不分发） |
| [**PowerShell**](https://github.com/PowerShell/PowerShell) | `host/` 脚本的运行环境 |
| [**Python**](https://www.python.org/) | `tools/` 自检脚本的运行时 |

## 许可证

本仓库以 [MIT License](https://github.com/MVennn/WindowsRemoteOps/blob/main/LICENSE) 发布；第三方组件的版权与许可证声明见 [NOTICE](https://github.com/MVennn/WindowsRemoteOps/blob/main/NOTICE)。
