# Merge against a fresh snapshot after staging, not the startup copy. The
# installer lock serializes our processes; the byte check detects other writers.
function Get-AIEditRegistrySnapshot([string]$Path) {
    $bytes=$null
    if (Test-Path -LiteralPath $Path) { $bytes=[IO.File]::ReadAllBytes($Path) }
    $data=if ($null -ne $bytes) { [Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF) | ConvertFrom-Json } else { [pscustomobject]@{ plugins=@() } }
    if ($null -eq $data -or $null -eq $data.plugins -or $data.plugins -isnot [System.Array]) { throw 'Invalid Adobe plugin registry. No registry overwritten.' }
    return [pscustomobject]@{ Bytes=$bytes; Data=$data }
}
function Test-AIEditRegistryBytes($Left,$Right) {
    if ($null -eq $Left -or $null -eq $Right) { return ($null -eq $Left -and $null -eq $Right) }
    return [Convert]::ToBase64String([byte[]]$Left) -ceq [Convert]::ToBase64String([byte[]]$Right)
}
function Write-AIEditPluginRegistry([string]$Registry,[hashtable]$Values,[scriptblock]$RegistryWriter) {
    $id='com.local.lk888.psedit'
    $before=Get-AIEditRegistrySnapshot $Registry
    $oldOwn=@($before.Data.plugins | Where-Object { $_.pluginId -eq $id })
    $other=@($before.Data.plugins | Where-Object { $_.pluginId -ne $id })
    $own=@()
    if ($null -ne $Values) {
        $entry=[pscustomobject]@{}
        if ($oldOwn.Count) { foreach ($property in $oldOwn[0].PSObject.Properties) { $entry | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value } }
        foreach ($field in $Values.Keys) { $entry | Add-Member -NotePropertyName $field -NotePropertyValue $Values[$field] -Force }
        $own=@($entry)
    }
    $before.Data.plugins=$other+$own
    $output=[Text.Encoding]::UTF8.GetBytes(($before.Data | ConvertTo-Json -Depth 100))
    $temp=$Registry+'.committing-'+[guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllBytes($temp,$output)
        $check=Get-AIEditRegistrySnapshot $Registry
        if (-not (Test-AIEditRegistryBytes $check.Bytes $before.Bytes)) { throw 'Adobe plugin registry changed concurrently. Please retry.' }
        try { & $RegistryWriter $temp $Registry | Out-Null }
        catch {
            # Do not roll back a third-party update using an older whole file.
            # Only undo our record if it still matches our attempted write.
            try {
                $current=Get-AIEditRegistrySnapshot $Registry
                $currentOwn=@($current.Data.plugins | Where-Object { $_.pluginId -eq $id })
                $sameOwn=(ConvertTo-Json -InputObject $currentOwn -Depth 100 -Compress) -ceq (ConvertTo-Json -InputObject $own -Depth 100 -Compress)
                if (-not (Test-AIEditRegistryBytes $current.Bytes $before.Bytes) -and $sameOwn) {
                    $restore=$before.Bytes
                    if (-not (Test-AIEditRegistryBytes $current.Bytes $output)) {
                        $current.Data.plugins=@($current.Data.plugins | Where-Object { $_.pluginId -ne $id })+$oldOwn
                        $restore=[Text.Encoding]::UTF8.GetBytes(($current.Data | ConvertTo-Json -Depth 100))
                    }
                    if ($null -ne $restore) {
                        [IO.File]::WriteAllBytes($temp,[byte[]]$restore)
                        $check=Get-AIEditRegistrySnapshot $Registry
                        if (Test-AIEditRegistryBytes $check.Bytes $current.Bytes) {
                            [IO.File]::Replace($temp,$Registry,[System.Management.Automation.Language.NullString]::Value)
                        }
                    } elseif (Test-AIEditRegistryBytes (Get-AIEditRegistrySnapshot $Registry).Bytes $current.Bytes) {
                        Remove-Item -LiteralPath $Registry -Force
                    }
                }
            } catch { Write-Warning 'Registry changed during rollback; preserved the latest registry for manual verification.' }
            throw
        }
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
}

# Shared by the GUI and command-line fallback. Tests supply isolated directories.
function Invoke-AIEditChange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$PayloadDirectory,
        [Parameter(Mandatory=$true)][string]$BaseDirectory,
        [switch]$Uninstall,
        [scriptblock]$BeforeRegistryCommit,
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
    New-Item -ItemType Directory -Path (Split-Path $registry -Parent) -Force | Out-Null
    $lock=[IO.File]::Open((Join-Path (Split-Path $registry -Parent) '.ai-edit-installer.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
    $initial=Get-AIEditRegistrySnapshot $registry
    $original=$initial.Bytes; $data=$initial.Data
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
        $moved = @()
        try {
            foreach ($folder in $old) { Move-Item -LiteralPath $folder.FullName -Destination (Join-Path $backup $folder.Name); $moved += $folder }
            if ($BeforeRegistryCommit) { & $BeforeRegistryCommit $registry | Out-Null }
            Write-AIEditPluginRegistry -Registry $registry -Values $null -RegistryWriter $RegistryWriter
        } catch {
            foreach ($folder in $moved) { Move-Item -LiteralPath (Join-Path $backup $folder.Name) -Destination $folder.FullName }
            throw
        }
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
    $moved = @(); $placed = $false
    try {
        Copy-Item -LiteralPath $payload -Destination $stage -Recurse
        if ((Get-Content -LiteralPath (Join-Path $stage 'manifest.json') -Raw -Encoding UTF8) -cne $manifestText) { throw 'Installer payload changed while reading. No plugin replaced.' }
        foreach ($folder in $old) { Move-Item -LiteralPath $folder.FullName -Destination (Join-Path $backup $folder.Name); $moved += $folder }
        Move-Item -LiteralPath $stage -Destination $target; $placed = $true
        if ($BeforeRegistryCommit) { & $BeforeRegistryCommit $registry | Out-Null }
        $values = @{ hostMinVersion=$info.host.minVersion; name=$info.name; path=('$localPlugins\External\' + (Split-Path $target -Leaf)); pluginId=$pluginId; status='enabled'; type='uxp'; versionString=$info.version }
        Write-AIEditPluginRegistry -Registry $registry -Values $values -RegistryWriter $RegistryWriter
        $result = [pscustomobject]@{ Action='Install'; Backup=$backup; Destination=$target; Version=$info.version }
    } catch {
        if ($placed) { Remove-Item -LiteralPath $target -Recurse -Force }
        foreach ($folder in $moved) { Move-Item -LiteralPath (Join-Path $backup $folder.Name) -Destination $folder.FullName }
        throw
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    }
    
    return $result
    } finally { $lock.Dispose() }
}
