// SHUOMI-ERP PRIVATE CUSTOMIZATION: sync static mini-program brand fields
import { readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { BRAND } from '../src/branding.js'

function updateJson(file, update) {
  const original = readFileSync(file, 'utf8')
  const data = JSON.parse(original)
  const before = JSON.stringify(data)
  update(data)
  if (JSON.stringify(data) !== before) {
    writeFileSync(file, JSON.stringify(data, null, 2) + '\n', 'utf8')
  }
}

export function syncMiniProgramBranding(sourceDirectory) {
  updateJson(join(sourceDirectory, 'manifest.json'), (manifest) => {
    manifest.name = BRAND.name
    manifest.description = `${BRAND.name} 移动端：审批、员工自助、销售外勤、扫码作业`
    manifest.h5 = { ...manifest.h5, title: BRAND.englishName }
  })
  updateJson(join(sourceDirectory, 'pages.json'), (pages) => {
    pages.globalStyle = { ...pages.globalStyle, navigationBarTitleText: BRAND.name }
  })
}
