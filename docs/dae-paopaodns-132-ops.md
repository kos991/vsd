# 132 网关运行记录

本文记录 `192.168.0.132` 当前 `daed + PaopaoDNS` 网关的稳定配置、已做变更、验证命令和回滚边界。

## 目标架构

```text
客户端
  -> dae/daed 劫持 DNS 和透明代理流量
  -> DNS 请求转给 PaopaoDNS 智能入口 127.0.0.1:53
  -> PaopaoDNS 返回目标 DIP
  -> daed 只按 DIP 路由
```

职责边界：

```text
PaopaoDNS: DNS 判断、防污染、国内 CDN/递归/加密上游
daed: eBPF 透明代理、DNS 劫持、按 DIP 分流
```

核心路由原则：

```text
dip(geoip:private) -> direct
dip(geoip:cn) -> direct
fallback: proxy
```

## 当前关键配置

daed 实际服务名：

```bash
systemctl status daed.service
```

PaopaoDNS 实际服务名：

```bash
systemctl status paopaodns.service
```

PaopaoDNS 监听关系：

```text
127.0.0.1 / *:53    -> mosdns，智能入口
0.0.0.0:5301        -> unbound_raw，递归 DNS
*:5302              -> dnscrypt-proxy
0.0.0.0:5304        -> unbound_forward，内部上游
```

daed DNS 配置应指向 PaopaoDNS 智能入口，而不是内部 `5304`：

```text
dns {
  upstream {
    paopaodns: 'udp://127.0.0.1:53'
  }

  routing {
    request {
      fallback: paopaodns
    }
  }
}
```

daed 路由当前应为：

```text
routing {
  sip(192.168.0.0/24) && !sip(192.168.0.132) && dip(
      1.1.1.1,
      1.0.0.1,
      8.8.8.8,
      8.8.4.4,
      9.9.9.9,
      149.112.112.112,
      94.140.14.14,
      94.140.15.15,
      76.76.2.0/24,
      45.90.28.0/24,
      45.90.30.0/24,
      223.5.5.5,
      223.6.6.6,
      119.29.29.29,
      180.76.76.76,
      114.114.114.114,
      101.101.101.101
  ) && dport(443, 853, 784, 8853) -> block
  sip(192.168.0.0/24) && !sip(192.168.0.132) && domain(
      full:dns.google,
      full:dns.google.com,
      full:one.one.one.one,
      full:mozilla.cloudflare-dns.com,
      full:cloudflare-dns.com,
      suffix:cloudflare-dns.com,
      full:dns.quad9.net,
      suffix:quad9.net,
      suffix:nextdns.io,
      suffix:dns.adguard.com,
      suffix:adguard-dns.com,
      suffix:controld.com,
      suffix:cleanbrowsing.org,
      suffix:doh.pub,
      suffix:alidns.com,
      suffix:dns.alidns.com,
      suffix:opendns.com,
      suffix:familyshield.opendns.com
  ) && dport(443, 853, 784, 8853) -> block
  pname(unbound) && dport(53) -> must_direct
  sip(192.168.0.0/24) && dip(192.168.0.132) && dport(53) -> must_direct
  sip(192.168.0.0/24) && !sip(192.168.0.132) && !dip(192.168.0.132) && dport(53, 853) -> block
  dip(geoip:private) -> direct
  dip(geoip:cn) -> direct
  fallback: proxy
}
```

`pname(unbound) && dport(53) -> must_direct` 是为了避免 PaopaoDNS 的递归 DNS 被 daed 劫持回自己，造成 `5301 SERVFAIL`。

## 已确认版本

```text
daed: v1.27.0
kernel: 7.0.13-x64v3-xanmod1
PaopaoDNS image: sliamb/paopaodns:latest
mosdns: kkkgo/mosdns:240822.1
unbound: 1.21.1
dnscrypt-proxy: 2.1.5
Redis: 7.2.5
Docker: 26.1.5+dfsg1
```

BBR3/TCP 状态：

```text
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
tcp_bbr version: 3
```

## 已做变更

1. daed DNS upstream 从 `127.0.0.1:5304` 改为 `127.0.0.1:53`。
2. daed routing 加入 `pname(unbound) && dport(53) -> must_direct`。
3. 解除 QUIC 阻断。
4. 删除 daed global 里的固定带宽：

```text
bandwidth_max_tx:"200 mbps"
bandwidth_max_rx:"1 gbps"
```

