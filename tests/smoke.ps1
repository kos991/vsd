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
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' 'forward_smartdns' 'MosDNS must forward CN to SmartDNS.'
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' 'https://8\.8\.8\.8/dns-query' 'MosDNS must DoH overseas via 8.8.8.8.'
Assert-FileContains 'packer/custom-services/mosdns/config.yaml' 'lazy_cache_ttl' 'MosDNS must enable lazy cache.'

# --- daed ---
Assert-FileContains 'packer/custom-services/daed/config.dae' "local: 'udp://127\.0\.0\.1:5335'" 'daed DNS upstream must be SmartDNS.'
Assert-FileContains 'packer/custom-services/daed/config.dae' 'fallback: proxy' 'daed must proxy overseas traffic by default.'
Assert-FileContains 'packer/custom-services/daed/config.dae' 'dport\(53, 853\) -> block' 'daed must block LAN DNS escape.'
Assert-FileContains 'packer/custom-services/daed/config.dae' 'dip\(geoip:cn\) -> direct' 'daed must direct CN destinations.'

# --- Scripts ---
Assert-FileContains 'packer/custom-services/scripts/custom-services-latebind.sh' 'seq 1 30' 'Late-bind must retry up to 30s for the LAN IP.'
Assert-FileContains 'packer/custom-services/scripts/custom-services-latebind.sh' 'Refusing unsafe' 'Late-bind must refuse unsafe binds.'
Assert-FileContains 'packer/custom-services/scripts/geosite-update.sh' 'MIN_LINES=1000' 'Geosite updater must enforce a minimum line count.'
Assert-FileContains 'packer/custom-services/scripts/geosite-update.sh' 'systemctl restart mosdns' 'Geosite updater must restart MosDNS on success.'
Assert-FileContains 'packer/custom-services/scripts/geosite-update.sh' 'direct-list\.txt' 'Geosite updater must use an existing CN rules text source.'
Assert-FileContains 'packer/custom-services/scripts/geosite-update.sh' 'proxy-list\.txt' 'Geosite updater must use an existing overseas rules text source.'
Assert-FileContains 'packer/custom-services/scripts/custom-services-latebind.sh' 'daed-provision\.sh' 'Late-bind must invoke the daed GraphQL provisioner.'
Assert-FileContains 'packer/custom-services/scripts/daed-provision.sh' 'graphql' 'daed provisioner must talk to the GraphQL endpoint.'
Assert-FileContains 'packer/custom-services/scripts/daed-provision.sh' 'createRouting' 'daed provisioner must import routing via GraphQL.'
Assert-FileContains 'packer/custom-services/scripts/daed-provision.sh' 'numberUsers' 'daed provisioner must be idempotent via numberUsers.'
Assert-FileDoesNotContain 'packer/custom-services/scripts/daed-provision.sh' 'run\(dry:false\)' 'daed provisioner must NOT run config at first boot (no node yet).'

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
Assert-FileDoesNotContain '.github/workflows/build-ova.yml' 'packer build' 'Workflow must not use Packer/QEMU to install the ISO.'

# --- README ---
Assert-FileContains 'README.md' 'VyOS' 'README must document the VyOS route.'
Assert-FileContains 'README.md' 'SmartDNS' 'README must document SmartDNS.'
Assert-FileContains 'README.md' 'MosDNS' 'README must document MosDNS.'
Assert-FileContains 'README.md' 'http://<gateway-ip>:2023' 'README must document the daed dashboard.'
Assert-FileDoesNotContain 'README.md' 'PaoPaoDNS' 'README must not reference the removed PaoPaoDNS route.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'Smoke tests passed.'
