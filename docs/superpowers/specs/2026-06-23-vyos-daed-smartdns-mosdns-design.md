# Design: VyOS + daed + SmartDNS + MosDNS Single-Route Gateway OVA

Date: 2026-06-23
Branch: `feature/vyos15-daed-packer`

## Goal

Collapse the repository to ONE route: a VyOS 1.5 immutable routing appliance (OVA)
built by Packer, integrating an eBPF transparent proxy (`daed`) and a dual-engine
DNS stack (`MosDNS` front desk + `SmartDNS` CN resolver). Remove the legacy Alpine
(`overlay/`) and Debian/PaoPaoDNS (`overlay-debian/`) routes entirely.

This is **cleanup + implementation of the 4-layer DNS flow**, not just cleanup.

## Non-Goals

- No baked-in proxy nodes, subscriptions, API keys, or secrets.
- No Docker in the appliance.
- No Web control panel rework (dropped).

## Repository Layout (keep existing `packer/custom-services/` convention)

```text
daed/
├── README.md                              # rewrite: VyOS route, mermaid diagram, firstboot
├── packer/
│   ├── build.pkr.hcl                      # keep; file provisioner uploads packer/custom-services/
│   ├── scripts/setup-gateway.sh           # rewrite: download bins + geo, copy custom-services, wire systemd
│   └── custom-services/
│       ├── daed/config.dae                # eBPF enforcer + tunnel (templated)
│       ├── mosdns/config.yaml             # LAN:53 front desk (templated)
│       ├── smartdns/smartdns.conf         # CN resolver, 127.0.0.1:5335
│       └── scripts/
│           ├── custom-services-latebind.sh
│           └── geosite-update.sh
├── scripts/dae-stability-collector.sh     # keep (diagnostics)
├── network_diag.sh                        # keep (diagnostics)
├── tests/smoke.ps1                         # rewrite: packer validate + bash -n
└── .github/workflows/build-ova.yml        # adjust: drop inline config generation
```

NOTE on the spec author's example tree: it used a placeholder root `my-router-ova/`
and put `custom-services/` at repo root with `smoke.ps1` under `packer/scripts/`.
We keep the EXISTING repo conventions instead (`packer/custom-services/`,
`tests/smoke.ps1`) so the working CI and Packer references stay intact. The tree
was illustrative; the substance (config values, rules, scripts, CI/README) is what
we implement.

## Delete List (one commit, A1)

- Dirs: `overlay/`, `overlay-debian/`
- Scripts: everything under `scripts/` EXCEPT `dae-stability-collector.sh`
  (`build-alpine-ova.sh`, `build-debian-ova.sh`, `ci-build-debian-ova.sh`,
  `ci-build-ova.sh`, `install-daed.sh`, `install-daed-debian.sh`,
  `install-mini-ppdns.sh`, `render-ovf.sh`)
- Docs: `docs/design.md`, `docs/progress-and-build.md`,
  `docs/gateway-web-rework-plan.md`, `docs/dae-paopaodns-132-ops.md`

## 4-Layer DNS Architecture

```text
LAN client → MosDNS(<LAN_BIND_IP>:53)
   ├─ cache hit → return
   ├─ geosite:cn        → forward_smartdns 127.0.0.1:5335 (concurrent CN upstreams + speed-check)
   └─ geosite:!cn / fb  → forward_doh https://8.8.8.8/dns-query
                            └─ daed fallback:proxy tunnels this TLS out → clean overseas IP
daed (eBPF :12345): allow client→gateway:53 + SmartDNS egress; block other DNS escape;
                    direct for geoip cn/private; proxy for the rest.
```

## Core Config Values (exact, per spec author)

### A. MosDNS `mosdns/config.yaml` — Front Desk
- Listen `<LAN_BIND_IP>:53` UDP+TCP. NOT 0.0.0.0.
- `cache` plugin with `lazy_cache_ttl`.
- `domain_set` loads `geolocation-cn.txt` and `geolocation-!cn.txt`.
- Sequence: CN → `forward_smartdns` (udp+tcp 127.0.0.1:5335); !CN → `forward_doh`
  (`https://8.8.8.8/dns-query`); fallback → `forward_doh`.

