# Design: Alpine daed Gateway OVA

## Goal

Build a reproducible GitHub Actions template that emits a generic OVA image containing Alpine Linux, daed, and mini-ppdns.

## Non-goals

- Do not install SMbox or Singbox.
- Do not run Docker in the appliance.
- Do not bundle private subscriptions, proxy nodes, API keys, or user secrets.
- Do not provide full PaoPaoDNS behavior; use mini-ppdns for lightweight DNS failover.

## Base System

The image is assembled from Alpine minirootfs on an ext4 disk image. The build script installs `linux-virt`, OpenRC, bootloader components, networking tools, BPF tooling, and virtual-machine guest utilities. The final disk is converted to VMDK and wrapped in OVF/OVA metadata.

## Kernel and eBPF

daed depends on dae's Linux eBPF transparent proxy model. The image uses Alpine `linux-virt` and configures:

- `bpffs /sys/fs/bpf bpf defaults 0 0`
- `cgroup2 /sys/fs/cgroup cgroup2 defaults 0 0`
- `net.ipv4.ip_forward=1`
- `net.ipv6.conf.all.forwarding=1`

An OpenRC `check-ebpf` service runs before daed and fails clearly when the kernel or mounts do not satisfy the requirements.

The `wkccd/luci-app-daed-runfiles` release packages were used as a reference point. They package OpenWrt-specific APK files, including `daed`, LuCI integration, geo data, and `vmlinux-btf`. Those packages are not installed in this Alpine appliance because they target OpenWrt 24/25 package ABI, but the BTF requirement is reflected in the Alpine preflight checks.

The same release also shows the expected daed runtime shape: daed plus `v2ray-geoip` and `v2ray-geosite`. The Alpine template installs `geoip.dat` and `geosite.dat` into `/etc/daed` so the dashboard can apply split rules without a missing data-file failure.

## daed

daed is downloaded from `daeuniverse/daed` releases. For `x86_64`, the build uses `daed-linux-x86_64.zip`. The installer resolves `latest` through the GitHub release API because daed publishes component releases as well as main program releases.

daed runs as an OpenRC supervised daemon with logs in `/var/log/daed/daed.log`. It starts by default after firstboot creates credentials and gateway sysctl settings.

## firstboot

The image locks root during build and runs a blocking console firstboot wizard on the first VM boot. The wizard sets the root password, stores a daed admin credential hint, writes one-arm gateway sysctl values, and optionally generates BBR/fq TCP tuning based on bandwidth, latency, and memory.

## mini-ppdns

mini-ppdns is downloaded from `kkkgo/mini-ppdns` release branch as `mini-ppdns_x86_64`. It runs as an OpenRC supervised daemon with config in `/etc/mini-ppdns.ini`.

## GitHub Actions

The workflow uses `workflow_dispatch` so users can click **Run workflow**. It installs Linux image tools, runs `scripts/build-alpine-ova.sh`, and uploads the OVA plus checksum manifest with `actions/upload-artifact@v4`.

## Verification

Static smoke tests validate the repository contract. The Actions build performs syntax checks and emits checksums. Full boot validation is left to the target hypervisor because this workspace is not a Linux VM builder environment.
