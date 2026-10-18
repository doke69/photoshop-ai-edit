$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $root 'installer\windows\InstallerCore.ps1')
$work = Join-Path ([IO.Path]::GetTempPath()) ('AI Edit 测试 ' + [guid]::NewGuid().ToString('N'))
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Expect-Failure([scriptblock]$Operation, [string]$Message) { $failed=$false; try { & $Operation | Out-Null } catch { $failed=$true }; Assert $failed $Message }
function Read-Registry($Path) { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $payload=Join-Path $work '安装文件'; Copy-Item -LiteralPath (Join-Path $root 'plugin') -Destination $payload -Recurse
    $base=Join-Path $work '用户目录\Adobe\UXP'
    $registry=Join-Path $base 'PluginsInfo\v1\PS.json'
    $first=Invoke-AIEditChange -PayloadDirectory $payload -BaseDirectory $base
    Assert (Test-Path -LiteralPath (Join-Path $first.Destination 'main.js')) 'Fresh install missing payload'
    $data=Read-Registry $registry
    Assert ($data.plugins.Count -eq 1) 'Missing registry entry'
    Assert ($data.plugins[0].path.StartsWith('$localPlugins\External\')) 'Incorrect Windows Adobe path'
    $data | Add-Member -NotePropertyName preservedField -NotePropertyValue 'keep'
    $data.plugins += [pscustomobject]@{ pluginId='another.plugin'; path='untouched'; custom='keep' }
    [IO.File]::WriteAllText($registry,($data|ConvertTo-Json -Depth 100),(New-Object Text.UTF8Encoding($true)))
    $private=Join-Path $base 'PluginsStorage\private-fixture.txt'; New-Item -ItemType Directory -Path (Split-Path $private) -Force | Out-Null
    [IO.File]::WriteAllText($private,'private-fixture')
    $second=Invoke-AIEditChange -PayloadDirectory $payload -BaseDirectory $base
    $data=Read-Registry $registry
    Assert ($data.plugins.Count -eq 2 -and $data.preservedField -eq 'keep') 'Registry metadata lost on upgrade'
    Assert ($data.plugins[1].pluginId -eq 'com.local.lk888.psedit' -and $data.plugins[0].custom -eq 'keep') 'Other plugin changed'
    Assert (Test-Path -LiteralPath (Join-Path $second.Backup (Split-Path $first.Destination -Leaf))) 'Upgrade backup missing'
    $before=[Convert]::ToBase64String([IO.File]::ReadAllBytes($registry))
    $fail={ param($Temporary,$Destination) throw 'Injected registry failure' }
    Expect-Failure { Invoke-AIEditChange -PayloadDirectory $payload -BaseDirectory $base -RegistryWriter $fail } 'Install failure ignored'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($registry)) -eq $before) 'Registry rollback failed'
    Assert (Test-Path -LiteralPath (Join-Path $first.Destination 'main.js')) 'Install rollback lost original files'
    Expect-Failure { Invoke-AIEditChange -PayloadDirectory $payload -BaseDirectory $base -Uninstall -RegistryWriter $fail } 'Uninstall failure ignored'
    Assert (Test-Path -LiteralPath (Join-Path $first.Destination 'main.js')) 'Uninstall rollback lost original files'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($registry)) -eq $before) 'Uninstall registry rollback failed'
    $removed=Invoke-AIEditChange -PayloadDirectory $payload -BaseDirectory $base -Uninstall
    Assert (-not (Test-Path -LiteralPath $first.Destination)) 'Uninstall left plugin'
    $data=Read-Registry $registry
    Assert ($data.plugins.Count -eq 1 -and $data.plugins[0].pluginId -eq 'another.plugin') 'Uninstall changed another plugin'
    Assert ([IO.File]::ReadAllText($private) -eq 'private-fixture') 'Private data lost'
    $repeat=Invoke-AIEditChange -PayloadDirectory $payload -BaseDirectory $base -Uninstall
    Assert $repeat.AlreadyRemoved 'Repeated uninstall failed'
    [IO.File]::WriteAllText($registry,'{"plugins":null}')
    Expect-Failure { Invoke-AIEditChange -PayloadDirectory $payload -BaseDirectory $base } 'Invalid registry accepted'
    [IO.File]::WriteAllText($registry,'{"plugins":[]}')
    New-Item -ItemType Directory -Path $first.Destination -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $first.Destination 'manifest.json'),'{"id":"another.plugin"}')
    Expect-Failure { Invoke-AIEditChange -PayloadDirectory $payload -BaseDirectory $base } 'Occupied target accepted'
    Assert ((Read-Registry (Join-Path $first.Destination 'manifest.json')).id -eq 'another.plugin') 'Occupied target altered'
    Write-Host 'Windows fixtures passed: Chinese paths, first install, BOM registry, upgrade backup, metadata, other plugins, private data, install/uninstall rollback, repeat uninstall, malformed registry and occupied target.'
} finally { Remove-Item -LiteralPath $work -Recurse -Force }
