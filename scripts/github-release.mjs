// SHUOMI-ERP PRIVATE CUSTOMIZATION: immutable draft/release coordination.
import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { appendFileSync, mkdtempSync, writeFileSync, unlinkSync, rmdirSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

class CoordinatorError extends Error {}
const fail = (message) => { throw new CoordinatorError(message) }
const hash = (bytes) => createHash('sha256').update(bytes).digest('hex')
const isDigest = (value) => typeof value === 'string' && /^sha256:[a-f0-9]{64}$/.test(value)
const isSha = (value) => typeof value === 'string' && /^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(value)
const readyName = 'release-ready.json'
const platforms = ['linux/amd64', 'linux/arm64']
const requestTimeout = 30_000
const responseLimit = 2 * 1024 * 1024
let repo, tag, sourceSha, version, expected, imageNames

// Do not relay subprocess stderr or network error objects: they may contain credentials.
function command(file, args, encoding = 'utf8') {
  try {
    return execFileSync(file, args, {
      encoding, timeout: file === 'git' ? 10_000 : 60_000,
      maxBuffer: responseLimit, stdio: ['ignore', 'pipe', 'pipe'],
      env: { ...process.env, GH_DEBUG: '', GH_PROMPT_DISABLED: '1' }
    })
  } catch (error) {
    const status = /HTTP ([0-9]{3})/.exec(error.stderr?.toString() || '')?.[1]
    const detail = status ? ' (HTTP ' + status + ')' : ''
    fail(file === 'git' ? 'git rev-parse HEAD failed or timed out.' : 'GitHub CLI request failed or timed out' + detail + '; verify repository access and authentication.')
  }
}

function parseJson(bytes, label) {
  try { return JSON.parse(bytes.toString('utf8')) } catch { fail(label + ' is not valid JSON.') }
}

function ghJson(endpoint, paginate = false) {
  const args = ['api', '-H', 'Accept: application/vnd.github+json']
  if (paginate) args.push('--paginate', '--slurp')
  args.push(endpoint)
  const value = parseJson(command('gh', args), 'GitHub API response')
  if (!paginate) return value
  if (!Array.isArray(value) || value.some((page) => !Array.isArray(page))) fail('GitHub API pagination returned an unexpected response.')
  return value.flat()
}

function download(asset) {
  const bytes = command('gh', ['api', '-H', 'Accept: application/octet-stream', 'repos/' + repo + '/releases/assets/' + asset.id], null)
  if (bytes.length !== asset.size || 'sha256:' + hash(bytes) !== asset.digest) fail('Downloaded ' + asset.name + ' does not match its API size/digest.')
  return bytes
}

function keys(value, names, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).sort().join(',') !== [...names].sort().join(',')) {
    fail(label + ' has missing or unknown fields.')
  }
}

function assertTagSource() {
  const ref = ghJson('repos/' + repo + '/git/ref/tags/' + encodeURIComponent(tag))
  if (ref.ref !== 'refs/tags/' + tag) fail('GitHub returned a different tag reference; refusing to build or verify it.')
  let object = ref.object
  for (let depth = 0; depth <= 10; depth++) {
    if (!object || !isSha(object.sha)) fail('GitHub tag reference has an invalid object SHA.')
    if (object.type === 'commit') {
      if (object.sha !== sourceSha) fail('TAG no longer resolves to the checkout source SHA; refusing to build, record, or verify it.')
      return
    }
    if (object.type !== 'tag') fail('GitHub tag does not resolve to a commit.')
    if (depth === 10) fail('Annotated tag resolution exceeded ten dereferences.')
    object = ghJson('repos/' + repo + '/git/tags/' + object.sha).object
  }
}

