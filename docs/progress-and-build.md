# Progress and Build Notes

## Current Goal

Create a GitHub Actions template that can generate a generic OVA gateway image with Alpine Linux, dae, and mini-ppdns.

Repository target mentioned by the user: `https://github.com/kos991/zabte.git`.

At the time of checking, `git ls-remote https://github.com/kos991/zabte.git HEAD refs/heads/*` returned no refs, so the remote appears empty or without a default branch.

## Current Implementation

The current workspace contains a self-contained template, not an initialized git repository.

Implemented files:

- `.github/workflows/build-ova.yml`
- `README.md`
- `docs/design.md`
- `docs/progress-and-build.md`
- `scripts/build-alpine-ova.sh`
- `scripts/install-dae.sh`
- `scripts/install-mini-ppdns.sh`
- `scripts/render-ovf.sh`
- `overlay/etc/dae/config.dae`
- `overlay/etc/mini-ppdns.ini`
- `overlay/etc/init.d/check-ebpf`
- `overlay/etc/init.d/dae`
- `overlay/etc/init.d/mini-ppdns`
- `overlay/usr/local/sbin/check-ebpf`
- `overlay/usr/local/sbin/dae-gateway-manager`
- `overlay/etc/motd`
- `tests/smoke.ps1`

## Design Decisions

### Base OS

Use Alpine Linux with `linux-lts`.

Reason: dae relies on Linux eBPF. Alpine `linux-lts` has the right BPF/BTF direction for a small VM appliance, while remaining lightweight.

### Proxy Engine

Use `dae` from `daeuniverse/dae` release tarballs.

The installer currently downloads:

- `https://github.com/daeuniverse/dae/releases/latest/download/dae-linux-x86_64.tar.xz` when `DAE_VERSION=latest`
- `https://github.com/daeuniverse/dae/releases/download/<tag>/dae-linux-x86_64.tar.xz` when a tag is specified

### DNS Component

Use `mini-ppdns`, not full PaoPaoDNS.

Reason: full PaoPaoDNS is a Docker image and combines unbound, redis, mosdns, dnscrypt-proxy, data update scripts, and multiple generated configs. `mini-ppdns` is a single native binary derived from PaoPaoDNS and fits the non-Docker Alpine appliance better.

### SMbox Reference

SMbox documentation was used only as an appliance UX reference: Alpine base, one-command management, clear status/log commands, and lightweight VM deployment. SMbox/Singbox is not installed.

### luci-app-daed-runfiles Reference

`wkccd/luci-app-daed-runfiles` was inspected as an OpenWrt/daed reference. Its `.run` package contains OpenWrt APKs:

- `daed`
- `luci-app-daed`
- `v2ray-geoip`
- `v2ray-geosite`
- `vmlinux-btf`

Those APKs are not installed because they target OpenWrt package ABI, not Alpine. The useful points were carried over:

- BTF is checked through `/sys/kernel/btf/vmlinux`.
- dae config uses geoip/geosite style split rules.

## Current Split Routing Template

`overlay/etc/dae/config.dae` currently provides a daed-style baseline:

- `mini-ppdns` traffic uses `must_direct` to avoid DNS loops.
- NetworkManager, multicast/broadcast, private IPs, CN IPs, and CN domains go direct.
- `geosite:geolocation-!cn` goes to the `proxy` group.
- DNS requests for CN domains use AliDNS.
- Other DNS requests use Google DNS.
- Non-CN domains returning private IPs are retried with Google DNS.
- UDP/443 is blocked by default to reduce QUIC/H3 overhead on small gateways.
- Fallback traffic goes to `proxy` after the user adds nodes or subscriptions.

dae is installed but not enabled at boot until `/etc/dae/config.dae` is customized. `mini-ppdns` is enabled by default.

## GitHub Actions Build Flow

Workflow: `.github/workflows/build-ova.yml`

Manual inputs:

- `alpine_version`, default `3.20`
- `dae_version`, default `latest`
- `mini_ppdns_ref`, default `release`
- `disk_size`, default `4G`
- `memory_mb`, default `1024`
- `cpu_count`, default `1`

Build steps:

1. Check out repository.
2. Install Linux build tools.
3. Run `tests/smoke.ps1`.
4. Run `scripts/build-alpine-ova.sh` as root.
5. Upload `dist/*.ova` and `dist/*.sha256` through `actions/upload-artifact@v4`.

The OVA build is designed for `ubuntu-latest` because it needs root, loop devices, mount, chroot, GRUB, and qemu-img.

## Verification Run Locally

Fresh checks run in this workspace:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/smoke.ps1
```

Result: `Smoke tests passed.`

Shell syntax checks:

```sh
bash -n scripts/build-alpine-ova.sh
bash -n scripts/install-dae.sh
bash -n scripts/install-mini-ppdns.sh
bash -n scripts/render-ovf.sh
bash -n overlay/usr/local/sbin/check-ebpf
bash -n overlay/usr/local/sbin/dae-gateway-manager
```

Result: exit code `0`.

The full OVA build was not run locally because the current workspace is on Windows and the build requires Linux loop devices and chroot.

## Next Steps

1. Initialize or clone `https://github.com/kos991/zabte.git` once the remote has a branch, or initialize the current directory and push it there.
2. Run the GitHub Actions workflow once in the target repository.
3. Inspect the workflow log for Alpine package or GRUB issues.
4. Import the generated OVA into the target hypervisor.
5. Boot the VM and run:

```sh
dae-gateway-manager ebpf
dae-gateway-manager status
```

6. Edit `/etc/dae/config.dae`, add nodes/subscriptions, then enable dae:

```sh
rc-update add dae default
rc-service dae start
```
