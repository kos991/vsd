# VyOS daed Gateway

基于 VyOS 1.5 搭建的透明代理和 DNS 分流网关（MosDNS + daed）。

## 更新与维护指南

所有的规则文件和程序本体都可以通过内置的自动化脚本进行无缝更新。

### 1. 更新 Geo 分流数据 (MosDNS txt & daed dat)

我们在 `/opt/custom-services/scripts/geosite-update.sh` 提供了一个自动化脚本，该脚本会自动从 GitHub 拉取最新的 Geo 数据，并确保 MosDNS 和 daed 使用的数据源完全一致，最后会自动重启服务。

**手动更新**：
在路由器内直接执行以下命令：
```bash
sudo /opt/custom-services/scripts/geosite-update.sh
```

**自动定时更新**：
你可以通过配置 `cron` 来实现每天自动拉取。
1. 在路由器内运行 `sudo crontab -e`
2. 添加以下内容（例如每天凌晨 4 点更新）：
```cron
0 4 * * * /opt/custom-services/scripts/geosite-update.sh > /tmp/geosite-update.log 2>&1
```

### 2. 更新 daed 二进制程序

随着 daed 项目的迭代，你可以使用 `/opt/custom-services/scripts/update-daed.sh` 脚本全自动拉取最新的 Release 二进制文件，并无缝覆盖和重启。

**更新命令**：
在路由器内直接执行：
```bash
sudo /opt/custom-services/scripts/update-daed.sh
```

该脚本会自动比对当前版本与 GitHub 上的最新版本，如果发现新版本，会自动下载、解压、安装并重启 `daed.service`。

---
*注：本项目中的部分配置文件使用了占位符（如 `<YOUR_NODE_IP>`、`<YOUR_DOH_ENDPOINT>`、`<LAN_BIND_IP>`），在实际部署时请确保将其替换为真实的配置值。*
