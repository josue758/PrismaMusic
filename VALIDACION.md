# Validación de Prisma Music 0.3.0

Fecha: 7 de noviembre de 2026. macOS 27.2, Apple Silicon, Xcode 27.2, Swift 6.4.2.

## Resultado

- Compilación de producción completada. Versión 0.3.0 instalada y abierta desde `/Applications/Prisma Music.app`.
- Suite: 15 pruebas registradas, 14 aprobadas, 1 omitida y 0 fallos. La prueba omitida es la consulta opt-in a proveedores de internet, cuya implementación no cambió en 0.3 y que pasó en la validación de 0.2.
- Se conservaron las pruebas de audio reales con EQ, balance, velocidad, búsqueda temporal y reproducción de M4A/AAC y WAV/PCM.

## Revisión en la aplicación instalada

Se observó la nueva vista Escuchando con carátula grande, datos de la canción, controles de reproducción y fondo difuminado. Se inició reproducción y se pasó de Luz de agua (paleta violeta/rosa) a Órbita (paleta turquesa). Se comprobó el cambio de carátula, colores, acentos y fondo, junto con el avance de posición y la detención al terminar la cola.

Se abrió Ajustes → Apariencia desde Luz ambiental y se comprobaron los interruptores de colores adaptativos, movimiento de fondo y movimiento de carátula, los controles de transparencia y luz ambiental y la indicación de la procedencia de la paleta. Las piezas demo no contienen una carátula incrustada: usan su portada vectorial y la interfaz muestra PALETA GENERATIVA. La extracción de una carátula de imagen real se verifica mediante las pruebas descritas abajo.

Después de empaquetar se volvió a abrir la compilación final. Se comprobó que conservaba la pantalla Inicio previamente elegida y que Escuchando abría la vista inmersiva. Se dejó esa vista abierta, con la biblioteca y el EQ conservados.

## Pruebas nuevas de la versión 0.3

1. Paleta a partir de una imagen PNG creada en memoria, con áreas rojas y cian y un borde blanco. Comprueba que el color dominante y el secundario proceden de los píxeles reales, que son distintos y que el resultado es determinista.
2. Imágenes negras, transparentes y datos inválidos: conserva paletas monocromas reales y solo usa la paleta generativa cuando no hay píxeles utilizables o no se puede decodificar la imagen.
3. Legibilidad del color de acento: comprueba contraste mínimo de 4,5:1 con los fondos de referencia claro y oscuro. Esta prueba no sustituye una auditoría de contraste sobre todas las posiciones de un fondo animado.
4. Migración de preferencias 0.2 sin las nuevas claves visuales: conserva preset y bandas del EQ, velocidad, densidad y ajuste de letras, y agrega los valores predeterminados de las nuevas opciones.

## Pruebas existentes

- Filtros combinados, búsqueda sin acentos y favoritos.
- Parser de letras LRC y múltiples marcas por línea.
- Metadatos de tres audios reales y propiedades de formato, bitrate, tamaño, frecuencia y canales.
- Persistencia de etiquetas editadas, favoritos y biblioteca; comportamiento con una ubicación desconectada o un archivo borrado.
- Codificación y normalización de las consultas a proveedores.
- Playlists, cola, aleatorio, preferencias, clasificación sin pérdida y temporizador.
- Migración del JSON de biblioteca 0.1.
- Renderizado offline que verifica atenuación real de una señal de 1 kHz con el EQ.
- M4A/AAC mono a 22,05 kHz procesado a 1,25×, EQ, conversión estéreo, balance por canal y salto a cinco segundos.

## Diseño, privacidad y límites

La paleta se obtiene de una miniatura de 48 píxeles en una tarea de segundo plano; no se envía la imagen a servicios externos. Al cambiar la canción se descartan los resultados de extracciones anteriores. Se reutiliza la imagen decodificada mientras no cambie la carátula.

El movimiento se modula con RMS real suavizado, con un límite de 24 fps. No se anuncia detección de tempo ni sincronización con cada beat. El fondo y la portada pueden desactivarse por separado y respetan Reducir movimiento. Reducir transparencia retira la decoración de fondo y usa materiales más opacos. Estas ramas de accesibilidad se revisaron en código; no se cambiaron las preferencias globales del Mac durante la prueba.

Pendiente: NAS reales del usuario, colecciones grandes, todos los códecs/variantes de etiquetas y otros Mac. El instalador es arm64, requiere macOS 26+, tiene firma ad hoc y no está notarizado para distribución pública. No incorpora modo exclusivo, garantía de salida bit-perfect, crossfade ni ReplayGain. El PiP sigue siendo un minirreproductor flotante de audio; las etiquetas editadas se guardan en la biblioteca, sin reescribir los archivos originales.
