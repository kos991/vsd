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
Assert-PathExists 'packer/custom-services/smartdns/smartdns.conf' 'SmartDNS config must exist.'
Assert-PathExists 'packer/custom-services/mosdns/config.yaml' 'MosDNS config must exist.'
Assert-PathExists 'packer/custom-services/daed/config.dae' 'daed config must exist.'
Assert-PathExists 'packer/custom-services/scripts/custom-services-latebind.sh' 'Late-bind script must exist.'
Assert-PathExists 'packer/custom-services/scripts/geosite-update.sh' 'Geosite updater must exist.'
Assert-PathExists 'packer/custom-services/scripts/daed-provision.sh' 'daed GraphQL provisioner must exist.'

# --- SmartDNS ---
Assert-FileContains 'packer/custom-services/smartdns/smartdns.conf' 'bind 127\.0\.0\.1:5335' 'SmartDNS must bind loopback:5335.'
Assert-FileContains 'packer/custom-services/smartdns/smartdns.conf' 'speed-check-mode tcp:443,icmp' 'SmartDNS must speed-check upstreams.'
Assert-FileContains 'packer/custom-services/smartdns/smartdns.conf' 'server-https https://doh\.pub/dns-query' 'SmartDNS must use doh.pub encrypted upstream.'
Assert-FileContains 'packer/custom-services/smartdns/smartdns.conf' 'cache-size 100000' 'SmartDNS must use a large cache.'

# --- MosDNS ---
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' '<LAN_BIND_IP>:53' 'MosDNS must listen on the LAN bind IP placeholder.'
Assert-FileDoesNotContain 'packer/custom-services/mosdns/config.yaml' '0\.0\.0\.0' 'MosDNS must never bind 0.0.0.0.'
Assert-FileDoesNotContain 'packer/custom-services/mosdns/config.yaml' '(?m)^servers:' 'MosDNS v5 config must not use the removed top-level servers key.'
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' 'type: udp_server' 'MosDNS v5 config must define the UDP listener as a plugin.'
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' 'type: tcp_server' 'MosDNS v5 config must define the TCP listener as a plugin.'
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' 'has_resp' 'MosDNS sequence must accept successful SmartDNS/cache responses before fallback DoH.'
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' 'exec: accept' 'MosDNS sequence must stop after successful CN/cache resolution.'
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' 'forward_smartdns' 'MosDNS must forward CN to SmartDNS.'
Assert-FileDoesNotContain 'packer/custom-services/mosdns/config.yaml' '8\.8\.8\.8' 'MosDNS must not use public 8.8.8.8 DoH for overseas.'
Assert-FileDoesNotContain 'packer/custom-services/mosdns/config.yaml' 'doh\.pub' 'MosDNS must not use doh.pub for overseas.'
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' 'https://dmit\.wwa\.im/dq' 'MosDNS must use Dmit node-owned DoH.'
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' '154\.17\.2\.123:443' 'MosDNS must pin Dmit DoH dial_addr.'
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' 'https://bwg\.wwa\.im/dq' 'MosDNS must use BWG node-owned DoH.'
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' '104\.194\.84\.105:443' 'MosDNS must pin BWG DoH dial_addr.'
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' 'lazy_cache_ttl' 'MosDNS must enable lazy cache.'
Assert-FileDoesNotContain 'packer/custom-services/mosdns/config.yaml' '192\.168\.0\.' 'MosDNS template must not hardcode a LAN address.'

