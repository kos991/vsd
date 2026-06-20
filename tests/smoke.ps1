param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
$failures = New-Object System.Collections.Generic.List[string]

function Assert-FileContains {
    param([string]$Path, [string]$Pattern, [string]$Message)
    $full = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $full)) {
        $failures.Add("Missing file: $Path")
        return
    }
    $text = Get-Content -LiteralPath $full -Raw
    if ($text -notmatch $Pattern) {
        $failures.Add($Message)
    }
}

function Assert-FileDoesNotContain {
    param([string]$Path, [string]$Pattern, [string]$Message)
    $full = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $full)) {
        $failures.Add("Missing file: $Path")
        return
    }
    $text = Get-Content -LiteralPath $full -Raw
    if ($text -match $Pattern) {
        $failures.Add($Message)
    }
}

function Assert-FileIsAscii {
    param([string]$Path, [string]$Message)
    $full = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $full)) {
        $failures.Add("Missing file: $Path")
        return
    }
    foreach ($byte in [System.IO.File]::ReadAllBytes($full)) {
        if ($byte -gt 127) {
            $failures.Add($Message)
            return
        }
    }
}

function Assert-PathExists {
    param([string]$Path, [string]$Message)
    if (-not (Test-Path -LiteralPath (Join-Path $Root $Path))) {
        $failures.Add($Message)
    }
}

Assert-FileContains '.github/workflows/build-ova.yml' 'workflow_dispatch' 'Workflow must support manual Run workflow.'
Assert-FileContains '.github/workflows/build-ova.yml' 'push:[\s\S]*branches:[\s\S]*- main' 'Workflow must auto-build when main is pushed.'
Assert-FileContains '.github/workflows/build-ova.yml' 'cancel-in-progress: true' 'Workflow must cancel stale in-progress OVA builds.'
Assert-FileContains '.github/workflows/build-ova.yml' "inputs\.debian_version \|\| '13'" 'Push builds must default to Debian 13.'
Assert-FileContains '.github/workflows/build-ova.yml' "inputs\.debian_codename \|\| 'trixie'" 'Push builds must default to Debian trixie.'
Assert-FileContains '.github/workflows/build-ova.yml' "inputs\.daed_version \|\| 'latest'" 'Push builds must default to latest daed.'
Assert-FileContains '.github/workflows/build-ova.yml' "inputs\.paopaodns_image \|\| 'sliamb/paopaodns:latest'" 'Push builds must default to the official PaoPaoDNS image.'
Assert-FileContains '.github/workflows/build-ova.yml' "inputs\.xanmod_package \|\| 'linux-xanmod-x64v3'" 'Push builds must default to the XanMod x64v3 kernel package.'
Assert-FileContains '.github/workflows/build-ova.yml' "inputs\.disk_size \|\| '8G'" 'Push builds must default to an 8G Debian disk.'
Assert-FileContains '.github/workflows/build-ova.yml' "inputs\.memory_mb \|\| '2048'" 'Push builds must default to 2GB memory.'
Assert-FileContains '.github/workflows/build-ova.yml' "inputs\.cpu_count \|\| '2'" 'Push builds must default to 2 CPUs.'
Assert-FileContains '.github/workflows/build-ova.yml' 'runs-on: ubuntu-24\.04' 'Workflow must pin the runner image instead of using ubuntu-latest for OVA builds.'
Assert-FileContains '.github/workflows/build-ova.yml' 'libguestfs-tools' 'Workflow must install libguestfs tools for Debian cloud image customization.'
Assert-FileContains '.github/workflows/build-ova.yml' 'docker --version' 'Workflow must verify the runner Docker CLI used to preload PaoPaoDNS.'
Assert-FileContains '.github/workflows/build-ova.yml' 'add-apt-repository -y universe' 'Workflow must enable the Ubuntu universe repository before installing guestfs and Docker tools.'
Assert-FileContains '.github/workflows/build-ova.yml' 'install-tools\.log' 'Workflow must preserve build-tool installation logs for early CI failures.'
Assert-FileContains '.github/workflows/build-ova.yml' 'apt-get purge -y passt' 'Workflow must remove passt so libguestfs falls back on GitHub runners.'
Assert-FileContains '.github/workflows/build-ova.yml' 'scripts/ci-build-debian-ova\.sh' 'Workflow must build the Debian OVA.'
Assert-FileContains '.github/workflows/build-ova.yml' 'daed-debian-gateway-ova' 'Workflow must upload the Debian OVA artifact.'
Assert-FileContains '.github/workflows/build-ova.yml' 'daed-debian-gateway-diagnostics' 'Workflow must upload diagnostics separately from the OVA artifact.'
Assert-FileContains '.github/workflows/build-ova.yml' '\$\{\{ github\.workspace \}\}/dist/\*\.ova' 'Workflow must upload only the OVA file.'
Assert-FileDoesNotContain '.github/workflows/build-ova.yml' 'daed-alpine-gateway-ova' 'Workflow must not publish the old Alpine artifact as the main output.'
Assert-FileDoesNotContain '.github/workflows/build-ova.yml' '\$\{\{ github\.workspace \}\}/dist/\*\.sha256' 'Workflow must not include checksum files in the downloadable OVA artifact.'
Assert-FileContains '.github/workflows/build-ova.yml' 'cat "\$\{GITHUB_WORKSPACE\}/dist/build\.log"' 'Workflow must print failed build logs.'
Assert-FileContains '.github/workflows/build-ova.yml' '::error title=OVA build failed::' 'Workflow must expose failed OVA logs in an annotation.'

