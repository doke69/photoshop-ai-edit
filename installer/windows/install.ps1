param([switch]$Uninstall, [switch]$NoGuide)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
try {
    . (Join-Path $PSScriptRoot 'InstallerCore.ps1')
    $result = Invoke-AIEditChange -PayloadDirectory (Join-Path $PSScriptRoot 'plugin') -BaseDirectory (Join-Path $env:APPDATA 'Adobe\UXP') -Uninstall:$Uninstall
    Write-Output ($result | ConvertTo-Json -Compress)
    if (-not $Uninstall -and -not $NoGuide) {
        try { Start-Process (Join-Path $PSScriptRoot '安装与使用指南.html') } catch { Write-Warning 'Open the included HTML guide manually.' }
    }
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
