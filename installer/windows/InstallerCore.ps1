# Shared by the GUI and command-line fallback. Tests supply isolated directories.
function Invoke-AIEditChange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$PayloadDirectory,
        [Parameter(Mandatory=$true)][string]$BaseDirectory,
        [switch]$Uninstall,
        [scriptblock]$RegistryWriter = {
            param($Temporary, $Destination)
            if (Test-Path -LiteralPath $Destination) { [IO.File]::Replace($Temporary,$Destination,[System.Management.Automation.Language.NullString]::Value) }
            else { [IO.File]::Move($Temporary,$Destination) }
        }
    )
    $ErrorActionPreference = 'Stop'
    $pluginId = 'com.local.lk888.psedit'
    $payload = $PayloadDirectory
    $manifestText = Get-Content -LiteralPath (Join-Path $payload 'manifest.json') -Raw -Encoding UTF8
    $info = $manifestText | ConvertFrom-Json
    if ($info.id -ne $pluginId -or $info.version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid installer payload.' }
    if (Get-Process -Name Photoshop -ErrorAction SilentlyContinue) { throw 'Save your work and quit Photoshop before installing.' }
    $base = $BaseDirectory
    $external = Join-Path $base 'Plugins\External'
    $registry = Join-Path $base 'PluginsInfo\v1\PS.json'
    $original = if (Test-Path -LiteralPath $registry) { [IO.File]::ReadAllBytes($registry) } else { $null }
    $data = if ($null -ne $original) { [Text.Encoding]::UTF8.GetString($original).TrimStart([char]0xFEFF) | ConvertFrom-Json } else { [pscustomobject]@{ plugins=@() } }
    if ($null -eq $data -or $null -eq $data.plugins -or $data.plugins -isnot [System.Array]) { throw 'Invalid Adobe plugin registry. No changes made.' }
    $target = Join-Path $external ($pluginId + '_' + $info.version)
    $backup = Join-Path $base ('Plugins\.AIEditInstallerBackups\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
    $stage = Join-Path $external ('.ai-edit-install-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $external -Force | Out-Null
    $old = @(Get-ChildItem -LiteralPath $external -Directory | Where-Object {
        if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
        $manifest = Join-Path $_.FullName 'manifest.json'
        if (-not (Test-Path -LiteralPath $manifest)) { return $false }
        try { return (Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json).id -eq $pluginId } catch { return $false }
    })
    if ($Uninstall) {
        $matching = @($data.plugins | Where-Object { $_.pluginId -eq $pluginId })
        if ($old.Count -eq 0 -and $matching.Count -eq 0) { return [pscustomobject]@{ Action='Uninstall'; Backup=$null; AlreadyRemoved=$true } }
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
        if ($null -ne $original) { [IO.File]::WriteAllBytes((Join-Path $backup 'PS.json'),$original) }
        $moved = @(); $touched = $false; $temp = $null
        try {
            foreach ($folder in $old) { Move-Item -LiteralPath $folder.FullName -Destination (Join-Path $backup $folder.Name); $moved += $folder }
            if ($matching.Count -gt 0) {
                $data.plugins = @($data.plugins | Where-Object { $_.pluginId -ne $pluginId })
                $temp = $registry + '.uninstalling-' + [guid]::NewGuid().ToString('N')
                [IO.File]::WriteAllText($temp,($data | ConvertTo-Json -Depth 100),(New-Object Text.UTF8Encoding($false)))
                $touched = $true
                & $RegistryWriter $temp $registry
            }
        } catch {
            if ($touched -and $null -ne $original) { [IO.File]::WriteAllBytes($registry,$original) }
            foreach ($folder in $moved) { Move-Item -LiteralPath (Join-Path $backup $folder.Name) -Destination $folder.FullName }
            throw
        } finally { if ($temp -and (Test-Path -LiteralPath $temp)) { Remove-Item -LiteralPath $temp -Force } }
        return [pscustomobject]@{ Action='Uninstall'; Backup=$backup; AlreadyRemoved=$false }
    }
    if ((Test-Path -LiteralPath $target) -and $target -notin @($old.FullName)) { throw 'Target directory is occupied by another file.' }
    # Preflight both destinations before changing any installed plugin files.
    New-Item -ItemType Directory -Path (Split-Path $registry -Parent) -Force | Out-Null
    foreach ($directory in @($external, (Split-Path $registry -Parent))) {
        $probe = Join-Path $directory ('.ai-edit-write-check-' + [guid]::NewGuid().ToString('N'))
        try { [IO.File]::WriteAllBytes($probe,[byte[]]@()) } finally { if (Test-Path -LiteralPath $probe) { Remove-Item -LiteralPath $probe -Force } }
    }
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    if ($null -ne $original) { [IO.File]::WriteAllBytes((Join-Path $backup 'PS.json'),$original) }
    $moved = @(); $placed = $false; $registryTouched = $false; $temp = $null
    try {
        Copy-Item -LiteralPath $payload -Destination $stage -Recurse
        if ((Get-Content -LiteralPath (Join-Path $stage 'manifest.json') -Raw -Encoding UTF8) -cne $manifestText) { throw 'Installer payload changed while reading. No plugin replaced.' }
        foreach ($folder in $old) { Move-Item -LiteralPath $folder.FullName -Destination (Join-Path $backup $folder.Name); $moved += $folder }
        Move-Item -LiteralPath $stage -Destination $target; $placed = $true
        $existing = @($data.plugins | Where-Object { $_.pluginId -eq $pluginId }) | Select-Object -First 1
        $entry = if ($existing) { $existing } else { [pscustomobject]@{} }
        $values = @{ hostMinVersion=$info.host.minVersion; name=$info.name; path=('$localPlugins\External\' + (Split-Path $target -Leaf)); pluginId=$pluginId; status='enabled'; type='uxp'; versionString=$info.version }
        foreach ($field in $values.Keys) { $entry | Add-Member -NotePropertyName $field -NotePropertyValue $values[$field] -Force }
        $data.plugins = @($data.plugins | Where-Object { $_.pluginId -ne $pluginId }) + @($entry)
        New-Item -ItemType Directory -Path (Split-Path $registry -Parent) -Force | Out-Null
        $temp = $registry + '.installing-' + [guid]::NewGuid().ToString('N')
        [IO.File]::WriteAllText($temp,($data | ConvertTo-Json -Depth 100),(New-Object Text.UTF8Encoding($false)))
        $registryTouched = $true
        & $RegistryWriter $temp $registry
        $result = [pscustomobject]@{ Action='Install'; Backup=$backup; Destination=$target; Version=$info.version }
    } catch {
        if ($registryTouched) { if ($null -ne $original) { [IO.File]::WriteAllBytes($registry,$original) } elseif (Test-Path -LiteralPath $registry) { Remove-Item -LiteralPath $registry } }
        if ($placed) { Remove-Item -LiteralPath $target -Recurse -Force }
        foreach ($folder in $moved) { Move-Item -LiteralPath (Join-Path $backup $folder.Name) -Destination $folder.FullName }
        throw
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
        if ($temp -and (Test-Path -LiteralPath $temp)) { Remove-Item -LiteralPath $temp -Force }
    }
    
    return $result
}
