param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
$failures = New-Object System.Collections.Generic.List[string]

function Assert-FileContains {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Message
    )
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

function Assert-TextOrder {
    param(
        [string]$Path,
        [string]$First,
        [string]$Second,
        [string]$Message
    )
    $full = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $full)) {
        $failures.Add("Missing file: $Path")
        return
    }
    $text = Get-Content -LiteralPath $full -Raw
    $firstIndex = $text.IndexOf($First)
    $secondIndex = $text.IndexOf($Second)
    if ($firstIndex -lt 0 -or $secondIndex -lt 0 -or $firstIndex -ge $secondIndex) {
        $failures.Add($Message)
    }
}

function Assert-FileContainsUtf8Text {
    param(
        [string]$Path,
        [string]$Base64Text,
        [string]$Message
    )
    $full = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $full)) {
        $failures.Add("Missing file: $Path")
        return
    }
    $text = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($full))
    $pattern = [regex]::Escape([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Base64Text)))
    if ($text -notmatch $pattern) {
        $failures.Add($Message)
    }
}
function Assert-FileIsAscii {
    param(
        [string]$Path,
        [string]$Message
    )
    $full = Join-Path $Root $Path
    if (-not (Test-Path -LiteralPath $full)) {
        $failures.Add("Missing file: $Path")
        return
    }
    $bytes = [System.IO.File]::ReadAllBytes($full)
    foreach ($byte in $bytes) {
        if ($byte -gt 127) {
            $failures.Add($Message)
            return
        }
    }
}
function Assert-FileDoesNotContain {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Message
    )
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

function Assert-PathMissing {
    param(
        [string]$Path,
        [string]$Message
    )
    $full = Join-Path $Root $Path
    if (Test-Path -LiteralPath $full) {
        $failures.Add($Message)
    }
}