Assert-FileContains 'scripts/build-debian-ova.sh' 'cloud\.debian\.org/images/cloud' 'Debian build must use the official Debian cloud image.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'debian-%s-genericcloud-amd64\.qcow2' 'Debian build must use the genericcloud amd64 image.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'qemu-img resize "\$\{QCOW_IMAGE\}" "\$\{DISK_SIZE\}"' 'Debian build must resize the cloud image to the requested disk size.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'nameserver 1\.1\.1\.1' 'Debian guest setup must seed resolv.conf before apt runs under libguestfs.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'virt_args=\(' 'Debian build must assemble a single virt-customize transaction.'
Assert-FileContains 'scripts/build-debian-ova.sh' '-a "\$\{QCOW_IMAGE\}"' 'Debian build must customize the cloud image offline with libguestfs.'
Assert-FileContains 'scripts/build-debian-ova.sh' '--network' 'Debian build must explicitly enable libguestfs network access for apt setup.'
Assert-FileContains 'scripts/build-debian-ova.sh' '--mkdir /root/dae-gateway-build' 'Debian build must create a persistent guest build staging directory.'
Assert-FileContains 'scripts/build-debian-ova.sh' '--upload "\$\{SETUP_SCRIPT\}:/root/dae-gateway-build/setup-debian-gateway\.sh"' 'Debian build must upload the setup script to a fixed guest path.'
Assert-FileContains 'scripts/build-debian-ova.sh' '--upload "\$\{PAOPAODNS_TAR\}:/root/dae-gateway-build/paopaodns\.tar"' 'Debian build must upload the preloaded PaoPaoDNS image to a fixed guest path.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'virt_args\+=\(--run-command "bash /root/dae-gateway-build/setup-debian-gateway\.sh"\)' 'Debian build must run guest setup as a guest command in the same virt-customize transaction as file uploads.'
Assert-FileDoesNotContain 'scripts/build-debian-ova.sh' '--run /root/dae-gateway-build/setup-debian-gateway\.sh' 'Debian build must not pass a guest path to virt-customize --run.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'virt-customize "\$\{virt_args\[@\]\}"' 'Debian build must execute the combined virt-customize arguments.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'XANMOD_PACKAGE="\$\{XANMOD_PACKAGE:-linux-xanmod-x64v3\}"' 'Debian build must default to the XanMod x64v3 kernel.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'https://dl\.xanmod\.org/archive\.key' 'Debian build must register the official XanMod archive key.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'gpg --dearmor -o /etc/apt/keyrings/xanmod-archive-keyring\.gpg' 'Debian build must dearmor the XanMod key into the apt keyrings directory.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'http://deb\.xanmod\.org \$\{DEBIAN_CODENAME\} main' 'Debian build must add the official XanMod apt repository for the selected Debian codename.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'apt-get install -y --no-install-recommends "\$\{XANMOD_PACKAGE\}"' 'Debian build must install the selected XanMod kernel package.'
Assert-FileDoesNotContain 'scripts/build-debian-ova.sh' 'linux-image-amd64 \\' 'Debian build must not install the stock Debian kernel as the main kernel.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'open-vm-tools' 'Debian build must install VMware guest tools.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'docker\.io' 'Debian build must install Docker for the official PaoPaoDNS container.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'install-mini-ppdns\.sh' 'Debian build must install mini-ppdns as a fallback.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'bpftool' 'Debian build must install bpftool for eBPF diagnostics.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'nftables' 'Debian build must install nftables.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'iproute2' 'Debian build must install iproute2 for tc and routing tools.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'DNSStubListener=no' 'Debian build must disable the systemd-resolved DNS stub so PaoPaoDNS can bind port 53.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'sed -i "s#\^PAOPAODNS_IMAGE=\.\*#PAOPAODNS_IMAGE=\$\{PAOPAODNS_IMAGE\}#"' 'Debian build must write the selected PaoPaoDNS image into runtime config.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'rm -f /etc/ssh/ssh_host_\*' 'Debian build must remove baked SSH host keys.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'docker save "\$\{PAOPAODNS_IMAGE\}"' 'Debian build must preload the PaoPaoDNS image when Docker is available.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'qemu-img convert -f qcow2 -O vmdk -o subformat=streamOptimized,adapter_type=lsilogic' 'Debian build must emit a VMware-compatible streamOptimized VMDK.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'Debian GNU/Linux 13 64-bit' 'Debian build must render Debian guest text into the OVF.'

