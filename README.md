# Debian 13 daed Gateway OVA

This repository builds a VMware OVA gateway image that stitches together mature components:

- Debian 13 (`trixie`) as the stable high-performance base.
- XanMod kernel, default `linux-xanmod-x64v3`, for stronger gateway throughput and scheduler latency.
- `daed` as the original proxy dashboard and transparent proxy runtime.
- `PaoPaoDNS` as the primary DNS service through the official container image.
- BBR/fq, eBPF/BTF checks, nftables tooling, and optional CAKE/IFB QoS.
- `open-vm-tools` for VMware guest integration.
- A small console `gateway` menu for status, start/stop/restart, logs, updates, and QoS.

The goal is not to replace daed or PaoPaoDNS. The image installs them, wires their services together, and gives you a simple recovery path.

## GitHub Actions Usage

1. Push this repository to GitHub.
2. Open the repository's **Actions** tab.
3. Select **Build Debian gateway OVA**.
4. Click **Run workflow**.
5. Download the `daed-debian-gateway-ova` artifact after the workflow finishes.

Workflow inputs:

- `debian_version`: Debian major version, default `13`.
- `debian_codename`: Debian codename, default `trixie`.
- `daed_version`: `latest` or a daed tag such as `v1.27.0`.
- `paopaodns_image`: PaoPaoDNS image, default `sliamb/paopaodns:latest`.
- `xanmod_package`: XanMod kernel package, default `linux-xanmod-x64v3`. Use `linux-xanmod-x64v2` for older CPUs.
- `disk_size`: virtual disk size, default `8G`.
- `memory_mb`: OVF memory hint, default `2048`.
- `cpu_count`: OVF CPU hint, default `2`.

## Firstboot

The image does not bake in a default `root` password. On first boot, the console wizard asks only for the root password.

The root password only needs to be non-empty and entered the same way twice. The wizard writes `/etc/dae-gateway-firstboot.done` after completion.

Create the daed administrator in the original daed dashboard:

```text
http://<gateway-ip>:2023
```

## Runtime Layout

Inside the generated VM:

- `/usr/bin/daed`
- `/etc/daed/`
- `/usr/share/daed/geoip.dat`
- `/usr/share/daed/geosite.dat`
- `/etc/paopaodns/paopaodns.env`
- `/var/lib/paopaodns/`
- `/usr/local/sbin/gateway`
- `/usr/local/sbin/daed-manager`
- `/usr/local/sbin/paopaodns-manager`
- `/usr/local/sbin/qos-manager`
- `/usr/local/sbin/check-ebpf`

Quick menu:

```sh
gateway
```

The menu uses number shortcuts:

- `1`: daed manager
- `2`: PaoPaoDNS manager
- `3`: eBPF check
- `4`: Gateway overview
- `5`: QoS / CAKE
- `6`: mini-ppdns fallback
- `0`: exit

## PaoPaoDNS

PaoPaoDNS is the primary DNS service. The first Debian version uses the official `sliamb/paopaodns` container with host networking for the least moving parts and good DNS performance.

Important paths:

```text
/etc/paopaodns/paopaodns.env
/var/lib/paopaodns/
```

Manage it from the console:

```sh
paopaodns-manager status
paopaodns-manager restart
paopaodns-manager logs
```

`systemd-resolved` stub listening is disabled so PaoPaoDNS can bind TCP/UDP port `53`.

`mini-ppdns` is installed only as a fallback. It is disabled by default because it also binds port `53`.

## daed

daed is installed from the upstream Debian package. Its original dashboard remains the place to create the admin user, add nodes, and manage daed's own configuration.

```text
http://<gateway-ip>:2023
```

Manage the service:

```sh
daed-manager status
daed-manager restart
daed-manager logs
```

## QoS

CAKE/IFB tools are installed but not blindly enabled. Configure them only after you know the real WAN interface and bandwidth:

```sh
qos-manager
```

Settings are saved to `/etc/dae-gateway-qos.conf`; `dae-qos.service` restores them at boot only when QoS is enabled.

## eBPF Notes

The Debian image installs the XanMod kernel from the official XanMod APT repository. The default package is `linux-xanmod-x64v3`; change the workflow input to `linux-xanmod-x64v2` if the VM host CPU is older.

The VM still verifies the real runtime state before daed starts.

The preflight checks:

- `/sys/fs/bpf` is mounted.
- `/sys/fs/cgroup` is cgroup v2.
- `/sys/kernel/btf/vmlinux` exists.
- `bpftool feature probe kernel` can run.
- `ip_forward` is enabled.

## Local Verification

Run the smoke tests from PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/smoke.ps1
```

The full OVA build is designed to run in GitHub Actions on `ubuntu-latest`.
