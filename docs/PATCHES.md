# VyOS 补丁系统说明

本项目集成了一套补丁管理系统，用于在构建 VyOS OVA 镜像时应用自定义修改和增强功能。

## 📁 目录结构

```
patches/
├── vyos-1x/                    # VyOS 核心系统补丁
│   ├── 001-fix-podman-memory-swap.patch
│   └── 002-add-mellanox-switch-support.patch
├── vyos-build/                 # VyOS 构建系统补丁
│   └── 001-add-nexttrace-repo.patch
└── kernel/                     # 内核配置补丁（仅用于自定义内核构建）
    └── 001-enable-swap-zram-wifi6.patch
```

## 🔧 已集成的补丁

### 1. **Podman 内存交换修复** (`vyos-1x/001-fix-podman-memory-swap.patch`)

**问题**: 在某些环境下，Podman 容器启动时会遇到 OCI 运行时错误：
```
OCI runtime error: crun: cannot set memory+swap limit less than the memory limit
```

**解决方案**: 移除 `--memory-swap 0` 参数，允许 Podman 使用默认的内存交换策略。

**适用场景**: 
- 使用 VyOS 容器功能时频繁遇到启动失败
- 运行在内存受限的环境中

### 2. **Mellanox 交换机支持** (`vyos-1x/002-add-mellanox-switch-support.patch`)

**功能**: 为 Mellanox Spectrum 系列交换机（如 SN2010）添加友好的网络接口命名。

**改进**:
- 接口名称与前面板标签匹配（例如：`en1`, `en2` 等）
- 简化交换机配置和管理
- 使用 `mlxsw_spectrum` 驱动的设备自动应用

