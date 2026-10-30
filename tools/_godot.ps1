# Localiza el ejecutable de Godot 4.7.2 (parámetro -Godot, variable GODOT o carpeta padre del proyecto).
function Get-GodotExe([string]$Override) {
    if ($Override) { return $Override }
    if ($env:GODOT) { return $env:GODOT }
    $candidate = Join-Path (Split-Path $PSScriptRoot -Parent) "..\Godot_v4.7.2-stable_win64.exe"
    if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    throw "No se encontró Godot. Usa -Godot <ruta> o define la variable de entorno GODOT."
}
$ProjectDir = Split-Path $PSScriptRoot -Parent
