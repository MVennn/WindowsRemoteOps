#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""验证到 Windows 主机的 SSH 通道：密钥登录 / 命令执行 / 文件传输 / PowerShell。

用法：
    python tools/verify-host.py --conf host/host.conf
    python tools/verify-host.py --conf host/host.conf --dry-run
    python tools/verify-host.py --host <HOST-IP> --user <HOST-USER>

退出码：0 四项全通过 / 1 有项目失败 / 2 配置缺失或不可读。

为什么要有这个脚本：`ssh` 连不上时的报错几乎不区分原因 —— 端口没开、防火墙拦了、
公钥写错文件、ACL 太宽、密码认证被关，全都长得差不多。这里把四件事分开测，
失败时直接给出 docs/TROUBLESHOOTING.md 的条目号。
"""
from __future__ import annotations

import argparse
import hashlib
import os
import secrets
import socket
import subprocess
import sys
import tempfile

CONF_DEFAULT = os.path.join("host", "host.conf")
TIMEOUT = 15


class ConfError(Exception):
    pass


def read_conf(path: str) -> dict:
    """读 key=value 配置；# 与空行忽略。文件不存在时抛 ConfError。"""
    if not os.path.isfile(path):
        raise ConfError(
            "找不到 %s —— 先复制样例：cp host/host.conf.example host/host.conf" % path
        )
    conf = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for lineno, raw in enumerate(fh, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                raise ConfError("%s:%d 不是 key=value 形式：%s" % (path, lineno, line))
            key, _, value = line.partition("=")
            conf[key.strip().lower()] = value.strip()
    return conf


def is_placeholder(value: str) -> bool:
    return not value or (value.startswith("<") and value.endswith(">"))


def build_ssh_base(args) -> list:
    cmd = [
        "ssh",
        "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "ConnectTimeout=10",
        "-p", str(args.port),
    ]
    if args.identity:
        cmd += ["-i", os.path.expanduser(args.identity)]
    return cmd


def run(cmd: list, timeout: int = TIMEOUT) -> tuple:
    """返回 (returncode, stdout, stderr)；超时返回 (-1, '', 'timeout')。"""
    try:
        proc = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout,
            encoding="utf-8", errors="replace",
        )
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except subprocess.TimeoutExpired:
        return -1, "", "timeout"
    except FileNotFoundError as exc:
        return -2, "", "找不到命令：%s" % exc


def hint_for(stderr: str) -> str:
    """把 ssh 的报错映射到排错手册条目。"""
    low = stderr.lower()
    if "connection refused" in low:
        return "T1（sshd 没起或没在监听）"
    if "timed out" in low or "timeout" in low:
        return "T2（防火墙 / 网络位置 / 地址不对）"
    if "permission denied" in low or "no such identity" in low:
        return "T3（公钥文件写错、ACL 过宽、或私钥没带对）"
    if "host key verification failed" in low:
        return "T3 变体（known_hosts 冲突：目标机重装过？）"
    if "connection closed" in low or "connection reset" in low:
        return "T4（登录后立刻断开）"
    return "TROUBLESHOOTING.md 逐条查"


def tcp_probe(host: str, port: int) -> tuple:
    try:
        with socket.create_connection((host, port), timeout=5) as sock:
            sock.settimeout(3)
            try:
                banner = sock.recv(64).decode("utf-8", "replace").strip()
            except (socket.timeout, OSError):
                banner = ""
        return True, banner
    except OSError as exc:
        return False, str(exc)


def check_key_login(ssh_base: list, target: str) -> tuple:
    cmd = ssh_base + [
        "-o", "PreferredAuthentications=publickey",
        "-o", "PasswordAuthentication=no",
        target, "hostname",
    ]
    rc, out, err = run(cmd)
    if rc == 0 and out:
        return True, out.splitlines()[0]
    return False, err or ("退出码 %d" % rc)


def check_command(ssh_base: list, target: str, marker: str) -> tuple:
    cmd = ssh_base + [target, "echo", marker]
    rc, out, err = run(cmd)
    if rc == 0 and marker in out:
        return True, out
    return False, err or out or ("退出码 %d" % rc)


