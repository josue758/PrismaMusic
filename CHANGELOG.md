# Cambios

## 0.16.1

- Publicación estable de las mejoras de la 0.16.0. Acerca de muestra la versión y el número de compilación.

## 0.16.0 (en pruebas)

- Canciones y Álbumes se filtran por NAS, archivos locales o una carpeta concreta. Desde el filtro de carpeta puedes buscar música nueva solo en esa fuente.
- La cola separa la pista actual de las siguientes. Selecciona varias para moverlas juntas, arrastrarlas o quitarlas con Deshacer.
- Ajustes → Biblioteca importa favoritos, listas y correcciones de exportaciones JSON de Prisma Windows o Mac, con vista previa de las rutas reubicadas y pendientes.
- Importa listas M3U/M3U8 con vista previa y recuperación de rutas de Windows o del NAS cuando coinciden de forma única con la biblioteca.
- Edita, reordena, duplica y exporta listas. El editor de listas inteligentes muestra coincidencias y usa los formatos y frecuencias disponibles.
- Inicio muestra música incorporada recientemente y accesos a listas. Al buscar en Canciones aparecen también los artistas y álbumes coincidentes.
- Inicio permite retomar la pista actual. Se guarda la posición cada cinco segundos durante la reproducción y al pausar o saltar.
- Revisión de etiquetas compara formato, duración y ruta. Las copias seleccionadas pueden ocultarse y volver a mostrarse.
- Ajustes permite buscar una sección, restablecer sus preferencias y previsualizar copias SQLite para aplicar al reiniciar, conservando la biblioteca anterior.
- El visualizador tiene su propio escenario a pantalla completa, seis estilos de Windows y Cintas. La salida local alimenta un espectro de 48 bandas mientras el escenario está abierto.
- Los ajustes del visualizador se abren desde el escenario. Puedes cambiar en vivo de estilo, sensibilidad y frecuencia objetivo de 24, 30 o 60 FPS.
- La reproducción sin pausas se puede desactivar. Si desaparece la salida elegida en modo estándar, Prisma puede continuar por la salida del sistema.
- El selector distingue la salida elegida de la activa. Las ventanas estrechas usan una barra lateral más compacta.
- Ajustes de Sonido muestra los dB de ReplayGain aplicados a la pista por separado de la preamplificación del ecualizador.

## 0.15.0

- Prisma programa la pista siguiente antes del final cuando comparte formato PCM y ganancia con la pista actual. Los cambios de frecuencia o de salida usan la transición normal.
- Una barra de recuperación indica cuándo vuelve a estar accesible la pista del NAS. Reanudar conserva la posición y el orden de la cola.
- Las listas inteligentes se actualizan por criterios, como género, formato, frecuencia, favoritos y pistas sin reproducir. La fecha de incorporación se registra en las nuevas importaciones.
- ReplayGain por pista o álbum usa las etiquetas de los FLAC con la salida estándar. El modo directo y AirPlay conservan su comportamiento.
- VoiceOver identifica los botones de reproducción, el estado de aleatorio y repetición y el volumen en porcentaje.
- La salida directa retoma la reproducción tras un aviso de Core Audio si el dispositivo y la frecuencia de la pista siguen siendo compatibles.

## 0.14.7

- La ficha de álbum muestra los géneros de sus canciones junto al año y la duración.

## 0.14.6

- Prisma recupera la cola con su orden exacto, el modo aleatorio y la repetición al volver a abrir.
- Si el NAS ya está conectado, **Reanudar pista** retoma la canción con su posición y cola.
- Quitar una canción de la cola ofrece Deshacer. Información muestra qué etiquetas se corrigieron en Prisma.

## 0.14.5

- El lápiz de la ficha de álbum reúne los datos, la carátula y la edición individual o por lotes de sus canciones.

- El editor detecta si la unidad o el NAS no tiene espacio para guardar un FLAC. Ante un error de escritura, permite conservar la edición en Prisma desde el mismo formulario.

