param([Parameter(Mandatory=$true)][string]$Executable, [Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class AIEditShellIcon {
    [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
    public static extern int SHDefExtractIcon(string file, int index, uint flags, out IntPtr large, out IntPtr small, uint size);
    [DllImport("user32.dll")]
    public static extern bool DestroyIcon(IntPtr icon);
}
'@
$large=[IntPtr]::Zero; $small=[IntPtr]::Zero
try {
    $result=[AIEditShellIcon]::SHDefExtractIcon((Resolve-Path -LiteralPath $Executable).Path,0,0,[ref]$large,[ref]$small,256)
    if ($result -ne 0 -or $large -eq [IntPtr]::Zero) { throw 'Windows shell could not extract the EXE icon.' }
    $icon=[Drawing.Icon]::FromHandle($large)
    $bitmap=$icon.ToBitmap()
    try {
        if ($bitmap.Width -ne 256 -or $bitmap.Height -ne 256) { throw 'EXE is missing its full-size 256px shell icon.' }
        # Brand icon must contain blue/cyan artwork, rather than a generic white EXE icon.
        $blue=0; $cyan=0
        for($y=0;$y -lt 256;$y+=4) { for($x=0;$x -lt 256;$x+=4) {
            $p=$bitmap.GetPixel($x,$y)
            if ($p.A -gt 100 -and $p.B -gt ($p.R+30)) { $blue++ }
            if ($p.A -gt 100 -and $p.G -gt 140 -and $p.B -gt 170 -and $p.R -lt 140) { $cyan++ }
        } }
        if ($blue -lt 500 -or $cyan -lt 50) { throw 'Extracted shell icon is missing the AI Edit brand colors.' }
        $bitmap.Save([IO.Path]::GetFullPath($Output),[Drawing.Imaging.ImageFormat]::Png)
        Write-Host 'Windows shell extracted the embedded 256px AI Edit icon from the EXE.'
    } finally { $bitmap.Dispose(); $icon.Dispose() }
} finally {
    if ($large -ne [IntPtr]::Zero) { [AIEditShellIcon]::DestroyIcon($large) | Out-Null }
    if ($small -ne [IntPtr]::Zero) { [AIEditShellIcon]::DestroyIcon($small) | Out-Null }
}
