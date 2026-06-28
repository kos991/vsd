#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')
import paramiko

HOST = "192.168.0.243"
USER = "vyos"
PASS = "vyos"

GREEN  = "\033[92m"; RED = "\033[91m"; CYAN = "\033[96m"; YELLOW = "\033[93m"; RESET = "\033[0m"

def banner(msg): print(f"\n{CYAN}{'='*60}\n  {msg}\n{'='*60}{RESET}")
def ok(msg):  print(f"{GREEN}  [PASS] {msg}{RESET}")
def fail(msg):print(f"{RED}  [FAIL] {msg}{RESET}")
def info(msg):print(f"{YELLOW}  > {msg}{RESET}")

def run(ssh, cmd, timeout=15):
    info(f"$ {cmd}")
    _, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode(errors="replace").strip()
    errt= stderr.read().decode(errors="replace").strip()
    rc  = stdout.channel.recv_exit_status()
    if out:  print(f"    {out}")
    if errt: print(f"    stderr: {errt}")
    return rc, out, errt

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(HOST, username=USER, password=PASS, look_for_keys=False, allow_agent=False)

# ── TEST 1: DNS 绑定确认 ─────────────────────────────────────────
banner("TEST 1: MosDNS 绑定地址确认")
rc, out, _ = run(ssh, "ss -tlnpu | grep ':53'")
if "192.168.0.243:53" in out:
    ok(f"MosDNS 正确绑定在 192.168.0.243:53")
else:
    fail("MosDNS 绑定地址异常")

# ── TEST 2: DNS 国内解析（baidu.com 应走国内 DNS）───────────────
banner("TEST 2: DNS 解析 - 国内域名 (baidu.com)")
rc, out, _ = run(ssh, "dig +short +timeout=5 baidu.com @192.168.0.243")
if out and rc == 0:
    ok(f"baidu.com 解析成功: {out.splitlines()[0]}")
else:
    fail(f"baidu.com 解析失败 (rc={rc})")

# ── TEST 3: DNS 国外解析（google.com 应走 Cloudflare DoH）───────
banner("TEST 3: DNS 解析 - 国外域名 (google.com)")
rc, out, _ = run(ssh, "dig +short +timeout=10 google.com @192.168.0.243")
if out and rc == 0:
    ok(f"google.com 解析成功: {out.splitlines()[0]}")
else:
    fail(f"google.com 解析失败 (rc={rc})")

# ── TEST 4: IPv6 查询应被 REJECT（MosDNS 中 qtype 28 → reject）
banner("TEST 4: IPv6 (AAAA) 查询应被拒绝")
rc, out, _ = run(ssh, "dig +short AAAA baidu.com @192.168.0.243")
if not out or "NXDOMAIN" in out or rc != 0:
    ok(f"AAAA 查询已被拒绝 (预期行为)")
else:
    fail(f"AAAA 未被拒绝，返回: {out}")

# ── TEST 5: DoT 853 应被防火墙拒绝 ──────────────────────────────
banner("TEST 5: DoT TCP 853 应被 nftables REJECT")
rc, out, err = run(ssh, "timeout 3 bash -c 'echo > /dev/tcp/192.168.0.243/853' 2>&1; echo rc=$?")
if "rc=1" in out or rc != 0:
    ok("TCP 853 已被 REJECT（不可达）")
else:
    fail(f"TCP 853 未被拦截: {out}")

# ── TEST 6: daed routing 关键规则验证 ───────────────────────────
banner("TEST 6: config.dae 关键规则确认")
rc, out, _ = run(ssh, "grep -E 'dip\\(1\\.1\\.1\\.1|fallback|geoip:private' /opt/custom-services/daed/config.dae")
checks = {
    "DoH 锚点 dip(1.1.1.1": "dip(1.1.1.1, 1.0.0.1) -> must_direct",
    "fallback: direct":     "fallback: direct",
    "geoip:private 提前":   "dip(geoip:private) -> direct",
}
for label, pattern in checks.items():
    if pattern in out:
        ok(f"{label}")
    else:
        fail(f"{label} 未找到")

# ── TEST 7: nftables DNS Hijack 规则完整性 ───────────────────────
banner("TEST 7: nftables DNS Hijack 规则")
rc, out, _ = run(ssh, "sudo nft list table inet daed_dns_hijack")
for rule in ["udp dport 53 redirect", "tcp dport 53 redirect", "tcp dport 853 reject"]:
    if rule in out:
        ok(f"规则存在: {rule}")
    else:
        fail(f"规则缺失: {rule}")

# ── TEST 8: daed TProxy 端口（eBPF 不一定显示为 LISTEN）────────
banner("TEST 8: daed 进程状态")
rc, out, _ = run(ssh, "ps aux | grep -E '[d]aed|[d]ae-wing' | head -5")
if out:
    ok(f"daed 进程运行中: {out.splitlines()[0][:80]}")
else:
    fail("daed 进程未找到")

# ── TEST 9: 系统日志最近错误 ────────────────────────────────────
banner("TEST 9: 服务日志（最近 10 行）")
run(ssh, "sudo journalctl -u daed.service -n 10 --no-pager 2>/dev/null | tail -10")
run(ssh, "sudo journalctl -u mosdns.service -n 5 --no-pager 2>/dev/null | tail -5")

banner("验证完成", GREEN)
ssh.close()
