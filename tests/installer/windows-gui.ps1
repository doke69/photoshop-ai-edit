$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$version = (Get-Content (Join-Path $root 'plugin\manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version
$exe = Join-Path $root ('dist\Photoshop-AI-Edit-'+$version+'-Windows-Setup.exe')
$shot = Join-Path $root 'dist\windows-installer-preview.png'
$work = Join-Path ([IO.Path]::GetTempPath()) ('AI Edit GUI 测试 '+[guid]::NewGuid().ToString('N'))
$previousAppData=$env:APPDATA
$process=$null
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
function Find-Control($Property, $Value) {
    $condition=New-Object Windows.Automation.PropertyCondition($Property,$Value)
    return $script:element.FindFirst([Windows.Automation.TreeScope]::Descendants,$condition)
}
function Wait-Control($Property, $Value) {
    for ($attempt=0;$attempt -lt 100;$attempt++) {
        if ($process.HasExited) { throw 'Installer exited unexpectedly.' }
        $control=Find-Control $Property $Value
        if ($null -ne $control) { return $control }
        Start-Sleep -Milliseconds 200
    }
    throw ('Timed out waiting for UI: '+$Value)
}
function Click($Name) {
    $control=Wait-Control ([Windows.Automation.AutomationElement]::AutomationIdProperty) $Name
    $invoke=$control.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern)
    $invoke.Invoke()
}
try {
    New-Item -ItemType Directory -Path $work | Out-Null
    $env:APPDATA=$work
    $preview=Start-Process -FilePath $exe -ArgumentList @('--preview',('"'+$shot+'"')) -PassThru
    if (-not $preview.WaitForExit(30000)) { $preview.Kill(); throw 'Preview timed out.' }
    if ($preview.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $shot)) { throw 'Preview failed.' }
    if (Test-Path -LiteralPath (Join-Path $work 'Adobe')) { throw 'Preview touched Adobe directories.' }
    $process=Start-Process -FilePath $exe -PassThru
    for($i=0;$i -lt 100;$i++) {
        $process.Refresh()
        if ($process.MainWindowHandle -ne [IntPtr]::Zero) { break }
        Start-Sleep -Milliseconds 200
    }
    if ($process.MainWindowHandle -eq [IntPtr]::Zero) { throw 'Installer window missing.' }
    $script:element=[Windows.Automation.AutomationElement]::FromHandle($process.MainWindowHandle)
    Click 'Primary'
    $null=Wait-Control ([Windows.Automation.AutomationElement]::NameProperty) '安装完成'
    $registry=Join-Path $work 'Adobe\UXP\PluginsInfo\v1\PS.json'
    $data=Get-Content -LiteralPath $registry -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($data.plugins[0].pluginId -ne 'com.local.lk888.psedit') { throw 'Packaged payload registration failed.' }
    $target=Join-Path $work ('Adobe\UXP\Plugins\External\com.local.lk888.psedit_'+$version)
    foreach ($file in Get-ChildItem (Join-Path $root 'plugin') -File -Recurse) {
        $relative=$file.FullName.Substring((Join-Path $root 'plugin').Length+1)
        if ((Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath (Join-Path $target $relative)).Hash) { throw ('Packaged payload mismatch: '+$relative) }
    }
    Click 'UninstallTab'
    Click 'Primary'
    $null=Wait-Control ([Windows.Automation.AutomationElement]::NameProperty) '卸载完成'
    if (Test-Path -LiteralPath $target) { throw 'Packaged GUI uninstall left plugin files.' }
    $data=Get-Content -LiteralPath $registry -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@($data.plugins).Count -ne 0) { throw 'Packaged GUI uninstall left registration.' }
    # Repeat-uninstall is covered by the core fixtures; do not wait on a stale
    # success label while a second asynchronous UI operation is starting.
    $process.CloseMainWindow() | Out-Null
    if (-not $process.WaitForExit(10000)) { throw 'Installer did not close.' }
    $report='Windows Server 2022: graphical installer compiled; safe preview rendered; real EXE UI automation installed the embedded payload into isolated Chinese APPDATA; payload hashes matched; GUI uninstall passed. Repeat-uninstall and rollback passed in core fixtures. No Photoshop or paid API calls. Windows 10/11 user machine and Photoshop loading remain unverified.'
    [IO.File]::WriteAllText((Join-Path $root 'dist\windows-smoke-report.txt'),$report)
    Write-Host $report
} finally {
    $env:APPDATA=$previousAppData
    if ($null -ne $process -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}