5. 保持 `wan_interface:"auto"`。
6. `proxy` 组保持 `min_moving_avg` 双节点，不固定单节点。
7. 将 `check_interval` 从 `30s` 调整为 `120s`，减少 Banwag/Dmit 之间频繁横跳。
8. 清理本机 DNS 泄露风险：`/etc/resolv.conf` 只保留 `127.0.0.1`，`systemd-resolved` 全局 DNS 只保留 `127.0.0.1`，`ens160` 不再接受 DHCP 下发的 DNS。
9. daed routing 增加 LAN 客户端 DoH/DoT/DoQ 阻断：普通外部 `53/853` 阻断，常见 DoH 域名和公共 DNS IP 的 `443/853/784/8853` 阻断；规则限定 `sip(192.168.0.0/24) && !sip(192.168.0.132)`，不影响 PaopaoDNS 自己出站。
10. 增加内核层兜底：`dns-leak-firewall.service` 调用 `/usr/local/sbin/dns-leak-firewall`，在 `DOCKER-USER` 链前置 `DNS_LEAK_GUARD`，阻断 LAN 客户端转发到外部 DNS/DoT/DoQ 和常见公共 DNS IP 的 DoH。
11. 针对 `ip.skk.moe/dns-exit-lookup`、BrowserLeaks、PerfOps、阿里 DNS 检测等域名，追加到 `/var/lib/paopaodns/force_dnscrypt_list.txt`，让检测域名的递归出口走 PaopaoDNS 的 `dnscrypt-proxy`，再由 daed 代理出去。

不要把 `pname(unbound) && dport(53) -> must_direct` 改成 `proxy`。实测这样会被 daed DNS 劫持重写成 `127.0.0.1:53`，出现递归自咬风险；正确控制点是 PaopaoDNS 的 `force_dnscrypt_list.txt`。

当前 DNS 防漏基线：

```text
/etc/resolv.conf:
nameserver 127.0.0.1
options edns0 trust-ad
search .

resolvectl:
Global DNS Servers: 127.0.0.1
Link 2 (ens160): Current Scopes: none, Default Route: no

systemd-networkd:
[DHCPv4]
UseDNS=no
UseDomains=no
```

## 重要备份

服务器上已有这些关键备份：

```text
/etc/daed/wing.db.bak-paopaodns-dns-only-1782035542
/etc/daed/wing.db.bak-dip-only-routing-1782035674
/etc/daed/wing.db.bak-enable-quic-1782046787
/etc/daed/wing.db.bak-fix-paopaodns-recursive-1782051728
/etc/daed/wing.db.bak-bandwidth-auto-1782055959
/etc/daed/wing.db.bak-check-interval-120s-1782057158
/root/daed-backups/wing.db.bak-dnsleak-public-dns-ip-block-*
/root/daed-backups/iptables.bak-dns-leak-firewall-*
/root/daed-backups/20-wired-dhcp.network.bak-dnsleak-hardening-*
/root/daed-backups/10-daed-local-dns.conf.bak-dnsleak-hardening-*
/root/daed-backups/disable-stub.conf.bak-dnsleak-hardening-*
/root/daed-backups/force_dnscrypt_list.txt.bak-skk-dns-exit-*
/root/daed-backups/wing.db.bak-unbound-recursive-via-proxy-*
/root/daed-backups/wing.db.bak-before-restore-unbound-must-direct-*
```

回滚方式：

```bash
cp -a /etc/daed/wing.db.bak-check-interval-120s-1782057158 /etc/daed/wing.db
systemctl restart daed.service
```

如需回到修复 DNS 递归前的状态，优先不要这么做；那会重新引入国内 CDN 解析错误和递归自咬风险。

## 验证命令

服务状态：

```bash
systemctl is-active daed.service paopaodns.service systemd-resolved systemd-networkd dns-leak-firewall.service
systemctl is-enabled dns-leak-firewall.service
ss -lntup | grep -E '(:53|:5301|:5302|:5304|:2023)[[:space:]]'
ss -lnuup | grep -E '(:53|:5301|:5302|:5304)[[:space:]]'
```

本机 DNS 防漏：

```bash
cat /etc/resolv.conf
resolvectl status | sed -n '1,90p'
iptables -S DOCKER-USER
iptables -S DNS_LEAK_GUARD
tail -n 30 /var/lib/paopaodns/force_dnscrypt_list.txt
```

DNS：

```bash
host -W 3 www.baidu.com 127.0.0.1
host -W 3 www.bilibili.com 127.0.0.1
host -W 3 www.google.com 127.0.0.1
```

国内直连：

```bash
curl -k -m 8 -o /dev/null -sS -w 'remote=%{remote_ip} code=%{http_code} total=%{time_total}\n' https://www.baidu.com
curl -m 8 -sS http://myip.ipip.net
```

国外代理：

```bash
curl -k -m 10 -o /dev/null -sS -w 'remote=%{remote_ip} code=%{http_code} total=%{time_total}\n' https://www.google.com/generate_204
curl -k -m 10 -sS https://ipinfo.io/ip
```

daed 实时日志：

```bash
journalctl -u daed.service -f
```

## 观察重点

稳定状态应该满足：

```text
daed/paopaodns active
国内域名返回 CN IP
国内站 total 通常 0.03s - 0.2s
国外站走 proxy
日志没有持续 level=error
Group re-selects dialer 不再频繁每 15-30 秒跳
qdisc fq 无新增 dropped
ens160 RX dropped 不持续快速增长
```

若明天仍觉得不稳，优先看：

```text
1. proxy 组是否仍频繁重选
2. 哪些域名反复触发 Cloudflare / Google 风控
3. 代理出口 IP 是否变化或被挑战
4. DNS 是否又出现国内域名返回海外 CDN
5. 客户端是否大量 UDP/QUIC 走 proxy
```
