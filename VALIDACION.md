# Validación de Prisma Music 0.5.1

7 de noviembre de 2026. macOS 27.2, Apple Silicon, Xcode 27.2 y Swift 6.4.2.

## Pruebas automatizadas

29 pruebas aprobadas, 0 omitidas, 0 fallos. Se activaron `PRISMA_LIVE_NETWORK=1` y `PRISMA_NAS_FILE` apuntando a un archivo FLAC del NAS SMB montado. Las pruebas comunes omiten las dos verificaciones externas cuando no se proporcionan esas variables. Los nombres y rutas de la colección personal no se incluyen en este informe.

La prueba NAS leyó metadatos y decodificó audio real en AVAudioEngine a través de SMB, sin copiar el archivo completo al disco local. Comprobó energía de salida, avance temporal, salto a 30 segundos, pausa y reanudación. Resultado del archivo utilizado: FLAC, 96.000 Hz, estéreo, 24 bits, 2.959.692 bit/s estimados. El renderizado de la prueba fue offline y no activó los altavoces.

Nuevas regresiones: una subcarpeta sin permisos hace incompleta la exploración y al recuperar permisos vuelve a leerse; dos fuentes superpuestas conservan una sola canción y retirar una de ellas no la borra si la otra la cubre; un audio dañado conserva el registro y el favorito previos; una base SQLite corrupta impide el reemplazo automático y mantiene sus bytes; los filtros y estadísticas se actualizan tras editar canciones y playlists; el progreso informa el total final y una cancelación previa impide recorrer los archivos. Un FLAC sintético de 24 bits valida la profundidad de origen y el bitrate.

Se mantiene la cobertura de migración, imágenes deduplicadas, escritura incremental, biblioteca JSON corrupta, 10.000 registros, guardado consolidado, filtros y acentos, letras LRC, metadatos, EQ renderizado, balance estéreo, velocidad, seek, playlists, cola, temporizador, paletas, contraste, reloj visual y Deshacer. Escritura inicial de 10.000 registros: aproximadamente 0,06 s en una ejecución local de desarrollo; no mide importación de audio ni latencia de red.

## Pruebas con la app instalada

Se reprodujo un FLAC del NAS con avance del contador. Se usó el salto temporal accesible, se abrió el minirreproductor flotante y se pausó desde él. Se canceló una exploración de la colección y la pista existente permaneció disponible. Se exportó una copia JSON mediante el panel nativo y se verificó que contenía la pista y su carátula embebida. La copia de prueba permanece fuera del repositorio.

La revisión visual detectó que una colección con un solo álbum estiraba demasiado la portada destacada. Se conserva ahora la cuadrícula de tres columnas. Se verificaron en la 0.5.1 instalada el tamaño de las portadas y el avance del contador de exploración del NAS. La lectura completa de la colección aún estaba en curso al cerrar esta comprobación. Se añaden progreso de exploración y cancelación en la barra inferior, y bits/kHz en la escucha inmersiva cuando se actualizan sus metadatos. La telemetría baja de 30 a 15 Hz sin cambiar el reloj independiente de las animaciones.

La carga de sesión se recupera antes del escaneo y solo se vuelve a intentar si no hay un reproductor ni una canción activa; así no reemplaza la selección iniciada durante la lectura. La búsqueda de carátulas y letras no reemplaza el mensaje de progreso del escaneo.

Una muestra puntual de la versión 0.5.0 tras la prueba NAS indicó huella física de 175,5 MiB y pico de 296,1 MiB; no es una medición de toda la colección ni una garantía de consumo. Las cachés tienen objetivos orientativos de 8 MiB de datos comprimidos y 32 MiB de imágenes decodificadas. Los registros de biblioteca guardan referencias a carátulas compartidas.

## Alcance pendiente

Se validó un archivo FLAC real por SMB, no toda la colección ni todos los códecs del NAS. No se expulsó el volumen durante la reproducción ni se alteraron archivos del servidor para simular fallos. La cobertura de desconexión y permisos utiliza directorios de prueba locales. Las llamadas al servidor o al decodificador pueden tardar antes de devolver el control al cancelar; todavía hay apertura inicial del decodificador en el hilo principal. No se garantiza ausencia de errores ni un límite fijo de RAM.

El instalador es arm64, requiere macOS 26 o posterior y usa firma ad hoc. Falta Developer ID y notarización para distribución pública convencional. No hay pruebas Intel ni una auditoría exhaustiva de todos los controles en todos los estados. Las etiquetas editadas se conservan en Prisma y no modifican el audio original. Las copias JSON incluyen rutas y carátulas, no el audio; no existe restauración guiada desde la interfaz.

Repositorio: https://github.com/josue758/PrismaMusic. La beta 0.5.0 se conserva como versión histórica; las mejoras se distribuyen en 0.5.1.
