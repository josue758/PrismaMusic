# Validación de Prisma Music 0.4.0

7 de noviembre de 2026. macOS 27.2, Apple Silicon, Xcode 27.2 y Swift 6.4.2.

## Resultado

- Compilación de producción completada; aplicación 0.4.0 instalada y abierta desde `/Applications/Prisma Music.app`.
- Suite: 18 pruebas registradas, 17 aprobadas, 1 omitida y 0 fallos. Se omite la consulta opt-in a internet; los proveedores no cambiaron y fueron verificados en 0.2.
- Se mantienen las pruebas de audio real de EQ, balance, velocidad y búsqueda temporal, la extracción de paletas y la migración de biblioteca/preferencias.

## Comprobaciones en la aplicación instalada

Se revisaron la biblioteca, la barra de reproducción y la transición hacia Escuchando. Se observó el indicador de sección y la carátula dentro de los límites de la vista.

Se marcó Órbita como favorita y se observó el aviso Añadida a favoritos con Deshacer. Al pulsar Deshacer, el corazón volvió al estado anterior y apareció Cambio deshecho. No quedó un favorito de prueba en la biblioteca.

Se utilizó la acción accesible Decrement de la nueva barra temporal: la posición pasó del final de la pista a aproximadamente 19 segundos. Increment la devolvió al final. Se comprobaron su etiqueta, valor temporal, ayuda y las acciones Increment/Decrement. El control ofrece previsualización bajo el cursor y arrastre mediante gestos nativos; la validación automatizada de UI de esta sesión utilizó las acciones accesibles, no una medición de precisión del arrastre.

Se dejó abierta la vista de escucha. No se cambiaron las preferencias globales de accesibilidad del Mac.

## Pruebas nuevas

- El reloj visual acumula únicamente el tiempo activo. Pausar, esperar y reanudar no cambia la fase; iniciar o detener repetidamente no la reinicia.
- Deshacer rechaza el identificador de un aviso antiguo y solo revierte la acción vigente. Si la reproducción ya avanzó a la canción añadida, deshacer la cola conserva la canción activa.
- Deshacer una eliminación de playlist recupera su identidad, contenido y posición y lo conserva al volver a cargar la biblioteca.
- La migración agrega las preferencias nuevas de interacción, profundidad y avisos sin cambiar el EQ, la velocidad, la pantalla de inicio ni los ajustes anteriores.

## Cobertura conservada

Filtros y acentos; LRC; metadatos y propiedades técnicas de tres M4A reales; favoritos y etiquetas editadas; ubicaciones desconectadas y archivos borrados; consultas codificadas a proveedores; playlists, cola y temporizador; migración desde 0.1; paletas dominantes, imágenes monocromas/transparentes y contraste de referencia; EQ real con una señal de 1 kHz; y M4A/AAC mono a 22,05 kHz procesado a 1,25× con conversión estéreo, balance y salto a una posición concreta.

## Movimiento y accesibilidad

Las animaciones de interacción son independientes del movimiento ambiental. Reducir movimiento suprime escala, paralaje y desplazamientos de transición. La barra permite ajuste de cinco segundos con flechas sin modificadores, conserva los comandos con Comando y ofrece acciones accesibles de incremento/decremento. La posición de arrastre se confirma al soltar; no se reinicia el motor por cada movimiento del cursor.

Los efectos de hover y las ramas de accesibilidad se revisaron en código y compilan con el SDK nativo. No se realizó una medición de FPS/GPU ni una auditoría completa de accesibilidad; no se afirma que esas comprobaciones estén completadas.

## Límites

Queda pendiente la conexión con los NAS del usuario, la prueba de colecciones grandes y de todos sus formatos y la validación en otros Mac. El paquete es arm64, requiere macOS 26+, tiene firma ad hoc y no está notarizado. No incluye modo exclusivo, garantía bit-perfect, crossfade ni ReplayGain. El minirreproductor sigue siendo una ventana flotante para audio. Las etiquetas editadas se guardan en la biblioteca sin modificar los originales.
