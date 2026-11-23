# 硕米ERP 私有二开记录

标记：`SHUOMI-ERP PRIVATE CUSTOMIZATION`。记录日期：2026-11-23（Asia/Shanghai）。

“私有二开”表示硕米内部定制改动的归属及范围，保留 [Lemon ERP](https://github.com/MakeSomeFakeNews/lemon-erp) 上游与 [Apache-2.0](../LICENSE) 许可证。该标记不替代许可证，也不改变 GitHub 仓库的访问权限。当前仓库是公开 fork。

## 仓库与分支

- 产品名称与目标仓库标识：`shuomi-erp`。
- 当前 GitHub fork：`hhhh-wang/shuomi-erp`；父仓库为 `MakeSomeFakeNews/lemon-erp`。
- 已更名为 `hhhh-wang/shuomi-erp`，继续保留 fork 及 `upstream`。
- `main` 是产品主线，功能使用 `feature/*`，上游同步使用 `sync/upstream-YYYYMMDD`，按需使用 `release/*`。
- 本次交付分支：`feature/shuomi-production-deployment`；部署、校验脚本通用修复、品牌集中配置和说明分别提交。
- 发布标签统一为 `shuomi-vX.Y.Z-N`，版本号依据源码版本确定。当前版本与发布状态见 [GitHub Releases](https://github.com/hhhh-wang/shuomi-erp/releases)。

## 本次改动范围

| 范围 | 文件 | 目的 |
| --- | --- | --- |
| 本地编排 | `docker/docker-compose.yml`、`.env.local.example`、`.env.example` | 保留原测试 MySQL/Redis 与数据卷 |
| 生产编排 | `docker/docker-compose.prod.yml`、`.env.prod.example`、`application-prod.yml` | 外部 MySQL、独立 Redis、应用三服务、关闭正常生产自动建表 |
| 镜像和代理 | `docker/*Dockerfile`、`build.sh`、`nginx.conf` | `shuomi-erp` 镜像名、应用健康检查、上传/流式代理配置 |
| Windows 入口 | `export-init-images.cmd`、`export-update-images.cmd`、`update-local-containers.cmd` | 初次包、更新包、本地更新三入口 |
| 发布脚本 | `scripts/docker-common.ps1`、`export-images.ps1`、`update-local-containers.ps1`、`update-production-containers.sh` | 校验镜像/归档、版本标签、健康、配置备份与失败回滚 |
| 首次生产初始化 | `sql/production-bootstrap.sql` | 仅空库使用，干净系统种子数据，管理员默认锁定 |
| 说明和私有文件边界 | `.gitignore`、`.dockerignore`、`docs/production-*.md` | 记录部署/更新方法，排除真实凭据和运维实值 |
| 品牌集中配置 | `lemon-web/src/branding.js`、两端 Vite 配置和相关语言包 | 共用默认值，保留运行时系统名/租户名覆盖与 Logo |
| 品牌和发布归属 | `README.md`、`docs/upstream-sync.md`、`.github/workflows/release.yml` | 标记二开、保留上游、统一硕米标签与对外发布名 |
| 发布验收与分发 | `scripts/github-release.mjs`、`release.yml`、镜像与 JAR 配置 | 草稿完整性、文件 SHA256、双架构镜像 digest、发布防覆盖及许可证副本 |

代码或脚本的定制位置使用上述标记注释；此表记录整体范围。生产账号、密码、JWT/AI 密钥及证书私钥使用本机/服务器私有文件，不进入提交、构建上下文或发布包。实际部署详情保存为忽略文件 `docker/production-status.private.md`。

## 兼容标识

保留 Java `com.lemon.*`、Gradle `lemon-*` 模块及 `rootProject.name`、构建内部 `lemon-erp.jar`、`LEMON_*` 环境变量。本地 Compose 项目 `lemon-erp`、数据库 `lemon_erp` 和现有数据卷继续兼容。生产项目、容器、镜像前缀、外部数据库名称使用 `shuomi-erp`。仓库更名不要求批量修改这些技术标识。

## 基线与验证

- 上游业务基线：`4c03efde`。
- 已有品牌提交：`0f7f9dd0`。
- 已有同步规范提交：`2d5b0b1c`。
- 本次部署提交：`8f6c237f`。
- 通用跨平台校验修复：`bffee749`。
- 品牌集中配置：`07add2a0`。
- 本次部署验收见[生产部署验收记录](production-status.md)；镜像/配置验证与本轮文档和发布规则检查分别记录。
- 本轮校验：两个 workflow YAML 解析、15 段 Shell 语法、6 组标签接受/拒绝与版本映射检查通过；Web/小程序 i18n、枚举与两端构建通过，产物品牌标题保持一致；提交内容未匹配实际私有凭据。
- 发布收尾：修复 Windows 脚本中部 BOM，三份脚本通过真实 PowerShell 5.1 语法解析；CI 同时检查 PowerShell 和发布脚本语法。产物记录将构建固定到同一源提交并在发布时验证标签、SHA256 和双架构镜像摘要。
- GitHub CI 包含后端 `gradlew build`（包含测试任务）、前端与小程序构建、多语言/枚举检查，以及 PR 中的 Docker 构建。`main` 要求对应四项检查通过，结果以当前 PR 和 Actions 为准。

## 后续上游同步

使用[上游同步规范](upstream-sync.md)：从 `main` 创建日期同步分支，`git merge --no-ff upstream/main`，处理冲突并完成 CI 后通过 PR 合并。同步 PR 保留 merge commit。品牌、内部部署与通用修复分别提交；可复用修复单独向上游提出。

本机已启用 `rerere`、`rerere.autoupdate`、`pull.ff=only` 和 `fetch.prune`；`.gitattributes` 已定义 LF 及 Windows 脚本 CRLF。品牌默认值已集中在 `lemon-web/src/branding.js`；AI、打印、登录及小程序语言包引用此源，静态标题/manifest/pages 由构建配置同步。`main` 已开启 PR、必需 CI、解决对话、禁强推和禁删除保护，管理员同样受规则约束。