function getRelease() {
  // The tags endpoint can return 404 for a draft; list releases under authentication.
  const matches = ghJson('repos/' + repo + '/releases?per_page=100', true).filter((release) => release.tag_name === tag)
  if (matches.length !== 1 || !Number.isSafeInteger(matches[0].id) || typeof matches[0].draft !== 'boolean') fail('Exactly one accessible Release for TAG is required.')
  const release = matches[0]
  release.assets = ghJson('repos/' + repo + '/releases/' + release.id + '/assets?per_page=100', true)
  return release
}

function assetsOf(release, includeReady) {
  const names = includeReady ? [...expected, readyName] : expected
  if (release.assets.length !== names.length) fail('Release has missing or unexpected assets; use a new revision for partial releases.')
  return names.map((name) => {
    const matches = release.assets.filter((asset) => asset.name === name)
    if (matches.length !== 1) fail('Release asset is missing or duplicated: ' + name)
    const asset = matches[0]
    if (!Number.isSafeInteger(asset.id) || !Number.isSafeInteger(asset.size) || asset.size <= 0 || !isDigest(asset.digest) || asset.state !== 'uploaded') {
      fail('Release asset lacks an uploaded state, valid size, or API SHA256 digest: ' + name)
    }
    return asset
  })
}

function verifyChecksums(assets) {
  const checksumAsset = assets.find((asset) => asset.name === 'SHA256SUMS.txt')
  const text = download(checksumAsset).toString('utf8')
  const checksums = new Map()
  for (const line of text.split(/\r?\n/)) {
    if (!line) continue
    const match = /^([a-f0-9]{64}) [ *]([^\r\n]+)$/.exec(line)
    if (!match || checksums.has(match[2])) fail('SHA256SUMS.txt has an invalid or duplicate entry.')
    checksums.set(match[2], match[1])
  }
  const files = assets.filter((asset) => asset.name !== 'SHA256SUMS.txt' && asset.name !== readyName)
  if (checksums.size !== files.length) fail('SHA256SUMS.txt contains missing or unexpected files.')
  for (const asset of files) {
    if ('sha256:' + checksums.get(asset.name) !== asset.digest) fail('SHA256SUMS.txt disagrees with the API digest for ' + asset.name)
  }
}

async function request(url, headers, label) {
  try {
    const response = await fetch(url, { headers, signal: AbortSignal.timeout(requestTimeout), redirect: 'error' })
    const bytes = Buffer.from(await response.arrayBuffer())
    if (bytes.length > responseLimit) fail(label + ' response is too large.')
    return { status: response.status, headers: response.headers, bytes }
  } catch {
    fail(label + ' network request failed, timed out, redirected unexpectedly, or exceeded the response limit.')
  }
}

async function registryToken(image, authenticated) {
  const headers = {}
  if (authenticated) {
    const actor = process.env.GITHUB_ACTOR || repo.split('/')[0]
    if (!/^[A-Za-z0-9_.-]+$/.test(actor)) fail('GITHUB_ACTOR is invalid.')
    headers.Authorization = 'Basic ' + Buffer.from(actor + ':' + process.env.GH_TOKEN).toString('base64')
  }
  const response = await request('https://ghcr.io/token?service=ghcr.io&scope=' + encodeURIComponent('repository:' + image + ':pull'), headers, 'GHCR token')
  if (response.status !== 200) return { status: response.status }
  const body = parseJson(response.bytes, 'GHCR token response')
  const token = body.token || body.access_token
  return typeof token === 'string' && token.length > 0 ? { status: 200, token } : { status: 200 }
}

