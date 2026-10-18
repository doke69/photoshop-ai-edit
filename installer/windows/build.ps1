$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$dist = Join-Path $root 'dist'
$version = (Get-Content (Join-Path $root 'plugin\manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json).version
python (Join-Path $root 'scripts\package.py') --windows-payload
if ($LASTEXITCODE -ne 0) { throw 'Payload build failed.' }
$work = Join-Path ([IO.Path]::GetTempPath()) ('ai-edit-build-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    Add-Type -AssemblyName System.Drawing
    # ICO contains PNG frames at Windows shell sizes, using the same brand master.
    $source = [Drawing.Image]::FromFile((Join-Path $root 'assets\branding\windows-installer.png'))
    $frames = @()
    try {
        foreach ($size in @(16,24,32,48,64,128,256)) {
            $bitmap = New-Object Drawing.Bitmap($size,$size)
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            $memory = New-Object IO.MemoryStream
            try {
                $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.DrawImage($source,0,0,$size,$size)
                $bitmap.Save($memory,[Drawing.Imaging.ImageFormat]::Png)
                $frames += [pscustomobject]@{ Size=$size; Bytes=$memory.ToArray() }
            } finally { $graphics.Dispose(); $bitmap.Dispose(); $memory.Dispose() }
        }
    } finally { $source.Dispose() }
    $icon = Join-Path $work 'AppIcon.ico'
    $writer = New-Object IO.BinaryWriter([IO.File]::Create($icon))
    try {
        $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$frames.Count)
        $offset = 6 + 16 * $frames.Count
        foreach ($frame in $frames) {
            $dimension = if ($frame.Size -eq 256) { 0 } else { $frame.Size }
            $writer.Write([byte]$dimension); $writer.Write([byte]$dimension); $writer.Write([byte]0); $writer.Write([byte]0)
            $writer.Write([uint16]1); $writer.Write([uint16]32); $writer.Write([uint32]$frame.Bytes.Length); $writer.Write([uint32]$offset)
            $offset += $frame.Bytes.Length
        }
        foreach ($frame in $frames) { $writer.Write([byte[]]$frame.Bytes) }
    } finally { $writer.Dispose() }
    $attributes = Join-Path $work 'Version.cs'
    [IO.File]::WriteAllText($attributes,('[assembly: System.Runtime.Versioning.TargetFramework(".NETFramework,Version=v4.8", FrameworkDisplayName=".NET Framework 4.8")][assembly: System.Reflection.AssemblyVersion("' + $version + '.0")][assembly: System.Reflection.AssemblyProduct("Photoshop AI Edit Installer")][assembly: System.Reflection.AssemblyTitle("Photoshop AI Edit")][assembly: System.Reflection.AssemblyDescription("Install, update or uninstall the Photoshop AI Edit plugin for the current user.")]'))
    $framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
    $output = Join-Path $dist ('Photoshop-AI-Edit-' + $version + '-Windows-Setup.exe')
    $arguments = @('/nologo','/target:winexe','/platform:anycpu','/optimize+','/utf8output','/codepage:65001',('/out:'+$output),('/win32icon:'+$icon),('/win32manifest:'+(Join-Path $PSScriptRoot 'app.manifest')),
        ('/resource:'+(Join-Path $PSScriptRoot 'Main.xaml')+',Main.xaml'),
        ('/resource:'+(Join-Path $root 'assets\branding\windows-installer.png')+',Brand.png'),
        ('/resource:'+(Join-Path $dist 'windows-payload.zip')+',Payload.zip'))
    foreach ($reference in @('System.dll','System.Core.dll','System.Xaml.dll','System.IO.Compression.dll')) { $arguments += '/reference:'+(Join-Path $framework $reference) }
    foreach ($reference in @('WindowsBase.dll','PresentationCore.dll','PresentationFramework.dll')) { $arguments += '/reference:'+(Join-Path $framework ('WPF\'+$reference)) }
    $arguments += (Join-Path $PSScriptRoot 'Installer.cs'); $arguments += $attributes
    & (Join-Path $framework 'csc.exe') @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Windows GUI compilation failed.' }
    Copy-Item -LiteralPath $icon -Destination (Join-Path $dist ('Photoshop-AI-Edit-'+$version+'-Windows.ico')) -Force
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $output).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText(($output+'.sha256'),($hash+'  '+[IO.Path]::GetFileName($output)+"`n"))
    Write-Host ('Built: '+$output)
} finally { Remove-Item -LiteralPath $work -Recurse -Force }
