# 硕米ERP 品牌默认值

<!-- SHUOMI-ERP PRIVATE CUSTOMIZATION: shared branding and override rules -->

Web 与小程序共用 `lemon-web/src/branding.js`，品牌名称与演示租户名称在此维护：

| 字段 | 用途 |
| --- | --- |
| `id` | 产品标识 `shuomi-erp`，不会改写 Java、Gradle、数据库等技术标识 |
| `name` | 中文品牌名、Web 静态标题、小程序静态名称与导航标题 |
| `englishName` | 英文品牌名、小程序 H5 标题 |
| `demoTenant` | Web 登录页演示租户名称，与本地初始化数据保持一致 |

AI 欢迎语、打印默认公司名和小程序 `common.appName` 保留原 i18n 键，由语言包引用品牌默认值。Web 标题由 Vite `transformIndexHtml` 写入；小程序启动构建时，`lemon-web/scripts/branding.mjs` 只同步 `manifest.json` 的名称/描述/H5 标题，以及 `pages.json` 的默认导航标题。AppID、版本、路由、权限和其他配置不改写。

系统参数返回的 `systemName`、用户/租户名称、打印模板及原有 `VITE_COMPANY_NAME` 的覆盖优先级继续沿用。品牌文件只提供构建与默认显示值，不会修改已有生产数据库中的用户设置或业务名称。Logo 继续使用上游原版资源。

修改品牌默认值后，分别验证：

```powershell
cd lemon-web
npm run i18n:check
npm run build
cd ..
cd lemon-mp
npm run i18n:check
npm run build:mp-weixin
cd ..
```

小程序构建可能同步两个静态 JSON 字段；检查这些生成差异再提交。发布前继续通过 `main` 的必需 CI。上线仍使用镜像导出与更新流程，单纯修改本机品牌文件不会更新线上容器。
