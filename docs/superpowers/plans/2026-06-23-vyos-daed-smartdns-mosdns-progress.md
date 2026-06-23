# VyOS + daed + SmartDNS + MosDNS — Execution Progress

Tracks subagent-driven execution of
[the implementation plan](2026-06-23-vyos-daed-smartdns-mosdns.md), which itself
realizes [the design spec](../specs/2026-06-23-vyos-daed-smartdns-mosdns-design.md).

- **Branch:** `feature/vyos15-daed-packer`
- **Base commit (before Task 1):** `a1996da`
- **Execution mode:** one fresh subagent per task; controller verifies each commit before logging.
- **Note:** the `codex` CLI backend was unstable (HTTP 503 / silent hangs) on Tasks 1-3,
  so implementation switched to Claude subagents from Task 3 onward.

## Status

| Task | Description | Status | Commit |
|------|-------------|--------|--------|
| 1 | Delete legacy Alpine/Debian routes + old docs | ✅ done | `00e36af` |
| 2 | SmartDNS CN resolver config | ✅ done | `7cca773` |
| 3 | MosDNS front-desk config template | ✅ done | `5b0a80a` |
| 4 | daed eBPF enforcer config (exact routing) | ✅ done | `33975e3` |
| 5 | Late-bind injector script (30s LAN-IP retry) | ✅ done | `e205bac` |
| 6 | Geosite updater (>1000-line failsafe) | ✅ done | `7bd5883` |
| 7 | Rewrite setup-gateway.sh provisioner | ✅ done | `59d3289` |
| 8 | Drop CI inline config generation | ✅ done | `0885510` |
| 9 | Rewrite smoke.ps1 for VyOS/packer contract | ✅ done | `1c2d7ed` |
| 10 | Rewrite README.md (mermaid, firstboot blackhole) | ✅ done | `fb9b6dd` |

**All 10 tasks complete.** `tests/smoke.ps1` passes; `bash -n` clean on all three
shell scripts. `packer validate` remains CI-only (not installed locally).

## Per-Task Notes

**Task 1** — 63 files deleted (`overlay/`, `overlay-debian/`, legacy build scripts,
old docs). `network_diag.sh` and `scripts/dae-stability-collector.sh` kept. Working
tree clean, verified via `git show --name-status`.

**Task 2** — `smartdns.conf` written verbatim per brief. The plan's expected directive
count was 16; actual is 17 (a plan miscount, not a file error — content is correct).

**Task 3** — `mosdns/config.yaml` verbatim. `<LAN_BIND_IP>:53` appears 2×; no `0.0.0.0`.

**Task 4** — `daed/config.dae` with the exact "MUST exactly be" routing rules. The
`dip(doh.pub) -> must_direct` rule carries a 3-line NOTE comment flagging it for
runtime confirmation with `daed validate`. `node {}` empty; placeholders kept.

**Task 5** — `custom-services-latebind.sh`, mode `100755`, `bash -n` OK. 30s LAN-IP
retry loop + unsafe-bind guard (`""|0.0.0.0|127.*`) + double `sed` render + 3-service
start all present.

**Task 6** — `geosite-update.sh`, mode `100755`, `bash -n` OK. `MIN_LINES=1000`
failsafe via `wc -l`, `systemctl reload mosdns` on success.

**Task 7** — `setup-gateway.sh` rewritten (208 lines), `bash -n` OK. All 3 binary
downloads (daed/mosdns/smartdns), geo data (dat + 2 txt lists), `/tmp/custom-services`
copy, `.template` snapshots, 6 systemd units, and the VyOS postconfig-bootup hook
present. File mode `100644` is fine — Packer invokes it via `bash` after `chmod +x`.

**Task 8** — Removed the 95-line "Generate config stubs" step from
`.github/workflows/build-ova.yml`; the committed `packer/custom-services/` is now the
single source. `build.pkr.hcl` provisioner source was already correct
(`packer/custom-services/`). Step sequence verified clean: Resolve ISO → Packer
init → validate → build → collect → upload.

## Remaining Work

**Task 9** — Rewrite `tests/smoke.ps1`: keep the four helper functions and the trailing
`if ($failures...)` block; replace the entire old Debian/PaoPaoDNS assertion block with
the VyOS/packer-contract assertions from the plan. A prior attempt left new + old
assertions coexisting (half-done) and was discarded — the replacement must DELETE the
old assertions, not just prepend new ones. Will fail README assertions until Task 10.

**Task 10** — Rewrite `README.md`: VyOS route, mermaid architecture diagram, 4-layer DNS
data flow, and the strict First-Boot note (overseas traffic blackholed until a proxy
node is added via daed UI on `:2023`). After this, full `smoke.ps1` should pass.

## Verification (current capability)

- `bash -n` available locally — used on all shell scripts.
- `powershell.exe` available — runs `tests/smoke.ps1`.
- `packer` / `pwsh` / `shellcheck` NOT installed locally — `packer validate` is CI-only.

## Known Risk (carried from spec)

`daed/config.dae` line `dip(doh.pub) -> must_direct`: dae's `dip()` normally matches
IP/CIDR/geoip, not domains. Not catchable by `packer validate` / `bash -n`. Confirm
with `daed validate` on a booted OVA; fallback `domain(suffix:doh.pub)` or pin doh.pub
fixed IPs.

## Final Whole-Branch Review (commit b880877 fixes applied)

Reviewer checked the full branch diff and verified real GitHub release asset names.

**Fixed:**
- **C1 (Critical)** — SmartDNS download regex matched no real asset (asset is
  `smartdns-x86_64`, no extension; old regex required `linux`→arch→`.tar.gz`). Would
  have failed every `packer build`. Fixed to `^smartdns-x86_64$`. daed/mosdns regexes
  verified correct against live API (`daed-linux-x86_64.zip`, `mosdns-linux-amd64.zip`).
- **I2 (Important)** — mosdns SIGHUP reload was unreliable. Changed
  `geosite-update.sh` to `systemctl restart mosdns.service` and the unit's
  `ExecReload` to `systemctl try-restart`. Smoke assertion updated to match.
- **M2/M3 (Minor)** — Removed stale `overlay/` rules from `.gitattributes`; added LF
  enforcement for `*.dae` and `*.conf`.

**OPEN — needs your decision (I1, Important):**
The reviewer flagged that `daed` (dae-wing) is a GraphQL/DB-driven backend that stores
config in `wing.db`, and may NOT auto-import a `config.dae` file dropped into its
`-c` directory. If so, the entire committed routing block (DNS anti-escape, CN-direct,
SmartDNS upstream, fallback proxy) and the late-bind `sed` rendering would be dead work —
the box would boot with none of the intended routing. The reviewer could not confirm
daed's import behavior from docs alone (rated Important, not Critical). This requires
verification on a booted OVA and may need a first-boot GraphQL import step. NOT yet
addressed — see decision needed below.

**Confirmed clean:** all committed config contracts (ports 5335, paths, placeholders,
the 7 daed routing rules in exact order, late-bind 30s loop + unsafe-bind guard,
geosite >1000-line failsafe), CI step sequence, no baked-in secrets, no dangling
references to deleted routes (except the two diagnostic scripts, M1 — retained
intentionally).
