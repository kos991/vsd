# VyOS 1.5 daed Gateway — 拓扑图

> 主机：`192.168.0.243` | 项目：[kos991/vsd](https://github.com/kos991/vsd)

---

## 整体架构图

```mermaid
flowchart TD
    subgraph WAN["🌐 WAN"]
        node_doh["☁️ 节点 DoH\n<YOUR_DOH_ENDPOINT>"]
        cn_dns["🇨🇳 国内 DNS\n223.5.5.5 / 119.29.29.29 / 114.114.114.114"]
        proxy_node["🔒 代理节点\n（用户自行添加）"]
        direct_out["📡 直连出口"]
    end

    subgraph VyOS["🖥️ VyOS 1.5 Gateway — 192.168.0.243"]
        direction TB

        subgraph boot["⚙️ 开机编排 (late-bind.service)"]
            lbs["📜 late-bind.sh\n① 探测 LAN IP\n② 渲染 MosDNS 模板\n③ 安装 nftables 规则\n④ 连接 geoip/geosite\n⑤ 启动 mosdns + daed"]
        end

        subgraph dns_layer["🔍 DNS 层"]
            hijack["🔀 DNS Hijack\n(nftables: inet daed_dns_hijack)\nTCP/UDP 53 → 本机\nTCP/UDP 853 → REJECT"]
            mosdns["🧠 MosDNS :53\ngeosite:cn → 国内 DNS\ngeosite:!cn → 节点 DoH (走代理)\n自身进程 must_direct"]
        end

        subgraph traffic_layer["🚦 流量层"]
            dae["⚡ daed eBPF/TProxy :12345\nDoH IP (<YOUR_NODE_IP>) → direct\ngeoip:private → direct\ngeoip:cn / geosite:cn → direct\nYouTube/Netflix/AI/X → proxy\nfallback → direct"]
        end

        subgraph kernel["🔧 内核调优"]
            bbr["📈 BBR + fq\n(99-daed-gateway.conf)"]
        end

        subgraph panel["🖥️ 管理面板"]
            web["🌐 daed Web UI\nhttp://192.168.0.243:2023"]
        end
    end

    subgraph LAN["🏠 LAN 客户端"]
        clients["💻 LAN Clients\n(PC / 手机 / IoT)"]
    end

    %% DNS 流程
    clients -->|"DNS 查询\nport 53"| hijack
    hijack -->|"重定向"| mosdns
    mosdns -->|"geosite:cn / fallback"| cn_dns
    mosdns -->|"geosite:!cn"| node_doh

    %% 流量流程
    clients -->|"TCP/UDP 流量"| dae
    dae -->|"geoip:cn / private / fallback"| direct_out
    dae -->|"streaming / AI / X"| proxy_node

    %% 开机流程
    lbs -.->|"启动"| mosdns
    lbs -.->|"启动"| dae
    lbs -.->|"安装规则"| hijack

    style WAN fill:#1a1a2e,stroke:#4a90d9,color:#add8e6
    style VyOS fill:#0d2137,stroke:#00b4d8,color:#caf0f8
    style LAN fill:#1a2e1a,stroke:#52b788,color:#b7e4c7
    style boot fill:#2d1b69,stroke:#7c3aed,color:#ddd6fe
    style dns_layer fill:#1e3a5f,stroke:#0077b6,color:#90e0ef
    style traffic_layer fill:#1f3a1f,stroke:#2d6a4f,color:#95d5b2
    style kernel fill:#3a1a00,stroke:#f77f00,color:#ffd166
    style panel fill:#2a1a3a,stroke:#9d4edd,color:#e0aaff
```

---

## DNS 流量详细路径

```mermaid
sequenceDiagram
    participant C as 💻 LAN Client
    participant FW as 🔀 nftables DNS Hijack
    participant M as 🧠 MosDNS :53
    participant CN as 🇨🇳 国内 DNS
    participant CF as ☁️ 节点 DoH (代理)

    C->>FW: DNS Query (port 53)
    FW->>M: 重定向至本机 MosDNS
    
    alt geosite:cn 域名
        M->>CN: UDP/TCP 53
        CN-->>M: 解析结果（国内 IP）
        M-->>C: 返回国内直连 IP
    else geosite:!cn 或未知域名
        M->>CF: HTTPS DoH 查询 (直发节点IP)
        CF-->>M: 解析结果（海外最优 CDN）
        M-->>C: 返回海外最优 IP
    end
    
    Note over FW: TCP/UDP 853 (DoT) → REJECT<br/>防止设备绕过本机 DNS
```

---

## 数据流量详细路径

```mermaid
flowchart LR
    C["💻 LAN Client"]
    
    subgraph daed["⚡ daed eBPF/TProxy"]
        rule_dns["DoH 节点IP (<YOUR_NODE_IP>)"]
        rule1["geoip:private\ngeoip:cn\ngeosite:cn"]
        rule2["YouTube / Netflix\nOpenAI / Claude\nX / Twitter"]
        rule3["fallback"]
        mosdns_proc["mosdns 进程\nmust_direct"]
    end
    
    direct["📡 直连 WAN"]
    proxy["🔒 代理节点"]
    
    C --> daed
    rule_dns --> direct
    rule1 --> direct
    rule2 --> proxy
    rule3 --> direct
    mosdns_proc --> direct
```

---

## 文件系统结构

```text
/opt/custom-services/
├── bin/
│   ├── daed         ← daed 可执行文件
│   └── mosdns       ← MosDNS 可执行文件
├── geo/
│   ├── geoip.dat
│   ├── geosite.dat
│   ├── geolocation-cn.txt
│   └── geolocation-!cn.txt
├── daed/
│   ├── config.dae   ← 流量分流规则
│   └── wing.db      ← 运行时数据（首次启动生成）
├── mosdns/
│   ├── config.yaml
│   └── config.yaml.template  ← 含 <LAN_BIND_IP> 占位符
└── scripts/
    ├── late-bind.sh      ← 开机编排主脚本
    ├── dns-hijack.sh     ← nftables 规则安装
    └── geosite-update.sh ← Geo 数据更新

/lib/systemd/system/
├── daed.service
├── mosdns.service
└── late-bind.service

/etc/sysctl.d/
└── 99-daed-gateway.conf  ← BBR + fq 内核参数
```

---

## 端口与服务汇总

| 服务 | 端口 | 协议 | 说明 |
|------|------|------|------|
| MosDNS | 53 | TCP/UDP | LAN 侧 DNS（由 nftables 劫持转发） |
| daed TProxy | 12345 | TCP/UDP | eBPF/TProxy 透明代理 |
| daed Web UI | 2023 | TCP | 管理面板，访问 `http://192.168.0.243:2023` |
| 节点 DoH | 443 | TCP | 上游 DNS（geosite:!cn 域名） |
| 国内 DNS | 53 | UDP | 223.5.5.5 / 119.29.29.29 / 114.114.114.114 |

---

> [!NOTE]  
> **镜像默认不内置代理节点**，需要在 `http://192.168.0.243:2023` 手动添加节点并应用配置后，海外流量才会正常走代理。
