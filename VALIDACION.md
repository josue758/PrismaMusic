# Validación de Prisma Music 0.7.0

8 de noviembre de 2026. macOS, Apple Silicon, compilación nativa Swift/SwiftUI para macOS 26 o posterior.

## Pruebas automatizadas

40 pruebas aprobadas, 0 omitidas, 0 fallos, con `PRISMA_LIVE_NETWORK=1`, un FLAC de un NAS SMB montado y un inventario independiente como referencia. Las tres comprobaciones externas se omiten en una ejecución sin esas opciones. No se publican nombres ni rutas de la colección personal.

El recorrido nativo encontró exactamente los mismos 7.854 archivos que el inventario independiente: 7.487 FLAC y 367 M4A. No hubo diferencias de conjuntos ni errores de directorio en esa prueba. Tiempo de recorrido en la ejecución final: 50,7 segundos; depende del servidor y sus cachés.

La prueba de reproducción abrió un FLAC real directamente por SMB, decodificó audio con AVAudioEngine, comprobó energía, salto temporal a 30 segundos, pausa y reanudación. El archivo de prueba era estéreo, 24 bits/96 kHz, con bitrate estimado de 2.960.172 bit/s. Se renderizó sin activar los altavoces. Esto no certifica cada muestra de audio de la colección.

La bienvenida tiene pruebas de migración y persistencia, finalización, reapertura desde Ajustes y conservación del ecualizador al aplicar estilos. El reintento selectivo recupera un audio de prueba reparado y conserva registros ajenos al reintento, incluso si sus originales ya no están presentes.

También se cubren importación paralela de 48 archivos, omisión de archivos sin cambios, edición y favoritos durante la lectura, concurrencia configurable, cancelación, cierre durante la carga inicial, carpetas inaccesibles, fuentes superpuestas, cambios de identidad, paquetes/enlaces/ocultos, archivos auxiliares sin distinguir mayúsculas, comentarios Vorbis Unicode, fechas, letras e imágenes FLAC, rechazo de cabeceras llenas de ceros, corrupción SQLite/JSON, migración, imágenes deduplicadas, escritura incremental, filtros, playlists, cola, EQ renderizado, balance, velocidad, temporizador, paletas, contraste, reloj visual y Deshacer.

La prueba de escritura inicial de 10.000 registros tardó aproximadamente 0,05 segundos en una ejecución local. No mide importación de audio ni latencia de red. Las cachés usan objetivos orientativos de 8 MiB comprimidos y 32 MiB de imágenes decodificadas; no son un límite de RAM total.

## Biblioteca personal

La lectura completa inicial incorporó 7.813 de 7.854 archivos. Las 41 entradas restantes coincidían exactamente con las rutas del informe de errores; no hubo entradas adicionales. Al menos un archivo que falló contenía una cabecera llena de ceros y fue rechazado también por AVFoundation. No se modificaron los audios originales. El reintento selectivo confirmó las mismas 41 incidencias y no eliminó ninguna de las 7.813 canciones: 18 rutas listadas por el NAS no se pudieron abrir porque el sistema devolvió archivo inexistente, 17 archivos tenían sus primeros 16 bytes a cero y 6 devolvieron lectura vacía. Estos resultados se comprobaron además con lecturas independientes de solo lectura. No se sustituyeron ni borraron archivos del servidor.

## Revisión instalada

Se instaló y abrió la 0.7.0 con la biblioteca personal. Se verificaron la bienvenida, el cambio inmediato entre español, inglés y portugués, su reapertura desde Ajustes, el acceso al editor de etiquetas y al formulario NAS, la biblioteca con 7.813 canciones y el progreso de escaneo. Se amplió la barra lateral para evitar recortar «Canciones» junto al contador y se actualizó la identificación visual de versión.

Una muestra puntual durante la exploración con la colección completa indicó unos 296 MiB de memoria residente y 12,8 % de CPU. Es una observación de ese instante, no una garantía de consumo ni una medición de pico. Las pruebas automatizadas cubren los estilos y su conservación de los ajustes de sonido; no se comprobó cada control en todas sus combinaciones.

## Límites de la distribución

El instalador es arm64, requiere macOS 26 o posterior y usa firma ad hoc. Falta Developer ID y notarización. No hay pruebas Intel ni garantía de ausencia de errores. La apertura inicial del decodificador y algunas llamadas SMB pueden tardar si el servidor no responde, incluso después de solicitar cancelación. No se expulsó el volumen durante la reproducción para simular una desconexión.

Las correcciones de etiquetas se guardan en Prisma sin escribir en el audio original. Los informes y las copias JSON contienen rutas personales; no se incluyen en el repositorio ni en el instalador. El informe conserva hasta 500 detalles de error, además de los contadores completos. No hay restauración guiada de copias desde la interfaz.
