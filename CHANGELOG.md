# Cambios

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
