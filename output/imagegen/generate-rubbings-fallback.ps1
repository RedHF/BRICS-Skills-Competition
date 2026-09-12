param(
    [string]$OutDir = (Join-Path $PSScriptRoot 'fallback-rubbings')
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$items = @(
    @{ Name='she_cheng_xiang'; Kind='dougong' },
    @{ Name='she_ning_an'; Kind='door' },
    @{ Name='she_hui_chun'; Kind='drum' },
    @{ Name='xi_xing_qiang'; Kind='stage' },
    @{ Name='xi_jue_chang'; Kind='robe' },
    @{ Name='fang_wu_ming'; Kind='paifang' },
    @{ Name='fang_jiang_hun'; Kind='joint' },
    @{ Name='tower_origin'; Kind='tower' },
    @{ Name='tower_epilogue'; Kind='ledger' }
)
function L([System.Drawing.Graphics]$g, [System.Drawing.Pen]$p, [int]$x1,[int]$y1,[int]$x2,[int]$y2) { $g.DrawLine($p,$x1,$y1,$x2,$y2) }
function P([System.Drawing.Graphics]$g, [System.Drawing.Pen]$p, [int[]]$coords) { $pts = [Drawing.Point[]]::new($coords.Count / 2); for($j=0;$j -lt $pts.Count;$j++){ $pts[$j] = [Drawing.Point]::new($coords[$j*2],$coords[$j*2+1]) }; $g.DrawPolygon($p,$pts) }
foreach ($item in $items) {
    $bmp = New-Object Drawing.Bitmap 1024,1536
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([Drawing.Color]::FromArgb(246,240,218))
    $ink = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(35,55,58)), 8
    $fine = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(69,91,88)), 4
    $gold = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(161,126,62)), 5
    $verm = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(155,61,47)), 7
    $g.DrawRectangle($gold,46,46,932,1444)
    $g.DrawRectangle($fine,72,72,880,1392)
    for($y=120;$y -lt 1420;$y+=38){ $g.DrawLine((New-Object Drawing.Pen ([Drawing.Color]::FromArgb(232,222,194)),1),90,$y,934,$y) }
    switch ($item.Kind) {
      'dougong' { for($i=0;$i -lt 5;$i++){ $x=190+$i*150; $g.DrawRectangle($ink,$x,500-$i*22,150,46); L $g $fine ($x+18) (546-$i*22) ($x+132) (650-$i*18); L $g $fine ($x+132) (546-$i*22) ($x+18) (650-$i*18) }; $g.DrawEllipse($gold,430,860,164,164); L $g $verm 512 1024 512 1260 }
      'door' { $g.DrawRectangle($ink,220,300,584,850); $g.DrawRectangle($fine,278,410,468,740); L $g $gold 278 410 746 410; $g.DrawEllipse($verm,450,810,24,24); for($i=0;$i -lt 7;$i++){L $g $fine (270+$i*70) 1040 (270+$i*70) 1170} }
      'drum' { $g.DrawEllipse($ink,180,420,664,420); $g.DrawEllipse($gold,215,455,594,350); L $g $verm 300 350 690 910; L $g $verm 720 350 335 910; for($i=0;$i -lt 10;$i++){ $a=$i*36; $g.DrawArc($fine,240+$a/3,510+$a/8,544-$a/2,250,210,120) } }
      'stage' { L $g $ink 150 980 874 980; L $g $ink 190 650 834 650; L $g $ink 220 650 180 1050; L $g $ink 804 650 844 1050; $g.DrawArc($gold,270,420,484,360,180,180); L $g $verm 470 690 390 930; L $g $verm 550 690 630 930; $g.DrawEllipse($fine,735,720,80,80) }
      'robe' { L $g $ink 250 1050 770 1050; P $g $ink @(390,520,635,520,760,1070,260,1070); L $g $gold 512 520 512 1060; $g.DrawEllipse($verm,492,700,40,40); L $g $fine 300 1150 720 1150 }
      'paifang' { foreach($x in @(220,470,720)){ $g.DrawRectangle($ink,$x,360,70,760) }; L $g $ink 180 360 844 360; L $g $gold 180 300 844 300; $g.DrawArc($fine,210,420,590,300,180,180); L $g $verm 160 1160 860 1160 }
      'joint' { $g.DrawRectangle($ink,190,650,560,150); $g.DrawRectangle($gold,510,500,150,460); L $g $verm 220 610 720 610; L $g $fine 220 840 720 840; for($i=0;$i -lt 8;$i++){ $g.DrawEllipse($fine,170+$i*90,1040,36,18) } }
      'tower' { for($i=0;$i -lt 7;$i++){ $x=300-$i*18; $y=1100-$i*105; $w=424+$i*36; P $g $ink @($x,$y,($x+$w),$y,($x+$w-56),($y-72),($x+56),($y-72)); L $g $fine ($x+40) ($y-72) ($x+$w-40) ($y-72) }; $g.DrawEllipse($verm,470,1180,84,84) }
      'ledger' { P $g $ink @(170,420,510,500,510,1170,170,1090); P $g $ink @(510,500,850,420,850,1090,510,1170); for($i=0;$i -lt 8;$i++){L $g $fine (220+$i*35) (600+$i*45) (470+$i*5) (600+$i*45); L $g $fine (550+$i*5) (600+$i*45) (800-$i*35) (600+$i*45)}; L $g $verm 510 540 510 1130 }
    }
    $g.Dispose(); $bmp.Save((Join-Path $OutDir ($item.Name+'.png')),[Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); $ink.Dispose(); $fine.Dispose(); $gold.Dispose(); $verm.Dispose()
}
Write-Output "Generated $($items.Count) fallback static rubbing images in $OutDir"
