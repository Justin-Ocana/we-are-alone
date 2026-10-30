param([string]$Godot = "")
. "$PSScriptRoot\_godot.ps1"
$exe = Get-GodotExe $Godot
& $exe --headless --fixed-fps 60 --quit-after 120000 --path $ProjectDir -- --smoke-test
exit $LASTEXITCODE
