param([string]$World = "proto_a", [switch]$NoVsync, [string]$Godot = "")
. "$PSScriptRoot\_godot.ps1"
$exe = Get-GodotExe $Godot
$userArgs = @("--", "--benchmark", "--world=$World")
if ($NoVsync) { $userArgs += "--novsync" }
& $exe --path $ProjectDir @userArgs
Write-Host "Resultados y capturas en: $env:APPDATA\WeAreAlone\bench"