## 0.14.4

- El editor individual y el editor por lotes pueden guardar etiquetas directamente en los archivos FLAC, conservando el audio codificado.
- Selección de canciones por arrastre sobre los títulos, Mayús con las flechas y ⌘A.

## 0.14.3

- Desde la ficha de un álbum se puede elegir una carátula local y volver a la original. La carátula elegida se guarda en Prisma para todas sus canciones.

## 0.14.2

- Las letras permiten elegir el idioma de destino y guardan la preferencia. El español sigue siendo el idioma inicial.
- En ventanas estrechas, Letras, Cola e Información se abren sobre la biblioteca. Se cierran con Esc, con el botón de cierre o pulsando fuera.

## 0.14.1

- El título del reproductor abre el álbum y destaca la pista. El nombre del artista abre su ficha o permite elegir entre los artistas acreditados.
- Las fichas de álbum y artista exportan sus canciones como M3U8. En la ficha de artista, ⌥↑ lleva a las canciones y ⌥↓ a los álbumes.

## 0.14.0

- Adaptación de funciones de Windows 0.62.9 al diseño nativo de macOS: revisión de etiquetas, selección múltiple con ⌘/Mayús y editor por lotes con vista previa y deshacer.
- Correcciones de etiquetas por campo, con migración de las ediciones anteriores, artista del álbum, disco y pista; recuperación de etiquetas del archivo original.
- Informe de escaneo con búsqueda y reintento de un archivo o de todas las incidencias. Recuperación incremental después de una interrupción.
- Verificación de reubicaciones con progreso, cancelación y comprobación de identidad de la ubicación.
- Comprobación de integridad SQLite, hasta siete copias diarias y recuperación conservando los originales dañados.
- Fichas de artista con las cinco canciones más reproducidas, saltos a canciones/álbumes y portadas que respetan el tamaño de Apariencia.
- Todas las nuevas opciones están traducidas al español, inglés y portugués.

## 0.13.5 (integrada en 0.14.0)

- Prisma busca canciones nuevas en segundo plano mientras la app está abierta. La búsqueda se puede desactivar desde **Ajustes → Biblioteca**.

## 0.13.4

- **Buscar canciones nuevas** recorre las carpetas sin volver a leer las etiquetas de las pistas ya importadas. La lectura completa sigue disponible en Ajustes.
- El menú Prisma Music muestra un engranaje junto a **Ajustes**.

## 0.13.3

- Inicio, Canciones, Álbumes y Artistas reutilizan el orden de la biblioteca y los resultados recientes al cambiar de sección.
- Las transiciones de la biblioteca y los paneles son más breves. En Ajustes cambia el contenido al instante y se anima la selección.
- La barra de menús agrupa las actualizaciones de idioma para evitar repetir trabajo al cambiar sus opciones.

## 0.13.2

- La barra de menús sigue el idioma de Prisma y conserva una sola entrada de Ajustes con el atajo ⌘ + coma.

## 0.13.1

- La búsqueda reutiliza el orden de la biblioteca al escribir y difiere el cálculo de los índices de las filas hasta que se usan.
- Siguiente y Anterior acceden a la pista contigua sin reconstruir la cola en el caso habitual.
- Al desmontarse el NAS durante la reproducción, Prisma conserva la pista y la posición y ofrece reconectar.

## 0.13.0

- **Buscar actualizaciones…** muestra las novedades y permite descargar, verificar y abrir el instalador desde Prisma Music.
- **Reconectar y reintentar** abre el recurso del NAS en Finder y vuelve a iniciar la pista en la posición solicitada cuando el archivo está disponible.
- **Reubicar fuente…** comprueba los archivos en la nueva ubicación y conserva los favoritos, listas y etiquetas guardadas.

## 0.12.3

