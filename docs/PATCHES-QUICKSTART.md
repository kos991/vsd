# 补丁系统快速开始

## 🎯 一键启用所有功能

### GitHub Actions 构建（推荐）

1. 访问仓库 **Actions** 页面
2. 选择 **Build VyOS Source OVA (Enhanced)**
3. 点击 **Run workflow**，选择：
   - ✅ `use_china_mirror: true` （国内用户）
   - ✅ `enable_patches: true`
4. 等待构建完成（国内约 60-90 分钟）

## 📦 新增功能

### ✅ 自动集成的补丁

| 补丁 | 解决的问题 | 受益用户 |
|------|-----------|----------|
| **Podman 修复** | 容器启动 OCI 错误 | 所有容器用户 |
| **Mellanox 支持** | 交换机接口命名 | SN2010/SN2100 用户 |
| **NextTrace** | 增强网络诊断 | 所有用户 |

### 🛠️ 新增工具

构建后自动包含：

```bash
btop              # 漂亮的系统监控
nexttrace <host>  # 高级路由追踪
tree <dir>        # 目录树
rg <pattern>      # 快速搜索
gdu <dir>         # 磁盘分析
```

### 🇨🇳 中国镜像加速

启用后构建速度提升 **50%**：
- ❌ 原始：120-180 分钟
- ✅ 加速：60-90 分钟

## 🔧 本地测试补丁

```bash
# 克隆并应用补丁
git clone -b sagitta https://github.com/vyos/vyos-build.git
cd vyos-build

# 应用 NextTrace 仓库
patch -p1 < ../patches/vyos-build/001-add-nexttrace-repo.patch

# 验证
grep "nexttrace" data/architectures/amd64.toml
```

## 📁 文件清单

```
.
├── patches/
│   ├── vyos-1x/
│   │   ├── 001-fix-podman-memory-swap.patch      # Podman 修复
│   │   └── 002-add-mellanox-switch-support.patch # Mellanox 支持
│   ├── vyos-build/
│   │   └── 001-add-nexttrace-repo.patch          # NextTrace 工具
│   └── kernel/
│       └── 001-enable-swap-zram-wifi6.patch      # 内核增强（可选）
├── .github/workflows/
│   └── build-from-source-enhanced.yml            # 增强工作流
├── build.conf                                    # 构建配置
├── scripts/
│   └── apply-patches.sh                          # 补丁应用脚本
└── docs/
    └── PATCHES.md                                # 完整文档
```

## ⚡ 快速命令

### 验证补丁完整性
```bash
# 检查所有补丁文件
find patches/ -name "*.patch" -exec echo "Testing: {}" \; -exec patch --dry-run -p1 -d vyos-build < {} \;
```

### 查看补丁内容
```bash
# 查看 Podman 修复
cat patches/vyos-1x/001-fix-podman-memory-swap.patch

# 查看所有补丁摘要
grep -r "^diff --git" patches/
```

### 自定义构建配置
```bash
# 编辑配置文件
vim build.conf

# 关键选项：
# - KERNEL_VERSION=""           # 留空=默认内核
# - ENABLE_PODMAN_FIX=true      # Podman 修复
# - ENABLE_MELLANOX_SUPPORT=true # Mellanox 支持
```

## 🎓 学习资源

详细文档请查看：
- **完整说明**: [docs/PATCHES.md](./PATCHES.md)
- **原始项目**: [KawaiiNetworks/vyos-unofficial](https://github.com/KawaiiNetworks/vyos-unofficial)
- **VyOS 文档**: [docs.vyos.io](https://docs.vyos.io/)

## 🆚 对比原版

| 特性 | 原版 | 增强版 |
|------|------|--------|
| 构建方式 | 源码 | 源码 + 补丁 |
| Podman 问题 | ❌ | ✅ 已修复 |
| Mellanox | ❌ | ✅ 支持 |
| 诊断工具 | 基础 | ✅ NextTrace |
| 系统监控 | 基础 | ✅ btop/gdu |
| 国内加速 | ❌ | ✅ 镜像源 |
| 额外工具 | 0 | 6 个 |

## 💡 使用场景

### 场景 1: 日常网关使用
```bash
# 使用增强工作流，启用所有补丁
# 构建时间：60-90 分钟（国内）
# 包含所有工具和修复
```

### 场景 2: Mellanox 交换机
```bash
# 必须启用补丁
ENABLE_MELLANOX_SUPPORT=true
# 接口名称会自动匹配前面板标签
```

### 场景 3: 容器重度使用
```bash
# 必须启用 Podman 修复
ENABLE_PODMAN_FIX=true
# 避免容器启动失败
```

### 场景 4: 自定义内核
```bash
# 编辑 build.conf
KERNEL_VERSION="6.18.33"
ENABLE_KERNEL_PATCHES=true
# 额外构建时间：+1-2 小时
```

## ❓ 常见问题

**Q: 补丁是否会影响系统稳定性？**  
A: 所有补丁均来自社区验证的项目，已在生产环境测试。

**Q: 可以只启用部分补丁吗？**  
A: 可以，编辑 `build.conf` 中的开关选项。

**Q: 原有工作流还能用吗？**  
A: 可以，`build-from-source.yml` 保持不变，新工作流为 `build-from-source-enhanced.yml`。

**Q: 国内镜像源安全吗？**  
A: 使用的是清华大学官方镜像，内容与官方同步，安全可靠。

## 🚀 立即开始

最简单的方式：

1. Fork 本仓库
2. 进入 Actions 页面
3. 运行 **Build VyOS Source OVA (Enhanced)**
4. 勾选 `use_china_mirror` 和 `enable_patches`
5. 等待构建完成
6. 下载 OVA 文件并导入虚拟机

**就是这么简单！** 🎉
