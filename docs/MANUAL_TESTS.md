# Pruebas manuales reproducibles

Lo que las pruebas automáticas no pueden comprobar (sensación con ratón y teclado reales, menús, juicio
visual). Ejecutar con `.\tools\play.ps1 -World moon` y anotar el resultado.

## Hito 2 — Nave

| # | Procedimiento | Resultado esperado | Estado |
|---|---|---|---|
| M1 | Al aparecer, mirar al este (la nave está a ~34 m). Caminar hasta la rampa y subir. | La puerta exterior se abre al acercarse (luz verde); se sube la rampa sin tropezar. | Pendiente del jugador |
| M2 | Entrar en la esclusa y esperar. | Se cierra la exterior, luces ámbar 2,5 s, se abre la interior. Nunca las dos abiertas. | Pendiente |
| M3 | Recorrer las 9 zonas (puertas automáticas). | Ninguna pared atravesable; no quedar atascado en el mobiliario; interiores iluminados. | Pendiente |
| M4 | En la cabina, acercarse al asiento, F. | Te sientas; se ven tus piernas y manos en los mandos; aparece la interfaz de pilotaje. | Pendiente |
| M5 | Espacio 3 s, soltar; W hasta ~100 m/s; mover el ratón. | Despega; acelera gradualmente; la palanca virtual gira la nave y vuelve sola al centro. | Pendiente |
| M6 | V. Mantener Alt y mover el ratón; Alt + rueda. | Vista exterior de la misma nave; órbita libre; zoom. V vuelve a la cabina. | Pendiente |
| M7 | Z (piloto automático), soltar todo 10 s; luego Q. | Mantiene rumbo y velocidad; Q lo desactiva y aparece el aviso. | Pendiente |
| M8 | Con el piloto automático activo, F (levantarse) y caminar por la nave. | Se camina con normalidad mientras la nave vuela; no te quedas atrás. | Pendiente |
| M9 | Volver al asiento, X, mantener Ctrl hasta posarse. | Descenso frenado cerca del suelo; "Nave posada"; rampa desplegada. | Pendiente |
| M10 | Salir por la esclusa y la rampa. | Ciclo inverso; fuera vuelve la gravedad lunar (saltos altos). | Pendiente |
| M11 | Esc pilotando, Reanudar. | El ratón vuelve a capturarse; la cámara correcta (cabina o exterior). | Pendiente |
| M12 | Subir a gran altitud, régimen 3 y luego 5 lejos del cuerpo (o pulsar 5 cerca). | Cerca: mensaje "Lumínico no disponible"; lejos: carga 3 s y se acerca a c; T para volver. | Pendiente |

Los mismos pasos están cubiertos de forma automática (con entradas simuladas) por `tools/ship_smoke.ps1`;
estas pruebas manuales evalúan la sensación y la legibilidad, que la automatización no puede juzgar.
