# AGENTS —— 机器协议

> **一句话**：三条硬规矩 —— **PROGRESS 按逻辑任务分家**、**主机相关的值一律外置**、
> **有 CodeGraph 就先用 CodeGraph**。其它都能从 [docs/](docs/README.md) 里查到。

---

## 1. PROGRESS：路径由逻辑任务决定，不是物理目录

- 每个逻辑任务目录内有**且仅有一个** `PROGRESS.md`（追加式批次日志）。
- 子代理**只写自己的分片文件**（`evidence/agent-<name>.md` 这类），
  **绝不写任何共享文件** —— 历史上并行子代理互相覆盖过同一个 PROGRESS。
- 分片写完同步根 `PROGRESS.md`。

## 2. 主机相关的值一律外置（脱敏红线）

**不许把下面这些写进源码、文档、示例、日志、提交信息**：

| 类别 | 例子 | 该放哪 |
|---|---|---|
| 主机地址 | 局域网 IP、IPv6、DDNS 名 | `host/host.conf`（不入库） |
| 主机标识 | 计算机名、MAC、WiFi SSID、DHCP 租约主机名 | 哪都不该放 |
| 账户 | 登录用户名、域/工作组名 | `host/host.conf`（不入库） |
| 凭据 | 口令 / 私钥 / passphrase | `~/.ssh/` 与密码管理器，仓库里只有占位符 |
| 本机绝对路径 | `C:\Users\<你>` / `/home/<你>` | 相对路径或 `~` 推导 |
| 真机实测记录 | 具体主机的探测输出、`ssh -v` 日志 | `.work/`（不入库） |

**占位符写法**：`<REDACTED-...>`（凭据）、`<REPLACE-...>`（需要你自己填的值）、
`<HOST-IP>` / `<HOST-USER>`（主机与账户）。示例文件只用这些占位符。

判断标准很简单：**这段文字贴到公开 Issue 里，会不会暴露某台具体机器的身份或入口？**
会，就不能进版本库。

## 3. CodeGraph

仓库根有 `.codegraph/` 时，**先 `codegraph_explore` 找代码，再 grep**。
没有就跳过 —— 别为此手动建索引。

```bash
codegraph explore "verify-host.py 校验逻辑"
```

---

## 其他约定（详见 docs/DOC-RULES.md）

- 每篇文档开头必须有 `> **一句话**：…` 引言块（根 README 与 `docs/release-notes/` 除外）。
- 相对链接 + 半角括号；改文档后跑 `python tools/check-docs.py`。
- 提交前跑 `python tools/check-secrets.py --all` —— 脱敏红线的可执行版本。
- `host/*.ps1` **必须纯 ASCII**：UTF-8 无 BOM 的中文注释在 Windows PowerShell 5.1 下会乱码，
  甚至让脚本解析失败。
- 提交信息用 Conventional Commits，**按对象拆行**。
