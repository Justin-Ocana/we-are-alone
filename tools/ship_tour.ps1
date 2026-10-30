param([string]$Quality = "", [switch]$NoVsync, [string]$Godot = "")
. "$PSScriptRoot\_godot.ps1"
$exe = Get-GodotExe $Godot
$userArgs = @("--", "--ship-tour")
if ($NoVsync) { $userArgs += "--novsync" }
if ($Quality) { $userArgs += "--quality=$Quality" }
& $exe --path $ProjectDir @userArgs
Write-Host "Capturas y resultados en: $env:APPDATA\WeAreAlone\bench (ship_*.png)"
