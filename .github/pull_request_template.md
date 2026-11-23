## 变更内容

<!-- 说明改了什么、为什么改，以及涉及的业务模块。 -->

## 验证

- [ ] `.\gradlew.bat --no-daemon build`
- [ ] `python scripts/check_i18n.py`
- [ ] `cd lemon-web && npm run i18n:check && npm run build`
- [ ] 涉及小程序时已执行 `npm run build:mp-weixin`
- [ ] 涉及部署时已执行对应的 Docker 构建

## 检查项

- [ ] 未提交 `.env`、密钥、构建产物或本地数据
- [ ] 品牌与技术标识变更符合 `docs/upstream-sync.md`
- [ ] 上游同步 PR 使用 merge commit，未使用 Squash / Rebase
- [ ] 如包含可回馈上游的通用修复，已与硕米品牌改动分开提交
