# 上游同步与二开分支规范

<!-- SHUOMI-ERP PRIVATE CUSTOMIZATION: fork development and release policy -->

本文说明硕米ERP 的 Git 分支、发布和 Lemon ERP 官方代码同步流程。目标是在持续获得上游修复与新功能的同时，保留硕米自己的品牌、配置和业务改动。

## 仓库关系

| 名称 | 地址 | 用途 |
| --- | --- | --- |
| `origin` | `git@github.com:hhhh-wang/lemon-erp.git` | 硕米ERP 的 GitHub fork，只向这里推送 |
| `upstream` | `git@github.com:MakeSomeFakeNews/lemon-erp.git` | Lemon ERP 官方仓库，只从这里拉取 |
| `main` | `origin/main` | 硕米ERP 产品主线，始终保持可构建、可部署 |
| `feature/*` | 从 `main` 拉出 | 自己的二开功能，通过 Pull Request 合并 |
| `sync/upstream-YYYYMMDD` | 从 `main` 拉出 | 同步官方代码和处理冲突，通过 Pull Request 合并 |
| `release/*` | 按需创建 | 维护旧版本或准备发布 |

截至 2026-11-23，GitHub 仓库名仍为 `lemon-erp`，它是 `MakeSomeFakeNews/lemon-erp` 的公开 fork。保留 fork 关系，目标更名为 `shuomi-erp`；“私有二开”只标记内部定制范围，不表示访问权限已变为 private。

GitHub 完成更名后，再更新本地远程并检查 README 的 CI 地址：

```powershell
git remote set-url origin git@github.com:hhhh-wang/shuomi-erp.git
git remote -v
```

`upstream` 始终保留官方地址。更名不改变 fork 关系；当前 GitHub CLI 未登录，需要在普通 PowerShell 中先运行 `& 'D:\work\GitHub CLI\gh.exe' auth login` 或在 GitHub 网页设置中操作。

`main` 已经和官方分叉，因此不要用 GitHub 的 “Sync fork” 按钮直接更新 `main`。统一使用同步分支和 Pull Request，保留 CI、审查和冲突处理记录。

## 一次性本地设置

```powershell
git remote -v
git config core.autocrlf false
git config core.eol lf
git config pull.ff only
git config rerere.enabled true
git config rerere.autoupdate true
git config fetch.prune true
```

`rerere` 会记住相同冲突的解决方式，后续同步遇到相同位置时自动复用。

## 日常二开

每个功能从最新的 `main` 拉出独立分支：

```powershell
git switch main
git pull --ff-only origin main
git switch -c feature/my-change

# 开发、验证、提交
git push -u origin feature/my-change
gh pr create --base main --head feature/my-change
```

普通功能 PR 可以使用 Squash merge。品牌文案、基础设施、上游可复用修复尽量拆成独立提交，方便以后单独回馈上游或在同步时识别冲突来源。

## 同步官方代码

每次同步都创建一个带日期的同步分支：

```powershell
git switch main
git pull --ff-only origin main
git fetch upstream --prune --tags

$date = Get-Date -Format "yyyyMMdd"
git switch -c "sync/upstream-$date"
git merge --no-ff upstream/main
```

如果有冲突，按以下原则处理：

1. 用户可见的品牌名称、硕米初始化数据和登录文案，保留硕米版本。
2. Logo 使用上游原版资源；没有品牌要求时不要修改 Logo 文件。
3. Java `com.lemon.*`、Gradle `lemon-*` 模块、`lemon-erp.jar`、`LEMON_*` 环境变量和本地 `lemon_erp` 数据库/`lemon-erp` 项目名继续沿用。生产项目、容器、镜像前缀和外部数据库使用 `shuomi-erp`，不因此批量重命名内部技术标识。
4. `sql/init.sql` 先接受上游结构变化，再重新核对硕米种子数据，不要直接覆盖线上数据库。
5. 多语言文件先合并上游新增键，再保留硕米品牌文案。
6. 构建产物、临时截图、`.env`、密钥和本地数据库文件不得提交。

解决冲突后执行验证：

```powershell
.\gradlew.bat --no-daemon build
python scripts/check_i18n.py

cd lemon-web
npm ci
npm run i18n:check
npm run build
cd ..

cd lemon-mp
npm ci
npm run i18n:check
npm run build:mp-weixin
cd ..
```

推送并创建 PR：

```powershell
git push -u origin HEAD
gh pr create --base main --head "sync/upstream-$date"
```

同步 PR 必须使用 **Create a merge commit**，不要 Squash 或 Rebase。这样 `main` 会保留与 `upstream/main` 的共同祖先，下一次同步不会重复处理同一批提交。

## 冲突预防

- `.gitattributes` 统一文本文件为 LF，Windows 脚本保持 CRLF。
- 不批量格式化未修改的文件，不重命名技术模块。
- 品牌配置逐步集中到少量文件；不要继续把系统名散落到业务代码。
- 可回馈上游的通用修复单独提交，优先向上游提 PR。上游合并后，分叉会自然缩小。
- 每次官方同步都先 fetch 再创建同步分支，不在已分叉的 `main` 上直接合并或强推。

## 发布与标签

硕米版本统一使用 `shuomi-vX.Y.Z-N`，其中 `N` 为同一上游版本下的硕米修订号，避免与官方 `v*` 标签冲突：

```text
shuomi-v1.2.0-1
shuomi-v1.2.0-2
shuomi-v1.2.1-1
```

发布步骤：

```powershell
git switch main
git pull --ff-only origin main
git tag -a shuomi-v1.2.0-1 -m "硕米ERP 1.2.0 (1)"
git push origin shuomi-v1.2.0-1
gh release create shuomi-v1.2.0-1 --title "硕米ERP 1.2.0 (1)" --generate-notes
```

发布 Release 后触发 `.github/workflows/release.yml`。工作流校验硕米标签，去掉 `shuomi-v` 得到镜像版本 `1.2.0-1`，使用 `shuomi-erp-backend`、`shuomi-erp-web` 和同名部署包。官方 `v*` Release 不触发硕米发布任务。首次带前缀的标签尚未创建；版本号需要按实际发布决定，示例不代表已发布。

本地离线导出脚本的 `-ReleaseTag` 是 Docker 镜像标签，也可使用同一规范化版本，例如 `1.2.0-1`；已有 `release-20261123-203650` 镜像与归档继续可用。

## GitHub 设置

建议在 GitHub 仓库设置中完成以下配置：

- 默认分支保持 `main`。
- 保护 `main`：禁止删除、禁止强制推送、必须通过 Pull Request。
- 要求 PR 通过 CI：`CI / 后端`、`CI / 前端`、`CI / 微信小程序`。
- 要求合并前解决所有对话；管理员也遵守规则。
- 不要求线性历史。普通功能 PR 可以 Squash，官方同步 PR 必须保留 merge commit。
- 仓库描述和 README 保留 Lemon ERP / Apache-2.0 上游归属。

仓库更名为 `shuomi-erp` 时保持 GitHub fork 与 `upstream` 关系。无需长期 `develop` 分支。当前 `main` 保护尚未开启；CI 文件已启用，但 GitHub 暂无运行记录，必须在 PR/主线实际通过后再把对应检查设置为必需。
