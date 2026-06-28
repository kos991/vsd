#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')
import time
import textwrap
import paramiko
from pathlib import Path

HOST = "<YOUR_ROUTER_IP>"
USER = "<YOUR_SSH_USER>"
PASS = "<YOUR_SSH_PASSWORD>"
BASE = "/opt/custom-services"

# 使用相对路径，确保在仓库根目录下运行
LOCAL_DAED_CFG    = Path("packer/custom-services/daed/config.dae")
LOCAL_GEOSITE_SH  = Path("packer/custom-services/scripts/geosite-update.sh")
LOCAL_UPDATE_DAED_SH = Path("packer/custom-services/scripts/update-daed.sh")
LOCAL_MOSDNS_CFG  = Path("packer/custom-services/mosdns/config.yaml")

REMOTE_DAED_CFG   = f"{BASE}/daed/config.dae"
REMOTE_GEOSITE_SH = f"{BASE}/scripts/geosite-update.sh"
REMOTE_UPDATE_DAED_SH = f"{BASE}/scripts/update-daed.sh"
REMOTE_MOSDNS_CFG = f"{BASE}/mosdns/config.yaml"

YELLOW = "\033[93m"
GREEN  = "\033[92m"
RED    = "\033[91m"
CYAN   = "\033[96m"
RESET  = "\033[0m"

def banner(msg, color=CYAN):
    print(f"\n{color}{'='*60}{RESET}")
    print(f"{color}  {msg}{RESET}")
    print(f"{color}{'='*60}{RESET}")

def ok(msg):  print(f"{GREEN}  [OK] {msg}{RESET}")
def err(msg): print(f"{RED}  [ERR] {msg}{RESET}")
def info(msg):print(f"{YELLOW}  > {msg}{RESET}")

def run(ssh, cmd, timeout=30):
    info(f"$ {cmd}")
    _, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode(errors="replace").strip()
    errt = stderr.read().decode(errors="replace").strip()
    rc = stdout.channel.recv_exit_status()
    if out:  print(f"    {out}")
    if errt: print(f"{YELLOW}    stderr: {errt}{RESET}")
    return rc, out, errt

def connect():
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, username=USER, password=PASS,
                look_for_keys=False, allow_agent=False, timeout=15)
    ok(f"SSH 连接成功 → {USER}@{HOST}")
    return ssh

def upload(ssh, local: Path, remote: str):
    sftp = ssh.open_sftp()
    sftp.put(str(local), remote)
    sftp.chmod(remote, 0o644)
    sftp.close()
    ok(f"上传: {local.name} → {remote}")

