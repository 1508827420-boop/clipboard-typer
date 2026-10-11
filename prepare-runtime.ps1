$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Download an unmodified upstream runtime; do not install or require admin rights.
$runtimeDir = Join-Path $PSScriptRoot 'runtime'
$runtimeExe = Join-Path $runtimeDir 'AutoHotkey64.exe'
if (Test-Path -LiteralPath $runtimeExe) {
    Write-Host 'AutoHotkey runtime is already available.'
    exit 0
}

$downloadUrl = 'https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.30/AutoHotkey_2.0.30.zip'
$expectedHash = '1E0ECE7ECB2D5646E55758150472677996A57F9DB5C83D2996D8B47B9E2F31A4'
$archivePath = Join-Path ([IO.Path]::GetTempPath()) ('clipboard-typer-' + [Guid]::NewGuid().ToString('N') + '.zip')
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Host 'Downloading AutoHotkey 2.0.30 from the official GitHub release...'
    Invoke-WebRequest -UseBasicParsing -Uri $downloadUrl -OutFile $archivePath
    $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash) {
        throw 'Runtime checksum mismatch. Nothing will be launched.'
    }
    Expand-Archive -LiteralPath $archivePath -DestinationPath $runtimeDir -Force
    if (-not (Test-Path -LiteralPath $runtimeExe)) {
        throw 'The official archive does not contain AutoHotkey64.exe.'
    }
    Write-Host 'Runtime prepared. Upstream license is in runtime/license.txt.'
} finally {
    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }
}