Assert-FileContains '.github/workflows/build-ova.yml' 'workflow_dispatch' 'Workflow must support manual Run workflow.'
Assert-FileContains '.github/workflows/build-ova.yml' 'push:[\s\S]*branches:[\s\S]*- main' 'Workflow must auto-build when main is pushed.'
Assert-FileContains '.github/workflows/build-ova.yml' 'cancel-in-progress: true' 'Workflow must cancel stale in-progress OVA builds when a newer commit is pushed.'
Assert-FileContains '.github/workflows/build-ova.yml' "inputs\.alpine_version \|\| '3\.24'" 'Push-triggered builds must fall back to the default Alpine version.'
Assert-FileContains '.github/workflows/build-ova.yml' "inputs\.daed_version \|\| 'latest'" 'Push-triggered builds must fall back to the default daed version.'
Assert-FileContains '.github/workflows/build-ova.yml' "inputs\.disk_size \|\| '4G'" 'Push-triggered builds must fall back to the default disk size.'
Assert-FileContains '.github/workflows/build-ova.yml' 'actions/upload-artifact@v4' 'Workflow must upload OVA artifact.'
Assert-FileContains '.github/workflows/build-ova.yml' 'daed-alpine-gateway-ova' 'Workflow must upload the daed OVA artifact.'
Assert-FileContains '.github/workflows/build-ova.yml' '\$\{\{ github\.workspace \}\}/dist/\*\.ova' 'Workflow must upload the OVA file.'
Assert-FileDoesNotContain '.github/workflows/build-ova.yml' '\$\{\{ github\.workspace \}\}/dist/\*\.sha256' 'Workflow must not upload checksum files when the user only wants the OVA.'
Assert-FileDoesNotContain '.github/workflows/build-ova.yml' '\$\{\{ github\.workspace \}\}/dist/build\.log' 'Workflow must not include build logs in the downloaded artifact when the user only wants the OVA.'
Assert-FileDoesNotContain '.github/workflows/build-ova.yml' 'path: \$\{\{ github\.workspace \}\}/dist\s' 'Workflow must not upload the whole dist directory because the standalone VMDK duplicates the VMDK already inside the OVA.'
Assert-FileContains '.github/workflows/build-ova.yml' 'Prepare diagnostics artifact' 'Workflow must create diagnostic files before any step that can fail.'
Assert-FileContains '.github/workflows/build-ova.yml' 'GITHUB_WORKSPACE.*/dist' 'Workflow must write diagnostics into the workspace dist directory.'
Assert-FileContains '.github/workflows/build-ova.yml' 'ci-context\.txt' 'Workflow must preserve CI context for diagnosing pre-build failures.'
Assert-FileContains '.github/workflows/build-ova.yml' 'smoke\.log' 'Workflow must preserve smoke test output when template checks fail.'
Assert-FileContains '.github/workflows/build-ova.yml' 'List artifact files' 'Workflow must print artifact contents before upload.'
Assert-FileContains '.github/workflows/build-ova.yml' 'shell: bash \{0\}' 'Workflow artifact listing step must disable the default bash -e wrapper.'
Assert-FileContains '.github/workflows/build-ova.yml' 'set \+e' 'Workflow artifact listing step must keep running even when diagnostics commands fail.'
Assert-FileContains '.github/workflows/build-ova.yml' 'exit 0' 'Workflow artifact listing step must not block artifact upload.'
Assert-FileContains '.github/workflows/build-ova.yml' 'cat "\$\{GITHUB_WORKSPACE\}/dist/build\.log"' 'Workflow must print the OVA build log when the build result is non-zero.'
Assert-FileContains '.github/workflows/build-ova.yml' '::error title=OVA build failed::' 'Workflow must expose failed OVA build logs in a public annotation.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'linux-virt' 'Build script must install Alpine linux-virt for VMware eBPF/BTF support.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'vmlinuz-virt' 'GRUB must boot the BTF-enabled Alpine virtual kernel.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'initramfs-virt' 'GRUB must use the initramfs for the Alpine virtual kernel.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'openssh-server' 'Build script must install OpenSSH server for first login access.'
Assert-FileDoesNotContain 'scripts/build-alpine-ova.sh' "root:dae123456" 'Build script must not bake the old default root password into the image.'
Assert-FileContains 'scripts/build-alpine-ova.sh' "root:!" 'Build script must lock root until firstboot sets a password.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'PermitRootLogin yes' 'Build script must allow root SSH password login for first access.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'PasswordAuthentication yes' 'Build script must allow SSH password authentication for first access.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'rc-update add sshd default' 'Build script must enable sshd by default.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'bpffs' 'Build script must configure bpffs mount.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'cgroup2' 'Build script must configure cgroup2 mount.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'iproute2-tc' 'Build script must install tc for CAKE/IFB QoS.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'adapter_type=lsilogic' 'VMDK conversion must use VMware-compatible lsilogic adapter metadata.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'sha256sum "\$\{OVA_FILE\}" >"\$\{DIST_DIR\}/\$\{IMAGE_NAME\}\.sha256"' 'Build script must publish a checksum for the OVA artifact users download.'
Assert-FileDoesNotContain 'scripts/build-alpine-ova.sh' 'sha256sum "\$\{OVA_FILE\}" "\$\{VMDK_IMAGE\}" "\$\{OVF_FILE\}"' 'Build script must not publish checksums for intermediate files that are not uploaded.'
Assert-FileContains 'scripts/ci-build-ova.sh' 'DIST_DIR=.*dist' 'CI build wrapper must target a dist artifact directory.'
Assert-FileContains 'scripts/ci-build-ova.sh' '\$\{DIST_DIR\}/build\.log' 'CI build wrapper must preserve build logs for failed OVA builds.'
Assert-FileContains 'scripts/ci-build-ova.sh' '\$\{DIST_DIR\}/build\.status' 'CI build wrapper must preserve the OVA build exit status.'
Assert-FileContains 'scripts/ci-build-ova.sh' 'LOG_FILE="/tmp/ova-build\.log"' 'CI build wrapper must keep a stable temporary OVA build log path.'
Assert-FileContains 'scripts/ci-build-ova.sh' 'tee "\$\{LOG_FILE\}"' 'CI build wrapper must stream OVA build logs while preserving them.'
Assert-FileContains 'scripts/ci-build-ova.sh' 'PIPESTATUS' 'CI build wrapper must preserve the real OVA build exit status through tee.'
Assert-FileContains 'scripts/ci-build-ova.sh' 'GITHUB_WORKSPACE' 'CI build wrapper must write logs back to the GitHub workspace dist directory.'
Assert-FileContains 'scripts/ci-build-ova.sh' 'sudo chown -R "\$\(id -u\):\$\(id -g\)" "\$\{DIST_DIR\}"' 'CI build wrapper must make sudo-created dist files writable by the runner before writing diagnostics.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'RAW_CAPACITY_BYTES' 'OVF capacity must come from the raw disk size, not qemu-img output from the streamOptimized VMDK.'
Assert-FileContains 'scripts/render-ovf.sh' 'CAPACITY_BYTES="\$\{6:\?capacity bytes required\}"' 'OVF renderer must require an explicit single capacity value.'
Assert-FileContains 'scripts/render-ovf.sh' '\[\[ "\$\{CAPACITY_BYTES\}" =~ \^\[0-9\]\+\$ \]\]' 'OVF renderer must reject non-numeric or multi-line capacity values.'
Assert-FileContains 'scripts/render-ovf.sh' 'ovf:capacity="\$\{CAPACITY_BYTES\}"' 'OVF disk capacity must be rendered from the validated explicit capacity value.'
Assert-FileContains 'scripts/render-ovf.sh' '<rasd:ElementName>Hard disk 1</rasd:ElementName>[\s\S]*<rasd:HostResource>ovf:/disk/vmdisk1</rasd:HostResource>[\s\S]*<rasd:InstanceID>3</rasd:InstanceID>[\s\S]*<rasd:Parent>5</rasd:Parent>[\s\S]*<rasd:ResourceType>17</rasd:ResourceType>' 'Hard disk OVF item must keep RASD elements in schema order for strict importers.'
Assert-FileContains 'scripts/render-ovf.sh' '<rasd:ResourceSubType>lsilogic</rasd:ResourceSubType>' 'OVF SCSI controller must use VMware-compatible lsilogic subtype.'
Assert-FileContains 'scripts/render-ovf.sh' '<rasd:ResourceSubType>VmxNet3</rasd:ResourceSubType>' 'OVF network adapter must use VMware-native VmxNet3 subtype for ESXi.'
Assert-FileContains 'scripts/render-ovf.sh' '<rasd:Description>VmxNet3 ethernet adapter</rasd:Description>' 'OVF network adapter description must match the VmxNet3 subtype.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'open-vm-tools' 'Build script must install VMware guest tools for ESXi.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'vmxnet3' 'Build script must preload VMware VmxNet3 network support.'
Assert-TextOrder 'scripts/build-alpine-ova.sh' 'chmod +x /etc/init.d/gateway-network-init' 'rc-update add gateway-network-init boot' 'Network init service must be registered after the overlay init script exists.'
Assert-FileDoesNotContain 'scripts/build-alpine-ova.sh' 'auto eth0\s+iface eth0 inet dhcp' 'Base network config must not assume eth0; the boot init service must persist the detected interface.'
Assert-FileContains 'scripts/install-daed.sh' 'daeuniverse/daed' 'daed installer must download from daeuniverse/daed.'
Assert-FileContains 'scripts/install-daed.sh' 'daed-linux-\$\{ASSET_ARCH\}\.zip' 'daed installer must use upstream daed binary release zips.'
Assert-FileDoesNotContain 'scripts/install-daed.sh' '-perm -u\+x' 'daed installer must not depend on zip executable permission bits.'
Assert-FileContains 'scripts/install-daed.sh' 'geoip\.dat' 'daed installer must install geoip.dat for split rules.'
Assert-FileContains 'scripts/install-daed.sh' 'geosite\.dat' 'daed installer must install geosite.dat for split rules.'
Assert-PathMissing 'scripts/install-dae.sh' 'Old dae installer must be removed from the daed-first image.'
Assert-FileContains 'scripts/install-mini-ppdns.sh' 'kkkgo/mini-ppdns' 'mini-ppdns installer must download from kkkgo/mini-ppdns.'
Assert-FileContains 'overlay/etc/init.d/daed' 'check-ebpf' 'daed OpenRC service must depend on eBPF preflight.'
Assert-FileContains 'overlay/etc/init.d/daed' 'run -c /etc/daed/' 'daed OpenRC service must run daed with /etc/daed as its config directory.'
Assert-FileContains 'overlay/etc/init.d/daed' 'command="/usr/bin/daed"' 'daed OpenRC service must launch the installed daed binary.'
Assert-PathMissing 'overlay/etc/init.d/dae' 'Old dae OpenRC service must be removed from the daed-first image.'
Assert-PathMissing 'overlay/usr/local/sbin/dae-manager' 'Old dae manager must be removed from the daed-first image.'
Assert-PathMissing 'overlay/etc/dae/config.dae' 'Old standalone dae config template must be removed from the daed-first image.'
Assert-FileContains 'overlay/etc/init.d/mini-ppdns' 'mini-ppdns' 'mini-ppdns OpenRC service must exist.'
Assert-FileContains 'overlay/etc/init.d/dae-qos' 'qos-manager' 'QoS OpenRC service must call qos-manager.'
Assert-FileContains 'overlay/etc/init.d/dae-qos' 'command_args="apply"' 'QoS OpenRC service must apply configured CAKE/IFB rules.'
Assert-FileContains 'overlay/usr/local/sbin/gateway-network-init' 'configure_iface_dhcp' 'Network init must persist DHCP config for the detected ESXi interface.'
Assert-FileContains 'overlay/usr/local/sbin/gateway-network-init' 'is_real_iface' 'Network init must filter virtual interfaces created after boot.'
Assert-FileContains 'overlay/usr/local/sbin/gateway-network-init' 'dae0|docker\*|veth\*|br-\*|tun\*|tap\*' 'Network init must ignore dae and container/tunnel virtual interfaces.'
Assert-FileContains 'overlay/usr/local/sbin/gateway-network-init' 'auto \$iface' 'Network init must write the detected interface name instead of assuming eth0.'
Assert-FileContains 'overlay/usr/local/sbin/gateway-network-init' 'iface \$iface inet dhcp' 'Network init must configure DHCP for the detected interface before OpenRC networking starts.'
Assert-FileContains 'overlay/usr/local/sbin/gateway-network-init' 'net\.ipv4\.ip_forward=1' 'Network init must enable IPv4 forwarding for default-gateway use.'
Assert-FileContains 'overlay/usr/local/sbin/gateway-network-init' 'rp_filter' 'Network init must disable rp_filter for same-LAN one-arm gateway mode.'
Assert-FileContains 'overlay/usr/local/sbin/gateway-network-init' 'send_redirects' 'Network init must disable ICMP redirects for same-LAN one-arm gateway mode.'
Assert-FileContains 'overlay/usr/local/sbin/gateway-network-init' 'accept_redirects' 'Network init must disable accepting redirects for gateway mode.'
Assert-FileContains 'overlay/usr/local/sbin/gateway-network-init' 'MASQUERADE' 'Network init must add NAT masquerading so same-LAN clients can use the VM as their gateway.'
Assert-FileContains 'overlay/usr/local/sbin/gateway-network-init' 'ip -4 route show dev "\$1" scope link' 'Network init must derive the LAN CIDR from the detected interface.'
Assert-FileContains 'overlay/usr/local/sbin/gateway' '1\) daed manager' 'gateway menu must route to daed manager.'
Assert-FileDoesNotContain 'overlay/usr/local/sbin/gateway' 'mini-ppdns manager' 'gateway menu must not show the mini-ppdns manager shortcut.'
Assert-FileContains 'overlay/usr/local/sbin/gateway' '2\) eBPF check' 'gateway menu must provide a numeric eBPF shortcut.'
Assert-FileDoesNotContain 'overlay/usr/local/sbin/gateway' 'IP and routes' 'gateway menu must not show the IP and routes shortcut.'
Assert-FileContains 'overlay/usr/local/sbin/gateway' '3\) Gateway overview' 'gateway menu must provide a concise overview shortcut.'
Assert-FileContains 'overlay/usr/local/sbin/gateway' '4\) QoS / CAKE' 'gateway menu must route to QoS manager.'
Assert-FileContains 'overlay/usr/local/sbin/gateway' '0\) Exit' 'gateway menu must provide an exit shortcut.'
Assert-FileContains 'overlay/usr/local/sbin/qos-manager' 'tc qdisc add dev "\$ifb_dev" root cake bandwidth' 'QoS manager must configure CAKE on IFB for download shaping.'
Assert-FileContains 'overlay/usr/local/sbin/qos-manager' 'mirred egress redirect dev "\$ifb_dev"' 'QoS manager must redirect ingress traffic to IFB.'
Assert-FileContains 'overlay/usr/local/sbin/qos-manager' 'tc qdisc replace dev "\$WAN_IFACE" root cake bandwidth' 'QoS manager must configure CAKE on the WAN interface for upload shaping.'
Assert-FileContains 'overlay/usr/local/sbin/qos-manager' '/etc/dae-gateway-qos.conf' 'QoS manager must persist configuration.'
Assert-FileContains 'overlay/usr/local/sbin/qos-manager' 'modprobe ifb' 'QoS manager must load IFB support.'
Assert-FileContains 'overlay/usr/local/sbin/daed-manager' 'daed status' 'daed manager must show a concise daed status view.'
Assert-FileContains 'overlay/usr/local/sbin/daed-manager' 'Details' 'daed manager must keep technical checks behind a details command.'
Assert-FileContains 'overlay/usr/local/sbin/daed-manager' 'https://api.github.com/repos/daeuniverse/daed/releases' 'daed manager must check the latest daed release.'
Assert-FileContains 'overlay/usr/local/sbin/daed-manager' 'start_service' 'daed manager must wrap start so stale OpenRC state can be recovered.'
Assert-FileContains 'overlay/usr/local/sbin/daed-manager' 'rc-service "\$service_name" zap' 'daed manager must clear stale OpenRC started state before retrying a stopped service.'
Assert-FileIsAscii 'overlay/usr/local/sbin/daed-firstboot' 'firstboot console wizard must stay ASCII-only because the VM text console may not have CJK fonts.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'prompt_msg' 'firstboot must print interactive prompts outside command substitution.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' '>&2' 'firstboot interactive prompts must be visible while captured values are returned on stdout.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'new root password' 'firstboot must visibly prompt for the root password in ASCII.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'Confirm .*label' 'firstboot must visibly prompt for password confirmation in ASCII.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'daed Alpine Gateway firstboot wizard' 'firstboot wizard header must be ASCII.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'Enable BBR TCP optimization' 'firstboot TCP tuning prompt must be ASCII.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'Creating the first daed admin user' 'firstboot daed admin creation status must be ASCII.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'Firstboot wizard completed' 'firstboot completion message must be ASCII.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'if ! read -r first' 'firstboot must restore terminal echo if password input is interrupted.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'if ! read -r second' 'firstboot must restore terminal echo if password confirmation is interrupted.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'write_tcp_tuning' 'firstboot must generate TCP tuning settings.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'net.ipv4.tcp_congestion_control=bbr' 'firstboot must enable BBR when TCP optimization is selected.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'net.core.default_qdisc=fq' 'firstboot must enable fq when TCP optimization is selected.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'createUser' 'firstboot must try to create the daed admin user through GraphQL.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'http://127\.0\.0\.1:2023/graphql' 'firstboot must use the local daed GraphQL endpoint.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'start_firstboot_daed' 'firstboot must start daed directly for setup instead of recursing into OpenRC.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' '--api-only' 'firstboot must start a temporary API-only daed process so user creation does not depend on transparent proxy startup.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'DAED_DATA_HOME="/root/\.local/share"' 'firstboot must pin the daed data home used for admin creation.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'HOME="\$DAED_HOME" XDG_DATA_HOME="\$DAED_DATA_HOME"' 'temporary firstboot daed must use the same home and data directory as the normal service.'
Assert-FileContains 'overlay/etc/init.d/daed' '--env HOME=/root --env XDG_DATA_HOME=/root/\.local/share' 'normal daed service must read the same user database created during firstboot.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'numberUsers' 'firstboot readiness must probe GraphQL instead of depending on the web UI root route.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'http://127\.0\.0\.1:2023/graphql' 'firstboot readiness must target the local GraphQL endpoint.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'firstboot-daed\.err' 'firstboot must keep temporary daed startup errors visible for diagnosis.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'connect-timeout' 'firstboot curl calls must have timeouts so setup cannot hang indefinitely.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'trap cleanup_firstboot EXIT INT TERM' 'firstboot must clean up a temporary daed process on exit or interruption.'
Assert-TextOrder 'overlay/usr/local/sbin/daed-firstboot' 'stop_firstboot_daed()' 'trap cleanup_firstboot EXIT INT TERM' 'firstboot must install cleanup trap after the cleanup function chain is defined.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'kill -KILL "\$DAED_FIRSTBOOT_PID"' 'firstboot must force-stop a temporary daed process if graceful shutdown does not finish.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'grep -Eq' 'firstboot must use an explicit extended regex for GraphQL token matching on Alpine.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' '"createUser"\[\[:space:\]\]\*:\[\[:space:\]\]\*"\[\^" \]\+"' 'firstboot must only report daed admin creation after GraphQL confirms createUser returned a token string.'
Assert-FileDoesNotContain 'overlay/usr/local/sbin/daed-firstboot' 'rc-service daed (start|restart)' 'firstboot must not call rc-service daed while it is ordered before daed.'
Assert-FileDoesNotContain 'overlay/usr/local/sbin/daed-firstboot' 'rc-service sshd' 'firstboot must not restart sshd and risk blocking the recovery path.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' '/etc/dae-gateway-firstboot.done' 'firstboot must write a completion marker.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'prompt_uint_default' 'firstboot must validate numeric TCP tuning input instead of exiting on shell arithmetic errors.'
Assert-FileContains 'overlay/usr/local/sbin/daed-firstboot' 'must be a positive integer' 'firstboot must explain invalid numeric TCP tuning input in ASCII.'
Assert-FileContains 'overlay/etc/init.d/daed-firstboot' 'keyword -timeout' 'firstboot OpenRC service must not time out while waiting for console input.'
Assert-FileContains 'overlay/etc/init.d/daed-firstboot' 'after bootmisc gateway-network-init check-ebpf mini-ppdns dae-qos sshd' 'firstboot must run after daed prerequisites and sshd so SSH remains available for recovery.'
Assert-FileContains 'overlay/etc/init.d/daed-firstboot' 'before daed' 'firstboot must finish before the normal daed service starts.'
Assert-FileDoesNotContain 'overlay/etc/init.d/daed-firstboot' 'before daed sshd' 'firstboot must not block sshd while waiting for interactive setup.'
Assert-FileContains 'overlay/usr/local/sbin/mini-ppdns-manager' 'mini-ppdns status' 'mini-ppdns manager must show a concise mini-ppdns status view.'
Assert-FileContains 'overlay/usr/local/sbin/mini-ppdns-manager' 'Details' 'mini-ppdns manager must keep technical checks behind a details command.'
Assert-FileContains 'overlay/usr/local/sbin/mini-ppdns-manager' 'https://raw.githubusercontent.com/kkkgo/mini-ppdns' 'mini-ppdns manager must probe the upstream binary.'
Assert-FileContains 'overlay/usr/local/sbin/mini-ppdns-manager' '7\) Configure DNS' 'mini-ppdns manager must expose interactive DNS configuration.'
Assert-FileContains 'overlay/usr/local/sbin/mini-ppdns-manager' 'configure_dns' 'mini-ppdns manager must implement DNS configuration.'
Assert-FileContains 'overlay/usr/local/sbin/mini-ppdns-manager' '223\.5\.5\.5:53 119\.29\.29\.29:53' 'mini-ppdns manager must provide recommended mainland DNS defaults.'
Assert-FileContains 'overlay/usr/local/sbin/mini-ppdns-manager' '1\.1\.1\.1:53 8\.8\.8\.8:53' 'mini-ppdns manager must provide recommended fallback DNS defaults.'
Assert-FileContains 'overlay/usr/local/sbin/mini-ppdns-manager' 'normalize_endpoint' 'mini-ppdns manager must normalize DNS endpoints and add default ports.'
Assert-FileContains 'overlay/etc/profile.d/dae-gateway.sh' 'gateway' 'Login profile must hint that gateway opens the management menu.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'chmod \+x /usr/local/sbin/gateway' 'Build script must make the gateway menu executable.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'chmod \+x /usr/local/sbin/qos-manager' 'Build script must make qos-manager executable.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'chmod \+x /etc/init.d/dae-qos' 'Build script must make QoS OpenRC service executable.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'chmod \+x /usr/local/sbin/daed-manager /usr/local/sbin/mini-ppdns-manager' 'Build script must make service managers executable.'
Assert-FileContains 'scripts/build-alpine-ova.sh' '/etc/dae-gateway-release' 'Build script must write gateway release metadata for update checks.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'rc-update add mini-ppdns default' 'mini-ppdns must start by default.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'rc-update add daed default' 'daed must start by default after the appliance boots.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'rc-update add daed-firstboot default' 'firstboot must run on the first appliance boot.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'tcp_bbr' 'Build script must preload the BBR module.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'sch_fq' 'Build script must preload fq qdisc support.'
Assert-FileContains 'README.md' 'GitHub Actions' 'README must document GitHub Actions build usage.'
Assert-FileDoesNotContain 'README.md' 'root / dae123456' 'README must not document the removed default root password.'
Assert-FileContains 'README.md' 'firstboot' 'README must document firstboot credential setup.'
Assert-FileContains 'README.md' 'mini-ppdns' 'README must document mini-ppdns rather than full PaoPaoDNS.'
Assert-FileContains 'README.md' 'gateway' 'README must document the gateway management menu.'
Assert-FileContains 'README.md' 'daed-manager' 'README must document the daed manager.'
Assert-FileContains 'README.md' 'mini-ppdns-manager' 'README must document the mini-ppdns manager.'
Assert-FileContains 'README.md' 'mini-ppdns-manager configure' 'README must document interactive mini-ppdns DNS configuration.'
Assert-FileContains 'README.md' 'qos-manager' 'README must document QoS manager.'
Assert-FileContains 'README.md' 'CAKE' 'README must document CAKE QoS.'
Assert-FileContains 'README.md' 'IFB' 'README must document IFB download shaping.'
Assert-FileContains 'README.md' 'Details' 'README must document that technical checks are in details views.'
Assert-FileContains 'README.md' 'http://<gateway-ip>:2023' 'README must document how to open the daed dashboard.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'Smoke tests passed.'
