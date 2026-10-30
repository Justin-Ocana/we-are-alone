param([string]$World = "", [string]$Godot = "")
. "$PSScriptRoot\_godot.ps1"
$exe = Get-GodotExe $Godot
$userArgs = @()
if ($World) { $userArgs = @("--", "--world=$World") }
& $exe --path $ProjectDir @userArgs
