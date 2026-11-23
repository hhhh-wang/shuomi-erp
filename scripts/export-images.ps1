# SHUOMI-ERP PRIVATE CUSTOMIZATION: production/local deployment
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('init', 'update')][string]$Package,
    [ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$')][string]$ReleaseTag = '',
    [ValidatePattern('^[a-z0-9][a-z0-9._/-]*(?::[0-9]+)?(?:/[a-z0-9][a-z0-9._/-]*)?$')][string]$ImagePrefix = 'shuomi-erp',
    [string]$OutputDirectory = '',
    [ValidatePattern('^[a-z0-9][a-z0-9_-]*$')][string]$SourceProject = 'lemon-erp',
    [string]$DockerExe = '',
    [AllowEmptyString()][string]$ProxyUrl = '',
    [switch]$CheckOnly
)
. (Join-Path $PSScriptRoot 'docker-common.ps1')
$TaskLf = [string][char]10
$TaskUtf8 = New-Object System.Text.UTF8Encoding($false)
if (-not $ReleaseTag) { $ReleaseTag = 'release-' + (Get-Date -Format yyyyMMdd-HHmmss) }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $TaskProjectRoot ('dist\' + $Package + '-' + $ReleaseTag) }
$TaskOutputRoot = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $TaskOutputRoot) { throw ('Output already exists; choose a new release tag/directory: ' + $TaskOutputRoot) }
$TaskDockerDirectory = Join-Path $TaskProjectRoot 'docker'
$TaskLocalEnv = Join-Path $TaskDockerDirectory '.env'
$TaskLocalCompose = Join-Path $TaskDockerDirectory 'docker-compose.yml'
if (-not (Test-Path -LiteralPath $TaskLocalEnv -PathType Leaf)) { throw 'Create docker/.env from docker/.env.local.example and test the local containers first.' }
foreach ($TaskRelative in @('LICENSE', 'docker/docker-compose.yml', 'docker/docker-compose.prod.yml', 'docker/.env.local.example', 'docker/.env.prod.example', 'docs/production-deployment.md', 'scripts/update-production-containers.sh')) {
    if (-not (Test-Path -LiteralPath (Join-Path $TaskProjectRoot $TaskRelative) -PathType Leaf)) { throw ('Required release file is missing: ' + $TaskRelative) }
}
if ($Package -eq 'init' -and -not (Test-Path -LiteralPath (Join-Path $TaskProjectRoot 'sql/init.sql') -PathType Leaf)) { throw 'sql/init.sql is missing.' }
Initialize-TaskDocker -DockerExe $DockerExe -ProxyUrl $ProxyUrl
$TaskComposeArgs = @('compose', '--project-name', 'lemon-erp', '--env-file', $TaskLocalEnv, '--file', $TaskLocalCompose)
[void](Invoke-TaskDocker ($TaskComposeArgs + @('config', '--quiet')))
$TaskImages = [ordered]@{}
$TaskSources = @{}
foreach ($TaskRole in @('backend', 'web')) {
    $TaskIds = @(Invoke-TaskDocker @('ps', '-q', '--filter', ('label=com.docker.compose.project=' + $SourceProject), '--filter', ('label=com.docker.compose.service=' + $TaskRole)))
    if ($TaskIds.Count -ne 1) { throw (('Expected exactly one running ' + $SourceProject + ' ') + $TaskRole + '. Run update-local-containers.cmd and test it first.') }
    $TaskContainers = ConvertFrom-Json ((Invoke-TaskDocker @('inspect', $TaskIds[0])) -join $TaskLf)
    $TaskContainer = @($TaskContainers)[0]
    if (-not $TaskContainer.State.Running) { throw ('Local service is not running: ' + $TaskRole) }
    $TaskHasHealth = $TaskContainer.State.PSObject.Properties.Name -contains 'Health'
    if (-not $TaskHasHealth -or $TaskContainer.State.Health.Status -ne 'healthy') { throw ('Local service must have a passing healthcheck: ' + $TaskRole + '. Update and test local containers first.') }
    # Resolve the tested running image, not a new image which happens to reuse its tag.
    $TaskSourceId = ((Invoke-TaskDocker @('image', 'inspect', '--format', '{{.Id}}', $TaskContainer.Config.Image)) -join '').Trim()
    $TaskImage = Get-TaskImage $TaskSourceId
    $TaskRunningManifest = ''
    if (($TaskContainer.PSObject.Properties.Name -contains 'ImageManifestDescriptor') -and $TaskContainer.ImageManifestDescriptor) { $TaskRunningManifest = [string]$TaskContainer.ImageManifestDescriptor.digest }
    if ($TaskRunningManifest) {
        if ($TaskImage.Id -ne $TaskRunningManifest -and $TaskContainer.Image -ne $TaskSourceId -and $TaskContainer.Image -ne $TaskImage.Id) { throw ('The image tag differs from the running ' + $TaskRole + '. Update and test again.') }
    } elseif ($TaskContainer.Image -ne $TaskSourceId -and $TaskContainer.Image -ne $TaskImage.Id) { throw ('The image tag differs from the running ' + $TaskRole + '. Update and test again.') }
    $TaskName = $ImagePrefix + '-' + $TaskRole + ':' + $ReleaseTag
    $TaskImages[$TaskRole] = [ordered]@{ Role = $TaskRole; Name = $TaskName; Id = $TaskImage.Id; Platform = 'linux/amd64' }
    $TaskSources[$TaskRole] = $TaskSourceId
    Write-Host ($TaskRole + ': verified healthy running image ' + $TaskImage.Id)
}
$TaskKnownImages = @(Invoke-TaskDocker @('image', 'ls', '--format', '{{.Repository}}:{{.Tag}}'))
foreach ($TaskAppImage in @($TaskImages.Values)) {
    if ($TaskKnownImages -contains $TaskAppImage.Name) {
        if ((Get-TaskImage $TaskAppImage.Name).Id -ne $TaskAppImage.Id) { throw ('Release tag points to a different image; choose a new tag: ' + $TaskAppImage.Name) }
        Write-Host ('Reusing identical release image: ' + $TaskAppImage.Name)
    }
}
$TaskDependencyReferences = [ordered]@{ redis = 'redis:7-alpine'; mysql = 'mysql:8.0' }
if ($CheckOnly) {
    if ($Package -eq 'init') { Write-Host ('Initial package also includes ' + ($TaskDependencyReferences.Values -join ', ') + ' and sql/init.sql (local empty database only).') }
    Write-Host ('Check passed. Release: ' + $ReleaseTag + '; output: ' + $TaskOutputRoot)
    return
}
if ($Package -eq 'init') {
    foreach ($TaskRole in $TaskDependencyReferences.Keys) {
        $TaskReference = $TaskDependencyReferences[$TaskRole]
        if ($TaskKnownImages -notcontains $TaskReference) { Invoke-TaskDocker @('pull', '--platform', 'linux/amd64', $TaskReference) }
        $TaskImage = Get-TaskImage $TaskReference
        $TaskImages[$TaskRole] = [ordered]@{ Role = $TaskRole; Name = $TaskReference; Id = $TaskImage.Id; Platform = 'linux/amd64' }
    }
}
foreach ($TaskRole in @('backend', 'web')) {
    Invoke-TaskDocker @('tag', $TaskSources[$TaskRole], $TaskImages[$TaskRole].Name)
    if ((Get-TaskImage $TaskImages[$TaskRole].Name).Id -ne $TaskImages[$TaskRole].Id) { throw ('Tagged image differs from the tested image: ' + $TaskRole) }
}
[void][IO.Directory]::CreateDirectory($TaskOutputRoot)
$TaskTar = Join-Path $TaskOutputRoot 'images.tar'
$TaskArchive = Join-Path $TaskOutputRoot 'images.tar.gz'
$TaskReferences = @($TaskImages.Values | ForEach-Object { $_.Name })
Write-Host ('Exporting ' + $TaskReferences.Count + ' images...')
Invoke-TaskDocker (@('save', '--output', $TaskTar) + $TaskReferences)
$TaskInput = [IO.File]::OpenRead($TaskTar)
try {
    $TaskOutput = [IO.File]::Create($TaskArchive)
    try {
        $TaskGzip = New-Object IO.Compression.GZipStream($TaskOutput, [IO.Compression.CompressionLevel]::Optimal)
        try { $TaskInput.CopyTo($TaskGzip) } finally { $TaskGzip.Dispose() }
    } finally { $TaskOutput.Dispose() }
} finally { $TaskInput.Dispose() }
$TaskReleaseFiles = @('LICENSE', 'docker/docker-compose.yml', 'docker/docker-compose.prod.yml', 'docker/.env.local.example', 'docker/.env.prod.example', 'docs/production-deployment.md', 'scripts/update-production-containers.sh')
if ($Package -eq 'init') {
    $TaskReleaseFiles += 'sql/init.sql'
    if (Test-Path -LiteralPath (Join-Path $TaskProjectRoot 'sql/production-bootstrap.sql') -PathType Leaf) { $TaskReleaseFiles += 'sql/production-bootstrap.sql' }
}
foreach ($TaskRelative in $TaskReleaseFiles) {
    $TaskTarget = Join-Path $TaskOutputRoot $TaskRelative
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($TaskTarget))
    $TaskContent = [IO.File]::ReadAllText((Join-Path $TaskProjectRoot $TaskRelative))
    if ($TaskRelative -eq 'docker/.env.prod.example') {
        $TaskContent = [regex]::Replace($TaskContent, '(?m)^IMAGE_TAG=.*$', ('IMAGE_TAG=' + $ReleaseTag))
        $TaskContent = [regex]::Replace($TaskContent, '(?m)^IMAGE_PREFIX=.*$', ('IMAGE_PREFIX=' + $ImagePrefix))
    }
    [IO.File]::WriteAllText($TaskTarget, ($TaskContent -replace '\r\n', $TaskLf), $TaskUtf8)
}
[IO.File]::WriteAllText((Join-Path $TaskOutputRoot 'docker/release.env'), ('IMAGE_PREFIX=' + $ImagePrefix + $TaskLf + 'IMAGE_TAG=' + $ReleaseTag + $TaskLf), $TaskUtf8)
$TaskArchiveHash = (Get-FileHash -LiteralPath $TaskArchive -Algorithm SHA256).Hash.ToLowerInvariant()
$TaskManifest = [ordered]@{
    SchemaVersion = 1
    Project = 'shuomi-erp'
    SourceProject = $SourceProject
    PackageType = $Package
    ReleaseTag = $ReleaseTag
    ImagePrefix = $ImagePrefix
    CreatedAt = [DateTimeOffset]::Now.ToString('o')
    Archive = 'images.tar.gz'
    ArchiveSha256 = $TaskArchiveHash
    Images = @($TaskImages.Values)
    Note = 'MySQL image and sql/init.sql are for a NEW LOCAL database only. Production uses a separately managed MySQL service; never run init.sql against an existing database.'
}
[IO.File]::WriteAllText((Join-Path $TaskOutputRoot 'images.json'), (($TaskManifest | ConvertTo-Json -Depth 6) + $TaskLf), $TaskUtf8)
$TaskHashFiles = @('images.tar.gz', 'images.json', 'docker/release.env') + $TaskReleaseFiles
$TaskHashLines = foreach ($TaskRelative in $TaskHashFiles) {
    (Get-FileHash -LiteralPath (Join-Path $TaskOutputRoot $TaskRelative) -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $TaskRelative
}
[IO.File]::WriteAllText((Join-Path $TaskOutputRoot 'SHA256SUMS'), (($TaskHashLines -join $TaskLf) + $TaskLf), $TaskUtf8)
if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($TaskTar)) -ne $TaskOutputRoot) { throw 'Unexpected intermediate archive path.' }
Remove-Item -LiteralPath $TaskTar
Write-Host ('Ready: ' + $TaskOutputRoot)
Write-Host ('Production: import images.tar.gz, set IMAGE_PREFIX=' + $ImagePrefix + ' and IMAGE_TAG=' + $ReleaseTag + ', then recompose docker/docker-compose.prod.yml with Force Pull disabled.')
Write-Host 'Keep images.json and SHA256SUMS with the release. Do not upload your local docker/.env.'
