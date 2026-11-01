# 凭据与主机配置

> **一句话**：凭据与主机标识的位置索引（**正本**，只写位置不写值）：
> 本仓存什么、不存什么、真值在哪。

---

## 1. 本仓存什么

| 内容 | 存不存 | 位置 |
|---|---|---|
| 公钥（`ssh-ed25519 AAAA...`） | ✅ 存 | 文档与 Issue 模板里的示例位置；**示例只放占位符** |
| 私钥 / passphrase | ❌ 不存 | 操作机的 `~/.ssh/` 与密码管理器 |
| 主机地址（IP / IPv6 / DDNS） | ❌ 不存 | `host/host.conf`（不入库） |
| 登录用户名 / 域 / 工作组 | ❌ 不存 | `host/host.conf`（不入库） |
| 计算机名 / MAC / WiFi SSID | ❌ 不存 | 哪都不该放；真机记录进 `.work/` |
| 真机探测原始输出 | ❌ 不存 | `.work/`（不入库） |

## 2. 真值在哪

| 值 | 真值位置 |
|---|---|
| 目标机地址与用户名 | `host/host.conf`（本地，`.gitignore` 已排除） |
| 私钥 | `~/.ssh/`（默认 `id_ed25519`；`host.conf` 的 `identity` 可覆盖） |
| 公钥 | `~/.ssh/id_ed25519.pub`，拷贝到目标机的授权文件 |
| 真机实测记录 | `.work/`（本地工作区，不入库） |

## 3. 占位符口径

| 占位符 | 代替什么 |
|---|---|
| `<HOST-IP>` | 目标机地址 |
| `<HOST-USER>` | 登录用户名 |
| `<HOST-NAME>` | 计算机名 |
| `<REDACTED-MAC>` | MAC 地址 |
| `<REDACTED-KEY>` | 私钥内容或 passphrase |
| `<REPLACE-...>` | 需要使用者自己填的值 |

## 4. 推送前脱敏

`tools/check-secrets.py` 是本节的可执行版本，扫描三类命中：

1. **凭据形态**：私钥块、GitHub token、云厂商 AK、各类 `sk-` key、订阅链接里的 token
2. **本机绝对路径**：`C:\Users\<真实用户名>`、`/home/<真实用户名>`
3. **真实邮箱**：`@qq.com` / `@163.com` / `@gmail.com` 等（GitHub noreply 地址不在其中）

放行口径：命中片段本身含 `REDACTED` / `REPLACE-` / `<...>` 占位符，或路径呈截断形式
（`C:/Users/...\...`）。**同一行里并排写下的完整真值仍然会被报出来** —— 占位符只豁免它自己那一段。

用法：

```sh
python tools/check-secrets.py          # 只扫已跟踪文件（需要 git）
python tools/check-secrets.py --all    # 扫工作树（含未跟踪，跳过 .git/.work 等）
```

CI 跑的是默认模式；本地开工前建议跑 `--all`。