async function registryImage(image, allowMissing = false) {
  const accept = 'application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json'
  let response
  // A denied anonymous pull is never treated as a nonexistent image.
  for (const authenticated of [false, true]) {
    const auth = await registryToken(image, authenticated)
    if (!auth.token) {
      if (!authenticated) continue
      fail('Authenticated GHCR token request failed (HTTP ' + auth.status + '); absence cannot be established.')
    }
    response = await request('https://ghcr.io/v2/' + image + '/manifests/' + version, { Accept: accept, Authorization: 'Bearer ' + auth.token }, 'GHCR manifest')
    if (!authenticated && [401, 403, 404].includes(response.status)) continue
    break
  }
  if (response.status === 404) {
    if (allowMissing) return null
    fail('Required version image is missing: ghcr.io/' + image + ':' + version)
  }
  if (response.status !== 200) fail('GHCR manifest request failed (HTTP ' + response.status + '); it is not evidence of absence.')
  const digest = response.headers.get('docker-content-digest')
  if (!isDigest(digest) || digest !== 'sha256:' + hash(response.bytes)) fail('GHCR image index digest is missing or does not match its response bytes.')
  const index = parseJson(response.bytes, 'GHCR image index')
  if (index.schemaVersion !== 2 || !['application/vnd.oci.image.index.v1+json', 'application/vnd.docker.distribution.manifest.list.v2+json'].includes(index.mediaType) || !Array.isArray(index.manifests)) {
    fail('GHCR version must resolve to a multi-platform image index.')
  }
  if (index.manifests.some((manifest) => !isDigest(manifest.digest))) fail('GHCR image index contains an invalid manifest digest.')
  for (const platform of platforms) {
    const matches = index.manifests.filter((manifest) => manifest.platform?.os + '/' + manifest.platform?.architecture === platform)
    if (matches.length !== 1) fail('GHCR image index must contain exactly one manifest for ' + platform)
  }
  return { name: 'ghcr.io/' + image + ':' + version, digest, platforms: [...platforms] }
}

function validateMarker(marker) {
  keys(marker, ['schema', 'tag', 'sourceSha', 'repo', 'runId', 'assets', 'images'], 'Release marker')
  if (marker.schema !== 1 || marker.tag !== tag || marker.repo !== repo || marker.sourceSha !== sourceSha || !isSha(marker.sourceSha) || typeof marker.runId !== 'string' || !/^[0-9]+$/.test(marker.runId)) {
    fail('Release marker schema, source SHA, tag, repository, or run ID is invalid.')
  }
  if (!Array.isArray(marker.assets) || marker.assets.length !== expected.length) fail('Release marker asset list is invalid.')
  marker.assets.forEach((asset, index) => {
    keys(asset, ['name', 'sha256', 'size'], 'Marker asset')
    if (asset.name !== expected[index] || !/^[a-f0-9]{64}$/.test(asset.sha256) || typeof asset.sha256 !== 'string' || !Number.isSafeInteger(asset.size) || asset.size <= 0) fail('Release marker asset is invalid.')
  })
  if (!Array.isArray(marker.images) || marker.images.length !== imageNames.length) fail('Release marker image list is invalid.')
  marker.images.forEach((image, index) => {
    keys(image, ['name', 'digest', 'platforms'], 'Marker image')
    if (image.name !== 'ghcr.io/' + imageNames[index] + ':' + version || !isDigest(image.digest) || !Array.isArray(image.platforms) || image.platforms.join(',') !== platforms.join(',')) fail('Release marker image is invalid.')
  })
}

async function verify(release) {
  const assets = assetsOf(release, true)
  const marker = parseJson(download(assets.find((asset) => asset.name === readyName)), 'Release marker')
  validateMarker(marker)
  verifyChecksums(assets)
  for (let index = 0; index < expected.length; index++) {
    if (assets[index].size !== marker.assets[index].size || assets[index].digest !== 'sha256:' + marker.assets[index].sha256) fail('Release asset changed after recording: ' + expected[index])
  }
  for (let index = 0; index < imageNames.length; index++) {
    const actual = await registryImage(imageNames[index])
    if (actual.digest !== marker.images[index].digest) fail('GHCR version image changed after recording: ' + actual.name)
  }
}

