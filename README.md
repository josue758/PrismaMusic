# Prisma Music

Reproductor nativo para macOS, escrito en Swift y SwiftUI. Primera versión local **0.1.0** para probar e iterar.

## Instalar y probar

Requiere **macOS 26 o posterior**. El instalador incluido contiene una compilación para **Apple Silicon**.

1. Abre `Prisma-Music-0.1.0.dmg` y arrastra **Prisma Music** a **Aplicaciones**.
2. Abre la aplicación. Incluye tres piezas instrumentales originales de 24 segundos, etiquetadas y listas para reproducir.
3. Pulsa **Añadir música** o `⌘O`: puedes elegir archivos, carpetas y volúmenes de red.
4. Haz doble clic en una canción o pulsa el botón de reproducción. También puedes abrir archivos de audio con la aplicación desde Finder.

En este Mac ya se instaló en `/Applications/Prisma Music.app`.

## Qué incluye

- Controles nativos y material Liquid Glass mediante `glassEffect` y estilos `glass` de SwiftUI.
- Biblioteca persistente; búsqueda por palabras y filtros combinados por artista, género y año. Busca también por título y álbum.
- Vistas de canciones, álbumes, artistas y favoritos; orden por título, artista, álbum o año.
- Reproducción, pausa, anterior/siguiente, búsqueda temporal, volumen, aleatorio y repetición de biblioteca o canción.
- Controles multimedia integrados con Now Playing y MPRemoteCommandCenter.
- Información técnica por canción: contenedor y códec, bitrate estimado del flujo de audio, tamaño del archivo (y bytes exactos), frecuencia de muestreo, canales y profundidad de bits cuando el formato la expone. Pulsa `⌘I`, el botón ⓘ o clic secundario → **Información del archivo**. El formato y bitrate también aparecen en la lista y en el reproductor.
- Cinco colores de acento, apariencia clara/oscura/sistema e idiomas español, inglés y portugués.
- Pantalla completa nativa (`⌃⌘F`). Visualizador Aurora inspirado en los visualizadores de iTunes: responde al nivel RMS real del audio, con respeto a Reducir movimiento. No es un analizador FFT.
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

La biblioteca y carátulas se guardan en `~/Library/Application Support/PrismaMusic/library.json`; las preferencias se guardan con el identificador `local.prisma.music`.

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

Las pruebas ordinarias no necesitan internet. Cubren filtros y acentos, parser LRC, lectura de etiquetas y decodificación de tres audios reales, persistencia de edición/favoritos y comportamiento con una ubicación desconectada o archivos borrados.

## GitHub

El código se entrega como repositorio Git local con `.gitignore`, pruebas y licencia MIT, listo para publicar. No se ha creado ningún repositorio remoto. Cuando decidas publicarlo, conecta tu cuenta y elige el nombre y la visibilidad. No publiques `library.json` ni tu música personal; no forman parte del proyecto.

```bash
# Si partiste del ZIP, primero: git init -b main; git add .; git commit -m "Initial version"
git remote add origin https://github.com/TU_USUARIO/PrismaMusic.git
git push -u origin main
```

Los binarios de instalación deben adjuntarse a una Release, no al historial de código. El proyecto incluye únicamente las tres piezas demo originales, que se pueden redistribuir bajo la licencia del proyecto.

## Referencias de APIs

- [Apple: aplicar Liquid Glass a vistas personalizadas](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Apple: medición de audio con AVAudioPlayer](https://developer.apple.com/documentation/avfaudio/avaudioplayer/updatemeters())
- [Apple: iTunes Search API](https://performance-partners.apple.com/search-api)
- [LRCLIB: documentación](https://lrclib.net/docs)
