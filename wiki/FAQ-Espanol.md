# Preguntas frecuentes

## ¿Funciona con cualquier auricular inalámbrico?

No se puede garantizar. `WindowsEndpoint` funciona cuando Windows expone un estado físico útil. Si no puede observar una señal segura, AutoSwitch no cambia la salida (comportamiento *fail closed*).

## ¿Por qué la familia Logitech PRO X necesita otro método?

Su endpoint puede seguir `Active` con el auricular apagado, así que el estado del endpoint por sí solo no distingue ON/OFF. Por eso existe la salida alternativa de G HUB para PRO X, PRO X 2 y PRO X Wireless.

## ¿El Arctis Nova 5/5X de SteelSeries necesita su software?

No. AutoSwitch lee el estado físico del receptor por HID, así que no se requiere SteelSeries GG.

## ¿AutoSwitch se ejecuta como administrador?

No durante el uso normal. Solo el asistente elevado de alcance limitado de Audio Enhancements solicita UAC cuando hace falta.

## ¿Puedo copiar config.json a otro PC?

No. Los Item ID de Windows son locales a cada equipo.

## ¿El WebSocket de G HUB es oficial?

No. Es una interfaz local obtenida por ingeniería inversa y puede cambiar.

## ¿Hay documentación en inglés?

Sí. Empieza en [[Home]].