def main():
    # ── 连接 ────────────────────────────────────────────────────
    banner("STEP 1: 连接 VyOS")
    try:
        ssh = connect()
    except Exception as e:
        err(f"连接失败: {e}")
        sys.exit(1)

    # ── 系统基本信息 ─────────────────────────────────────────────
    banner("STEP 2: 系统基本信息")
    run(ssh, "cat /etc/issue | head -3")
    run(ssh, "uptime")
    run(ssh, "ip -4 addr show scope global | grep inet")

    # ── 部署前状态快照 ───────────────────────────────────────────
    banner("STEP 3: 部署前服务状态")
    run(ssh, "systemctl is-active mosdns.service daed.service 2>&1 || true")
    run(ssh, "ss -tlnp | grep -E ':53|:12345|:2023' || true")

    # ── 备份旧配置 ───────────────────────────────────────────────
    banner("STEP 4: 备份旧配置")
    ts = int(time.time())
    run(ssh, f"cp -v {REMOTE_DAED_CFG} {REMOTE_DAED_CFG}.bak.{ts} 2>/dev/null || true")
    run(ssh, f"cp -v {REMOTE_GEOSITE_SH} {REMOTE_GEOSITE_SH}.bak.{ts} 2>/dev/null || true")

    # ── 上传新配置 ───────────────────────────────────────────────
    banner("STEP 5: 上传修复后的配置文件")
    try:
        # 上传到 /tmp（vyos 用户有权限），再 sudo 移入目标目录
        upload(ssh, LOCAL_DAED_CFG,   "/tmp/config.dae.new")
        upload(ssh, LOCAL_GEOSITE_SH, "/tmp/geosite-update.sh.new")
        upload(ssh, LOCAL_UPDATE_DAED_SH, "/tmp/update-daed.sh.new")
        upload(ssh, LOCAL_MOSDNS_CFG, "/tmp/mosdns_config.yaml.new")
        run(ssh, f"sudo cp -v /tmp/config.dae.new {REMOTE_DAED_CFG}")
        run(ssh, f"sudo cp -v /tmp/geosite-update.sh.new {REMOTE_GEOSITE_SH}")
        run(ssh, f"sudo cp -v /tmp/update-daed.sh.new {REMOTE_UPDATE_DAED_SH}")
        run(ssh, f"sudo cp -v /tmp/mosdns_config.yaml.new {REMOTE_MOSDNS_CFG}")
        run(ssh, f"sudo sed -i 's/<LAN_BIND_IP>/192.168.0.243/g' {REMOTE_MOSDNS_CFG}")
        run(ssh, f"sudo chmod +x {REMOTE_GEOSITE_SH} {REMOTE_UPDATE_DAED_SH}")
        run(ssh, "rm -f /tmp/config.dae.new /tmp/geosite-update.sh.new /tmp/update-daed.sh.new /tmp/mosdns_config.yaml.new")
    except Exception as e:
        err(f"上传失败: {e}")
        ssh.close()
        sys.exit(1)

    # ── 验证文件内容 ─────────────────────────────────────────────
    banner("STEP 6: 验证文件内容")
    run(ssh, f"grep -n 'dip(1.1.1.1' {REMOTE_DAED_CFG}")
    run(ssh, f"grep -n 'fallback' {REMOTE_DAED_CFG}")
    run(ssh, f"grep -n 'geoip:private' {REMOTE_DAED_CFG}")

    # ── 重启 daed ────────────────────────────────────────────────
    banner("STEP 7: 重启 daed 服务")
    rc, _, _ = run(ssh, "sudo systemctl restart daed.service", timeout=30)
    time.sleep(5)
    rc2, out, _ = run(ssh, "systemctl is-active daed.service")
    if out.strip() == "active":
        ok("daed.service 重启成功，状态: active")
    else:
        err(f"daed.service 状态异常: {out}")

    # ── 重启 mosdns ──────────────────────────────────────────────
    banner("STEP 8: 重启 mosdns 服务")
    rc, _, _ = run(ssh, "sudo systemctl restart mosdns.service", timeout=20)
    time.sleep(3)
    rc2, out, _ = run(ssh, "systemctl is-active mosdns.service")
    if out.strip() == "active":
        ok("mosdns.service 重启成功，状态: active")
    else:
        err(f"mosdns.service 状态异常: {out}")

    # ── 端口验证 ─────────────────────────────────────────────────
    banner("STEP 9: 端口监听验证")
    run(ssh, "ss -tlnpu | grep -E ':53|:12345|:2023'")

    # ── DNS 功能测试 ─────────────────────────────────────────────
    banner("STEP 10: DNS 功能测试")
    # 测试国内域名解析
    run(ssh, "dig +short +timeout=5 baidu.com @127.0.0.1 || nslookup baidu.com 127.0.0.1 2>&1 | head -10")
    # 测试国外域名解析
    run(ssh, "dig +short +timeout=5 google.com @127.0.0.1 || nslookup google.com 127.0.0.1 2>&1 | head -10")

    # ── nftables 规则验证 ────────────────────────────────────────
    banner("STEP 11: nftables DNS Hijack 规则验证")
    run(ssh, "sudo nft list table inet daed_dns_hijack 2>/dev/null || echo 'table not loaded (expected if not root)'")

    # ── daed 路由规则确认 ────────────────────────────────────────
    banner("STEP 12: daed 配置最终确认")
    run(ssh, f"cat {REMOTE_DAED_CFG}")

    # ── 完成 ─────────────────────────────────────────────────────
    banner("✅ 部署与验证完成", GREEN)
    print(f"""
{GREEN}  修复内容已部署到 {HOST}:{RESET}
  • config.dae: DoH 锚点 + 私有IP规则提前 + fallback: direct
  • geosite-update.sh: 统一 dat+txt 数据源 + 完整性校验

{CYAN}  daed 管理面板: http://{HOST}:2023{RESET}
""")
    ssh.close()

if __name__ == "__main__":
    main()
