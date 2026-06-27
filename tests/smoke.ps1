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

# --- Packer / VyOS route contract ---
Assert-PathExists 'packer/build.pkr.hcl' 'Packer build file must exist.'
Assert-PathExists 'packer/scripts/setup-gateway.sh' 'Packer provisioner must exist.'
Assert-FileContains 'packer/build.pkr.hcl' 'source\s*=\s*"packer/custom-services/"' 'Packer must upload the committed custom-services dir.'

# --- Committed config single source of truth ---
Assert-PathExists 'packer/custom-services/mosdns/config.yaml' 'MosDNS config must exist.'
Assert-PathExists 'packer/custom-services/daed/config.dae' 'daed config must exist.'
Assert-PathExists 'packer/custom-services/scripts/custom-services-latebind.sh' 'Late-bind script must exist.'
Assert-PathExists 'packer/custom-services/scripts/dns-hijack.sh' 'DNS hijack script must exist.'
Assert-PathExists 'packer/custom-services/scripts/geosite-update.sh' 'Geosite updater must exist.'
Assert-PathExists 'packer/custom-services/system/sysctl.conf' 'Golden image sysctl tuning must exist.'
Assert-FileDoesNotContain 'packer/custom-services/daed/config.dae' '(?s)^dns\s*\{' 'daed must not provide the LAN DNS entrypoint; MosDNS is the only DNS engine.'
Assert-FileDoesNotContain 'packer/custom-services/mosdns/config.yaml' 'smartdns|127\.0\.0\.1:5335|5335' 'MosDNS must not chain to SmartDNS.'

# --- MosDNS ---
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' '<LAN_BIND_IP>:53' 'MosDNS must receive LAN DNS directly on the late-bound LAN IP.'
Assert-FileDoesNotContain 'packer/custom-services/mosdns/config.yaml' '127\.0\.0\.1:5353' 'MosDNS must not be hidden behind daed DNS.'
Assert-FileDoesNotContain 'packer/custom-services/mosdns/config.yaml' '0\.0\.0\.0' 'MosDNS must never bind 0.0.0.0.'
Assert-FileDoesNotContain 'packer/custom-services/mosdns/config.yaml' '(?m)^servers:' 'MosDNS v5 config must not use the removed top-level servers key.'
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' 'type: udp_server' 'MosDNS v5 config must define the UDP listener as a plugin.'
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' 'type: tcp_server' 'MosDNS v5 config must define the TCP listener as a plugin.'
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' 'has_resp' 'MosDNS sequence must accept successful direct/cache responses before fallback DoH.'
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' 'exec: accept' 'MosDNS sequence must stop after successful CN/cache resolution.'
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' 'forward_cn' 'MosDNS must resolve CN domains itself without SmartDNS.'
Assert-FileDoesNotContain 'packer/custom-services/mosdns/config.yaml' '8\.8\.8\.8' 'MosDNS must not use public 8.8.8.8 DoH for overseas.'
Assert-FileDoesNotContain 'packer/custom-services/mosdns/config.yaml' 'doh\.pub' 'MosDNS must not use doh.pub for overseas.'
Assert-FileDoesNotContain 'packer/custom-services/mosdns/config.yaml' 'https://dmit\.wwa\.im/dq' 'MosDNS must not use rate-limited Dmit DoH for overseas.'
Assert-FileDoesNotContain 'packer/custom-services/mosdns/config.yaml' '154\.17\.2\.123:443' 'MosDNS must not pin rate-limited Dmit DoH dial_addr.'
Assert-FileDoesNotContain 'packer/custom-services/mosdns/config.yaml' 'https://bwg\.wwa\.im/dq' 'MosDNS must not depend on BWG node-owned DoH.'
Assert-FileDoesNotContain 'packer/custom-services/mosdns/config.yaml' '104\.194\.84\.105:443' 'MosDNS must not pin BWG DoH dial_addr.'
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' 'https://cloudflare-dns\.com/dns-query' 'MosDNS must use Cloudflare DoH for overseas.'
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' '1\.1\.1\.1:443' 'MosDNS must pin Cloudflare DoH dial_addr.'
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' 'lazy_cache_ttl' 'MosDNS must enable lazy cache.'
Assert-FileDoesNotContain 'packer/custom-services/mosdns/config.yaml' '192\.168\.0\.' 'MosDNS template must not hardcode a LAN address.'

