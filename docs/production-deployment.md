<!-- SHUOMI-ERP PRIVATE CUSTOMIZATION: production/local deployment -->
# 硕米ERP：本地部署、镜像导出与生产更新

本地编排为 MySQL、Redis、后端和前端四个服务，项目名固定为 `lemon-erp`，沿用已有数据卷。生产编排为 Redis、后端和前端三个服务，项目名为 `shuomi-erp`；MySQL 使用独立托管服务。生产入口容器名为 `shuomi-erp`，HTTPS 由 1Panel 的 OpenResty 网站终止并代理至 `127.0.0.1:18102`。

本文中的域名、服务器 IP、数据库入口和密钥路径使用示例值。实际部署记录保存在本机忽略文件 `docker/production-status.private.md`；生产凭据使用私有环境文件。

## 文件与环境变量

| 文件 | 用途 |
| --- | --- |
| `docker/docker-compose.yml` | 本地四服务编排；已有 `lemon-erp` 数据卷保持兼容 |
| `docker/docker-compose.prod.yml` | 生产三服务编排；无 MySQL 容器及自动 SQL 初始化 |
| `docker/.env.local.example` | 本地环境示例，复制为 `docker/.env` |
| `docker/.env.prod.example` | 生产环境示例，在服务器复制为 `.env`（1Panel权威环境文件） |
| `update-local-containers.cmd` | 构建本地应用镜像并等待容器健康 |
| `scripts/update-production-containers.sh` | 上传更新包后，在服务器校验、备份、重新编排并在失败时回滚 |
| `export-init-images.cmd` | 初次镜像包：后端、前端、Redis、MySQL及本地初始化SQL |
| `export-update-images.cmd` | 版本更新包：仅后端和前端镜像 |

真实数据库密码、Redis 密码、JWT 签名密钥、AI 密钥、证书私钥均保存在本机或服务器私有环境文件中。不要把本地 `docker/.env` 上传覆盖生产环境，也不要把真实环境文件提交到 Git。环境文件修改后需重新编排，单纯重启容器不会替换容器的环境变量。

生产关键配置示例（真实密码在服务器填写）：

```dotenv
IMAGE_PREFIX=shuomi-erp
IMAGE_TAG=2026.11.23-1
WEB_BIND_IP=127.0.0.1
WEB_PORT=18102
DB_URL='jdbc:mysql://mysql.example.com:3306/shuomi-erp?useUnicode=true&characterEncoding=utf8&zeroDateTimeBehavior=convertToNull&useSSL=true&serverTimezone=GMT%2B8&nullCatalogMeansCurrent=true'
DB_USERNAME=填写生产数据库账号
DB_PASSWORD='填写生产数据库密码'
REDIS_PASSWORD='填写强密码'
JWT_SECRET='填写至少32字节的随机密钥'
FLOWABLE_DATABASE_SCHEMA_UPDATE=false
```

数据库名为 **`shuomi-erp`**。生产验收所用的云数据库入口未宣告 SSL 能力，连接参数保持用户提供的 `useSSL=true`；这是 Connector/J 的尽力连接设置，不能据此宣称数据库链路已加密。云端开启 SSL 并完成连接验证后，才增加 `requireSSL=true` 等强制参数。

1Panel 通过编排 API 编辑时会重写与 `compose.yaml` 相邻的 `.env`，调用该 API 必须提供完整环境变量正文；该文件是生产唯一权威来源。兼容的 `.env.prod` 符号链接可以保留，日常操作只使用 `.env`。保留原有 JWT、Redis、AI 加密密钥，避免版本更新后会话及保存的 AI API Key 失效。包含 `$`、`#` 等字符的值可使用 dotenv 单引号字面值；最终以 `docker compose ... config --quiet` 验证解析。

## 本地更新和验证

在 Windows PowerShell 中进入项目根目录：

```powershell
Copy-Item docker\.env.local.example docker\.env   # 仅首次；已有 .env 时不要覆盖
notepad docker\.env
.\update-local-containers.cmd
```

