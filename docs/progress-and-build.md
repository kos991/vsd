# Progress and Build Notes

## Current Target

Build a GitHub Actions template that generates a generic Alpine Linux OVA gateway image with:

- Alpine `linux-virt`
- `daed` from `daeuniverse/daed`
- `geoip.dat` and `geosite.dat`
- `mini-ppdns`
- OpenRC services
- blocking firstboot console setup
- BBR/fq TCP optimization
- one-arm same-LAN gateway sysctl

## Key Files

- `.github/workflows/build-ova.yml`
- `scripts/build-alpine-ova.sh`
- `scripts/install-daed.sh`
- `scripts/install-mini-ppdns.sh`
- `scripts/render-ovf.sh`
- `overlay/etc/init.d/daed`
- `overlay/etc/init.d/daed-firstboot`
- `overlay/etc/init.d/mini-ppdns`
- `overlay/etc/init.d/check-ebpf`
- `overlay/usr/local/sbin/daed-firstboot`
- `overlay/usr/local/sbin/daed-manager`
- `overlay/usr/local/sbin/mini-ppdns-manager`
- `overlay/usr/local/sbin/gateway-network-init`
- `overlay/usr/local/sbin/gateway`

## Kernel Decision

Use Alpine `linux-virt`, not `linux-lts`, because dae/daed requires eBPF and BTF support. Alpine `linux-virt` provides:

- `CONFIG_BPF_SYSCALL=y`
- `CONFIG_BPF_JIT=y`
- `CONFIG_CGROUP_BPF=y`
- `CONFIG_DEBUG_INFO_BTF=y`
- `CONFIG_TCP_CONG_BBR=m`
- `CONFIG_NET_SCH_FQ=m`
- `CONFIG_NETFILTER_XT_TARGET_TPROXY=m`
- NAT/MASQUERADE support
- VMware/VirtIO network modules

The stable Alpine OVA uses standard BBR plus `fq`. BBR3 is intentionally left for a separate Debian 13 + XanMod experiment.

## daed

`scripts/install-daed.sh` downloads the latest main `daed` release that contains a `daed-linux-<arch>.zip` asset. The installer copies:

- `daed-linux-x86_64` to `/usr/bin/daed`
- `geoip.dat` to `/etc/daed/geoip.dat` and `/usr/share/daed/geoip.dat`
- `geosite.dat` to `/etc/daed/geosite.dat` and `/usr/share/daed/geosite.dat`

The OpenRC service runs:

```sh
/usr/bin/daed run -c /etc/daed/
```

The dashboard listens on:

```text
http://<gateway-ip>:2023
```

## Firstboot

The build locks root with `passwd -l root`; no default password is baked into the image.

`daed-firstboot` runs from OpenRC on the first boot and asks for:

- root password
- daed admin username
- daed admin password
- TCP optimization choice
- bandwidth, latency, and memory for TCP buffer sizing

The script validates daed passwords with the upstream rule:

```text
too weak password; should contain numbers and letters, and no less than 6 in length
```

It then starts daed, waits for `http://127.0.0.1:2023/graphql`, and tries to run the `createUser` mutation. If the API is not ready, the saved `/etc/daed/firstboot-admin.env` file remains as a recovery hint.

## Network

`gateway-network-init` detects the first physical interface and ignores virtual interfaces:

- `dae0`
- `docker*`
- `veth*`
- `br-*`
- `tun*`
- `tap*`
- `wg*`
- `zt*`
- `ifb*`
- `dummy*`

It persists DHCP for the detected interface, enables forwarding, disables `rp_filter`, disables redirects, and adds a NAT masquerade rule for same-LAN gateway use.

## Local Verification

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke.ps1
```

Run shell syntax checks:

```powershell
bash -n scripts/build-alpine-ova.sh
bash -n scripts/install-daed.sh
bash -n overlay/usr/local/sbin/daed-firstboot
bash -n overlay/usr/local/sbin/daed-manager
bash -n overlay/usr/local/sbin/gateway-network-init
```

Full OVA validation is performed by GitHub Actions on `ubuntu-latest` because it needs loop devices, chroot, GRUB, qemu-img, and OVA packaging tools.