- Reflejo más suave y pequeño al mover el cursor, con menos brillo sobre las carátulas.
- Navegación hacia atrás entre artistas y álbumes. La carátula del reproductor abre la sala de pantalla completa.
- Búsqueda de biografías y retratos de artistas en más idiomas, con datos de la biblioteca cuando falta una coincidencia fiable.
- Atajo «Reproducir canción» para compilaciones con una firma que macOS valide. El instalador público usa firma ad hoc y macOS rechazó el atajo con esa firma en las pruebas.

## 0.11.3

La barra principal y la pantalla completa muestran «Activar volumen» cuando la salida directa fija la ganancia. El botón vuelve a la salida ajustable y recupera el volumen guardado.

## 0.11.2

Álbumes respeta el orden por nombre, artista o año. Las recopilaciones usan la etiqueta de artista del álbum cuando existe. Canciones adapta las columnas al ancho disponible y conserva el álbum y año debajo del título en la vista compacta.

## 0.11.1

La etiqueta de la sala de escucha muestra el formato, la profundidad de bits y la frecuencia de muestreo disponibles para la pista.

## 0.11.0 — 8 de noviembre de 2026

Pantalla completa abre una ventana de escucha independiente con carátula, controles compartidos y letras. Volver o Esc la cierra y conserva la biblioteca. Traducción nativa de Apple al español bajo cada línea original, con detección/corrección de idioma, modelos instalables, errores visibles y caché limitada. Letras sincronizadas conservan los tiempos y permiten saltar a un verso; se respetan Reducir movimiento y la preferencia de desplazamiento automático.

Búsqueda de letras con Unicode canónico, acentos latinos y marcas japonesas preservadas, alternativas de búsqueda sin álbum y validación de artista, duración y versión. Los campos vacíos cuentan como letras faltantes, sin sobrescribir letras locales válidas. Pruebas reales de catálogo japonés/portugués.

Catorce pruebas nuevas de documentos de letras, traducciones fuera de orden, límites, caché, migración y modelos nativos inglés/japonés. Se contempla el japonés con estribillos ingleses y se reutilizan los modelos ya instalados sin abrir una descarga implícita.

Flujo local de firma Developer ID, Hardened Runtime, timestamp, notarización de app/DMG, tickets y Gatekeeper. Rechaza certificados de desarrollo y credenciales ausentes. Está preparado pero no se ha ejecutado con una identidad Developer ID: la beta publicada sigue con firma ad hoc porque falta la membresía y sus certificados.

## 0.10.0 — 8 de noviembre de 2026

Navegación por teclado en listas compartidas, selección sin reproducción automática, Intro para reproducir, ⌘F para buscar y Esc para salir. Acciones y selección expuestas a accesibilidad. ⌘I conserva la canción inspeccionada.

Superficies opacas con Reducir transparencia. Versión y build centralizados en un manifiesto compartido por interfaz, peticiones y empaquetado. Script de verificación de pruebas, compilación, firma e integridad del DMG.

GitHub Actions en macOS 26 arm64 con permisos de lectura, acciones fijadas por SHA y conservación del instalador/log. README en inglés, guía española, arquitectura, contribuciones y roadmap con límites explícitos. Dos regresiones nuevas de selección y foco de búsqueda. Formato Swift consistente en fuentes y pruebas, con configuración y script del formatter incluido en el toolchain.

## 0.9.0 — 8 de noviembre de 2026

Página de álbum con lista ordenada por disco y pista, duración, portada y reproducción independiente de la apertura. Lectura de numeración FLAC/ID3/MP4 bajo demanda, con fallback al nombre del archivo. Agrupación de colaboraciones bajo el artista principal.

Fotografías de artistas vinculadas mediante Wikidata, selección por resolución/fecha/encuadre, encuadre de rostros con Vision y selector con créditos y elección persistente. Retratos reales en la cuadrícula, carga progresiva serializada y cachés limitadas.

