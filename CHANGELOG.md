# Cambios

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