# --- daed ---
Assert-FileDoesNotContain 'packer/custom-services/daed/config.dae' "mosdns: 'udp://127\.0\.0\.1:5353'" 'daed must not forward DNS to MosDNS; DNS is handled outside daed.'
Assert-FileDoesNotContain 'packer/custom-services/daed/config.dae' '127\.0\.0\.1:5335|smartdns' 'daed must not mention SmartDNS.'
Assert-FileDoesNotContain 'packer/custom-services/daed/config.dae' 'dip\(doh\.pub\)' 'daed must not use the invalid doh.pub dip rule.'
Assert-FileDoesNotContain 'packer/custom-services/daed/config.dae' 'dmit\.wwa\.im|bwg\.wwa\.im' 'daed must not keep stale node-owned DoH bypasses.'
Assert-FileContains 'packer/custom-services/daed/config.dae' '(?s)group\s*\{.*proxy\s*\{' 'daed template must define the proxy group used by fallback.'
Assert-FileContains 'packer/custom-services/daed/config.dae' 'fallback: proxy' 'daed must proxy overseas traffic by default.'
Assert-FileContains 'packer/custom-services/daed/config.dae' 'dip\(geoip:cn\) -> direct' 'daed must direct CN destinations.'
Assert-FileContains 'packer/custom-services/daed/config.dae' 'domain\(geosite:cn\) -> direct' 'daed must direct CN domains.'
Assert-FileContains 'packer/custom-services/daed/config.dae' 'pname\(NetworkManager, systemd-resolved, dnsmasq, chronyd, mosdns\) -> must_direct' 'MosDNS must bypass daed so DNS egress stays decoupled from proxy routing.'
Assert-FileDoesNotContain 'packer/custom-services/daed/config.dae' 'pname\(.*smartdns' 'SmartDNS must not appear in daed routing after removal.'
Assert-FileContains 'packer/custom-services/daed/config.dae' 'suffix:youtube\.com' 'daed must route YouTube before CN geoip fallback.'
Assert-FileContains 'packer/custom-services/daed/config.dae' 'suffix:googlevideo\.com' 'daed must route Googlevideo before CN geoip fallback.'
Assert-FileContains 'packer/custom-services/daed/config.dae' 'suffix:nflxvideo\.net' 'daed must route Netflix video before CN geoip fallback.'
Assert-FileContains 'packer/custom-services/daed/config.dae' 'suffix:openai\.com' 'daed must route AI domains before CN geoip fallback.'
Assert-FileDoesNotContain 'packer/custom-services/daed/config.dae' '192\.168\.0\.' 'daed template must not hardcode a LAN address.'
Assert-FileDoesNotContain 'packer/custom-services/daed/config.dae' 'sip\(<LAN_SUBNET>\)' 'daed template must not depend on LAN subnet rules.'
Assert-FileDoesNotContain 'packer/custom-services/daed/config.dae' 'l4proto\(udp\) && dport\(443\) -> block' 'daed template must not rely on broad QUIC block rules.'