Filas compartidas entre canciones, artistas, álbumes, favoritos, recientes y playlists. Navegación que limpia el contexto anterior, búsqueda global desde fichas, recuentos correctos y conservación del archivo inspeccionado. Cancelar la preparación de un álbum o eliminarlo durante la carga ya no deja el indicador pendiente. Nueve pruebas nuevas de presentación, orden, navegación, cancelación y fotografías.

## 0.8.0 — 8 de noviembre de 2026

Selector de dispositivos Core Audio, detección de cambios, UID persistente y pausa si desaparece la salida elegida. Modo directo sin DSP ni atenuación, frecuencia nativa y acceso exclusivo opcional con comprobación del propietario. Restauración de frecuencia y reserva al cambiar de ruta o cerrar.

AirPlay nativo mediante AVPlayer, con retorno al motor local e indicación de ruta. Se evita que un reproductor anterior pause una nueva canción al compartir el transporte AirPlay.

Icono fijo de dispositivos independiente de AirPlay y cabecera de artista con foto amplia, fondo difuminado y colores extraídos de la imagen.

Ficha de artista con biografía y foto acreditada de Wikipedia/Wikimedia, biblioteca local, álbumes seleccionables, reproducción y favoritos. Agrupación de colaboraciones por participante y consultas de colección reutilizadas hasta que cambian los datos. Nuevas pruebas de PCM directo, dispositivos reales, migración, artistas y transporte AirPlay.

## 0.7.1 — 8 de noviembre de 2026

Apertura de audio serializada fuera de la interfaz, estado de carga cancelable y protección frente a respuestas de solicitudes anteriores. Siguiente usa la selección pendiente; pausar, buscar y salir cancelan la carga. Restaurar la sesión no abre el archivo hasta solicitar reproducir. Se evita solapar dos canciones al cambiar y se conservan los controles del audio actual si falla el nuevo. Indicadores de carga y etiqueta Recientes más breve.

Se corrige además la lectura de M4A/AAC guardado con extensión FLAC: detección del contenedor real, indicación MIME para AVFoundation y clasificación de calidad por códec.

Se corrige el estado al terminar una canción si la siguiente no se puede abrir, y se sincronizan los controles del sistema después de un fallo de apertura.

Seis regresiones nuevas: interfaz disponible durante una apertura suspendida, última solicitud propietaria del error, rechazo de respuestas tardías al cancelar/salir, navegación rápida y restauración sin abrir el audio. La prueba SMB usa el nuevo cargador en segundo plano y comprueba su hilo de ejecución.

## 0.7.0 — 8 de noviembre de 2026

Bienvenida en cuatro pasos y tres idiomas: colección local/NAS, etiquetas, estilos Cristal vivo/Calma/Contraste y preferencias de escucha. Se guarda la finalización y se puede reabrir desde Ajustes o el menú. Los estilos no modifican el ecualizador.

Reintento selectivo de los archivos con error del último informe, conservando las demás entradas. Configuración de dos, cuatro u ocho lecturas simultáneas, ajustable durante el escaneo. Se corrige el cierre durante la carga inicial para que no arranque una exploración al salir.

Importación de bibliotecas grandes en SMB con recorrido POSIX, consultas de cambios y metadatos con concurrencia limitada y configurable, lectura directa de cabeceras y etiquetas FLAC, y detección de carátulas/letras por carpeta. Se evitan consultas repetidas a archivos auxiliares inexistentes y se comprueba el tamaño de las imágenes antes de cargarlas.

Informe persistente de lectura con totales y errores, progreso en Ajustes y conservación de lo importado al cancelar. Restaurar una ruta mediante bookmark remapea canciones, playlists, etiquetas editadas y sesión. Los lotes combinan el estado de usuario más reciente al incorporarse a la biblioteca.

Se añaden pruebas de importación paralela, escaneo incremental, rutas restauradas, paquetes/enlaces ocultos, comentarios Vorbis, límites y archivos auxiliares. La validación de toda la colección se documenta en VALIDACION.md.

