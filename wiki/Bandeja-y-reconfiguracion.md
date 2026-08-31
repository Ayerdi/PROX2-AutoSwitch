# Bandeja y reconfiguración

La bandeja muestra auricular, salida alternativa y el próximo cambio esperado.

Permite:

- activar/desactivar AutoSwitch; en PRO X 2 el estado y la batería por HID directo siguen actualizándose mientras AutoSwitch está pausado, pero no se cambia ninguna salida de audio;
- deshabilitar/habilitar Audio Enhancements con UAC solo para el helper elevado;
- ejecutar `Reconfigure...` y validar un nuevo ciclo ON → OFF → ON;
- salir.

La reconfiguración tolera la latencia real de Bluetooth y puede refrescar el Item ID si Windows recrea el endpoint.

[[Tray-and-Reconfiguration|Read in English]]


## PRO X 2 en v1.5.0

Logitech PRO X 2 LIGHTSPEED usa Centurion HID directo para conocer el estado físico ON/OFF y el porcentaje de batería. El valor de configuración sigue siendo `LogitechGHub` por compatibilidad, pero ya no se usa la ruta eliminada `/battery/<deviceId>/state` de G HUB para detectar el estado del PRO X 2. Una lectura HID desconocida nunca cambia el audio y el apagado sigue necesitando varias observaciones confirmadas.