Docker Desktop 必须使用 Linux 容器，并选择本地 Desktop context。脚本会显式指定 `--env-file` 和 `lemon-erp` 项目名，构建 `backend/web` 后执行 `up --wait`，自动启动依赖并保留 MySQL、Redis、上传文件数据卷。完成后使用脚本输出的地址访问系统，验证登录、菜单和至少一个业务页面。

可选参数：

```powershell
.\update-local-containers.cmd -CheckOnly
.\update-local-containers.cmd -WaitTimeout 600
.\update-local-containers.cmd -ProxyUrl http://127.0.0.1:10809
# 已导入某版本的全部镜像时，跳过构建并禁止自动拉取：
.\update-local-containers.cmd -SkipBuild -ReleaseTag 2026.11.23-1
```

代理仅作用于本次 Docker 客户端进程，不修改系统代理或 Docker Desktop 设置。Dockerfile 基础镜像的拉取由 Docker Desktop 引擎完成；如果仍无法访问镜像仓库，在 Docker Desktop 配置相应代理或镜像源。

## 导出初次包和更新包

先用本地更新脚本构建、启动并验证保存的代码，再导出实际健康容器所使用的镜像；不要导出尚未启动验证的镜像。

```powershell
# 初次部署；每个版本使用独立发布标签
.\export-init-images.cmd -ReleaseTag 2026.11.23-1
# 后续版本更新；只含业务镜像，上传更快
.\export-update-images.cmd -ReleaseTag 2026.11.24-1
# 仅校验，不打标签、不创建归档
.\export-update-images.cmd -ReleaseTag 2026.11.24-1 -CheckOnly
# 独立本地验证栈（backend/web 两服务均通过健康检查）也可作为来源：
.\export-update-images.cmd -ReleaseTag 2026.11.24-1 -SourceProject shuomi-erp-verify
# 可选自定义导出目录和构建客户端代理
.\export-update-images.cmd -ReleaseTag 2026.11.24-1 -OutputDirectory D:\releases\shuomi-erp-2026.11.24-1 -ProxyUrl http://127.0.0.1:10809
```

镜像名称为 `shuomi-erp-backend:<版本>` 和 `shuomi-erp-web:<版本>`。默认输出到 `dist/init-<版本>` 或 `dist/update-<版本>`。归档目录包含：

- `images.tar.gz`：可直接用 Docker/1Panel 导入的镜像归档。
- `images.json`：版本、镜像ID、平台和归档 SHA256；仅导出 Linux amd64 镜像。
- `SHA256SUMS`：上传后使用 `sha256sum -c SHA256SUMS` 校验文件。
- `LICENSE`：沿用上游 Apache-2.0 许可证全文。
- `docker/`：本地和生产 Compose、无真实凭据的环境示例、`release.env` 发布标签记录。
- `docs/production-deployment.md`：本操作说明。
- `scripts/update-production-containers.sh`：上传后可直接运行的服务器更新脚本。
- 初次包额外含 `mysql:8.0`、`redis:7-alpine`、本地 `sql/init.sql` 和生产空库专用 `sql/production-bootstrap.sql`。

首次包中的 MySQL 镜像和 `sql/init.sql` 仅用于**全新本地测试数据库**；额外的 `sql/production-bootstrap.sql` 是人工确认空库后的生产首次初始化专用文件。生产仅执行生产 Compose，因此导入初次包不会启动 MySQL。更新包不含 Redis/MySQL，需要服务器保留初次部署的 Redis 镜像。导出不会复制真实 `.env`；同名标签指向不同镜像或同名输出目录已存在时会停止，以保留版本可追溯性；已存在且ID相同的目标镜像可直接复用。

## 使用 GitHub Release 的 GHCR 配置包

