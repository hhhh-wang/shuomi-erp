# SHUOMI-ERP PRIVATE CUSTOMIZATION: production/local deployment
# Shared Docker Desktop helpers for the Windows deployment entry points.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:TaskDockerHost = ''
$script:TaskProjectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Initialize-TaskDocker {
    param([string]$DockerExe = '', [string]$ProxyUrl = '')
    $script:TaskProxyUrl = $ProxyUrl
    $TaskProxyUri = $null
    if ($ProxyUrl -and (-not [Uri]::TryCreate($ProxyUrl, [UriKind]::Absolute, [ref]$TaskProxyUri) -or $TaskProxyUri.Scheme -notin @('http', 'https'))) {
        throw 'ProxyUrl must be an HTTP/HTTPS URL, or empty for a direct connection.'
    }
    foreach ($TaskPair in @(
        @('USERNAME', [Environment]::UserName),
        @('USERDOMAIN', [Environment]::UserDomainName),
        @('ProgramData', [Environment]::GetFolderPath('CommonApplicationData')),
        @('APPDATA', [Environment]::GetFolderPath('ApplicationData')),
        @('LOCALAPPDATA', [Environment]::GetFolderPath('LocalApplicationData'))
    )) {
        if (-not [Environment]::GetEnvironmentVariable($TaskPair[0])) { [Environment]::SetEnvironmentVariable($TaskPair[0], $TaskPair[1], 'Process') }
    }
    if (-not $env:ComSpec) { $env:ComSpec = Join-Path $env:SystemRoot 'System32\cmd.exe' }
    $script:TaskPathExt = $env:PATHEXT
    if (($script:TaskPathExt -split ';') -notcontains '.EXE') { $script:TaskPathExt = '.COM;.EXE;.BAT;.CMD;' + $script:TaskPathExt }
    if (-not $DockerExe) {
        $TaskCommand = Get-Command docker.exe -CommandType Application -ErrorAction SilentlyContinue
        if ($TaskCommand) { $DockerExe = $TaskCommand.Source }
        if (-not $DockerExe) {
            foreach ($TaskCandidate in @(
                (Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\resources\bin\docker.exe'),
                (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Docker\Docker\resources\bin\docker.exe')
            )) {
                if (Test-Path -LiteralPath $TaskCandidate -PathType Leaf) { $DockerExe = $TaskCandidate; break }
            }
        }
    }
    if (-not $DockerExe -or -not (Test-Path -LiteralPath $DockerExe -PathType Leaf)) { throw 'Docker Desktop CLI was not found.' }
    $script:TaskDockerExe = [IO.Path]::GetFullPath($DockerExe)
    $TaskContext = ((Invoke-TaskDocker @('context', 'show')) -join '').Trim()
    $TaskEndpointJson = (Invoke-TaskDocker @('context', 'inspect', $TaskContext, '--format', '{{json .Endpoints.docker}}')) -join ''
    $script:TaskDockerHost = ($TaskEndpointJson | ConvertFrom-Json).Host
    if (-not $script:TaskDockerHost.StartsWith('npipe:')) { throw 'Select a local Docker Desktop context; remote contexts are not accepted.' }
    if (((Invoke-TaskDocker @('info', '--format', '{{.OSType}}')) -join '').Trim() -ne 'linux') { throw 'Docker Desktop must be running with Linux containers.' }
    [void](Invoke-TaskDocker @('compose', 'version'))
}

function Invoke-TaskDocker {
    param([Parameter(Mandatory = $true)][string[]]$TaskArguments)
    $TaskFullArguments = @()
    if ($script:TaskDockerHost) { $TaskFullArguments += @('--host', $script:TaskDockerHost) }
    $TaskFullArguments += $TaskArguments
    $TaskQuoted = @($TaskFullArguments | ForEach-Object {
        $TaskArgument = [regex]::Replace($_, '(\\*)"', '$1$1\"')
        $TaskArgument = [regex]::Replace($TaskArgument, '(\\+)$', '$1$1')
        '"' + $TaskArgument + '"'
    })
    $TaskProcess = New-Object System.Diagnostics.Process
    $TaskProcess.StartInfo.FileName = $script:TaskDockerExe
    $TaskProcess.StartInfo.Arguments = [string]::Join(' ', $TaskQuoted)
    $TaskProcess.StartInfo.WorkingDirectory = $script:TaskProjectRoot
    $TaskProcess.StartInfo.UseShellExecute = $false
    $TaskProcess.StartInfo.CreateNoWindow = $true
    $TaskProcess.StartInfo.RedirectStandardOutput = $true
    $TaskProcess.StartInfo.RedirectStandardError = $true
    $TaskProcess.StartInfo.EnvironmentVariables['PATH'] = (Split-Path -Parent $script:TaskDockerExe) + ';' + $env:PATH
    $TaskProcess.StartInfo.EnvironmentVariables['PATHEXT'] = $script:TaskPathExt
    foreach ($TaskProxyVariable in @('HTTP_PROXY', 'HTTPS_PROXY')) {
        if ($script:TaskProxyUrl) { $TaskProcess.StartInfo.EnvironmentVariables[$TaskProxyVariable] = $script:TaskProxyUrl }
        else { $TaskProcess.StartInfo.EnvironmentVariables.Remove($TaskProxyVariable) }
    }
    if ($script:TaskDockerHost) {
        $TaskProcess.StartInfo.EnvironmentVariables.Remove('DOCKER_CONTEXT')
        $TaskProcess.StartInfo.EnvironmentVariables['DOCKER_HOST'] = $script:TaskDockerHost
    }
    try {
        [void]$TaskProcess.Start()
        $TaskOut = $TaskProcess.StandardOutput.ReadToEndAsync()
        $TaskErr = $TaskProcess.StandardError.ReadToEndAsync()
        $TaskProcess.WaitForExit()
        $TaskOutput = $TaskOut.Result
        $TaskError = $TaskErr.Result
        $TaskExit = $TaskProcess.ExitCode
    } finally { $TaskProcess.Dispose() }
    if ($TaskError) { [Console]::Error.Write($TaskError) }
    if ($TaskExit -ne 0) { throw ('Docker command failed (exit ' + $TaskExit + '): ' + ($TaskArguments -join ' ')) }
    if ($TaskOutput) { $TaskOutput.TrimEnd() -split '\r?\n' }
}

function Get-TaskImage {
    param([Parameter(Mandatory = $true)][string]$Reference)
    $TaskInfo = ConvertFrom-Json ((Invoke-TaskDocker @('image', 'inspect', $Reference)) -join "
")
    $TaskImage = @($TaskInfo)[0]
    if ($TaskImage.Os -ne 'linux' -or $TaskImage.Architecture -ne 'amd64') { throw ('Expected linux/amd64 image: ' + $Reference) }
    return $TaskImage
}
