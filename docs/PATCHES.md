# 构建说明：源码 ISO + Packer 转 OVA

本项目用两段式流水线产出 daed 网关 OVA，工作流见
`.github/workflows/build-ova.yml`。

## 为什么是两段式

VyOS 1.5 的 `build-vyos-image` 只能产出 ISO/raw 镜像；VMware OVA 需要
VyOS 私有的签名工具，社区构建拿不到。所以：

- **第一段（源码构建 ISO）**：用 `vyos/vyos-build:current` 容器，按官方方式
  `sudo --preserve-env ./build-vyos-image --architecture amd64 --build-by ... generic`
  构建出 `build/live-image-amd64.hybrid.iso`。
- **第二段（Packer 转 OVA）**：把该 ISO 喂给 `packer/build.pkr.hcl`——qemu
  装进虚拟机、`setup-gateway.sh` 注入 daed/mosdns/smartdns、`qemu-img` 转
  streamOptimized vmdk、手写 OVF、tar 成 `.ova`。

> 历史教训：1.4/1.5 **没有** `./configure` 或 `make vmware`（那是 1.3 equuleus
> 时代的命令）。1.5 的 flavor 只有 `generic`，hooks 目录是 `hooks/`（不是
> `hooks.chroot`）。

## 补丁

```
patches/
└── vyos-build/
    └── 001-add-nexttrace-repo.patch   # 给 amd64.toml 加 nexttrace apt 源
```

只有一个补丁，它在第一段构建期由工作流内联应用（`patch -p1 -d vyos-build`）。

**nexttrace 仓库补丁**：往 `data/architectures/amd64.toml` 追加 nexttrace 的
apt 源，使 `--custom-package nexttrace` 能装上高级路由追踪工具。已对 `current`
分支 dry-run 验证可应用。

### 为什么没有 Podman / Mellanox / 内核补丁

这些补丁针对 `vyos-1x` 源码或内核 defconfig。但 1.5 镜像里的 `vyos-1x` 是从
`packages.vyos.net` 装的**预编译 deb**（见 `vyos-base.list.chroot`），克隆源码
打补丁不会生效——除非完整重新编译 `vyos-1x` 的 deb，代价高且需版本精确对齐。
当前定位是"可用的 daed 网关 OVA"，故不做。需要时可另起一段源码编译再加回。

## 额外工具包

第一段通过 `--custom-package` 注入：`btop`、`nexttrace`、`tree`、`ripgrep`、`gdu`。

## 中国镜像源

`workflow_dispatch` 勾选 `use_china_mirror: true` 时，第一段对 Debian 包使用清华
镜像（`--debian-mirror` / `--debian-security-mirror`），加速 apt 阶段。VyOS 自有
仓库 `packages.vyos.net` 不走镜像。

## 触发构建

GitHub → Actions → **Build VyOS 1.5 daed Gateway OVA (source ISO + packer)** →
Run workflow：

- `daed_version`：daed 版本，默认 `latest`
- `use_china_mirror`：国内构建建议 `true`
- `disk_size`：OVA 虚拟磁盘 MB，默认 `8192`

产物：`vyos15-daed-gateway-ova` artifact（保留 14 天）。

## 参考

- 官方构建命令出处：vyos-build `current` 分支 `.github/workflows/package-smoketest.yml`
- nexttrace 补丁灵感：[KawaiiNetworks/vyos-unofficial](https://github.com/KawaiiNetworks/vyos-unofficial)
- [VyOS 文档](https://docs.vyos.io/) ｜ [NextTrace](https://github.com/nxtrace/nexttrace)
