# 📖 完整的项目文档导航

## 🎯 根据需求选择文档

### 我是新用户，想快速开始
👉 **[快速参考卡片](./QUICKREF.md)** - 3 分钟了解所有新功能  
👉 **[快速开始指南](./docs/PATCHES-QUICKSTART.md)** - 5 分钟上手教程

### 我想了解增强功能
👉 **[功能总览](./docs/ENHANCEMENTS.md)** - 所有新功能的详细说明  
👉 **[补丁系统文档](./docs/PATCHES.md)** - 技术细节和使用方法

### 我是开发者或维护者
👉 **[项目总结](./docs/SUMMARY.md)** - 完整的开发记录和技术细节  
👉 **[构建配置](./build.conf)** - 构建选项说明

### 我遇到了问题
👉 **[故障排除](./docs/PATCHES.md#-故障排除)** - 常见问题解决方案  
👉 **[验证脚本](./scripts/verify-patches.sh)** - 检查补丁完整性

---

## 📂 文档结构

```
项目根目录/
│
├── 📄 README.md                          # 主文档（原版）
├── 📄 QUICKREF.md                        # ⭐ 快速参考卡片
├── 📄 NAVIGATION.md                      # 📍 本文档（导航）
│
├── 📁 docs/                              # 详细文档目录
│   ├── PATCHES-QUICKSTART.md            # ⚡ 5 分钟快速上手
│   ├── ENHANCEMENTS.md                  # ✨ 功能总览
│   ├── PATCHES.md                       # 🔧 完整技术文档
│   └── SUMMARY.md                       # 📊 项目总结
│
├── 📁 patches/                           # 补丁文件
│   ├── vyos-1x/                         # VyOS 核心补丁
│   ├── vyos-build/                      # 构建系统补丁
│   └── kernel/                          # 内核补丁（可选）
│
├── 📁 scripts/                           # 自动化脚本
│   ├── apply-patches.sh                 # 应用补丁
│   └── verify-patches.sh                # 验证补丁
│
├── 📁 .github/workflows/                 # CI/CD 工作流
│   ├── build-from-source.yml            # 原始工作流
│   └── build-from-source-enhanced.yml   # ⭐ 增强工作流
│
└── 📄 build.conf                         # 构建配置文件
```

---

## 🎯 按场景导航

### 场景 1: 我想构建增强版 VyOS
```
1. 阅读: QUICKREF.md（了解新功能）
2. 前往: GitHub Actions
3. 运行: Build VyOS Source OVA (Enhanced)
4. 参考: docs/PATCHES-QUICKSTART.md（如有问题）
```

### 场景 2: 我想了解补丁系统
```
1. 快速了解: docs/ENHANCEMENTS.md
2. 技术细节: docs/PATCHES.md
3. 查看补丁: patches/ 目录
4. 测试补丁: scripts/verify-patches.sh
```

### 场景 3: 我是 Mellanox 交换机用户
```
1. 阅读: docs/PATCHES.md#2-mellanox-交换机支持
2. 确认: 必须使用增强工作流
3. 启用: enable_patches: true
4. 验证: show interfaces（部署后）
```

### 场景 4: 我想贡献新补丁
```
1. 学习格式: docs/PATCHES.md#-贡献
2. 查看示例: patches/*/001-*.patch
3. 创建补丁: git diff > patches/xxx/NNN-description.patch
4. 验证补丁: bash scripts/verify-patches.sh
5. 提交 PR
```

### 场景 5: 构建失败了
```
1. 检查: GitHub Actions 日志
2. 验证: bash scripts/verify-patches.sh
3. 参考: docs/PATCHES.md#-故障排除
4. 尝试: 使用原始工作流排除问题
```

---

## 📊 文档对比表

| 文档 | 长度 | 受众 | 目的 |
|------|------|------|------|
| **QUICKREF.md** | 短 (1 页) | 所有人 | 快速参考 |
| **PATCHES-QUICKSTART.md** | 中 (10 分钟) | 用户 | 快速上手 |
| **ENHANCEMENTS.md** | 中 (15 分钟) | 用户 | 功能说明 |
| **PATCHES.md** | 长 (30 分钟) | 开发者 | 完整文档 |
| **SUMMARY.md** | 长 (20 分钟) | 维护者 | 项目总结 |

---

## 🔗 外部资源

### 参考项目
- [KawaiiNetworks/vyos-unofficial](https://github.com/KawaiiNetworks/vyos-unofficial) - 补丁来源
- [VyOS 官方文档](https://docs.vyos.io/) - VyOS 使用指南
- [NextTrace](https://github.com/nxtrace/nexttrace) - 路由追踪工具

### 技术博客
- [Scott Lamb - VyOS on Mellanox](https://scottstuff.net/posts/2025/11/11/vyos-on-mellanox-sn2010-switch-part1/)

---

## 🎓 学习路径

### 初学者
```
1. QUICKREF.md                    # 3 分钟
2. docs/PATCHES-QUICKSTART.md     # 5 分钟
3. 实践：运行 Enhanced 工作流      # 60-90 分钟
4. docs/ENHANCEMENTS.md           # 15 分钟（深入了解）
```

### 进阶用户
```
1. docs/PATCHES.md                # 30 分钟
2. 查看补丁文件                    # 10 分钟
3. 本地测试补丁应用                # 30 分钟
4. build.conf 自定义配置          # 15 分钟
```

### 开发者
```
1. docs/SUMMARY.md                # 20 分钟
2. 阅读所有补丁文件                # 30 分钟
3. 研究构建脚本                    # 30 分钟
4. 本地完整构建测试                # 2-3 小时
5. 贡献新补丁                      # 根据需求
```

---

## ⚡ 快速命令

```bash
# 查看所有文档
ls docs/

# 验证补丁
bash scripts/verify-patches.sh

# 查看补丁内容
cat patches/vyos-1x/001-fix-podman-memory-swap.patch

# 测试补丁应用（需要先克隆 vyos-build）
bash scripts/apply-patches.sh

# 搜索文档内容
grep -r "Mellanox" docs/
```

---

## 📝 文档版本

| 文档 | 版本 | 日期 |
|------|------|------|
| QUICKREF.md | 1.0 | 2026-06-24 |
| PATCHES-QUICKSTART.md | 1.0 | 2026-06-24 |
| ENHANCEMENTS.md | 1.0 | 2026-06-24 |
| PATCHES.md | 1.0 | 2026-06-24 |
| SUMMARY.md | 1.0 | 2026-06-24 |
| NAVIGATION.md | 1.0 | 2026-06-24 |

---

## 🎯 常见问题快速跳转

| 问题 | 文档位置 |
|------|----------|
| 如何快速开始？ | [QUICKREF.md](./QUICKREF.md) |
| 补丁都做了什么？ | [PATCHES.md](./docs/PATCHES.md#-已集成的补丁) |
| 如何启用中国镜像？ | [PATCHES-QUICKSTART.md](./docs/PATCHES-QUICKSTART.md#-中国用户优化) |
| Podman 错误如何修复？ | [PATCHES.md](./docs/PATCHES.md#1-podman-内存交换修复) |
| Mellanox 如何支持？ | [PATCHES.md](./docs/PATCHES.md#2-mellanox-交换机支持) |
| 构建失败怎么办？ | [PATCHES.md](./docs/PATCHES.md#-故障排除) |
| 如何贡献补丁？ | [PATCHES.md](./docs/PATCHES.md#-贡献) |
| 项目开发记录？ | [SUMMARY.md](./docs/SUMMARY.md) |

---

## 💡 提示

- 📱 **移动设备用户**: 推荐先阅读 QUICKREF.md
- 💻 **桌面用户**: 可以从 ENHANCEMENTS.md 开始
- 🔧 **技术用户**: 直接查看 PATCHES.md
- 🚀 **赶时间**: 只看 QUICKREF.md 即可

---

**需要帮助？** 按场景选择对应文档，或提交 GitHub Issue。

**反馈建议？** 欢迎在 Issues 中提出文档改进建议。

---

*本导航最后更新: 2026-06-24*