## 0.5.1 — 7 de noviembre de 2026

Prueba real de streaming desde SMB: FLAC de 24 bits/96 kHz, decodificación, seek y pausa/reanudación. 29 pruebas aprobadas con red y NAS activados.

Exploración con progreso y cancelación directa; resultados por lotes pequeños; bitrate y profundidad de origen en formatos lossless; indicador NAS en metadatos nuevos; profundidad de bits en la vista inmersiva. Se reduce la frecuencia de telemetría a 15 Hz y se limita el tamaño de las portadas destacadas cuando hay pocos álbumes.

La restauración de sesión conserva la reproducción iniciada durante el escaneo; las consultas online no reemplazan el estado de lectura. Se amplía la cobertura de permisos, recuperación, fuentes superpuestas, audio dañado, SQLite corrupto, consultas y cancelación.

## 0.5.0 — 7 de noviembre de 2026

Guardado incremental SQLite en segundo plano; migración con copia de seguridad; carátulas deduplicadas y miniaturas con caché acotada; resultados de filtros, grupos y estadísticas reutilizables. Se reducen las actualizaciones en pausa.

Escaneo conservador ante errores, desconexión, cancelación o reemplazo de la carpeta, con estados de origen y botón de cancelar. Quitar una fuente conserva las canciones cubiertas por otra. Abrir desde Finder reproduce el archivo y el atajo de reproducción deja libres los espacios de búsqueda. Guardado pendiente esperado al cerrar y exportación JSON con imágenes en segundo plano. Consultas online con tamaño limitado.

22 pruebas aprobadas, incluidos proveedores reales y persistencia de 10.000 registros. Pendiente prueba con NAS real y firma Developer ID/notarización para distribución pública.

## 0.4.0 — 7 de noviembre de 2026

Pulido de movimiento y respuesta: navegación animada, transiciones de vistas y paneles, profundidad e iluminación bajo el cursor, respuesta de botones y corazones y fundido entre portadas. La animación ambiental conserva su fase al pausar y reanudar.

Nueva barra temporal con previsualización, confirmación al soltar y ajuste mediante teclado/accesibilidad. Avisos con Deshacer para acciones de favoritos, cola y playlists. Preferencias independientes de animación, profundidad y avisos.

## 0.3.0 — 7 de noviembre de 2026

Nueva vista de escucha inmersiva. Colores extraídos localmente de la carátula, fondo de malla con imagen difuminada, cristal más transparente, pulso sutil de la portada y movimiento modulado por el audio real. Controles independientes de color, movimiento y transparencia, con respeto a las opciones de accesibilidad.

Migración de preferencias compatible con versiones anteriores; mantiene el EQ y la biblioteca. Las instalaciones nuevas comienzan en la vista inmersiva; las existentes conservan la pantalla de inicio elegida.

## 0.2.0 — 7 de noviembre de 2026

Rediseño de Prisma alrededor de superficies Liquid Glass, iluminación ambiental, una portada para la colección, álbumes destacados y una barra de reproducción más completa.

El panel de ajustes pasa a siete secciones con controles funcionales de sonido, biblioteca, apariencia y experiencia. El reproductor utiliza ahora AVAudioEngine para procesar un EQ de diez bandas, balance estéreo y velocidad con conservación del tono. Se añaden cola editable, playlists, historial, vista de formatos sin pérdida, temporizador de sueño, recuperación de sesión y ajustes de letras/visualizadores.

Se conservan los datos de la biblioteca 0.1, los favoritos y las etiquetas editadas. El instalador continúa siendo local, arm64, firmado ad hoc y sin notarización para distribución pública.

## 0.1.0

Primera versión nativa: importación desde Finder/NAS montados, metadatos locales, filtros, reproducción, letras y carátulas en internet, visualizador, minirreproductor y datos técnicos del archivo.
