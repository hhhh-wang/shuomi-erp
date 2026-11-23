# 硕米ERP 生产部署验收记录

<!-- SHUOMI-ERP PRIVATE CUSTOMIZATION: deployment acceptance -->

2026-11-23 已完成本地与生产部署验收，生产镜像版本为 `release-20261123-203650`。具体服务器地址、1Panel 记录和访问凭据保存在本机忽略文件 `docker/production-status.private.md`、`docker/production-access.txt` 及服务器私有环境文件中。

| 验收项 | 结果 |
| --- | --- |
| 生产服务 | `shuomi-erp`、`shuomi-erp-backend`、`shuomi-erp-redis` 均 healthy |
| 生产 MySQL | 独立托管服务，数据库 `shuomi-erp`，生产 Compose 不包含 MySQL 容器 |
| 本地服务 | 原 `lemon-erp` 四服务健康，已有 MySQL/Redis 容器、数据卷和关键数据计数保持一致 |
| 数据库初始化 | 空库守卫后初始化 269 张业务表，Flowable 受控创建 32 张引擎表 |
| 正常生产启动 | `FLOWABLE_DATABASE_SCHEMA_UPDATE=false`，Spring SQL init 为 `never` |
| HTTPS | 由 1Panel 管理可信证书、自动续期、HTTP 跳转和反向代理 |
| 管理员 | admin 已启用，独立初始密码与首次改密标记，test 停用 |
| 应用验证 | 首页、history 路由、健康检查、认证配置、管理员登录、用户信息及菜单通过 |
| 更新验证 | 同版本更新包校验、导入和重新编排成功，三个生产容器保持 healthy |
| 离线导出 | 初次包和更新包完成，两个默认导出入口的 `-CheckOnly` 通过 |

数据库验收时所用入口未支持 TLS。`useSSL=true` 会采用 Connector/J 兼容行为；该设置不能作为数据库连接已经加密的证明。云端启用 SSL 后，按[部署说明](production-deployment.md)验证并加入强制参数。

损坏校验和、不可覆盖的镜像标签、持久化卷变化拒绝路径和失败回滚已在隔离环境验证。同版本生产更新未模拟线上故障，也未进行跨版本数据库迁移。

后续更新使用 `update-local-containers.cmd`、`export-update-images.cmd` 和包内 `scripts/update-production-containers.sh`，具体操作见[部署说明](production-deployment.md)。