# --- Scripts ---
Assert-FileContains 'packer/custom-services/scripts/custom-services-latebind.sh' 'seq 1 30' 'Late-bind must retry while waiting for the LAN IP.'
Assert-FileContains 'packer/custom-services/scripts/custom-services-latebind.sh' 'Refusing unsafe' 'Late-bind must refuse unsafe LAN DNS binds.'
Assert-FileContains 'packer/custom-services/scripts/custom-services-latebind.sh' '<LAN_BIND_IP>' 'Late-bind must render the MosDNS LAN listener.'
Assert-FileContains 'packer/custom-services/scripts/custom-services-latebind.sh' 'dns-hijack\.sh' 'Late-bind must apply DNS hijack after rendering the LAN IP.'
Assert-FileContains 'packer/custom-services/scripts/custom-services-latebind.sh' 'cp -f "\$\{BASE\}/daed/config\.dae\.template"' 'Late-bind must copy the daed loopback template.'
Assert-FileContains 'scripts/late-bind.sh' 'resolve_lan_if' 'Source-build late-bind must auto-detect the LAN interface.'
Assert-FileContains 'scripts/late-bind.sh' '<LAN_BIND_IP>' 'Source-build late-bind must render the MosDNS LAN listener.'
Assert-FileContains 'scripts/late-bind.sh' 'dns-hijack\.sh' 'Source-build late-bind must apply DNS hijack after rendering the LAN IP.'
Assert-FileContains 'scripts/late-bind.sh' 'cp -f "\$\{BASE\}/daed/config\.dae\.template"' 'Source-build late-bind must copy the daed loopback template.'
Assert-FileDoesNotContain 'scripts/late-bind.sh' 'LAN_IF="\$\{LAN_INTERFACE:-eth1\}"' 'Source-build late-bind must not hardcode eth1 as the LAN interface.'
Assert-FileContains 'scripts/99-custom-proxy.chroot' 'systemctl enable late-bind\.service' 'Build hook must enable late-bind as the boot orchestrator.'
Assert-FileDoesNotContain 'scripts/99-custom-proxy.chroot' 'systemctl enable daed\.service mosdns\.service smartdns\.service late-bind\.service' 'Build hook must not enable services that race before late-bind renders configs.'
Assert-FileContains 'packer/custom-services/scripts/geosite-update.sh' 'MIN_LINES=1000' 'Geosite updater must enforce a minimum line count.'
Assert-FileContains 'packer/custom-services/scripts/geosite-update.sh' 'systemctl restart mosdns' 'Geosite updater must restart MosDNS on success.'
Assert-FileContains 'packer/custom-services/scripts/geosite-update.sh' 'direct-list\.txt' 'Geosite updater must use an existing CN rules text source.'
Assert-FileContains 'packer/custom-services/scripts/geosite-update.sh' 'proxy-list\.txt' 'Geosite updater must use an existing overseas rules text source.'
Assert-FileDoesNotContain 'packer/custom-services/scripts/custom-services-latebind.sh' 'daed-provision\.sh|graphql|updateDns|createDns' 'Late-bind must not inject DNS into daed wing.db.'
Assert-FileContains 'packer/custom-services/scripts/dns-hijack.sh' 'table inet daed_dns_hijack' 'DNS hijack must use a dedicated nftables table.'
Assert-FileContains 'packer/custom-services/scripts/dns-hijack.sh' 'hook prerouting priority dstnat' 'DNS hijack must run in prerouting dstnat.'
Assert-FileContains 'packer/custom-services/scripts/dns-hijack.sh' 'iifname "\$\{LAN_IF\}" udp dport 53 redirect to :53' 'DNS hijack must redirect LAN UDP/53 to local MosDNS.'
Assert-FileContains 'packer/custom-services/scripts/dns-hijack.sh' 'iifname "\$\{LAN_IF\}" tcp dport 53 redirect to :53' 'DNS hijack must redirect LAN TCP/53 to local MosDNS.'
Assert-FileContains 'packer/custom-services/scripts/dns-hijack.sh' 'tcp dport 853 reject' 'DNS hijack must block LAN DoT escapes.'
Assert-FileContains 'packer/custom-services/scripts/dns-hijack.sh' 'udp dport 853 reject' 'DNS hijack must block LAN DoT escapes over UDP.'
Assert-FileContains 'packer/custom-services/system/sysctl.conf' 'net\.core\.default_qdisc=fq' 'Golden image must enable fq.'
Assert-FileContains 'packer/custom-services/system/sysctl.conf' 'net\.ipv4\.tcp_congestion_control=bbr' 'Golden image must enable BBR.'
Assert-FileContains 'packer/custom-services/system/sysctl.conf' 'net\.ipv6\.conf\.all\.disable_ipv6=1' 'Golden image must disable IPv6 globally.'
Assert-FileContains 'packer/custom-services/system/sysctl.conf' 'net\.ipv6\.conf\.default\.disable_ipv6=1' 'Golden image must disable IPv6 by default.'

# --- Provisioner ---
Assert-FileContains 'packer/scripts/setup-gateway.sh' 'daeuniverse/daed' 'Provisioner must download daed.'
Assert-FileContains 'packer/scripts/setup-gateway.sh' 'IrineSistiana/mosdns' 'Provisioner must download MosDNS.'
Assert-FileContains 'packer/scripts/setup-gateway.sh' 'dns-hijack\.sh' 'Provisioner must install the DNS hijack script.'
Assert-FileContains 'packer/scripts/setup-gateway.sh' 'sysctl\.conf' 'Provisioner must install Golden Image sysctl tuning.'
Assert-FileContains 'packer/scripts/setup-gateway.sh' 'systemctl restart systemd-sysctl' 'Provisioner must apply sysctl tuning during image setup.'
Assert-FileDoesNotContain 'packer/scripts/setup-gateway.sh' 'pymumu/smartdns|smartdns\.service|SMARTDNS_DIR' 'Provisioner must not install SmartDNS.'
Assert-FileContains 'packer/scripts/setup-gateway.sh' 'geolocation-!cn\.txt' 'Provisioner must download the overseas geosite list.'
Assert-FileDoesNotContain 'packer/scripts/setup-gateway.sh' 'bind 127\.0\.0\.1:6053' 'Provisioner must not inline old SmartDNS config.'
Assert-FileContains 'packer/scripts/setup-gateway.sh' 'MosDNS LAN DNS engine' 'Provisioner must describe MosDNS as the LAN DNS engine.'

