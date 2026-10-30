param([string]$Godot = "")
. "$PSScriptRoot\_godot.ps1"
$exe = Get-GodotExe $Godot
& $exe --headless --path $ProjectDir --import | Out-Null
& $exe --headless --path $ProjectDir -- --run-tests
exit $LASTEXITCODE
