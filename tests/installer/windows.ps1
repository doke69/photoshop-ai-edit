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
    # Simulate an Adobe update after the installer has staged its files.
    $concurrent=Join-Path $work '并发登记测试'
    $installed=Invoke-AIEditChange -PayloadDirectory $payload -BaseDirectory $concurrent
    $concurrentRegistry=Join-Path $concurrent 'PluginsInfo\v1\PS.json'
    function Add-ExternalPlugin($Path,$Id) {
        $json=Read-Registry $Path
        $json.plugins+=@([pscustomobject]@{pluginId=$Id; path='new-path'; revision=7})
        $json | Add-Member -NotePropertyName externalRevision -NotePropertyValue $Id -Force
        [IO.File]::WriteAllText($Path,($json|ConvertTo-Json -Depth 100),(New-Object Text.UTF8Encoding($false)))
    }
    $null=Invoke-AIEditChange -PayloadDirectory $payload -BaseDirectory $concurrent -BeforeRegistryCommit { param($Path) Add-ExternalPlugin $Path 'late.install' }
    $json=Read-Registry $concurrentRegistry
    Assert ($json.plugins.pluginId -contains 'late.install' -and $json.externalRevision -eq 'late.install') 'Install overwrote concurrent registration'
    $null=Invoke-AIEditChange -PayloadDirectory $payload -BaseDirectory $concurrent -Uninstall -BeforeRegistryCommit { param($Path) Add-ExternalPlugin $Path 'late.uninstall' }
    $json=Read-Registry $concurrentRegistry
    Assert ($json.plugins.Count -eq 2 -and $json.externalRevision -eq 'late.uninstall') 'Uninstall overwrote concurrent registration'
    $null=Invoke-AIEditChange -PayloadDirectory $payload -BaseDirectory $concurrent
    $failAfterWrite={ param($Temporary,$Destination)
        [IO.File]::Replace($Temporary,$Destination,[System.Management.Automation.Language.NullString]::Value)
        Add-ExternalPlugin $Destination 'late.rollback'
        throw 'Failure after registry write'
    }
    Expect-Failure { Invoke-AIEditChange -PayloadDirectory $payload -BaseDirectory $concurrent -Uninstall -RegistryWriter $failAfterWrite } 'Post-write failure ignored'
    $json=Read-Registry $concurrentRegistry
    Assert ($json.externalRevision -eq 'late.rollback' -and $json.plugins.pluginId -contains 'late.rollback') 'Rollback lost concurrent plugin or metadata'
    Assert ($json.plugins.pluginId -contains 'com.local.lk888.psedit') 'Rollback lost own registry entry'
    Assert (Test-Path -LiteralPath $installed.Destination) 'Rollback lost own files'
    $lock=[IO.File]::Open((Join-Path (Split-Path $concurrentRegistry -Parent) '.ai-edit-installer.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try { Expect-Failure { Invoke-AIEditChange -PayloadDirectory $payload -BaseDirectory $concurrent -Uninstall } 'Concurrent installer lock ignored' }
    finally { $lock.Dispose() }
    $null=Invoke-AIEditChange -PayloadDirectory $payload -BaseDirectory $concurrent -Uninstall
    Write-Host 'Concurrent registry fixtures passed: latest install/uninstall merge, selective rollback and installer lock.'
    Write-Host 'Windows fixtures passed: Chinese paths, first install, BOM registry, upgrade backup, metadata, other plugins, private data, install/uninstall rollback, repeat uninstall, malformed registry and occupied target.'
} finally { Remove-Item -LiteralPath $work -Recurse -Force }
