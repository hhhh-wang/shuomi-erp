# SHUOMI-ERP PRIVATE CUSTOMIZATION: production/local deployment
﻿[CmdletBinding()]
param(
    [string]$EnvFile = '',
    [ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$')][string]$ReleaseTag = '',
    [ValidateRange(60, 3600)][int]$WaitTimeout = 300,
    [string]$DockerExe = '',
    [AllowEmptyString()][string]$ProxyUrl = '',
    [switch]$SkipBuild,
    [switch]$CheckOnly
)
. (Join-Path $PSScriptRoot 'docker-common.ps1')
$TaskCompose = Join-Path $TaskProjectRoot 'docker/docker-compose.yml'
if (-not $EnvFile) { $EnvFile = Join-Path $TaskProjectRoot 'docker/.env' }
$TaskEnvFile = [IO.Path]::GetFullPath($EnvFile)
if (-not (Test-Path -LiteralPath $TaskEnvFile -PathType Leaf)) { throw 'Create docker/.env from docker/.env.local.example, then set the database/cache passwords and JWT_SECRET.' }
if (-not (Test-Path -LiteralPath $TaskCompose -PathType Leaf)) { throw 'docker/docker-compose.yml was not found.' }
Initialize-TaskDocker -DockerExe $DockerExe -ProxyUrl $ProxyUrl
$TaskOldImageTag = [Environment]::GetEnvironmentVariable('IMAGE_TAG', 'Process')
try {
    if ($ReleaseTag) { $env:IMAGE_TAG = $ReleaseTag }
    $TaskComposeArgs = @('compose', '--project-name', 'lemon-erp', '--env-file', $TaskEnvFile, '--file', $TaskCompose)
    [void](Invoke-TaskDocker ($TaskComposeArgs + @('config', '--quiet')))
    if ($CheckOnly) {
        Invoke-TaskDocker ($TaskComposeArgs + @('config', '--services'))
        Write-Host 'Check passed. This command uses local Docker Desktop, project lemon-erp, and the existing named data volumes.'
        return
    }
    if (-not $SkipBuild) {
        Write-Host 'Building the saved backend and frontend source...'
        Invoke-TaskDocker ($TaskComposeArgs + @('build', 'backend', 'web'))
    }
    Write-Host 'Starting the updated app and required local MySQL/Redis services...'
    $TaskUpArgs = @('up', '--detach', '--wait', '--wait-timeout', [string]$WaitTimeout, '--no-build')
    if ($SkipBuild) { $TaskUpArgs += @('--pull', 'never') }
    Invoke-TaskDocker ($TaskComposeArgs + $TaskUpArgs + @('backend', 'web'))
    Invoke-TaskDocker ($TaskComposeArgs + @('ps'))
    $TaskWebId = ((Invoke-TaskDocker ($TaskComposeArgs + @('ps', '--quiet', 'web'))) -join '').Trim()
    $TaskInspect = ConvertFrom-Json ((Invoke-TaskDocker @('inspect', $TaskWebId)) -join ([string][char]10))
    $TaskContainer = @($TaskInspect)[0]
    $TaskPorts = @($TaskContainer.NetworkSettings.Ports.'80/tcp')
    if ($TaskPorts.Count -gt 0) { Write-Host ('Update succeeded. Open http://localhost:' + $TaskPorts[0].HostPort + ' and press Ctrl+F5.') }
    else { Write-Host 'Update succeeded. Check the web port in docker/.env.' }
    Write-Host 'MySQL, Redis and uploaded-file volumes were retained. Test login and a business page before exporting release images.'
} finally {
    [Environment]::SetEnvironmentVariable('IMAGE_TAG', $TaskOldImageTag, 'Process')
}
