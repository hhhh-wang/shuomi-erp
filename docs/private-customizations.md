# 硕米ERP 私有二开记录

标记：`SHUOMI-ERP PRIVATE CUSTOMIZATION`。记录日期：2026-11-23（Asia/Shanghai）。

“私有二开”表示硕米内部定制改动的归属及范围，保留 [Lemon ERP](https://github.com/MakeSomeFakeNews/lemon-erp) 上游与 [Apache-2.0](../LICENSE) 许可证。该标记不替代许可证，也不改变 GitHub 仓库的访问权限。当前仓库是公开 fork。

## 仓库与分支

- 产品名称与目标仓库标识：`shuomi-erp`。
- 当前 GitHub fork：`hhhh-wang/lemon-erp`；父仓库为 `MakeSomeFakeNews/lemon-erp`。
- 计划更名为 `hhhh-wang/shuomi-erp`，继续保留 fork 及 `upstream`。更名尚未完成。
- `main` 是产品主线，功能使用 `feature/*`，上游同步使用 `sync/upstream-YYYYMMDD`，按需使用 `release/*`。
- 本次交付分支：`feature/shuomi-production-deployment`；部署调整与二开/发布标记分别提交。
- 发布标签统一为 `shuomi-vX.Y.Z-N`。本次不凭示例版本号创建发布标签。

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
| 品牌和发布归属 | `README.md`、`docs/upstream-sync.md`、`.github/workflows/release.yml` | 标记二开、保留上游、统一硕米标签与对外发布名 |

代码或脚本的定制位置使用上述标记注释；此表记录整体范围。生产账号、密码、JWT/AI 密钥及证书私钥使用本机/服务器私有文件，不进入提交、构建上下文或发布包。实际部署详情保存为忽略文件 `docker/production-status.private.md`。

## 兼容标识

保留 Java `com.lemon.*`、Gradle `lemon-*` 模块及 `rootProject.name`、构建内部 `lemon-erp.jar`、`LEMON_*` 环境变量。本地 Compose 项目 `lemon-erp`、数据库 `lemon_erp` 和现有数据卷继续兼容。生产项目、容器、镜像前缀、外部数据库名称使用 `shuomi-erp`。仓库更名不要求批量修改这些技术标识。

## 基线与验证

- 上游业务基线：`4c03efde`。
- 已有品牌提交：`0f7f9dd0`。
- 已有同步规范提交：`2d5b0b1c`。
- 本次部署提交：`8f6c237f`。
- 本次部署验收见[生产部署验收记录](production-status.md)；镜像/配置验证与本轮文档和发布规则检查分别记录。
- 本轮校验：两个 workflow YAML 解析、15 段 Shell 语法、6 组标签接受/拒绝与版本映射检查通过；提交内容未匹配实际私有凭据。
- GitHub CI 已有后端 `gradlew build`（包含测试任务）、前端构建、小程序构建与检查。核对时工作流 active，但运行记录为 0；不能把文件存在视为 CI 已通过。

## 后续上游同步

使用[上游同步规范](upstream-sync.md)：从 `main` 创建日期同步分支，`git merge --no-ff upstream/main`，处理冲突并完成 CI 后通过 PR 合并。同步 PR 保留 merge commit。品牌、内部部署与通用修复分别提交；可复用修复单独向上游提出。

本机已启用 `rerere`、`rerere.autoupdate`、`pull.ff=only` 和 `fetch.prune`；`.gitattributes` 已定义 LF 及 Windows 脚本 CRLF。品牌文案目前仍分布于多语言、AI、打印、小程序及登录配置中，集中品牌配置尚未全部完成。`main` 的 PR/CI/禁强推/禁删除保护也尚未配置。
