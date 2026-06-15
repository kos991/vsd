# dae Alpine Gateway OVA

This template builds a lightweight Alpine Linux gateway OVA with:

- `dae` installed as a native OpenRC service.
- Alpine `linux-lts` selected for eBPF support.
- `mini-ppdns` installed as a native OpenRC DNS failover service.
- No Docker, no SMbox, no Singbox, and no full PaoPaoDNS container stack.

The intended workflow is simple: push this repository to GitHub, open **Actions**, run **Build Alpine gateway OVA**, and download the generated OVA artifact.

## Why mini-ppdns

Full PaoPaoDNS is a Docker image that coordinates unbound, redis, mosdns, dnscrypt-proxy, data update scripts, and several generated configuration files. That is powerful, but heavy for a small gateway VM.

`mini-ppdns` is a small native DNS forwarder derived from PaoPaoDNS. It provides DNS failover, AAAA handling, and client-based fallback rules as a single Linux binary. This template uses `mini-ppdns` because it fits an Alpine appliance image cleanly.

## GitHub Actions Usage

1. Push these files to a GitHub repository.
2. Open the repository's **Actions** tab.
3. Select **Build Alpine gateway OVA**.
4. Click **Run workflow**.
5. Download the `dae-alpine-gateway-ova` artifact after the workflow finishes.

Workflow inputs:

- `alpine_version`: Alpine branch, for example `3.20`.
- `dae_version`: `latest` or a dae tag such as `v1.1.0`.
- `mini_ppdns_ref`: source ref for mini-ppdns release branch, normally `release`.
- `disk_size`: raw disk size, default `4G`.
- `memory_mb`: OVF memory hint, default `1024`.
- `cpu_count`: OVF CPU hint, default `1`.

## Runtime Layout

Inside the generated VM:

- `/usr/sbin/dae`
- `/usr/sbin/mini-ppdns`
- `/etc/dae/config.dae`
- `/etc/mini-ppdns.ini`
- `/usr/local/sbin/dae-gateway-manager`
- `/usr/local/sbin/check-ebpf`
- `/var/log/dae/`
- `/var/log/mini-ppdns/`

Services:

```sh
rc-service check-ebpf start
rc-service mini-ppdns start
rc-service dae start
```

`mini-ppdns` starts by default. `dae` is installed but not enabled at boot until you edit `/etc/dae/config.dae` for your nodes and routing policy. Enable it with:

```sh
rc-update add dae default
rc-service dae start
```

Manager:

```sh
dae-gateway-manager status
dae-gateway-manager logs
dae-gateway-manager restart
dae-gateway-manager ebpf
```

## eBPF Notes

dae relies on Linux eBPF for its transparent proxy and traffic splitting model. The image installs Alpine `linux-lts`, mounts `bpffs` at `/sys/fs/bpf`, mounts cgroup v2 at `/sys/fs/cgroup`, and installs a preflight service that probes BPF support before dae starts.

The preflight checks:

- `/sys/fs/bpf` is mounted.
- `/sys/fs/cgroup` is mounted as cgroup2.
- `/sys/kernel/btf/vmlinux` exists for BTF-enabled eBPF program loading.
- `bpftool feature probe kernel` can run.
- `ip_forward` is enabled.

The OpenWrt `luci-app-daed-runfiles` packages include a `vmlinux-btf` package, which is the same class of requirement. This Alpine image handles it by using `linux-lts` with BTF support instead of installing OpenWrt APKs.

## Default Network Behavior

The image uses DHCP on `eth0` by default. It enables IPv4 and IPv6 forwarding, but dae is not enabled at boot because the sample config does not include your private proxy nodes. You should import the OVA, verify network access, then adjust `/etc/dae/config.dae` for your LAN and proxy nodes.

`mini-ppdns` listens on port 53 and forwards to the DNS upstreams configured in `/etc/mini-ppdns.ini`.

The dae template uses a daed-style split baseline:

- `mini-ppdns`, LAN, multicast, private IP, CN IP, and CN domains go direct.
- DNS requests for CN domains use AliDNS; other DNS requests use Google DNS.
- Non-CN geosite traffic goes to the `proxy` group.
- UDP/443 is blocked by default to avoid QUIC/H3 overhead on small gateways.
- Fallback traffic goes to `proxy` after you add nodes or subscriptions.

## Local Verification

Run the smoke tests from PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/smoke.ps1
```

The full OVA build requires Linux tools and is designed to run in GitHub Actions on `ubuntu-latest`.