# --- daed ---
Assert-FileContains 'packer/custom-services/daed/config.dae' "mosdns: 'udp://<LAN_BIND_IP>:53'" 'daed DNS upstream must be MosDNS.'
Assert-FileDoesNotContain 'packer/custom-services/daed/config.dae' '127\.0\.0\.1:5335' 'daed must not use SmartDNS directly for internal DNS.'
Assert-FileDoesNotContain 'packer/custom-services/daed/config.dae' 'dip\(doh\.pub\)' 'daed must not use the invalid doh.pub dip rule.'
Assert-FileContains 'packer/custom-services/daed/config.dae' 'domain\(full: dmit\.wwa\.im\) -> must_direct' 'daed must bypass Dmit DoH endpoint domain.'
Assert-FileContains 'packer/custom-services/daed/config.dae' 'domain\(full: bwg\.wwa\.im\) -> must_direct' 'daed must bypass BWG DoH endpoint domain.'
Assert-FileContains 'packer/custom-services/daed/config.dae' '(?s)group\s*\{.*proxy\s*\{' 'daed template must define the proxy group used by fallback.'
Assert-FileContains 'packer/custom-services/daed/config.dae' 'fallback: proxy' 'daed must proxy overseas traffic by default.'
Assert-FileContains 'packer/custom-services/daed/config.dae' 'dip\(geoip:cn\) -> direct' 'daed must direct CN destinations.'
Assert-FileContains 'packer/custom-services/daed/config.dae' 'domain\(geosite:cn\) -> direct' 'daed must direct CN domains.'
Assert-FileContains 'packer/custom-services/daed/config.dae' 'pname\(NetworkManager, systemd-resolved, dnsmasq, chronyd, mosdns, smartdns\) -> must_direct' 'daed must bypass DNS/control-plane processes.'
Assert-FileContains 'packer/custom-services/daed/config.dae' 'suffix:youtube\.com' 'daed must route YouTube before CN geoip fallback.'
Assert-FileContains 'packer/custom-services/daed/config.dae' 'suffix:googlevideo\.com' 'daed must route Googlevideo before CN geoip fallback.'
Assert-FileContains 'packer/custom-services/daed/config.dae' 'suffix:nflxvideo\.net' 'daed must route Netflix video before CN geoip fallback.'
Assert-FileContains 'packer/custom-services/daed/config.dae' 'suffix:openai\.com' 'daed must route AI domains before CN geoip fallback.'
Assert-FileDoesNotContain 'packer/custom-services/daed/config.dae' '192\.168\.0\.' 'daed template must not hardcode a LAN address.'
Assert-FileDoesNotContain 'packer/custom-services/daed/config.dae' 'sip\(<LAN_SUBNET>\)' 'daed template must not depend on LAN subnet rules.'
Assert-FileDoesNotContain 'packer/custom-services/daed/config.dae' 'l4proto\(udp\) && dport\(443\) -> block' 'daed template must not rely on broad QUIC block rules.'

# --- Scripts ---
Assert-FileContains 'packer/custom-services/scripts/custom-services-latebind.sh' 'seq 1 30' 'Late-bind must retry up to 30s for the LAN IP.'
Assert-FileContains 'packer/custom-services/scripts/custom-services-latebind.sh' 'Refusing unsafe' 'Late-bind must refuse unsafe binds.'
Assert-FileContains 'scripts/late-bind.sh' 'resolve_lan_if' 'Source-build late-bind must auto-detect the LAN interface.'
Assert-FileDoesNotContain 'scripts/late-bind.sh' 'LAN_IF="\$\{LAN_INTERFACE:-eth1\}"' 'Source-build late-bind must not hardcode eth1 as the LAN interface.'
Assert-FileContains 'scripts/99-custom-proxy.chroot' 'systemctl enable late-bind\.service' 'Build hook must enable late-bind as the boot orchestrator.'
Assert-FileDoesNotContain 'scripts/99-custom-proxy.chroot' 'systemctl enable daed\.service mosdns\.service smartdns\.service late-bind\.service' 'Build hook must not enable services that race before late-bind renders configs.'
Assert-FileContains 'packer/custom-services/scripts/geosite-update.sh' 'MIN_LINES=1000' 'Geosite updater must enforce a minimum line count.'
Assert-FileContains 'packer/custom-services/scripts/geosite-update.sh' 'systemctl restart mosdns' 'Geosite updater must restart MosDNS on success.'
Assert-FileContains 'packer/custom-services/scripts/geosite-update.sh' 'direct-list\.txt' 'Geosite updater must use an existing CN rules text source.'
Assert-FileContains 'packer/custom-services/scripts/geosite-update.sh' 'proxy-list\.txt' 'Geosite updater must use an existing overseas rules text source.'
Assert-FileContains 'packer/custom-services/scripts/custom-services-latebind.sh' 'daed-provision\.sh' 'Late-bind must invoke the daed GraphQL provisioner.'
Assert-FileContains 'packer/custom-services/scripts/daed-provision.sh' 'graphql' 'daed provisioner must talk to the GraphQL endpoint.'
Assert-FileContains 'packer/custom-services/scripts/daed-provision.sh' 'createRouting' 'daed provisioner must import routing via GraphQL.'
Assert-FileContains 'packer/custom-services/scripts/daed-provision.sh' 'updateDns' 'daed provisioner must update selected DNS on each late-bind run.'
Assert-FileContains 'packer/custom-services/scripts/daed-provision.sh' 'updateRouting' 'daed provisioner must update selected routing on each late-bind run.'
Assert-FileContains 'packer/custom-services/scripts/daed-provision.sh' 'numberUsers' 'daed provisioner must be idempotent via numberUsers.'
Assert-FileContains 'packer/custom-services/scripts/daed-provision.sh' 'run\(dry:true\)' 'daed provisioner must dry-run validate selected config.'
Assert-FileContains 'packer/custom-services/scripts/daed-provision.sh' 'PROXY_NODES' 'daed provisioner must gate apply on proxy group nodes.'
Assert-FileContains 'packer/custom-services/scripts/daed-provision.sh' 'run\(dry:false\)' 'daed provisioner may apply only after proxy nodes exist.'