Assert-FileContains 'scripts/ci-build-debian-ova.sh' 'DIST_DIR=.*dist' 'Debian CI wrapper must target dist.'
Assert-FileContains 'scripts/ci-build-debian-ova.sh' '\$\{DIST_DIR\}/build\.log' 'Debian CI wrapper must preserve build logs.'
Assert-FileContains 'scripts/ci-build-debian-ova.sh' '\$\{DIST_DIR\}/build\.status' 'Debian CI wrapper must preserve build status.'
Assert-FileContains 'scripts/ci-build-debian-ova.sh' 'PIPESTATUS' 'Debian CI wrapper must preserve build status through tee.'
Assert-FileContains 'scripts/ci-build-debian-ova.sh' 'XANMOD_PACKAGE' 'Debian CI wrapper must pass the selected XanMod kernel package through sudo.'
Assert-FileContains 'scripts/ci-build-debian-ova.sh' 'LIBGUESTFS_BACKEND=direct' 'Debian CI wrapper must force the direct libguestfs backend on GitHub runners.'
Assert-FileContains 'scripts/ci-build-debian-ova.sh' 'systemctl stop apparmor' 'Debian CI wrapper must avoid AppArmor blocking libguestfs passt startup.'

Assert-FileContains 'scripts/render-ovf.sh' 'GUEST_INFO="\$\{7:-Linux daed gateway\}"' 'OVF renderer must support distro-specific guest text.'
Assert-FileContains 'scripts/render-ovf.sh' 'OS_INFO="\$\{8:-Linux 64-bit\}"' 'OVF renderer must support distro-specific OS text.'
Assert-FileContains 'scripts/render-ovf.sh' '<rasd:ResourceSubType>lsilogic</rasd:ResourceSubType>' 'OVF SCSI controller must use lsilogic.'
Assert-FileContains 'scripts/render-ovf.sh' '<rasd:ResourceSubType>VmxNet3</rasd:ResourceSubType>' 'OVF network adapter must use VmxNet3.'

Assert-FileContains 'scripts/install-daed-debian.sh' 'daeuniverse/daed' 'Debian daed installer must download from daeuniverse/daed.'
Assert-FileContains 'scripts/install-daed-debian.sh' 'installer-daed-linux-\$\{ASSET_ARCH\}\.deb' 'Debian daed installer must use upstream deb packages.'
Assert-FileContains 'scripts/install-daed-debian.sh' 'dpkg -i' 'Debian daed installer must install the upstream deb.'
Assert-FileContains 'scripts/build-debian-ova.sh' 'install-daed-debian\.sh' 'Debian build must install daed through the Debian installer wrapper.'

