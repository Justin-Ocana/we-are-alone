# Genera el paquete para compartir (ronda 14): build/WeAreAlone.exe + WeAreAlone.pck + LEEME.txt y un .zip.
# Sin plantillas de exportación: el .exe es el binario oficial de Godot 4.7.2 renombrado, que carga automáticamente
# el .pck con su mismo nombre. Con las plantillas instaladas se podría exportar un .exe más pequeño y rápido.
$godot = Join-Path $PSScriptRoot "..\..\Godot_v4.7.2-stable_win64.exe"
$proj = Join-Path $PSScriptRoot ".."
$out = Join-Path $proj "build"
New-Item -ItemType Directory -Force $out | Out-Null
if (-not (Test-Path (Join-Path $out ".gdignore"))) { New-Item -ItemType File (Join-Path $out ".gdignore") | Out-Null }
# Start-Process -Wait: Godot es una aplicación de ventana y PowerShell no esperaría a que acabe la exportación.
$pck = Join-Path $out "WeAreAlone.pck"
if (Test-Path $pck) { Remove-Item $pck -Force }
Start-Process -FilePath $godot -ArgumentList "--headless", "--path", "`"$proj`"", "--export-pack", "`"Windows Desktop`"", "`"$pck`"" -Wait -NoNewWindow
if (-not (Test-Path $pck)) { Write-Host "ERROR: no se generó el .pck"; exit 1 }
Copy-Item $godot (Join-Path $out "WeAreAlone.exe") -Force
Copy-Item (Join-Path $PSScriptRoot "LEEME_AMIGOS.txt") (Join-Path $out "LEEME.txt") -Force
$zip = Join-Path $out "WeAreAlone.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $out "WeAreAlone.exe"), (Join-Path $out "WeAreAlone.pck"), (Join-Path $out "LEEME.txt") -DestinationPath $zip
Write-Host "Listo: $zip"