# --- Provisioner ---
Assert-FileContains 'packer/scripts/setup-gateway.sh' 'daeuniverse/daed' 'Provisioner must download daed.'
Assert-FileContains 'packer/scripts/setup-gateway.sh' 'IrineSistiana/mosdns' 'Provisioner must download MosDNS.'
Assert-FileContains 'packer/scripts/setup-gateway.sh' 'pymumu/smartdns' 'Provisioner must download SmartDNS.'
Assert-FileContains 'packer/scripts/setup-gateway.sh' 'geolocation-!cn\.txt' 'Provisioner must download the overseas geosite list.'
Assert-FileDoesNotContain 'packer/scripts/setup-gateway.sh' 'bind 127\.0\.0\.1:6053' 'Provisioner must not inline old SmartDNS config.'

# --- CI ---
Assert-FileContains '.github/workflows/build-ova.yml' 'workflow_dispatch' 'Workflow must support manual Run workflow.'
Assert-FileContains '.github/workflows/build-ova.yml' 'vyos/vyos-build:current' 'Workflow must build via the VyOS Docker framework.'
Assert-FileContains '.github/workflows/build-ova.yml' 'data/live-build-config/includes\.chroot' 'Workflow must inject files through live-build includes.chroot.'
Assert-FileContains '.github/workflows/build-ova.yml' 'data/live-build-config/hooks/live' 'Workflow must install the chroot hook in the VyOS live-build hooks directory.'
Assert-FileContains '.github/workflows/build-ova.yml' 'vyos15-daed-gateway-iso' 'Workflow must upload the source-built VyOS ISO artifact.'
Assert-FileContains '.github/workflows/build-ova.yml' 'direct-list\.txt' 'Workflow must download an existing CN rules text source.'
Assert-FileContains '.github/workflows/build-ova.yml' 'proxy-list\.txt' 'Workflow must download an existing overseas rules text source.'
Assert-FileContains '.github/workflows/build-ova.yml' 'daed-provision\.sh "\$\{CUSTOM\}/scripts/"' 'Workflow must inject the daed GraphQL provisioner.'
Assert-FileContains '.github/workflows/build-ova.yml' 'sudo chown -R "\$\(id -u\):\$\(id -g\)" .*vyos-build/build' 'Workflow must reclaim Docker root-owned build artifacts before verify/upload.'
Assert-FileContains '.github/workflows/build-ova.yml' "name 'vyos-\*\.iso'" 'Workflow must accept the actual VyOS ISO artifact name.'
Assert-FileDoesNotContain '.github/workflows/build-ova.yml' 'packer build' 'Workflow must not use Packer/QEMU to install the ISO.'

# --- README ---
Assert-FileContains 'README.md' 'VyOS' 'README must document the VyOS route.'
Assert-FileContains 'README.md' 'SmartDNS' 'README must document SmartDNS.'
Assert-FileContains 'README.md' 'MosDNS' 'README must document MosDNS.'
Assert-FileContains 'README.md' 'http://<gateway-ip>:2023' 'README must document the daed dashboard.'
Assert-FileDoesNotContain 'README.md' 'PaoPaoDNS' 'README must not reference the removed PaoPaoDNS route.'
Assert-FileDoesNotContain 'README.md' '8\.8\.8\.8' 'README must not document public 8.8.8.8 overseas DoH.'
Assert-FileDoesNotContain 'README.md' 'dip\(doh\.pub\)' 'README must not document the removed doh.pub dip rule.'
Assert-FileContains 'README.md' 'dmit\.wwa\.im/dq' 'README must document Dmit node-owned DoH.'
Assert-FileContains 'README.md' 'bwg\.wwa\.im/dq' 'README must document BWG node-owned DoH.'
Assert-FileContains 'README.md' '<LAN_BIND_IP>' 'README must document late-bound LAN IP.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'Smoke tests passed.'