Assert-PathExists 'overlay-debian/etc/systemd/system/daed.service.d/10-gateway.conf' 'Debian daed systemd drop-in must exist.'
Assert-PathExists 'overlay-debian/etc/systemd/system/paopaodns.service' 'Debian PaoPaoDNS systemd unit must exist.'
Assert-PathExists 'overlay-debian/etc/systemd/system/mini-ppdns.service' 'Debian mini-ppdns fallback unit must exist.'
Assert-PathExists 'overlay-debian/etc/systemd/system/check-ebpf.service' 'Debian eBPF check unit must exist.'
Assert-PathExists 'overlay-debian/etc/systemd/system/dae-gateway-firstboot.service' 'Debian firstboot unit must exist.'
Assert-PathExists 'overlay-debian/etc/systemd/system/dae-ssh-hostkeys.service' 'Debian SSH host key unit must exist.'
Assert-PathExists 'overlay-debian/etc/systemd/network/20-wired-dhcp.network' 'Debian DHCP networkd config must exist.'
Assert-PathExists 'overlay-debian/etc/sysctl.d/99-dae-gateway.conf' 'Debian gateway sysctl profile must exist.'

Assert-FileContains 'overlay-debian/etc/systemd/system/daed.service.d/10-gateway.conf' 'After=dae-gateway-firstboot\.service check-ebpf\.service paopaodns\.service' 'daed must start after firstboot, eBPF check, and PaoPaoDNS.'
Assert-FileContains 'overlay-debian/etc/systemd/system/daed.service.d/10-gateway.conf' 'Requires=check-ebpf\.service' 'daed must not start when the eBPF preflight fails.'
Assert-FileContains 'overlay-debian/etc/systemd/system/daed.service.d/10-gateway.conf' 'Environment=XDG_DATA_HOME=/root/\.local/share' 'daed must use a stable data home.'
Assert-FileContains 'overlay-debian/etc/systemd/system/paopaodns.service' '--network host' 'PaoPaoDNS must use host networking for DNS performance.'
Assert-FileContains 'overlay-debian/etc/systemd/system/paopaodns.service' '--env-file /etc/paopaodns/paopaodns\.env' 'PaoPaoDNS must read env config from /etc/paopaodns.'
Assert-FileContains 'overlay-debian/etc/systemd/system/paopaodns.service' '-v /var/lib/paopaodns:/data' 'PaoPaoDNS data must persist under /var/lib/paopaodns.'
Assert-FileContains 'overlay-debian/etc/systemd/system/paopaodns.service' '\$\{PAOPAODNS_IMAGE\}' 'PaoPaoDNS service must use the configured image name.'
Assert-FileContains 'overlay-debian/etc/systemd/system/paopaodns.service' 'Conflicts=mini-ppdns\.service' 'PaoPaoDNS must conflict with mini-ppdns because both bind port 53.'
Assert-FileContains 'overlay-debian/etc/systemd/system/paopaodns.service' 'LimitNOFILE=1048576' 'PaoPaoDNS must raise file descriptor limits.'
Assert-FileContains 'overlay-debian/etc/systemd/system/mini-ppdns.service' 'Conflicts=paopaodns\.service' 'mini-ppdns fallback must conflict with PaoPaoDNS.'
Assert-FileContains 'overlay-debian/etc/paopaodns/paopaodns.env' 'PAOPAODNS_IMAGE=sliamb/paopaodns:latest' 'PaoPaoDNS env must define the runtime image.'
Assert-FileContains 'overlay-debian/etc/paopaodns/paopaodns.env' 'CNAUTO=yes' 'PaoPaoDNS must default to CN-aware mode.'
Assert-FileContains 'overlay-debian/etc/paopaodns/paopaodns.env' 'USE_MARK_DATA=yes' 'PaoPaoDNS must default to mark data enabled.'
Assert-FileContains 'overlay-debian/etc/sysctl.d/99-dae-gateway.conf' 'net\.ipv4\.ip_forward = 1' 'Debian sysctl profile must enable IPv4 forwarding before eBPF checks.'
Assert-FileContains 'overlay-debian/etc/sysctl.d/99-dae-gateway.conf' 'net\.ipv4\.tcp_congestion_control = bbr' 'Debian sysctl profile must enable BBR.'
Assert-FileContains 'overlay-debian/etc/sysctl.d/99-dae-gateway.conf' 'net\.core\.default_qdisc = fq' 'Debian sysctl profile must use fq as the default qdisc.'
Assert-FileContains 'overlay-debian/etc/sysctl.d/99-dae-gateway.conf' 'net\.ipv4\.conf\.all\.rp_filter = 0' 'Debian sysctl profile must allow one-arm gateway routing.'

