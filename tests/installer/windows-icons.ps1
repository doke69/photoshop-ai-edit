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
foreach ($size in @(16,24,32,48,64,128,256)) {
    $large=[IntPtr]::Zero; $small=[IntPtr]::Zero
    try {
        $result=[AIEditShellIcon]::SHDefExtractIcon((Resolve-Path -LiteralPath $Executable).Path,0,0,[ref]$large,[ref]$small,$size)
        if ($result -ne 0 -or $large -eq [IntPtr]::Zero) { throw ('Windows shell could not extract the EXE icon at '+$size) }
        $icon=[Drawing.Icon]::FromHandle($large); $bitmap=$icon.ToBitmap()
        try {
            if ($bitmap.Width -ne $size -or $bitmap.Height -ne $size) { throw 'Missing native icon size.' }
            $near=[int][Math]::Floor($size/10); $far=[int][Math]::Floor(9*$size/10); $mid=[int][Math]::Floor($size/2)
            $probes=@(@(0,0),@(($size-1),0),@(0,($size-1)),@(($size-1),($size-1)),@($mid,0),@($mid,($size-1)),@(0,$mid),@(($size-1),$mid),@($near,$near),@($far,$near),@($near,$far),@($far,$far))
            foreach ($point in $probes) {
                $alpha=$bitmap.GetPixel([int]$point[0],[int]$point[1]).A
                if ($alpha -gt 10) { throw ('Opaque exterior / uncut rounded corner in '+$size+'px icon at '+$point[0]+','+$point[1]+': alpha='+$alpha) }
            }
            if ($bitmap.GetPixel($mid,$mid).A -lt 240) { throw 'Icon body is incorrectly transparent.' }
            $blue=0; $cyan=0; $sampled=0; $step=[Math]::Max(1,[int][Math]::Floor($size/64))
            for($y=0;$y -lt $size;$y+=$step) { for($x=0;$x -lt $size;$x+=$step) {
                $p=$bitmap.GetPixel($x,$y);$sampled++
                if ($p.A -gt 100 -and $p.B -gt ($p.R+30)) { $blue++ }
                if ($p.A -gt 100 -and $p.G -gt 140 -and $p.B -gt 170 -and $p.R -lt 140) { $cyan++ }
            } }
            if ($blue -lt $sampled*0.15 -or $cyan -lt $sampled*0.008) { throw 'Extracted icon is missing the AI Edit brand colors.' }
            $destination=if ($size -eq 256) { [IO.Path]::GetFullPath($Output) } else { Join-Path (Split-Path $Output -Parent) ('windows-shell-icon-'+$size+'.png') }
            $bitmap.Save($destination,[Drawing.Imaging.ImageFormat]::Png)
            Write-Host ('PASS Windows shell '+$size+'px: transparent exterior, rounded corners, opaque body and brand colors.')
        } finally { $bitmap.Dispose(); $icon.Dispose() }
    } finally {
        if ($large -ne [IntPtr]::Zero) { [AIEditShellIcon]::DestroyIcon($large) | Out-Null }
        if ($small -ne [IntPtr]::Zero) { [AIEditShellIcon]::DestroyIcon($small) | Out-Null }
    }
}
