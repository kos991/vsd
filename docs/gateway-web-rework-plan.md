# Dae Gateway Web Rework Plan

## Goal

Build a practical gateway management surface instead of a visual clone:

- Use a thin Dae Gateway control panel for overview, diagnostics, logs, and module entry points.
- Reuse or link to the original daed UI for detailed dae configuration where possible.
- Keep mini-ppdns, QoS, and Doctor as small purpose-built pages.
- Keep DNS Tunnel VPN optional and out of the default runtime path.

## Product Shape

```text
Dae Gateway Web
+-- Overview
|   +-- Network status
|   +-- eBPF/BTF status
|   +-- dae status
|   +-- mini-ppdns status
|   +-- QoS status
|   +-- links to daed / DNS / QoS / Doctor
+-- dae
|   +-- service status
|   +-- start / stop / restart
|   +-- logs
|   +-- update check
|   +-- open original daed UI
+-- mini-ppdns
|   +-- service status
|   +-- upstream DNS form
|   +-- port 53 check
|   +-- logs
+-- QoS / CAKE
|   +-- enabled state
|   +-- WAN interface
|   +-- download/upload bandwidth
|   +-- apply / clear
+-- Doctor
|   +-- VMware tools
|   +-- NIC visible
|   +-- DHCP
|   +-- default route
|   +-- DNS resolution
|   +-- bpffs
|   +-- cgroup2
|   +-- BTF vmlinux
|   +-- port 53
+-- System
    +-- versions
    +-- backups
    +-- logs
    +-- password reset
```

## What To Stop Doing

- Stop cloning SMBox page-by-page.
- Stop building a custom dae rules editor before proving daed UI integration.
- Stop putting every idea on the dashboard.
- Stop making DNS Tunnel VPN part of the default product path.

## Architecture

```text
gateway-core
  Shared module commands and status output.

gateway
  Console/TUI fallback. Works without network.

gateway-web
  Thin Web UI. Calls gateway-core. Links to daed for detailed dae editing.

daed UI
  Preferred surface for dae-specific rules, nodes, and subscriptions.
```

## Phase 1: Correct Preview

Purpose: give the user a realistic direction before implementation.

- Replace the current 8081 prototype with a thin control panel.
- Show the daed integration as a first-class card.
- Keep pages minimal:
  - Overview
  - dae
  - DNS
  - QoS
  - Doctor
  - System

No backend integration in this phase.

## Phase 2: VMware Base Fix

Purpose: make the OVA usable in VMware before adding a Web dependency.

- Use Alpine `linux-virt` for BTF support.
- Add `open-vm-tools` and enable it at boot.
- Add network diagnostics: `pciutils`, `ethtool`, and useful `iproute2` tools.
- Prefer VMware-friendly NIC metadata and boot-time module loading.
- Stop relying on a hard-coded `eth0` as the only possible interface.

## Phase 3: Server-Side Skeleton

Files to create later:

```text
overlay/usr/local/sbin/gateway-core
overlay/usr/local/sbin/gateway-web
overlay/etc/init.d/gateway-web
overlay/opt/dae-gateway/ui/
```

Core commands:

```sh
gateway-core overview
gateway-core doctor
gateway-core module dae status
gateway-core module mini-ppdns status
gateway-core module qos status
gateway-core logs dae
gateway-core logs mini-ppdns
```

Web service:

```text
http://<gateway-ip>:8080
```

Console fallback:

```sh
gateway
```

## Phase 4: daed UI Research

Research tasks:

- Identify how upstream daed serves its UI.
- Identify required daed binary and config paths.
- Decide whether to:
  - launch daed directly,
  - link to daed UI,
  - or package static daed UI with our gateway.

Known reference:

- daed is the dae Web dashboard.
- Typical access target is `http://localhost:2023`.

Decision rule:

- If daed UI can manage dae cleanly, reuse it.
- If it requires a heavier daemon than this appliance should run, link out or document it as optional.

## Phase 5: Real Integration

- Add `gateway-web` service to the image.
- Keep `gateway` TUI as the first recovery path.
- Add tests for file presence, service registration, and route links.
- Do not require the Web UI to fix networking.

## MVP Acceptance

- User can open Web panel and immediately see whether the gateway base is healthy.
- User can open daed UI from the dae card.
- User can manage mini-ppdns without editing ini manually.
- User can enable/disable QoS without hand-writing `tc` commands.
- User can run Doctor and see why VMware/network/eBPF is failing.
- Web UI is not required to recover the box; console `gateway` still works.