Assert-FileIsAscii 'overlay-debian/usr/local/sbin/dae-gateway-firstboot' 'Debian firstboot must stay ASCII-only for VM consoles.'
Assert-FileContains 'overlay-debian/usr/local/sbin/dae-gateway-firstboot' 'new root password' 'Debian firstboot must prompt for the root password.'
Assert-FileDoesNotContain 'overlay-debian/usr/local/sbin/dae-gateway-firstboot' 'daed admin username|daed admin password|createUser|/graphql' 'Debian firstboot must not create daed admin users.'
Assert-FileContains 'overlay-debian/usr/local/sbin/gateway' '1\) daed manager' 'Debian gateway menu must include daed manager.'
Assert-FileContains 'overlay-debian/usr/local/sbin/gateway' '2\) PaoPaoDNS manager' 'Debian gateway menu must include PaoPaoDNS manager.'
Assert-FileContains 'overlay-debian/usr/local/sbin/gateway' '5\) QoS / CAKE' 'Debian gateway menu must include QoS.'
Assert-FileContains 'overlay-debian/usr/local/sbin/gateway' '6\) mini-ppdns fallback' 'Debian gateway menu must include mini-ppdns fallback.'
Assert-FileContains 'overlay-debian/usr/local/sbin/daed-manager' 'systemctl start "\$service_name"' 'Debian daed manager must use systemd.'
Assert-FileContains 'overlay-debian/usr/local/sbin/paopaodns-manager' 'systemctl start "\$service_name"' 'PaoPaoDNS manager must use systemd.'
Assert-FileContains 'overlay-debian/usr/local/sbin/paopaodns-manager' 'mini-ppdns-manager switch' 'PaoPaoDNS manager must provide a fallback switch.'
Assert-FileContains 'overlay-debian/usr/local/sbin/paopaodns-manager' 'Action: check only, no image pull and no restart' 'PaoPaoDNS update check must be check-only.'
Assert-FileDoesNotContain 'overlay-debian/usr/local/sbin/paopaodns-manager' 'docker pull sliamb/paopaodns:latest' 'PaoPaoDNS update check must not pull the latest image.'
Assert-FileContains 'overlay-debian/usr/local/sbin/mini-ppdns-manager' 'systemctl stop paopaodns\.service' 'mini-ppdns fallback switch must stop PaoPaoDNS first.'
Assert-FileContains 'overlay-debian/usr/local/sbin/qos-manager' 'tc qdisc replace dev "\$WAN_IFACE" root cake bandwidth' 'Debian QoS manager must configure CAKE upload shaping.'
Assert-FileContains 'overlay-debian/usr/local/sbin/qos-manager' 'mirred egress redirect dev ifb0' 'Debian QoS manager must configure IFB download shaping.'
Assert-FileContains 'overlay-debian/usr/local/sbin/check-ebpf' '/sys/kernel/btf/vmlinux' 'Debian eBPF check must verify BTF.'

Assert-FileContains 'README.md' 'Debian 13' 'README must document Debian 13 as the main image.'
Assert-FileContains 'README.md' 'PaoPaoDNS' 'README must document PaoPaoDNS.'
Assert-FileContains 'README.md' 'http://<gateway-ip>:2023' 'README must document the daed dashboard.'
Assert-FileDoesNotContain 'README.md' 'root / dae123456' 'README must not document the removed default root password.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'Smoke tests passed.'
