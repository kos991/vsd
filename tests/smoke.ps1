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

Assert-FileContains '.github/workflows/build-ova.yml' 'workflow_dispatch' 'Workflow must support manual Run workflow.'
Assert-FileContains '.github/workflows/build-ova.yml' 'push:[\s\S]*branches:[\s\S]*- main' 'Workflow must auto-build when main is pushed.'
Assert-FileContains '.github/workflows/build-ova.yml' "inputs\.alpine_version \|\| '3\.20'" 'Push-triggered builds must fall back to the default Alpine version.'
Assert-FileContains '.github/workflows/build-ova.yml' "inputs\.disk_size \|\| '4G'" 'Push-triggered builds must fall back to the default disk size.'
Assert-FileContains '.github/workflows/build-ova.yml' 'actions/upload-artifact@v4' 'Workflow must upload OVA artifact.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'linux-lts' 'Build script must install Alpine linux-lts for eBPF support.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'openssh-server' 'Build script must install OpenSSH server for first login access.'
Assert-FileContains 'scripts/build-alpine-ova.sh' "echo 'root:dae123456' \| chpasswd" 'Build script must set the documented initial root password.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'PermitRootLogin yes' 'Build script must allow root SSH password login for first access.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'PasswordAuthentication yes' 'Build script must allow SSH password authentication for first access.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'rc-update add sshd default' 'Build script must enable sshd by default.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'bpffs' 'Build script must configure bpffs mount.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'cgroup2' 'Build script must configure cgroup2 mount.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'adapter_type=lsilogic' 'VMDK conversion must use VMware-compatible lsilogic adapter metadata.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'RAW_CAPACITY_BYTES' 'OVF capacity must come from the raw disk size, not qemu-img output from the streamOptimized VMDK.'
Assert-FileContains 'scripts/render-ovf.sh' 'CAPACITY_BYTES="\$\{6:\?capacity bytes required\}"' 'OVF renderer must require an explicit single capacity value.'
Assert-FileContains 'scripts/render-ovf.sh' '\[\[ "\$\{CAPACITY_BYTES\}" =~ \^\[0-9\]\+\$ \]\]' 'OVF renderer must reject non-numeric or multi-line capacity values.'
Assert-FileContains 'scripts/render-ovf.sh' 'ovf:capacity="\$\{CAPACITY_BYTES\}"' 'OVF disk capacity must be rendered from the validated explicit capacity value.'
Assert-FileContains 'scripts/render-ovf.sh' '<rasd:ElementName>Hard disk 1</rasd:ElementName>[\s\S]*<rasd:HostResource>ovf:/disk/vmdisk1</rasd:HostResource>[\s\S]*<rasd:InstanceID>3</rasd:InstanceID>[\s\S]*<rasd:Parent>5</rasd:Parent>[\s\S]*<rasd:ResourceType>17</rasd:ResourceType>' 'Hard disk OVF item must keep RASD elements in schema order for strict importers.'
Assert-FileContains 'scripts/render-ovf.sh' '<rasd:ResourceSubType>lsilogic</rasd:ResourceSubType>' 'OVF SCSI controller must use VMware-compatible lsilogic subtype.'
Assert-FileContains 'scripts/render-ovf.sh' '<rasd:ResourceSubType>E1000</rasd:ResourceSubType>' 'OVF network adapter must use broad-compatible E1000 subtype.'
Assert-FileContains 'scripts/install-dae.sh' 'daeuniverse/dae' 'dae installer must download from daeuniverse/dae.'
Assert-FileContains 'scripts/install-mini-ppdns.sh' 'kkkgo/mini-ppdns' 'mini-ppdns installer must download from kkkgo/mini-ppdns.'
Assert-FileContains 'overlay/etc/init.d/dae' 'check-ebpf' 'dae OpenRC service must depend on eBPF preflight.'
Assert-FileContains 'overlay/etc/init.d/mini-ppdns' 'mini-ppdns' 'mini-ppdns OpenRC service must exist.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'rc-update add mini-ppdns default' 'mini-ppdns must start by default.'
Assert-FileContains 'README.md' 'GitHub Actions' 'README must document GitHub Actions build usage.'
Assert-FileContains 'README.md' 'root / dae123456' 'README must document initial login credentials.'
Assert-FileContains 'README.md' 'change the root password' 'README must tell users to change the initial password.'
Assert-FileContains 'README.md' 'mini-ppdns' 'README must document mini-ppdns rather than full PaoPaoDNS.'
Assert-FileContains 'README.md' 'rc-update add dae default' 'README must document how to enable dae after configuration.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'Smoke tests passed.'
