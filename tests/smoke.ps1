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
Assert-FileContains '.github/workflows/build-ova.yml' 'actions/upload-artifact@v4' 'Workflow must upload OVA artifact.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'linux-lts' 'Build script must install Alpine linux-lts for eBPF support.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'bpffs' 'Build script must configure bpffs mount.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'cgroup2' 'Build script must configure cgroup2 mount.'
Assert-FileContains 'scripts/render-ovf.sh' '<rasd:ElementName>Hard disk 1</rasd:ElementName>[\s\S]*<rasd:HostResource>ovf:/disk/vmdisk1</rasd:HostResource>[\s\S]*<rasd:InstanceID>3</rasd:InstanceID>[\s\S]*<rasd:Parent>5</rasd:Parent>[\s\S]*<rasd:ResourceType>17</rasd:ResourceType>' 'Hard disk OVF item must keep RASD elements in schema order for strict importers.'
Assert-FileContains 'scripts/install-dae.sh' 'daeuniverse/dae' 'dae installer must download from daeuniverse/dae.'
Assert-FileContains 'scripts/install-mini-ppdns.sh' 'kkkgo/mini-ppdns' 'mini-ppdns installer must download from kkkgo/mini-ppdns.'
Assert-FileContains 'overlay/etc/init.d/dae' 'check-ebpf' 'dae OpenRC service must depend on eBPF preflight.'
Assert-FileContains 'overlay/etc/init.d/mini-ppdns' 'mini-ppdns' 'mini-ppdns OpenRC service must exist.'
Assert-FileContains 'scripts/build-alpine-ova.sh' 'rc-update add mini-ppdns default' 'mini-ppdns must start by default.'
Assert-FileContains 'README.md' 'GitHub Actions' 'README must document GitHub Actions build usage.'
Assert-FileContains 'README.md' 'mini-ppdns' 'README must document mini-ppdns rather than full PaoPaoDNS.'
Assert-FileContains 'README.md' 'rc-update add dae default' 'README must document how to enable dae after configuration.'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'Smoke tests passed.'