**参考**: [Scott Lamb's Guide](https://scottstuff.net/posts/2025/11/11/vyos-on-mellanox-sn2010-switch-part1/)

### 3. **NextTrace 网络诊断工具** (`vyos-build/001-add-nexttrace-repo.patch`)

**功能**: 添加 NextTrace 软件源，提供更强大的路由追踪功能。

**优势**:
- 支持多种协议（TCP, UDP, ICMP）
- 显示 IP 地理位置信息
- 可视化路由路径
- 比传统 traceroute 更准确

**使用示例**:
```bash
nexttrace google.com
nexttrace -T 443 github.com  # TCP 追踪
```

### 4. **内核增强** (`kernel/001-enable-swap-zram-wifi6.patch`)

⚠️ **注意**: 此补丁仅在构建自定义内核时使用（默认不启用）

**功能**:
- **SWAP 支持**: 启用交换分区，改善内存管理
- **ZRAM 支持**: 内存压缩，提高低内存系统性能
- **WiFi 6/6E 支持**: 启用以下驱动
  - `ATH11K` - Qualcomm WiFi 6
  - `ATH12K` - Qualcomm WiFi 6E
  - `MT7921E` - MediaTek WiFi 6
  - `MT7996E` - MediaTek WiFi 6E
- **压缩算法**: 添加 LZO 和 ZSTD 加密支持

## 🚀 使用方法

### 方法 1: GitHub Actions（推荐）

使用增强版工作流构建：

1. 进入仓库的 **Actions** 标签页
2. 选择 **Build VyOS Source OVA (Enhanced)**
3. 点击 **Run workflow**
4. 配置选项：
   - `daed_version`: daed 版本（默认：latest）
   - `use_china_mirror`: 是否使用中国镜像源（加速构建）
   - `enable_patches`: 是否启用补丁（默认：true）

### 方法 2: 本地构建

```bash
# 1. 配置构建选项
cp build.conf.example build.conf
vim build.conf

# 2. 克隆 vyos-build
git clone -b sagitta --single-branch https://github.com/vyos/vyos-build.git

# 3. 应用补丁
bash scripts/apply-patches.sh

# 4. 继续正常构建流程...
```

## ⚙️ 配置选项 (`build.conf`)

```bash
# 自定义内核版本（留空使用 VyOS 默认内核）
KERNEL_VERSION=""

# VyOS 构建分支
VYOS_BUILD_REF="sagitta"

# 中国镜像源（加速构建）
# DEBIAN_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/debian"
# DEBIAN_SECURITY_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/debian-security"

# 额外软件包
ADDITIONAL_PACKAGES=(
    "btop"           # 系统监控
    "nexttrace"      # 路由追踪
    "tree"           # 目录树显示
    "ripgrep"        # 快速文本搜索
    "gdu"            # 磁盘使用分析
    "qemu-guest-agent"  # QEMU 虚拟机增强
)

# 启用/禁用补丁
ENABLE_PODMAN_FIX=true
ENABLE_MELLANOX_SUPPORT=true
ENABLE_NEXTTRACE_REPO=true
ENABLE_KERNEL_PATCHES=false  # 仅在构建自定义内核时启用
```

## 📦 额外工具包

启用补丁后，系统会自动包含以下工具：

| 工具 | 用途 | 命令示例 |
|------|------|----------|
| **btop** | 资源监控（CPU、内存、网络） | `btop` |
| **nexttrace** | 高级路由追踪 | `nexttrace -T 443 github.com` |
| **tree** | 目录树显示 | `tree /config` |
| **ripgrep** | 快速文本搜索 | `rg "pattern" /config` |
| **gdu** | 磁盘使用分析 | `gdu /var` |
| **qemu-guest-agent** | 虚拟机集成 | 自动运行 |

## 🇨🇳 中国用户优化

### 使用国内镜像源

在 `build.conf` 中取消注释：

```bash
DEBIAN_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/debian"
DEBIAN_SECURITY_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/debian-security"
```

**可选镜像源**:
- 清华大学：`https://mirrors.tuna.tsinghua.edu.cn/debian`
- 中科大：`https://mirrors.ustc.edu.cn/debian`
- 阿里云：`https://mirrors.aliyun.com/debian`
- 华为云：`https://mirrors.huaweicloud.com/debian`

### 构建时间对比

| 镜像源 | 预计构建时间 |
|--------|--------------|
| 官方源（国外） | 120-180 分钟 |
| 国内镜像源 | 60-90 分钟 |

## 🔍 自定义内核构建

如需构建特定内核版本（例如 6.18.33）：

1. 编辑 `build.conf`:
   ```bash
   KERNEL_VERSION="6.18.33"
   ENABLE_KERNEL_PATCHES=true
   ```

2. 内核构建会额外需要 **1-2 小时**

3. 启用的内核功能：
   - SWAP + ZRAM（内存优化）
   - WiFi 6/6E 驱动（无线网络）
   - 压缩算法（性能优化）

⚠️ **注意**: 自定义内核构建复杂度高，仅在需要特定硬件支持时使用。

## 📊 工作流对比

| 特性 | 原始工作流 | 增强工作流 |
|------|-----------|-----------|
| 补丁系统 | ❌ | ✅ |
| 中国镜像源 | ❌ | ✅ |
| Podman 修复 | ❌ | ✅ |
| Mellanox 支持 | ❌ | ✅ |
| 额外工具包 | ❌ | ✅ (6个) |
| 自定义内核 | ❌ | ✅ (可选) |
| 构建时间（国内） | 120min | 60-90min |

## 🐛 故障排除

### 补丁应用失败

```bash
# 查看补丁是否已应用
patch --dry-run -p1 -d vyos-build < patches/vyos-build/001-add-nexttrace-repo.patch

# 强制重新应用（慎用）
patch --force -p1 -d vyos-build < patches/vyos-build/001-add-nexttrace-repo.patch
```

### 构建超时

- 启用中国镜像源（`use_china_mirror: true`）
- 增加 GitHub Actions 超时时间（已设置为 6 小时）

### 工具不可用

检查补丁是否正确应用：

```bash
# 验证 nexttrace 仓库
grep -r "nexttrace" vyos-build/data/architectures/amd64.toml
```

## 📚 参考资源

- [VyOS 官方文档](https://docs.vyos.io/)
- [KawaiiNetworks/vyos-unofficial](https://github.com/KawaiiNetworks/vyos-unofficial) - 补丁来源
- [NextTrace 项目](https://github.com/nxtrace/nexttrace)
- [Scott Lamb's Mellanox Guide](https://scottstuff.net/posts/2025/11/11/vyos-on-mellanox-sn2010-switch-part1/)

## 🤝 贡献

欢迎提交新的补丁！请遵循以下命名规范：

```
patches/<target>/NNN-<description>.patch

例如：
patches/vyos-1x/003-add-feature-xyz.patch
```

补丁格式：
```bash
# 生成补丁
cd vyos-build
git diff > ../patches/vyos-build/002-my-feature.patch

# 测试补丁
patch --dry-run -p1 -d vyos-build < patches/vyos-build/002-my-feature.patch
```

## 📝 更新日志

### v1.1 (2026-06-24)
- ✅ 添加补丁管理系统
- ✅ 集成 Podman 修复
- ✅ 添加 Mellanox 交换机支持
- ✅ 集成 NextTrace 工具
- ✅ 支持中国镜像源
- ✅ 添加 6 个实用工具包
- ✅ 支持自定义内核构建（可选）

### v1.0
- 初始版本：基础 daed 网关构建
