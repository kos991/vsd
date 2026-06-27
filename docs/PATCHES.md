# 构建说明：源码 ISO/OVA + Golden Image 注入

本项目用 VyOS 源码构建流水线产出 daed 网关 ISO/OVA，工作流见
`.github/workflows/build-ova.yml`。

## 当前结合方式

当前主流程不是另起一个 `vyos-golden-image/` 项目，而是复用现有
`.github/workflows/build-ova.yml`：

1. 克隆 `vyos-build`。
2. 在 `data/live-build-config/includes.chroot` 注入 daed、MosDNS、geo 数据、配置模板、systemd 服务和 `/etc/sysctl.d/99-daed-gateway.conf`。
3. 在 `data/live-build-config/hooks/live` 注入 `99-custom-proxy.chroot`，负责 live-build 阶段补权限和启用 late-bind。
4. 运行 `build-vyos-image` 产出 ISO，并通过 flavor build hook 尝试产出 OVA。

`packer/build.pkr.hcl` 保留为旧的“安装 ISO 后再注入”的兼容路径；GitHub Actions 当前不再调用 `packer build`。

## 为什么不是旧两段式

VyOS 1.5 的 `build-vyos-image` 只能产出 ISO/raw 镜像；VMware OVA 需要
VyOS 私有的签名工具，社区构建拿不到。所以：

- **源码构建 ISO/OVA**：用 `vyos/vyos-build:current` 容器，按官方方式
  `sudo --preserve-env ./build-vyos-image --architecture amd64 --build-by ... generic`
  构建出 ISO，并用 flavor `build_hook` 将 raw 镜像转成 streamOptimized vmdk、
  手写 OVF、tar 成 `.ova`。ISO 是主产物；OVA 是 best-effort 可选产物，CI 环境无法完成 OVA 转换时只保留 ISO。

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

GitHub → Actions → **Build VyOS 1.5 daed Gateway Image** →
Run workflow：

- `daed_version`：daed 版本，默认 `latest`
- `use_china_mirror`：国内构建建议 `true`

产物：

- `vyos15-daed-gateway-iso`：必需 artifact，保留 14 天。
- `vyos15-daed-gateway-ova`：best-effort 可选 artifact，只有 OVA 文件实际生成时才上传。

## 参考

- 官方构建命令出处：vyos-build `current` 分支 `.github/workflows/package-smoketest.yml`
- nexttrace 补丁灵感：[KawaiiNetworks/vyos-unofficial](https://github.com/KawaiiNetworks/vyos-unofficial)
- [VyOS 文档](https://docs.vyos.io/) ｜ [NextTrace](https://github.com/nxtrace/nexttrace)
