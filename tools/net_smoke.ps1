# Prueba de red con tres procesos (ADR-044/046/047): anfitrión e invitados por 127.0.0.1.
# Sin --fixed-fps: con él, el anfitrión en la sala (sin mundo) no llega a aceptar conexiones ENet; la prueba usa tiempo real.
$godot = Join-Path $PSScriptRoot "..\..\Godot_v4.7.2-stable_win64.exe"
$proj = Join-Path $PSScriptRoot ".."
$h = Start-Process -FilePath $godot -ArgumentList "--headless","--path",$proj,"--","--net-smoke=host" -PassThru -NoNewWindow
Start-Sleep -Seconds 4
$j2 = Start-Process -FilePath $godot -ArgumentList "--headless","--path",$proj,"--","--net-smoke=join2" -PassThru -NoNewWindow
& $godot --headless --path $proj -- --net-smoke=join
$j2.WaitForExit(60000) | Out-Null
$h.WaitForExit(60000) | Out-Null
