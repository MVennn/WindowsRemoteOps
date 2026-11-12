# 工具清单

> **一句话**：工具清单（**正本**）：每个脚本干什么、会不会改目标机状态、怎么调。

---

## 1. 清单

| 脚本 | 跑在哪 | 干什么 | 会改状态吗 |
|---|---|---|---|
| `host/bootstrap-openssh.ps1` | 目标机（管理员 PowerShell） | 装 `OpenSSH.Server`、设自启、放行 22、写公钥、收紧 ACL | **会** —— 见 [ARCHITECTURE.md](ARCHITECTURE.md) §2 |
| `tools/verify-host.py` | 操作机 | 四项验证：密钥登录 / 命令执行 / 文件传输 / PowerShell 可用 | 不改；`--dry-run` 连临时文件都不写 |
| `tools/check-docs.py` | 操作机 / CI | 文档自检：断链、失效锚点、缺引言块、孤儿文档 | 不改 |
| `tools/check-secrets.py` | 操作机 / CI | 脱敏扫描：私钥、token、本机绝对路径、真实邮箱 | 不改 |
| `tools/make_social_preview.py` | 操作机 | 从 `assets/icon.svg` 渲染 `logo.png` 与 `social-preview.png` | 只写 `assets/` |

## 2. 目录结构

```text
WindowsRemoteOps/
├── host/                        目标机侧
│   ├── bootstrap-openssh.ps1    一次性开通（纯 ASCII）
│   └── host.conf.example        主机配置模板（只有占位符）
├── tools/                       操作机侧
│   ├── verify-host.py           四项验证
│   ├── check-docs.py            文档自检
│   ├── check-secrets.py         脱敏扫描
│   └── make_social_preview.py   门面资源渲染
├── docs/                        文档（索引见 docs/README.md）
├── assets/                      门面资源（icon.svg 是正本）
└── .github/                     Issue 表单与 CI
```

## 3. 用法

### 3.1 目标机侧（一次性）

把 `host/bootstrap-openssh.ps1` 与你的公钥拷到目标机，在**管理员 PowerShell** 里：

```powershell
powershell -ExecutionPolicy Bypass -File .\bootstrap-openssh.ps1 -PublicKeyFile .\id_ed25519.pub
```

| 参数 | 必填 | 说明 |
|---|---|---|
| `-PublicKeyFile` | ✅ | 公钥文件路径（`.pub`）。内容会被追加到正确的授权文件 |
| `-User` | ❌ | 公钥归属的账户，默认当前登录用户；**决定写哪个授权文件** |
| `-Port` | ❌ | 防火墙放行端口，默认 22；脚本标注 `[ValidateRange(1, 65535)]`，越界在参数绑定阶段就报错 |
| `-DisablePasswordAuth` | ❌ | 显式要求关掉密码认证与 keyboard-interactive（两条都写 `no`）并重启 `sshd`；默认不动 `sshd_config` |
| `-WhatIf` | ❌ | 只打印将要做什么，不执行 |

### 3.2 操作机侧

```sh
cp host/host.conf.example host/host.conf    # 填 host / user
python tools/verify-host.py --conf host/host.conf --dry-run   # 只读探测
python tools/verify-host.py --conf host/host.conf             # 四项验证
```

退出码：`0` 全通过 / `1` 有项目失败 / `2` 配置缺失或不可读。
失败项会打印对应 [TROUBLESHOOTING.md](TROUBLESHOOTING.md) 的条目号。

### 3.3 自检

```sh
python tools/check-docs.py
python tools/check-secrets.py --all
```

CI 跑的就是这两条，外加 Python 语法与 PowerShell 解析。
