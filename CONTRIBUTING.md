# 参与贡献

> **一句话**：怎么把东西跑起来、改脚本守什么规矩、提交前跑什么。

## 跑起来

```sh
# 主机配置：复制样例后按自己的环境改（该文件不入库）
cp host/host.conf.example host/host.conf

# 操作机侧验证（只读，不改目标机）
python tools/verify-host.py --conf host/host.conf --dry-run
python tools/verify-host.py --conf host/host.conf
```

> `host/bootstrap-openssh.ps1` **会改目标机的系统状态**。执行前先读
> [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) 的「会改什么」一节。

## 硬规矩

### 1. 主机相关的值一律外置（脱敏红线）

**不许**把下面这些写进源码、文档、示例、日志、提交信息：

| 类别 | 例子 | 该放哪 |
|---|---|---|
| 主机地址 | 局域网 IP、IPv6、DDNS 名 | `host/host.conf` |
| 主机标识 | 计算机名、MAC、WiFi SSID | 哪都不该放 |
| 账户 | 登录用户名、域/工作组名 | `host/host.conf` |
| 凭据 | 口令 / 私钥 / passphrase | `~/.ssh/`，仓库里只有占位符 |
| 本机绝对路径 | 你的家目录 | 相对路径或 `~` 推导 |
| 真机实测记录 | 探测输出、`ssh -v` 日志 | `.work/` |

**占位符写法**：`<REDACTED-...>`（凭据）、`<REPLACE-...>`（需要你自己填的值）、
`<HOST-IP>` / `<HOST-USER>`（主机与账户）。

提交前跑 `python tools/check-secrets.py --all` —— 这是红线的可执行版本。

### 2. 逻辑不要动

改脚本时**只改「值从哪来」**，不要顺手重构判定逻辑 —— 这些脚本在真实主机上跑着，
行为变更需要真机验证。

### 3. 格式

- `host/*.ps1` **必须纯 ASCII**：Windows PowerShell 5.1 读 UTF-8 无 BOM 的中文会乱码，
  可能直接解析失败。注释用英文。
- Python 只用标准库（`tools/make_social_preview.py` 例外，它需要 numpy + Pillow）。
- 所有文本文件 **LF 换行**（`.gitattributes` 已锁）。

## 文档

规则见 [docs/DOC-RULES.md](docs/DOC-RULES.md)（单一正本、每篇开头一句话引言块、
索引唯一、孤儿零容忍）。改完跑：

```bash
python tools/check-docs.py
```

## 提交前自检

```bash
# PowerShell 语法（需要 pwsh 或 Windows PowerShell）
pwsh -NoProfile -Command '$e=$null; [System.Management.Automation.Language.Parser]::ParseFile("host/bootstrap-openssh.ps1",[ref]$null,[ref]$e); if($e){$e; exit 1}'

# Python 语法
python -c "import ast,glob; [ast.parse(open(f,encoding='utf-8').read(), f) for f in glob.glob('**/*.py', recursive=True)]"

# 文档 + 脱敏
python tools/check-docs.py
python tools/check-secrets.py --all
```

CI（`.github/workflows/ci.yml`）跑的就是这几样。

## 提交信息

Conventional Commits：`feat:` `fix:` `docs:` `chore:` `refactor:` `test:` `perf:`。
多个改动**按对象拆行**（一行一个对象），不要打包成「代码整理」。