def check_transfer(ssh_base: list, target: str, remote_name: str) -> tuple:
    """上传 → 取回 → 比哈希 → 删远端。全程用相对路径（sshd 的 CWD 是用户目录）。"""
    if not shutil_which("scp"):
        return False, "找不到 scp 命令"
    payload = secrets.token_hex(32).encode()
    local_digest = hashlib.sha256(payload).hexdigest()
    tmpdir = tempfile.mkdtemp(prefix="wro-verify-")
    src = os.path.join(tmpdir, "payload.bin")
    back = os.path.join(tmpdir, "payload.back")
    with open(src, "wb") as fh:
        fh.write(payload)

    port_args = ["-P", str(ssh_base[ssh_base.index("-p") + 1])]
    ident_args = []
    if "-i" in ssh_base:
        ident_args = ["-i", ssh_base[ssh_base.index("-i") + 1]]

    def scp(args: list) -> tuple:
        return run(["scp", "-q", "-o", "BatchMode=yes",
                    "-o", "StrictHostKeyChecking=accept-new"] + port_args + ident_args + args)

    try:
        rc, _, err = scp([src, "%s:%s" % (target, remote_name)])
        if rc != 0:
            return False, "上传失败：%s" % (err or ("退出码 %d" % rc))
        rc, _, err = scp(["%s:%s" % (target, remote_name), back])
        if rc != 0:
            return False, "取回失败：%s" % (err or ("退出码 %d" % rc))
        with open(back, "rb") as fh:
            got = hashlib.sha256(fh.read()).hexdigest()
        if got != local_digest:
            return False, "往返内容不一致（上传后取回哈希不同）"
        return True, "往返一致，%d 字节" % len(payload)
    finally:
        # 无论成败都尝试清理远端临时文件
        run(ssh_base + [target, "powershell", "-NoProfile", "-Command",
                        "Remove-Item -LiteralPath '%s' -Force -ErrorAction SilentlyContinue" % remote_name],
            timeout=10)
        for path in (src, back):
            try:
                os.remove(path)
            except OSError:
                pass
        try:
            os.rmdir(tmpdir)
        except OSError:
            pass


def check_powershell(ssh_base: list, target: str) -> tuple:
    cmd = ssh_base + [target, "powershell", "-NoProfile", "-Command",
                      "(Get-Host).Version.ToString()"]
    rc, out, err = run(cmd)
    if rc == 0 and out:
        return True, out.splitlines()[0]
    return False, err or out or ("退出码 %d" % rc)


def shutil_which(name: str) -> bool:
    from shutil import which
    return which(name) is not None


def main() -> int:
    parser = argparse.ArgumentParser(description="验证到 Windows 主机的 SSH 通道")
    parser.add_argument("--conf", default=CONF_DEFAULT, help="主机配置路径（默认 host/host.conf）")
    parser.add_argument("--host", help="覆盖配置里的 host")
    parser.add_argument("--user", help="覆盖配置里的 user")
    parser.add_argument("--port", type=int, help="覆盖配置里的 port")
    parser.add_argument("--identity", help="私钥路径（默认交给 ssh 自己找）")
    parser.add_argument("--dry-run", action="store_true",
                        help="只做只读探测（TCP 连通 + SSH 横幅），不登录、不传文件")
    args = parser.parse_args()

    # 命令行把 host 与 user 都给全了就不需要配置文件；否则必须能读到。
    need_conf = not (args.host and args.user)
    try:
        conf = read_conf(args.conf) if (need_conf or os.path.isfile(args.conf)) else {}
    except ConfError as exc:
        print("✗ %s" % exc, file=sys.stderr)
        print("  条目：T8", file=sys.stderr)
        return 2

    args.host = args.host or conf.get("host", "")
    args.user = args.user or conf.get("user", "")
    args.port = args.port or int(conf.get("port") or 22)
    args.identity = args.identity or conf.get("identity", "")

    if is_placeholder(args.host) or is_placeholder(args.user):
        print("✗ host / user 仍是占位符，或缺失。", file=sys.stderr)
        print("  在 %s 里填真值，或用 --host / --user 覆盖。条目：T8" % args.conf, file=sys.stderr)
        return 2

    target = "%s@%s" % (args.user, args.host)
    print("目标：%s  端口：%d" % (target, args.port))
    print("-" * 60)

    ok, detail = tcp_probe(args.host, args.port)
    if not ok:
        print("✗ TCP %d 不可达：%s" % (args.port, detail))
        print("  条目：T2（防火墙 / 网络位置 / 地址不对）")
        return 1
    print("✓ TCP %d 可达%s" % (args.port, ("，横幅：" + detail) if detail else ""))

    if args.dry_run:
        print("-" * 60)
        print("dry-run：只做了只读探测，未登录、未传文件。")
        return 0

    ssh_base = build_ssh_base(args)
    marker = "wro-" + secrets.token_hex(6)
    remote_name = marker + ".bin"

    checks = [
        ("密钥登录", lambda: check_key_login(ssh_base, target)),
        ("命令执行", lambda: check_command(ssh_base, target, marker)),
        ("文件传输", lambda: check_transfer(ssh_base, target, remote_name)),
        ("PowerShell", lambda: check_powershell(ssh_base, target)),
    ]

    failed = []
    for name, fn in checks:
        passed, detail = fn()
        if passed:
            print("✓ %s：%s" % (name, detail))
        else:
            print("✗ %s：%s" % (name, detail))
            print("  条目：%s" % hint_for(detail))
            failed.append(name)

    print("-" * 60)
    if failed:
        print("✗ %d/%d 项失败：%s" % (len(failed), len(checks), "、".join(failed)))
        return 1
    print("✓ 四项全部通过，通道可用。")
    print("  下一步：确认密钥登录稳定后，再用 -DisablePasswordAuth 关闭密码认证。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
