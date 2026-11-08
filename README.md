# Prisma Music

Reproductor nativo para macOS, escrito en Swift y SwiftUI. Versión beta local **0.9.0** para probar e iterar.

[Descargar la versión 0.9.0 beta para Apple Silicon](https://github.com/josue758/PrismaMusic/releases/tag/v0.9.0) · [Ver el código](https://github.com/josue758/PrismaMusic)

## Instalar y probar

Requiere **macOS 26 o posterior**. El instalador incluido contiene una compilación para **Apple Silicon**.

1. Abre `Prisma-Music-0.9.0.dmg` y arrastra **Prisma Music** a **Aplicaciones**.
2. Abre la aplicación y sigue la bienvenida para elegir idioma, biblioteca y estilo. Incluye tres piezas instrumentales originales de 24 segundos, etiquetadas y listas para reproducir.
3. Pulsa **Añadir música** o `⌘O`: puedes elegir archivos, carpetas y volúmenes de red.
4. Haz doble clic en una canción o pulsa el botón de reproducción. También puedes abrir archivos de audio con la aplicación desde Finder.

En este Mac se actualiza en `/Applications/Prisma Music.app`. Si Prisma estaba abierta, ciérrala por completo (`⌘Q`) y vuelve a abrirla para cargar la versión 0.9. La actualización conserva tus datos.

## Novedades de la versión 0.9

**Álbumes con su propia página.** Pulsar una carátula o su título abre sus canciones; el botón de reproducción es independiente. La ficha muestra portada cuadrada, artista, año, duración y controles para reproducir o mezclar el álbum. Lee números de disco y pista de FLAC, ID3 y MP4; si faltan, utiliza el prefijo numérico del archivo y su nombre. Los álbumes de artistas distintos conservan su identidad y las colaboraciones separadas por `;` se reúnen bajo su primer artista.

**Fotografías de artistas.** La cuadrícula utiliza retratos reales cuando están disponibles y unas iniciales cuando no hay foto. Las fichas priorizan fotografías de Wikimedia vinculadas al artista por Wikidata, resolución, encuadre y fecha. Incluyen encuadre que considera los rostros, fondo difuminado y colores de la fotografía. **Cambiar foto** permite elegir entre las imágenes encontradas y guardar la elección en este Mac; cada opción enlaza a su autor y licencia. No se garantiza que Wikimedia tenga una fotografía adecuada para todos los artistas.

**Navegación coherente.** Canciones, favoritos, recientes, playlists y fichas comparten filas y controles. Se corrigen títulos, recuentos, filtros y la salida de una ficha al navegar o buscar. Las fotos se cargan de forma progresiva, con descargas serializadas y cachés limitadas; la nueva lectura del orden se limita al álbum abierto y conserva tus favoritos y etiquetas editadas.

Con internet activado, la sección Artistas consulta nombres en Wikipedia/Wikimedia al mostrar sus fichas e imágenes. No envía archivos de audio ni la biblioteca completa. Las elecciones se guardan en `artist-photo-choices.json`, dentro de los datos personales de Prisma, fuera del repositorio y del instalador.

## Novedades de la versión 0.8

**DAC y salidas de audio.** El botón de altavoz de la barra y Ajustes → Sonido permiten elegir una salida Core Audio por su identificador persistente, ver canales y frecuencia y seguir la salida predeterminada de macOS. Se actualiza al conectar/desconectar dispositivos; una salida elegida que desaparece pausa la reproducción y no la desvía silenciosamente a otros altavoces.

**Salida directa para uso bit-perfect.** Omite físicamente el EQ, balance y velocidad en el grafo, utiliza ganancia unitaria y solicita la frecuencia nativa de la canción. El acceso exclusivo es opcional y se muestra solo si el dispositivo lo concede. Se rechazan rutas inalámbricas o frecuencias/canales incompatibles; se intenta restaurar la frecuencia anterior y liberar la reserva al cambiar de ruta o cerrar. El volumen de Prisma queda al 100 % en este modo: ajusta primero el volumen físico del equipo. Tus ajustes DSP se conservan al volver al modo normal. La prueba de renderizado confirma igualdad exacta de muestras PCM de 24 bits dentro de Prisma; no certifica los bits entregados por un DAC físico ni los efectos del controlador o del sistema.

**AirPlay.** Botón nativo de selección de destinos, conectado a un reproductor AVPlayer real. Esta ruta usa el transporte del sistema; no aplica el EQ, balance ni la salida directa del motor Core Audio. El panel permite volver a la salida local. La aparición y funcionamiento de receptores depende de macOS, la red y los dispositivos disponibles.

**Artistas.** Pulsar un artista abre su ficha con biografía, fotografía atribuida cuando está disponible, álbumes, canciones, géneros y duración de tu colección. Puedes reproducir todo, mezclar, seleccionar un álbum, consultar una canción o marcar favoritos. Las colaboraciones etiquetadas con `;` aparecen en las fichas de cada participante. Desde la versión 0.9, Wikipedia y Wikimedia se consultan al mostrar artistas o abrir una ficha con internet activado; se envía el nombre del artista, no tu colección. Las coincidencias ambiguas o no musicales se omiten y la biblioteca local sigue disponible.

## Novedades de la versión 0.7.1

La apertura del audio se realiza en segundo plano, con una sola apertura simultánea y cancelación de solicitudes que ya no interesan. Si el NAS tarda, la interfaz sigue disponible y muestra la canción pendiente. Puedes cancelar desde el botón de reproducción. Una respuesta antigua no reemplaza la selección más reciente, y pulsar Siguiente varias veces avanza desde la canción pendiente.

Los archivos con extensión FLAC cuyo contenido corresponde a otro formato se identifican por sus datos y se entregan a AVFoundation con el tipo correcto. Se muestra el códec real y se evita clasificar AAC como sin pérdida por el nombre del archivo.

La restauración de sesión recupera selección y posición sin abrir el archivo hasta que se solicita reproducir. Los errores de apertura distinguen el fallo del audio sin etiquetar todos los errores como desconexiones. La barra, el minirreproductor, la escucha inmersiva y la fila pendiente muestran el estado de carga. Se acorta el nombre de Recientes en la barra lateral para evitar recortes.

Las llamadas de apertura del sistema pueden tardar en terminar aunque se cancele: Prisma descarta el resultado y limita la concurrencia, pero no interrumpe por la fuerza la operación SMB. La construcción y el control del motor permanecen en el hilo principal.

## Novedades de la versión 0.7

La nueva bienvenida permite elegir español, inglés o portugués, añadir música local o conectar un NAS, leer/editar etiquetas de biblioteca, probar tres estilos de cristal y ajustar la pantalla inicial, la recuperación de sesión y las búsquedas online. Se puede reabrir desde el menú de Prisma Music o Ajustes. Los estilos conservan el ecualizador y los ajustes de sonido.

**Reintentar archivos con error**, en Ajustes → Biblioteca, vuelve a leer los fallos del último informe sin eliminar canciones ajenas al reintento.

La importación de colecciones grandes en NAS usa un recorrido de directorios que evita consultas repetidas por cada nombre de archivo. La comprobación de fechas/tamaños y la lectura de etiquetas se distribuyen entre un máximo configurable de dos, cuatro u ocho archivos simultáneos (cuatro por defecto). Los resultados se guardan por lotes y las canciones sin cambios se omiten al volver a escanear.

Los FLAC se leen mediante sus cabeceras STREAMINFO, comentarios Vorbis y bloques de imagen, con límites de tamaño y validación de longitudes. Se extraen título, artista, álbum, género, fecha, letras, carátula, duración, canales y profundidad, sin decodificar ni copiar el audio completo. El bitrate mostrado es una estimación del flujo comprimido. Los casos no compatibles conservan la vía de AVFoundation. Esto valida la lectura de metadatos y cabeceras; no acredita cada muestra de audio de cada archivo.

El recorrido identifica una sola vez por carpeta los archivos `cover.jpg`, `folder.jpg`, `cover.png`, `.lrc` y `.txt`, sin distinguir mayúsculas. Se comprueba el tamaño de las imágenes externas antes de cargarlas. La importación conserva favoritos, historial y etiquetas editadas incluso cuando se actualizan durante el escaneo.

La validación de una colección real encontró los 7.854 archivos de su inventario independiente: 7.813 importados y 41 incidencias identificadas, sin omisiones fuera del informe. El reintento confirmó archivos con cabecera a cero, lecturas vacías y rutas que el NAS listaba pero no permitía abrir. Los originales se conservaron.

**Ajustes → Biblioteca** muestra el progreso y el resumen de lectura. **Mostrar informe de lectura** revela `scan-report.json` en la carpeta de datos, con los totales y las rutas de los archivos que dieron error. El informe se conserva entre sesiones. Es un archivo personal y no debe publicarse junto al código.

Al restaurar un bookmark cuya ruta cambia, se trasladan también las referencias de canciones, playlists, etiquetas editadas y sesión. La cancelación conserva los lotes ya leídos y espera el guardado pendiente.

## Novedades de la versión 0.5.1

La prueba con un NAS SMB real reprodujo y decodificó un FLAC de 24 bits/96 kHz, avanzó a otra posición y reanudó después de pausar. También se probó su control desde el minirreproductor y se exportó una copia JSON con la carátula incorporada. Esto verifica ese archivo y esas operaciones, no todos los formatos ni una desconexión real durante la reproducción.

La exploración muestra la carpeta y el número de audios encontrados, con cancelación directa en la barra de estado. Durante la lectura de etiquetas, los resultados llegan por lotes de hasta 32 archivos o aproximadamente cada segundo, después de completar cada lectura individual. Las llamadas de red del sistema pueden tardar antes de devolver el control al cancelar.

Se recuperan bitrate y profundidad de origen mediante AudioToolbox cuando no están disponibles en la descripción habitual del flujo; la vista inmersiva muestra bits y kHz. El indicador de origen muestra NAS para las pistas identificadas como volumen de red al leer sus metadatos. Los FLAC antiguos sin estos datos se vuelven a leer en el próximo escaneo.

Los álbumes destacados conservan tres columnas cuando hay pocas portadas para evitar una carátula enorme. La telemetría del reproductor se actualiza a 15 Hz; el reloj visual mantiene su animación independiente. La restauración de sesión respeta una reproducción iniciada mientras se escaneaba, y las consultas de metadatos no reemplazan el estado del escaneo.

29 pruebas aprobadas con las opciones de NAS e internet activadas: permisos denegados y recuperación, fuentes superpuestas, audio dañado, SQLite corrupto, invalidación de consultas, progreso/cancelación, metadatos FLAC de 24 bits y decodificación real desde SMB, además de la cobertura anterior.

## Novedades de la versión 0.5

- Guardado incremental en segundo plano, con transacciones SQLite y consolidación de cambios pendientes. Al salir se espera la escritura; un error impide cerrar sin avisar.
- Migración desde JSON que conserva una copia `library-v0.4-backup.json`. Una biblioteca dañada muestra un error y bloquea el reemplazo automático.
- Carátulas compartidas por contenido, reducidas hasta 1024 px. Cachés con objetivos de 8 MiB para datos y 32 MiB para imágenes decodificadas; son límites orientativos de NSCache, no una garantía de RAM total.
- Filtros, agrupaciones y estadísticas reutilizan resultados mientras no cambien los datos. En pausa se evitan publicaciones continuas de posición y nivel sin cambios.
- Una lectura incompleta, cancelada o de una ubicación que cambió de identidad conserva las entradas existentes. El escaneo permite cancelar y muestra el estado de cada fuente. No se monta un NAS automáticamente al restaurar bookmarks.
- Abrir un audio desde Finder lo importa y reproduce. Reproducir/pausar usa `⇧⌘P`, evitando capturar los espacios de la búsqueda. Las copias JSON incorporan sus carátulas y se escriben en segundo plano.
- Respuestas de proveedores limitadas a 8 MiB y cancelables.

En 0.5.1 se realizó una prueba de streaming con un archivo FLAC desde un NAS real montado en Finder. Para usar tu servidor, móntalo en Finder mediante `smb://servidor/carpeta` y añade su carpeta de música. Las pruebas con directorios locales complementan la cobertura de errores y desconexión. La apertura inicial del decodificador y algunas operaciones del sistema pueden tardar si el servidor no responde.

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

Prisma recuerda las ubicaciones con bookmarks. Si el NAS está desconectado, conserva la biblioteca y muestra un aviso. Vuelve a montar el recurso en Finder y pulsa Actualizar biblioteca (`⌘R`). No incorpora descubrimiento automático, cliente SMB propio ni almacenamiento de contraseñas. Se verificó la reproducción de un FLAC desde un NAS SMB real en 0.5.1; otros formatos y la desconexión real durante la reproducción quedan pendientes.

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

Para repetir la comprobación con un audio de tu NAS ya montado:

```bash
PRISMA_NAS_FILE="/Volumes/TuNAS/Musica/prueba.flac" PRISMA_LIVE_NETWORK=1 swift test
```

El archivo se abre solo para lectura y se decodifica mediante renderizado offline, sin modificar el audio ni hacer sonar los altavoces. Sin las variables correspondientes, se omiten las dos pruebas externas.

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
