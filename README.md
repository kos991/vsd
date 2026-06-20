# daed Alpine Gateway OVA

This template builds a lightweight Alpine Linux gateway OVA with:

- `daed` installed as the primary dashboard and daemon.
- Alpine `linux-virt` selected for VMware-friendly eBPF/BTF support.
- `geoip.dat` and `geosite.dat` installed with daed for split rules.
- `mini-ppdns` installed as a native OpenRC DNS failover service.
- Firstboot console setup for the root password and TCP tuning.
- No Docker, no SMbox, no Singbox, and no full PaoPaoDNS container stack.

The intended workflow is simple: push this repository to GitHub, open **Actions**, run **Build Alpine gateway OVA**, and download the generated OVA artifact.

## GitHub Actions Usage

1. Push these files to a GitHub repository.
2. Open the repository's **Actions** tab.
3. Select **Build Alpine gateway OVA**.
4. Click **Run workflow**.
5. Download the `daed-alpine-gateway-ova` artifact after the workflow finishes.

Workflow inputs:

- `alpine_version`: Alpine branch, default `3.24`.
- `daed_version`: `latest` or a daed tag such as `v1.27.0`.
- `mini_ppdns_ref`: source ref for mini-ppdns release branch, normally `release`.
- `disk_size`: raw disk size, default `4G`.
- `memory_mb`: OVF memory hint, default `1024`.
- `cpu_count`: OVF CPU hint, default `1`.

## Firstboot

The image no longer bakes in a default `root` password. On first boot, the console wizard asks for:

- root password
- whether to enable BBR/fq TCP optimization
- bandwidth, latency, and memory values for Omnitt-style TCP buffer sizing

The root password only needs to be non-empty and entered the same way twice. The wizard writes `/etc/dae-gateway-firstboot.done` after completion.

Create the daed administrator in the official daed dashboard after firstboot:

```text
http://<gateway-ip>:2023
```

Reset the wizard if needed:

```sh
daed-firstboot reset
reboot
```

## Runtime Layout

Inside the generated VM:

- `/usr/bin/daed`
- `/usr/sbin/mini-ppdns`
- `/etc/daed/`
- `/etc/daed/geoip.dat`
- `/etc/daed/geosite.dat`
- `/etc/mini-ppdns.ini`
- `/usr/local/sbin/gateway`
- `/usr/local/sbin/daed-manager`
- `/usr/local/sbin/mini-ppdns-manager`
- `/usr/local/sbin/dae-gateway-manager`
- `/usr/local/sbin/daed-firstboot`
- `/usr/local/sbin/check-ebpf`
- `/var/log/daed/`
- `/var/log/mini-ppdns/`

Open the dashboard after firstboot and create the daed administrator there:

```text
http://<gateway-ip>:2023
```

Quick menu:

```sh
gateway
```

The menu uses number shortcuts:

- `1`: daed manager
- `2`: mini-ppdns manager
- `2`: eBPF check
- `4`: IP and routes
- `3`: Gateway overview
- `4`: QoS / CAKE
- `0`: exit

Service managers show short status first:

```sh
daed-manager status
mini-ppdns-manager status
```

Use `Details` in the menu, or run `details`, when you need technical paths, service state, config files, and logs:

```sh
daed-manager details
mini-ppdns-manager details
```

## TCP Optimization

The stable Alpine image uses the official Alpine `linux-virt` kernel with standard BBR and fq:

```conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
```

BBR3 is intentionally not part of this default Alpine image. If BBR3 becomes required, use a separate Debian 13 + XanMod experimental image rather than changing this stable appliance.

## mini-ppdns

`mini-ppdns` starts by default and listens on port `53`. Configure DNS endpoints without editing the ini file manually:

```sh
mini-ppdns-manager configure
```

The wizard can apply the recommended DNS set, ask for custom DNS IPs, show the current config, and optionally restart `mini-ppdns` after writing `/etc/mini-ppdns.ini`.

## QoS

Optional QoS uses Linux `tc`, CAKE, and IFB for upload and download shaping:

```sh
qos-manager
```

It is installed but disabled until you enter the WAN interface and real download/upload bandwidth. The settings are saved to `/etc/dae-gateway-qos.conf`; the `dae-qos` OpenRC service restores them at boot only when QoS is enabled.

## eBPF Notes

daed relies on dae's Linux eBPF transparent proxy model. The image installs Alpine `linux-virt`, mounts `bpffs` at `/sys/fs/bpf`, mounts cgroup v2 at `/sys/fs/cgroup`, and installs a preflight service that probes BPF support before daed starts.

The preflight checks:

- `/sys/fs/bpf` is mounted.
- `/sys/fs/cgroup` is mounted as cgroup2.
- `/sys/kernel/btf/vmlinux` exists for BTF-enabled eBPF program loading.
- `bpftool feature probe kernel` can run.
- `ip_forward` is enabled.

## Default Network Behavior

The image detects the first physical non-loopback network interface at boot, persists DHCP for that interface, and ignores virtual interfaces such as `dae0`, Docker bridges, veth pairs, tunnels, and IFB devices.

It enables one-arm same-LAN gateway sysctl settings:

- IPv4 forwarding enabled.
- `rp_filter` disabled.
- `send_redirects` disabled.
- `accept_redirects` disabled.
- NAT masquerading added for traffic leaving the detected LAN interface.

Client machines can use the VM IP as gateway and DNS after daed and mini-ppdns are configured.

## Local Verification

Run the smoke tests from PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/smoke.ps1
```

The full OVA build requires Linux tools and is designed to run in GitHub Actions on `ubuntu-latest`.
