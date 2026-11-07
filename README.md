# Prisma Music

Reproductor nativo para macOS, escrito en Swift y SwiftUI. Versión beta local **0.5.0** para probar e iterar.

[Descargar la versión 0.5.0 beta para Apple Silicon](https://github.com/josue758/PrismaMusic/releases/tag/v0.5.0) · [Ver el código](https://github.com/josue758/PrismaMusic)

## Instalar y probar

Requiere **macOS 26 o posterior**. El instalador incluido contiene una compilación para **Apple Silicon**.

1. Abre `Prisma-Music-0.5.0.dmg` y arrastra **Prisma Music** a **Aplicaciones**.
2. Abre la aplicación. Incluye tres piezas instrumentales originales de 24 segundos, etiquetadas y listas para reproducir.
3. Pulsa **Añadir música** o `⌘O`: puedes elegir archivos, carpetas y volúmenes de red.
4. Haz doble clic en una canción o pulsa el botón de reproducción. También puedes abrir archivos de audio con la aplicación desde Finder.

En este Mac se actualiza en `/Applications/Prisma Music.app`. Si Prisma estaba abierta, ciérrala por completo (`⌘Q`) y vuelve a abrirla para cargar la versión 0.5. La actualización conserva tus datos.

## Novedades de la versión 0.5

- Guardado incremental en segundo plano, con transacciones SQLite y consolidación de cambios pendientes. Al salir se espera la escritura; un error impide cerrar sin avisar.
- Migración desde JSON que conserva una copia `library-v0.4-backup.json`. Una biblioteca dañada muestra un error y bloquea el reemplazo automático.
- Carátulas compartidas por contenido, reducidas hasta 1024 px. Cachés con objetivos de 8 MiB para datos y 32 MiB para imágenes decodificadas; son límites orientativos de NSCache, no una garantía de RAM total.
- Filtros, agrupaciones y estadísticas reutilizan resultados mientras no cambien los datos. En pausa se evitan publicaciones continuas de posición y nivel sin cambios.
- Una lectura incompleta, cancelada o de una ubicación que cambió de identidad conserva las entradas existentes. El escaneo permite cancelar y muestra el estado de cada fuente. No se monta un NAS automáticamente al restaurar bookmarks.
- Abrir un audio desde Finder lo importa y reproduce. Reproducir/pausar usa `⇧⌘P`, evitando capturar los espacios de la búsqueda. Las copias JSON incorporan sus carátulas y se escriben en segundo plano.
- Respuestas de proveedores limitadas a 8 MiB y cancelables.

El NAS real del usuario sigue pendiente de validación: debe montarse en Finder o indicarse la dirección `smb://servidor/carpeta`. Las pruebas con directorios locales no sustituyen la prueba de streaming por red. La apertura inicial del decodificador y algunas operaciones del sistema pueden tardar si el servidor no responde.

## Novedades de la versión 0.4

Esta versión refina la respuesta de la interfaz:

- Transiciones suaves entre biblioteca, escucha y visualizador; el indicador de selección acompaña el cambio de sección. Los paneles laterales aparecen con una transición breve.
- Carátulas y tarjetas con iluminación y profundidad sutil al pasar el cursor. Los botones responden a la presión y los corazones cambian de estado con una animación corta.
- Fundido entre portadas al cambiar de canción, también en la barra inferior y el minirreproductor. El icono de reproducción cambia con una transición nativa.
- El fondo y la carátula conservan la fase de su movimiento al pausar; al reanudar continúan desde allí, sin volver a una posición inicial.
- Barra temporal con previsualización de tiempo bajo el cursor. Al arrastrar, la posición se confirma al soltar para evitar reiniciar el audio en cada movimiento. Una vez enfocada permite saltos de cinco segundos con las flechas; conserva los atajos de siguiente/anterior con Comando.
- Avisos breves para favoritos, cola y playlists, con **Deshacer** en las acciones compatibles. Una eliminación de playlist puede deshacerse durante el aviso. Las acciones antiguas no pueden deshacer un aviso más reciente, y deshacer un cambio de cola conserva la canción activa.

Los controles **Animaciones de la interfaz**, **Profundidad al pasar el cursor** y **Avisos breves con Deshacer** están en Ajustes → Apariencia. El movimiento de fondo sigue teniendo sus propios controles. La opción global **Reducir movimiento** retira las transiciones espaciales y el paralaje. No se agregan sonidos de interfaz que interrumpan la música.

## Novedades de la versión 0.3

La nueva vista **Escuchando** da protagonismo a la carátula, con un fondo difuminado, cristal más transparente y una paleta que sigue a la canción. Se abre desde la barra lateral, el botón de escucha inmersiva o haciendo clic en la carátula del reproductor. Puedes elegirla como pantalla de inicio en Ajustes → Apariencia. Se conserva la pantalla de inicio que ya tuvieras configurada; las instalaciones nuevas comienzan en la vista inmersiva.

Los colores se extraen de la carátula local en segundo plano, sin enviar la imagen a servicios externos. Una transición suave acompaña los cambios de canción. Cuando no hay imagen, se utiliza la paleta de la portada generativa de Prisma; la interfaz indica su procedencia. Las imágenes blancas, negras o transparentes tienen tratamiento específico.

El fondo y la carátula tienen un movimiento suave modulado por el nivel RMS real del audio, no por una detección de tempo ni por datos inventados. La animación se limita a 24 fps, se detiene en pausa y respeta **Reducir movimiento**. **Reducir transparencia** desactiva el fondo decorativo translúcido y usa materiales más opacos.

En **Ajustes → Apariencia** puedes activar o desactivar por separado los colores adaptativos, el movimiento del fondo y la animación de la carátula, además de regular transparencia y luz ambiental. Elegir uno de los ocho colores manuales desactiva la adaptación de color; puedes reactivarla con su interruptor. Los ajustes de sonido y biblioteca de 0.2 se migran sin restablecerlos.

La vista de escucha muestra título, artista, álbum, año y calidad del archivo. Si hay letras, incluye una vista previa sincronizada; el panel lateral mantiene las letras completas.

## Novedades de la versión 0.2

- Diseño renovado: pantalla de inicio editorial, álbumes en primer plano, estadísticas reales de la colección, barra lateral flotante y controles con Liquid Glass nativo. Nuevas carátulas generativas vectoriales para archivos sin imagen.
- Panel de configuración en siete secciones: Sonido, Reproducción, Biblioteca, Metadatos e internet, Apariencia, Letras y visualizador, Atajos y acerca de.
- Motor de audio AVAudioEngine con ecualizador de diez bandas, seis presets y modo personalizado, preamplificación y compensación automática de realces. Balance estéreo y velocidad 0,5×–1,5× conservando el tono.
- Cola editable: reproducir a continuación, añadir, subir/bajar y quitar canciones pendientes.
- Playlists locales, favoritos, historial de escucha y vista de formatos sin pérdida.
- Temporizador de sueño (15/30/60/90 minutos), detener después de la canción y continuar o pausar al terminar cada pista.
- Recuperación de la canción y posición en pausa al abrir. Opción de evitar el reposo del sistema mientras se reproduce.
- Ocho colores, material suave/cristalino, luz ambiental, densidad de filas, tamaño de álbumes, indicadores de calidad y pantalla de inicio configurable.
- Letras con tamaño configurable, ajuste de sincronización ±10 segundos y seguimiento opcional del verso.
- Tres visualizadores reactivos al RMS: Aurora, Órbita y Ondas. Sensibilidad y 24/30/60 fps configurables; respeta Reducir movimiento.
- Minirreproductor con nivel flotante y visibilidad en todos los escritorios configurables.
- Búsqueda de carátulas y letras activable por separado; relectura completa de etiquetas, escaneo con/sin subcarpetas y exportación de biblioteca JSON o selección M3U8.

No incluye modo de audio exclusivo, salida bit-perfect, crossfade, ReplayGain ni reproducción sin pausas garantizada. La salida y su frecuencia se gestionan desde macOS. La compensación de EQ conserva margen según el mayor realce, pero no es un limitador de picos. La vista Sin pérdida clasifica el **archivo de origen**, no garantiza una ruta de salida sin procesamiento. La copia JSON es una exportación; esta versión no tiene restauración automática desde ella.

## Qué incluye

- Controles nativos y material Liquid Glass mediante `glassEffect` y estilos `glass` de SwiftUI.
- Biblioteca persistente; búsqueda por palabras y filtros combinados por artista, género y año. Busca también por título y álbum.
- Vistas de canciones, álbumes, artistas y favoritos; orden por título, artista, álbum o año.
- Reproducción, pausa, anterior/siguiente, búsqueda temporal, volumen, aleatorio y repetición de biblioteca o canción.
- Controles multimedia integrados con Now Playing y MPRemoteCommandCenter.
- Información técnica por canción: contenedor y códec, bitrate estimado del flujo de audio, tamaño del archivo (y bytes exactos), frecuencia de muestreo, canales y profundidad de bits cuando el formato la expone. Pulsa `⌘I`, el botón ⓘ o clic secundario → **Información del archivo**. El formato y bitrate también aparecen en la lista y en el reproductor.
- Ocho colores de acento, apariencia clara/oscura/sistema e idiomas español, inglés y portugués.
- Pantalla completa nativa (`⌃⌘F`). Visualizadores inspirados en los visualizadores de iTunes: responde al nivel RMS real del audio, con respeto a Reducir movimiento. No es un analizador FFT.
- Minirreproductor flotante (`⇧⌘M`), visible en los escritorios y sobre otras aplicaciones. **Es una ventana de audio tipo PiP; no implementa el PiP de vídeo del sistema.**
- Lectura automática de título, artista, álbum, género, año, carátulas y letras desde los metadatos del archivo al importar. En los siguientes inicios, revisa los cambios de las ubicaciones guardadas.
- Carátulas locales `cover.jpg`, `folder.jpg`, `Folder.jpg` y `cover.png`; letras `.lrc` o `.txt` con el mismo nombre base del audio. Las letras LRC se sincronizan y permiten saltar a un verso.
- Búsqueda de carátulas en iTunes y letras en LRCLIB al reproducir una canción que tenga datos faltantes. Se puede desactivar en Ajustes. También hay búsqueda manual en el menú contextual y el panel Letras.
- Edición de título, artista, álbum, género y año en la biblioteca: clic secundario → Editar etiquetas de biblioteca.

**Los cambios de etiquetas y los resultados de internet se guardan en la biblioteca de Prisma. No se reescriben las etiquetas de los archivos originales.** La primera versión no incluye un servicio de identificación acústica de canciones sin etiquetas.

El escáner reconoce MP3, M4A, AAC, AIFF, WAV, FLAC, CAF, MP4 y ALAC; la reproducción y extracción concretas dependen del códec que admita AVFoundation en el sistema. Los archivos DRM no están soportados. Las pruebas de audio incluidas verifican M4A/AAC.

## Finder y NAS

Pulsa **Conectar a un NAS…**, introduce `smb://servidor/recurso` y abre la dirección en Finder. Finder gestiona la autenticación y el montaje; no almacenes contraseñas en la dirección. Después pulsa **Añadir música** y selecciona la carpeta montada en **Ubicaciones** o `/Volumes`.

Prisma recuerda las ubicaciones con bookmarks. Si el NAS está desconectado, conserva la biblioteca y muestra un aviso. Vuelve a montar el recurso en Finder y pulsa Actualizar biblioteca (`⌘R`). No incorpora descubrimiento automático, cliente SMB propio ni almacenamiento de contraseñas. La conexión real con tus NAS queda pendiente de probar con tus servidores.

Para quitar una carpeta, clic secundario en su nombre → **Quitar ubicación**. Esto solo elimina su referencia de Prisma; no borra los archivos.

## Datos e internet

La biblioteca se guarda de forma incremental en `~/Library/Application Support/PrismaMusic/library.sqlite` (SQLite con WAL) y las carátulas compartidas en `Artwork/`; los ajustes de escucha se guardan en `preferences.json` y la sesión pausada en `playback.json`, junto a la biblioteca. El color, idioma, tema y volumen se guardan con el identificador `local.prisma.music`. Se conservan la biblioteca, favoritos y etiquetas de la versión 0.1.

La opción **Completar desde internet** está activada inicialmente. Envía título y artista a iTunes; título, artista, álbum y duración a LRCLIB. No se envían archivos de audio, rutas locales ni credenciales del NAS. Las búsquedas solo aceptan coincidencia de título/artista para carátulas; las letras usan el endpoint exacto de LRCLIB con duración. La disponibilidad depende del catálogo y de la conexión. Los resultados pueden requerir revisión para versiones en directo o remasterizadas. Se muestra la procedencia de letras y un enlace a iTunes cuando hay carátula en línea.

Las piezas demo no realizan búsquedas en internet.

## Desarrollar

No tiene dependencias externas de Swift. Requiere Xcode 26+ / Swift 6.2+ y el SDK de macOS 26 o posterior.

```bash
swift test
./scripts/build.sh
open "build/Prisma Music.app"
```

Abre `Package.swift` en Xcode para editar el proyecto. `./scripts/build.sh debug` crea un paquete de depuración. El script genera el `.app`, copia el bundle de recursos y aplica una firma ad hoc local. El `.app` entregado no está notarizado ni firmado con un certificado Developer ID; para distribución pública será necesario configurar la firma y notarización de Apple.

Pruebas de proveedores en internet, opcionales:

```bash
PRISMA_LIVE_NETWORK=1 swift test
```

Las pruebas ordinarias no necesitan internet. También verifican la migración desde 0.1, playlists/cola, persistencia de ajustes y que el ecualizador atenúe una señal real de 1 kHz mediante renderizado offline sin activar los altavoces. Cubren filtros y acentos, parser LRC, lectura de etiquetas y decodificación de tres audios reales, persistencia de edición/favoritos y comportamiento con una ubicación desconectada o archivos borrados.

## GitHub

Repositorio público: [josue758/PrismaMusic](https://github.com/josue758/PrismaMusic), bajo licencia MIT. Las descargas están en [Releases](https://github.com/josue758/PrismaMusic/releases).

Para descargar el código y ejecutar las pruebas en un Mac con las herramientas indicadas arriba:

```bash
git clone https://github.com/josue758/PrismaMusic.git
cd PrismaMusic
swift test
./scripts/build.sh
```

Los archivos personales de biblioteca (`library.sqlite`, `library.json`, `Artwork/`) y tu música no forman parte del proyecto y no deben agregarse al repositorio.

Los binarios de instalación deben adjuntarse a una Release, no al historial de código. El proyecto incluye únicamente las tres piezas demo originales, que se pueden redistribuir bajo la licencia del proyecto.

## Referencias de APIs

- [Apple: aplicar Liquid Glass a vistas personalizadas](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Apple: medición de audio con AVAudioEngine](https://developer.apple.com/documentation/avfaudio/avaudioplayer/updatemeters())
- [Apple: iTunes Search API](https://performance-partners.apple.com/search-api)
- [LRCLIB: documentación](https://lrclib.net/docs)
