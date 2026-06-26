# VyOS 1.5 daed Gateway

自用 VyOS 1.5 网关镜像：`MosDNS + SmartDNS + daed`。

## 结构

```text
LAN DNS -> MosDNS(<LAN_BIND_IP>:53)
CN      -> SmartDNS(127.0.0.1:5335) -> 国内 DNS
非 CN   -> dmit.wwa.im/dq + bwg.wwa.im/dq

LAN 流量 -> daed eBPF
CN/private/control-plane -> direct
YouTube/Netflix/AI/X/海外 fallback -> proxy
```

模板不写死 LAN 地址。开机由 `late-bind.sh` 探测网关 IP，渲染
`<LAN_BIND_IP>` / `<LAN_SUBNET>`，再通过 daed GraphQL 更新 `wing.db`。

## 路径

```text
/config/custom-services/
  bin/
  geo/
  daed/
  mosdns/
  smartdns/
  scripts/
```

CI 源码构建时会把同一套文件注入到 `/opt/custom-services/`。

## 面板

```text
http://<gateway-ip>:2023
```

首次启动生成账号密码：

```bash
sudo cat /config/custom-services/daed/admin-credentials
```

## 验证

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/smoke.ps1
```

```bash
bash -n scripts/late-bind.sh packer/custom-services/scripts/custom-services-latebind.sh packer/custom-services/scripts/daed-provision.sh packer/custom-services/scripts/geosite-update.sh scripts/99-custom-proxy.chroot
```