[硕米 GitHub Releases](https://github.com/hhhh-wang/shuomi-erp/releases) 提供 `shuomi-erp-docker-<版本>.zip` 和 `SHA256SUMS.txt`。下载后对照校验和核验 ZIP；该包包含本地/生产 Compose、环境模板、SQL 和许可证，镜像通过 GHCR 拉取。源码导出脚本生成的离线包另含镜像归档与服务器更新脚本。

解压后在包内 `docker` 目录复制 `.env.prod.example` 为私有 `.env.prod`，填写生产配置，完成独立数据库初始化，再执行：

```bash
docker compose --env-file .env.prod -f docker-compose.prod.yml config --quiet
docker compose --env-file .env.prod -f docker-compose.prod.yml pull --policy always
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --no-build --pull never --wait --wait-timeout 300
```

生产 Compose 的 `pull_policy: never` 用于避免启动时意外更换镜像，因此在线安装必须显式 `pull --policy always`。GHCR 包的环境模板已固定 `IMAGE_PREFIX=ghcr.io/hhhh-wang/shuomi-erp` 和版本标签。

更新现有 1Panel 编排时，沿用应用目录的 `.env` 与持久化卷，备份配置，审阅 Compose 变化，再更新 `IMAGE_PREFIX` 和 `IMAGE_TAG`。在该应用目录执行 `docker compose -p shuomi-erp --env-file .env -f compose.yaml pull --policy always backend web`，之后执行 `docker compose -p shuomi-erp --env-file .env -f compose.yaml up -d --no-deps --no-build --pull never --wait --wait-timeout 300 backend web`。保留上一版本镜像和配置，以便按本文回滚步骤恢复。

## 使用 PowerShell 上传至服务器

下例使用文档专用地址 `203.0.113.10:22` 和 root SSH；请将服务器地址、域名、数据库入口及密钥路径替换为实际值。首次连接先核对服务器 SSH 主机指纹，不关闭主机验证。

```powershell
$Key = 'D:\keys\server.pem'
$Ssh = Join-Path $env:LOCALAPPDATA 'Atlassian\SourceTree\git_local\usr\bin\ssh.exe'
$Scp = Join-Path $env:LOCALAPPDATA 'Atlassian\SourceTree\git_local\usr\bin\scp.exe'
$Tag = '2026.11.24-1'
$Release = Join-Path $PWD ('dist\update-' + $Tag)
& $Ssh -i $Key -p 22 root@203.0.113.10
# 在远程会话创建 /model/shuomi-erp/releases 后退出
& $Scp -i $Key -P 22 -r $Release root@203.0.113.10:/model/shuomi-erp/releases/
& $Ssh -i $Key -p 22 root@203.0.113.10
```

当前服务器的系统 OpenSSH 客户端在自动化调用中出现静默失败，以上使用 Git 附带的 SSH/SCP。自动化使用 `Start-Process` 时加 `-WindowStyle Hidden -Wait -PassThru`，检查退出码并保存输出日志。

下文以 `/model/1Panel/1panel/docker/compose/shuomi-erp` 为应用目录。该目录属于实际 1Panel 编排目录（服务器 base 为 `/model/1Panel/1panel`），始终操作同一个 `shuomi-erp` 编排项目。发布目录存放镜像及配置快照；应用目录下的私有 `.env` 持续沿用。

## 第一次生产部署

1. 确认 `erp.example.com` 的 DNS A 记录指向 `203.0.113.10`，80/443 可访问，1Panel 的 OpenResty 已运行。
2. 在服务器准备应用目录和发布目录，上传初次包，验证 `SHA256SUMS` 并导入镜像。
3. 从生产示例创建私有 `.env`，填写生产数据库、缓存、JWT 等实际参数，使用 `chmod 600` 限制权限。
4. 检查生产数据库结构已经准备完成；确认 ERP 和 Flowable 表都可用后启动应用。
5. 用生产 Compose 编排；在 1Panel 创建反向代理网站和证书。

```bash
mkdir -p /model/shuomi-erp/releases /model/1Panel/1panel/docker/compose/shuomi-erp
cd /model/shuomi-erp/releases/init-2026.11.23-1
sha256sum -c SHA256SUMS
docker load --input images.tar.gz
cp docker/docker-compose.prod.yml /model/1Panel/1panel/docker/compose/shuomi-erp/compose.yaml
cp docker/.env.prod.example /model/1Panel/1panel/docker/compose/shuomi-erp/.env
chmod 600 /model/1Panel/1panel/docker/compose/shuomi-erp/.env
# 使用服务器编辑器填写 .env 真实值
cd /model/1Panel/1panel/docker/compose/shuomi-erp
docker compose -p shuomi-erp --env-file .env -f compose.yaml config --quiet
docker compose -p shuomi-erp --env-file .env -f compose.yaml up -d --no-build --pull never --wait --wait-timeout 300
```

**生产数据库初始化必须单独执行。** 首次使用 `sql/production-bootstrap.sql`，仅在应用尚未公开访问且已确认 `SELECT DATABASE()` 为目标库 `shuomi-erp`、库内表数量为 0 后人工执行；出现任何错误立即停止，不使用 `mysql --force`。该文件不含 DROP/自动选库，创建 ERP 结构和干净的系统基础数据，admin/test 默认锁定且没有可用默认密码。公开访问前必须为 admin 写入单独生成的 BCrypt 密码、启用账号并要求首次改密，test 保持禁用。原始 `sql/init.sql` 含大量 `DROP TABLE` 和演示数据，仅供全新本地测试使用。已有生产库只执行对应版本审核迁移。

Flowable 表不在 bootstrap SQL 中，首次需在维护阶段受控地只启动后端，临时 `FLOWABLE_DATABASE_SCHEMA_UPDATE=true` 创建所需结构，核实 ACT_/FLW_ 表完整后恢复 `false` 并重新编排，再开放入口。日常更新始终保持 `false`。这些初始化动作不会随镜像导入或更新脚本自动执行。

生产持久化卷为 `shuomi-erp-redis-data` 和 `shuomi-erp-files`。数据库由独立 MySQL 服务备份和维护；编排更新只更新 ERP 应用容器。

## 1Panel 网站与 HTTPS

在 1Panel 的“网站”中新增反向代理网站：主域名 `erp.example.com`，代理目标为 `http://127.0.0.1:18102`。本服务器 OpenResty 使用 host 网络，因此该地址可以访问宿主机的 ERP 入口；生产真实 `.env` 使用 `WEB_PORT=18102` 覆盖模板默认端口。后端和 Redis 没有发布到公网的端口。

在“网站 → 证书”申请 `erp.example.com` 证书，使用 1Panel 已配置的 ACME 账户。HTTP 验证需要域名正确指向服务器且挑战路径可从公网 80 端口访问；DNS 验证使用已有 DNS 账户。绑定到网站，开启 HTTPS 和 HTTP 跳转 HTTPS，保留自动续签。证书、续签配置和反向代理由 1Panel 管理，应用镜像更新不需要重新申请证书。

验证真实公网入口：

```bash
curl --fail --silent --show-error https://erp.example.com/healthz
curl --fail --silent --show-error https://erp.example.com/api/auth/config
openssl s_client -connect erp.example.com:443 -servername erp.example.com </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates
```

不要用 `curl -k` 作为证书验证成功的依据。

## 生产版本更新：服务器一条命令

上传完整更新包后，推荐在服务器执行包内脚本：

```bash
bash /model/shuomi-erp/releases/update-2026.11.24-1/scripts/update-production-containers.sh /model/shuomi-erp/releases/update-2026.11.24-1
# 可选第二参数：已有应用目录的绝对路径
```

脚本需要 Bash、Python 3、Docker Compose 和常见 Linux 命令（包括 flock）；仅接受 `export-update-images.cmd` 生成的更新包，首次生产部署仍按独立流程进行。脚本验证所有 SHA256、发布标签、两份业务镜像清单及导入后的镜像 ID/平台；在同一应用目录加锁，备份 `.env` 和 `compose.yaml`，沿用密码和长期密钥，只改变 `IMAGE_TAG`，然后使用 `--no-deps` 仅重建 `backend/web` 并等待健康检查。脚本固定使用服务器本机 Docker socket，避免受远程 Docker context 影响。

更新失败时恢复配置和旧版本并重新等待健康，打印备份路径和回滚结果；不执行 SQL、不删除数据卷。脚本执行前会确认旧版镜像仍在本机，并拒绝覆盖已指向不同镜像ID的发布标签；旧镜像需保留以供回滚。它还会比较持久化卷、网络、应用挂载和 Redis 配置，发现变更时停止，要求单独审核基础设施变更。成功后仍须验证公网 HTTPS 登录和业务页面。

## 手动更新：导入、环境变量、重新编排

更新前记录当前版本和镜像ID、备份 `.env`/Compose，确认数据库及上传文件已有可恢复的备份。若新版需要数据库迁移，先审核迁移和回滚策略；镜像回滚不能撤销数据库结构变更。

在服务器上传后的更新包目录执行：

```bash
cd /model/shuomi-erp/releases/update-2026.11.24-1
sha256sum -c SHA256SUMS
docker load --input images.tar.gz
# 对照 images.json 确认两个镜像ID及 linux/amd64 平台
docker image inspect shuomi-erp-backend:2026.11.24-1 shuomi-erp-web:2026.11.24-1 --format '{{.RepoTags}} {{.Id}} {{.Os}}/{{.Architecture}}'
cd /model/1Panel/1panel/docker/compose/shuomi-erp
release_backup="backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$release_backup"
cp .env compose.yaml "$release_backup/"
chmod 700 "$release_backup"
chmod 600 "$release_backup/.env"
# 审阅发布包Compose的变化，确认后复制
cp /model/shuomi-erp/releases/update-2026.11.24-1/docker/docker-compose.prod.yml compose.yaml
# 在 .env 中只更新 IMAGE_TAG=2026.11.24-1，并补齐新版新增变量
# 沿用真实数据库及缓存、JWT、AI密钥；不要复制示例覆盖已有.env
docker compose -p shuomi-erp --env-file .env -f compose.yaml config --quiet
docker compose -p shuomi-erp --env-file .env -f compose.yaml up -d --no-build --pull never --wait --wait-timeout 300 backend web
docker compose -p shuomi-erp --env-file .env -f compose.yaml ps
```

也可用 1Panel：在“容器 → 镜像”导入 `images.tar.gz`；进入原有 `shuomi-erp` 编排，审阅并更新 Compose 和生产环境变量中的 `IMAGE_TAG` 后重新编排，关闭“强制拉取镜像”。使用现有编排和固定卷，不新建不同项目名的编排。后台日志应能成功连接独立 MySQL 和 Redis，后端、入口容器都应健康。

验证以下项目后才认为更新完成：

- `docker compose ... ps` 中后端和入口为 healthy，无反复重启。
- `https://erp.example.com/healthz` 返回成功；`/api/auth/config` 正常，HTTPS 证书受信任且域名匹配。
- 浏览器登录、菜单、主要业务页及文件预览正常，业务数据仍在。
- `docker inspect shuomi-erp-backend --format '{{.Config.Image}}'` 和入口镜像均为新版本。

必要时查看有限日志（可能含业务信息，分享前先脱敏）：

```bash
docker compose -p shuomi-erp --env-file .env -f compose.yaml logs --tail 100 backend web
```

## 回滚

保留旧版镜像和配置快照。若新版启动或业务验证失败且没有不兼容数据库迁移，恢复刚才备份的 Compose 和私有环境文件，重新编排应用服务：

```bash
cd /model/1Panel/1panel/docker/compose/shuomi-erp
# 将路径替换为本次更新前生成的实际备份目录
cp backups/20261124-100000/compose.yaml compose.yaml
cp backups/20261124-100000/.env .env
chmod 600 .env
docker compose -p shuomi-erp --env-file .env -f compose.yaml config --quiet
docker compose -p shuomi-erp --env-file .env -f compose.yaml up -d --no-build --pull never --wait --wait-timeout 300 backend web
```

按更新后的同一组检查验证回滚。存在数据库结构变更时遵循该迁移的专门恢复方案。不要使用 `docker compose down -v`、删除持久化卷或全局镜像清理命令；旧版镜像至少保留到新版业务验证和备份恢复验证完成。