function outputBuild(build) {
  if (!process.env.GITHUB_OUTPUT) fail('GITHUB_OUTPUT is required by prepare.')
  appendFileSync(process.env.GITHUB_OUTPUT, 'build=' + build + '\nsource-sha=' + sourceSha + '\n')
  console.log('Release preparation complete: build=' + build)
}

async function prepare(release) {
  if (release.assets.some((asset) => asset.name === readyName)) {
    await verify(release)
    outputBuild(false)
    return
  }
  if (process.env.GITHUB_EVENT_NAME !== 'workflow_dispatch') fail('Published/event Release has no valid completion marker; refusing to build or overwrite it.')
  if (!release.draft) fail('A new build requires a draft Release.')
  if (release.assets.length !== 0) fail('Draft has partial assets but no completion marker; use a new revision.')
  for (const image of imageNames) {
    if (await registryImage(image, true)) fail('Version image already exists without a completion marker; use a new revision.')
  }
  outputBuild(true)
}

async function record(release) {
  if (!release.draft) fail('Completion can only be recorded on a draft Release.')
  const runId = process.env.GITHUB_RUN_ID
  if (!runId || !/^[0-9]+$/.test(runId)) fail('GITHUB_RUN_ID is required by record.')
  const assets = assetsOf(release, false)
  verifyChecksums(assets)
  const images = []
  for (const image of imageNames) images.push(await registryImage(image))
  const marker = {
    schema: 1, tag, sourceSha, repo, runId,
    assets: assets.map((asset) => ({ name: asset.name, sha256: asset.digest.slice(7), size: asset.size })), images
  }
  validateMarker(marker)
  const directory = mkdtempSync(join(tmpdir(), 'shuomi-release-'))
  const filename = join(directory, readyName)
  try {
    writeFileSync(filename, JSON.stringify(marker, null, 2) + '\n', { mode: 0o600 })
    command('gh', ['release', 'upload', tag, filename, '--repo', repo])
  } finally {
    // Only remove this explicitly created file and empty temporary directory.
    try { unlinkSync(filename) } catch {}
    try { rmdirSync(directory) } catch {}
  }
  console.log('Draft completion marker uploaded without overwriting existing assets.')
}

async function main() {
  const mode = process.argv[2]
  if (!['prepare', 'record', 'verify'].includes(mode) || process.argv.length !== 3) fail('Usage: node scripts/github-release.mjs prepare|record|verify')
  tag = process.env.TAG
  repo = process.env.GITHUB_REPOSITORY
  if (!/^shuomi-v[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$/.test(tag || '')) fail('TAG must be shuomi-vX.Y.Z-N.')
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo || '')) fail('GITHUB_REPOSITORY must be owner/repository.')
  if (!process.env.GH_TOKEN) fail('GH_TOKEN is required.')
  sourceSha = command('git', ['rev-parse', 'HEAD']).trim()
  if (!isSha(sourceSha)) fail('Checkout source SHA is invalid.')
  assertTagSource()
  version = tag.slice('shuomi-v'.length)
  expected = ['init.sql', 'LICENSE', 'shuomi-erp-backend-' + version + '.jar', 'shuomi-erp-docker-' + version + '.zip', 'shuomi-erp-web-' + version + '.zip', 'upgrade-sql-' + version + '.zip', 'SHA256SUMS.txt']
  imageNames = ['backend', 'web'].map((name) => repo.split('/')[0].toLowerCase() + '/shuomi-erp-' + name)
  const release = getRelease()
  if (mode === 'prepare') await prepare(release)
  else if (mode === 'record') await record(release)
  else { await verify(release); console.log('Release completion marker, assets, checksums, and image indexes verified.') }
}

main().catch((error) => {
  let message = error instanceof CoordinatorError ? error.message : 'Unexpected local or metadata failure; no credentials or raw error output will be displayed.'
  if (process.env.GH_TOKEN) message = message.replaceAll(process.env.GH_TOKEN, '[REDACTED]')
  console.error('Release coordinator: ' + message)
  process.exitCode = 1
})