### B. SmartDNS `smartdns/smartdns.conf` — CN Resolver
- `bind 127.0.0.1:5335`, `bind-tcp 127.0.0.1:5335`.
- UDP upstreams: 119.29.29.29, 119.28.28.28, 223.5.5.5, 223.6.6.6,
  114.114.114.114, 114.114.115.115, 180.76.76.76.
- Encrypted: `server-tls 223.5.5.5`, `server-https https://doh.pub/dns-query`.
- `speed-check-mode tcp:443,icmp`, `prefetch-domain yes`, `serve-expired yes`,
  `cache-size 100000`.

### C. daed `daed/config.dae` — eBPF Enforcer + Tunnel
- `dns { upstream { local: 'udp://127.0.0.1:5335' } routing { request { fallback: local } } }`
- Routing rules EXACTLY:
  ```text
  dip(114.114.114.114, 114.114.115.115, 119.29.29.29, 119.28.28.28, 180.76.76.76, 223.5.5.5, 223.6.6.6) -> must_direct
  dip(doh.pub) -> must_direct
  sip(<LAN_SUBNET>) && dip(<LAN_BIND_IP>) && dport(53) -> must_direct
  sip(<LAN_SUBNET>) && !dip(<LAN_BIND_IP>) && dport(53, 853) -> block
  dip(geoip:private) -> direct
  dip(geoip:cn) -> direct
  fallback: proxy
  ```
- `node {}` empty.

## Automation Scripts

### A. `custom-services-latebind.sh` (VyOS postconfig-bootup)
- Retry loop (~30s timeout) waiting for LAN interface to acquire a valid IPv4
  address + subnet (race-condition fix).
- `sed` replaces `<LAN_BIND_IP>` and `<LAN_SUBNET>` in MosDNS + daed templates.
- Refuse unsafe binds (empty / 0.0.0.0 / 127.*).
- Link + enable + start `daed`, `mosdns`, `smartdns` systemd services.

### B. `geosite-update.sh` + systemd `.service`/`.timer` (weekly)
- Download latest CN and !CN text lists.
- Failsafe: `wc -l` must be > 1000 lines per file, else abort (don't break DNS).
- On success `systemctl reload mosdns`.

### C. `setup-gateway.sh` (Packer provisioner)
- Download latest `daed`, `mosdns`, `smartdns` amd64 from GitHub releases.
- Download initial `geoip.dat` + the two geosite `.txt` files.
- Copy `custom-services/` into `/config/custom-services/`.
- Create systemd service units; wire late-bind into VyOS startup.

## CI / Validation / README

- `build-ova.yml`: `workflow_dispatch`; build VyOS ISO (existing vyos-jenkins path),
  `packer build` → upload OVA. Remove the inline heredoc config generation; rely on
  committed `packer/custom-services/`.
- `smoke.ps1`: validate Packer syntax (`packer validate`) + `bash -n setup-gateway.sh`
  (and the other shipped shell scripts).
- `README.md`: mermaid architecture diagram, DNS data-flow explanation, strict
  First-Boot note: **all overseas traffic is blackholed until a proxy node is added
  via the daed web UI on :2023**.

## Known Risk (verify at runtime, not buildable-checkable)

`dip(doh.pub) -> must_direct`: dae's `dip()` matches destination IP/CIDR/geoip;
domain matching normally uses `domain()`. Whether `dip(<domain>)` resolves is
uncertain and cannot be caught by `packer validate` / `bash -n` (daed runtime
semantics). Implement as written per spec, flag in README, and confirm with
`daed validate` on a booted OVA. Fallback options if it errors: `domain(suffix:doh.pub)`
or pin doh.pub's fixed IPs.

## Verification

- Local: `packer validate` + `bash -n` on all shell scripts + `tests/smoke.ps1`.
- CI: `workflow_dispatch` runs full Packer build, produces OVA artifact.