# --- CI ---
Assert-FileContains '.github/workflows/build-ova.yml' 'workflow_dispatch' 'Workflow must support manual Run workflow.'
Assert-FileContains '.github/workflows/build-ova.yml' 'vyos/vyos-build:current' 'Workflow must build via the VyOS Docker framework.'
Assert-FileContains '.github/workflows/build-ova.yml' 'data/live-build-config/includes\.chroot' 'Workflow must inject files through live-build includes.chroot.'
Assert-FileContains '.github/workflows/build-ova.yml' 'data/live-build-config/hooks/live' 'Workflow must install the chroot hook in the VyOS live-build hooks directory.'
Assert-FileContains '.github/workflows/build-ova.yml' '\$\{CUSTOM\}/system' 'Workflow must stage Golden Image system config.'
Assert-FileContains '.github/workflows/build-ova.yml' '/etc/sysctl\.d/99-daed-gateway\.conf' 'Workflow must inject sysctl tuning into the image.'
Assert-FileContains '.github/workflows/build-ova.yml' 'vyos15-daed-gateway-iso' 'Workflow must upload the source-built VyOS ISO artifact.'
Assert-FileContains '.github/workflows/build-ova.yml' 'direct-list\.txt' 'Workflow must download an existing CN rules text source.'
Assert-FileContains '.github/workflows/build-ova.yml' 'proxy-list\.txt' 'Workflow must download an existing overseas rules text source.'
Assert-FileDoesNotContain '.github/workflows/build-ova.yml' 'pymumu/smartdns|smartdns\.service|daed-provision\.sh|updateDns|createDns' 'Workflow must not inject SmartDNS or daed DNS provisioning.'
Assert-FileContains '.github/workflows/build-ova.yml' 'dns-hijack\.sh' 'Workflow must inject the DNS hijack script.'
Assert-FileContains '.github/workflows/build-ova.yml' 'MosDNS LAN DNS engine' 'Workflow must install MosDNS as the LAN DNS engine.'
Assert-FileContains '.github/workflows/build-ova.yml' 'sudo chown -R "\$\(id -u\):\$\(id -g\)" .*vyos-build/build' 'Workflow must reclaim Docker root-owned build artifacts before verify/upload.'
Assert-FileContains '.github/workflows/build-ova.yml' "name 'vyos-\*\.iso'" 'Workflow must accept the actual VyOS ISO artifact name.'
Assert-FileDoesNotContain '.github/workflows/build-ova.yml' 'packer build' 'Workflow must not use Packer/QEMU to install the ISO.'

# --- README ---
Assert-FileContains 'README.md' 'VyOS' 'README must document the VyOS route.'
Assert-FileContains 'README.md' 'Golden Image v1' 'README must state the golden image goal.'
Assert-FileContains 'README.md' 'boot-ready' 'README must document the boot-ready behavior.'
Assert-FileContains 'README.md' 'MosDNS' 'README must document MosDNS.'
Assert-FileContains 'README.md' 'BBR' 'README must document BBR tuning.'
Assert-FileContains 'README.md' 'fq' 'README must document fq tuning.'
Assert-FileContains 'README.md' 'IPv6' 'README must document IPv6 policy.'
Assert-FileContains 'README.md' 'http://<gateway-ip>:2023' 'README must document the daed dashboard.'
Assert-FileDoesNotContain 'README.md' 'PaoPaoDNS' 'README must not reference the removed PaoPaoDNS route.'
Assert-FileDoesNotContain 'README.md' 'daed DNS|127\.0\.0\.1:5353|127\.0\.0\.1:5335|forward_smartdns' 'README must document MosDNS-only DNS, not the old daed/SmartDNS chain.'
Assert-FileContains 'README.md' 'DNS Hijack' 'README must document the VyOS firewall DNS hijack layer.'
Assert-FileContains 'README.md' 'Build VyOS 1\.5 daed Gateway Image' 'README must document the GitHub Actions build workflow.'
Assert-FileContains 'README.md' 'vyos15-daed-gateway-iso' 'README must document the ISO artifact.'
Assert-FileContains 'README.md' 'vyos15-daed-gateway-ova' 'README must document the OVA artifact.'
Assert-FileContains 'README.md' 'live-build includes\.chroot' 'README must explain how the existing VyOS build flow is used.'
Assert-FileContains 'README.md' '99-daed-gateway\.conf' 'README must document where sysctl tuning is injected.'
Assert-FileDoesNotContain 'README.md' '8\.8\.8\.8' 'README must not document public 8.8.8.8 overseas DoH.'
Assert-FileDoesNotContain 'README.md' 'dip\(doh\.pub\)' 'README must not document the removed doh.pub dip rule.'
Assert-FileDoesNotContain 'README.md' 'dmit\.wwa\.im/dq' 'README must not document rate-limited Dmit DoH.'
Assert-FileContains 'README.md' 'cloudflare-dns\.com/dns-query' 'README must document Cloudflare DoH.'
Assert-FileContains 'README.md' '<LAN_BIND_IP>:53' 'README must document the late-bound MosDNS LAN listener.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'Smoke tests passed.'
