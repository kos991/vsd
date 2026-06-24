# 🆕 增强功能说明

> 本项目已集成补丁管理系统，提供更强大的功能和更好的兼容性。

## ✨ 新增功能概览

### 1. 🔧 自动修复和增强

| 功能 | 说明 | 状态 |
|------|------|------|
| **Podman 内存修复** | 修复容器启动 OCI 运行时错误 | ✅ 默认启用 |
| **Mellanox 交换机支持** | SN2010/SN2100 接口命名优化 | ✅ 默认启用 |
| **NextTrace 诊断工具** | 高级网络路由追踪 | ✅ 默认启用 |

### 2. 🛠️ 实用工具包

构建后的系统自动包含以下工具：

```bash
# 系统监控
btop                    # 现代化的系统资源监控器

# 网络诊断
nexttrace google.com    # 高级路由追踪，显示地理位置
nexttrace -T 443 github.com  # TCP 端口追踪

# 文件系统
tree /config            # 目录树显示
gdu /var                # 磁盘使用分析（交互式）

# 文本搜索
rg "pattern" /config    # 超快速文本搜索（ripgrep）
```

### 3. 🇨🇳 中国用户优化

#### 镜像源加速
使用国内镜像源，构建速度提升 50%：
- **原始构建时间**: 120-180 分钟
- **加速后时间**: 60-90 分钟

#### 如何启用
在 GitHub Actions 中运行 **Build VyOS Source OVA (Enhanced)** 工作流时：
- 勾选 `use_china_mirror: true`

## 📚 详细文档

- **[补丁系统完整说明](./docs/PATCHES.md)** - 所有补丁的详细技术说明
- **[快速开始指南](./docs/PATCHES-QUICKSTART.md)** - 5 分钟上手教程

## 🔄 工作流选择

本项目提供两个构建工作流：

### 原始工作流 (build-from-source.yml)
- 基础 VyOS + daed 网关
- 适合不需要额外功能的用户
- 构建时间：120-180 分钟

### 增强工作流 (build-from-source-enhanced.yml) ⭐推荐
- 包含所有补丁和工具
- 支持中国镜像源加速
- 可选启用/禁用功能
- 构建时间：60-90 分钟（使用国内镜像）

## 🚀 快速开始

### 使用增强构建（推荐）

1. 进入仓库的 **Actions** 标签页
2. 选择 **Build VyOS Source OVA (Enhanced)**
3. 点击 **Run workflow**
4. 配置选项：
   - `daed_version`: `latest`
   - `use_china_mirror`: `true` (国内用户)
   - `enable_patches`: `true` (推荐)
5. 等待构建完成并下载 OVA

### 验证新功能

部署 OVA 后，登录系统验证：

```bash
# 检查工具是否安装
which btop nexttrace tree gdu rg

# 测试 NextTrace
nexttrace www.google.com

# 测试系统监控
btop

# 检查容器功能（Podman 修复）
show container

# 如果是 Mellanox 交换机，检查接口命名
show interfaces
```

## 🐛 已修复的问题

### Podman 容器错误
**问题**:
```
OCI runtime error: crun: cannot set memory+swap limit less than the memory limit
```

**解决**: 自动应用补丁，移除有问题的内存交换限制参数

### Mellanox 交换机接口混乱
**问题**: Mellanox SN2010 等交换机的接口名称与前面板标签不匹配

**解决**: 使用 `mlxsw_spectrum` 驱动自动匹配，接口名称如 `en1`, `en2` 等与物理端口对应

## 📊 功能对比

| 特性 | 原始版本 | 增强版本 |
|------|----------|----------|
| daed 透明代理 | ✅ | ✅ |
| MosDNS + SmartDNS | ✅ | ✅ |
| Podman 容器支持 | ⚠️ 可能出错 | ✅ 已修复 |
| Mellanox 交换机 | ❌ | ✅ 支持 |
| 网络诊断工具 | 基础 | ✅ NextTrace |
| 系统监控 | 基础 | ✅ btop, gdu |
| 文本搜索 | 基础 grep | ✅ ripgrep |
| 构建速度（国内） | 慢 | ✅ 加速 50% |
| 补丁管理 | ❌ | ✅ 系统化 |

## 🔍 技术细节

### 补丁来源
所有补丁均来自经过验证的开源项目：
- [KawaiiNetworks/vyos-unofficial](https://github.com/KawaiiNetworks/vyos-unofficial) - 主要补丁来源
- [NextTrace](https://github.com/nxtrace/nexttrace) - 网络诊断工具
- [Scott Lamb's Guide](https://scottstuff.net/posts/2025/11/11/vyos-on-mellanox-sn2010-switch-part1/) - Mellanox 支持

### 补丁管理
```
patches/
├── vyos-1x/          # VyOS 核心系统补丁
├── vyos-build/       # 构建系统补丁
└── kernel/           # 内核配置（可选）
```

### 自动化验证
```bash
# 验证所有补丁的完整性
bash scripts/verify-patches.sh
```

## 💡 使用建议

### 推荐配置
- ✅ 使用增强工作流
- ✅ 启用所有补丁
- ✅ 国内用户启用镜像加速
- ✅ 包含所有工具包

### 适用场景

#### 场景 1: 家庭/办公室网关
使用增强版本，获得最佳的兼容性和诊断能力。

#### 场景 2: Mellanox 交换机用户
**必须**使用增强版本并启用补丁，否则接口命名会混乱。

#### 场景 3: Docker/Podman 重度使用
启用 Podman 修复补丁，避免容器启动失败。

#### 场景 4: 网络运维/调试
包含的 `nexttrace`、`btop` 等工具可大幅提升效率。

## 🆘 故障排除

### 补丁未生效
检查工作流日志中的 "Apply patches" 步骤，确认补丁已成功应用。

### 工具不可用
确认使用的是 **Enhanced** 工作流，并且 `enable_patches: true`。

### 构建失败
1. 检查补丁完整性：`bash scripts/verify-patches.sh`
2. 尝试使用原始工作流排除补丁问题
3. 查看 GitHub Actions 日志

## 🤝 贡献

欢迎提交新的补丁和改进！请查看 [docs/PATCHES.md](./docs/PATCHES.md) 了解补丁编写规范。

## 📝 变更日志

### v1.1 - Enhanced Edition (2026-06-24)
- ✅ 添加补丁管理系统
- ✅ 修复 Podman 容器问题
- ✅ 支持 Mellanox 交换机
- ✅ 集成 NextTrace 诊断工具
- ✅ 添加 btop, gdu, ripgrep, tree 工具
- ✅ 支持中国镜像源加速
- ✅ 新增增强工作流
- ✅ 完整的补丁文档

### v1.0 - Initial Release
- ✅ VyOS 1.5 + daed 透明代理
- ✅ MosDNS + SmartDNS 双引擎 DNS
- ✅ 基于 Packer 的可重现构建

---

**需要帮助？** 查看 [快速开始指南](./docs/PATCHES-QUICKSTART.md) 或提交 Issue。
