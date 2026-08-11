# UDMPAINT Trial Bypass

CLIP STUDIO PAINT (Unicorn 学习版包装) 试用限制绕过研究项目。提供可复现的 patch 脚本与完整逆向分析文档。

## 背景

`UDMPAINT.app` 为 CLIP STUDIO PAINT 4.0.5 (CELSYS) 套一层 Unicorn 自制激活器包装（bundle `xmunicorn.udongman.paint`）。本仓库分析了其试用/激活机制的三层判定，并提供绕过补丁。

## 版本与环境（针对性声明）

本补丁**针对性极强**，字节偏移仅适用于以下精确匹配的目标：

| 项 | 值 |
|---|---|
| 应用 | CLIP STUDIO PAINT（Unicorn 包装） |
| 版本 | 4.0.5 |
| bundle id（主程序 / 激活器） | `xmunicorn.udongman.paint` / `xmunicorn.udongman.active` |
| 架构 | arm64（Apple Silicon） |
| 测试系统 | macOS 15.7.4 (Build 24G517)，Darwin 24.6.0 |
| 测试日期 | 2026-08-11 |

原版二进制 SHA256 校验值见 [docs/analysis.md](docs/analysis.md)。**不匹配则不可用。**

## 结构

```
udmpaint-trial-bypass/
├── README.md
├── scripts/
│   └── patch_udmpaint.sh    # 一键 patch 脚本 (apply / verify / restore)
└── docs/
    └── analysis.md          # 完整逆向分析（机制 + Patch 清单 + 验证过程）
```

## 用法

```bash
# 应用补丁（自动备份 + patch + adhoc 重签）
./scripts/patch_udmpaint.sh apply

# 校验所有 patch 点是否已生效
./scripts/patch_udmpaint.sh verify

# 从备份恢复原版
./scripts/patch_udmpaint.sh restore
```

环境变量：`APP`（应用路径，默认 `/Applications/Unicorn/PAINT/UDMPAINT.app`）、`BK_DIR`（备份目录，默认 `/tmp/udmpaint_backup`）。

## 效果

- 30 天试用判定永不过期
- 启动次数（com.app.kml 计数）不限制
- 系统时间回拨不触发作废
- 每次启动直接进主界面，无需激活器交互

## Patch 点摘要

| 组件 | 数量 | 内容 |
|---|---|---|
| PaintActivation.app | 8 处 | 30 天判定 x3 NOP、次数判定 x1 NOP、回拨检测 x5 NOP |
| CLIP STUDIO PAINT | 2 处 | 跳过激活器检查 (tbnz->b) |

详细分析见 [docs/analysis.md](docs/analysis.md)。

## 免责声明

本项目仅供授权安全研究与 CTF 学习用途。请勿用于绕过商业软件授权。
