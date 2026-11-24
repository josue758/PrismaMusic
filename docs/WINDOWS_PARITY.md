# Adaptación de Windows a macOS

Referencia examinada: PrismaMusic-Windows 0.62.10, commit `ce01993` (rama main). Se revisaron README, historial y código de revisión/edición de etiquetas, exportación, escaneo, audio y navegación.

La adaptación de macOS 0.16.0 usa como referencia Windows **0.65.2**, commit `c5ce173`.

| Cambio de Windows 0.63–0.65.2 | Adaptación en macOS 0.16.0 |
| --- | --- |
| Editor de álbum, enlaces desde el reproductor, historial y recuperación NAS | Ya existían en macOS. La ficha del álbum muestra el género y el editor reúne carátula, datos y canciones. |
| Gestión de listas e importación M3U/M3U8 | Vista previa, resolución de rutas locales y coincidencia única por sufijo para rutas trasladadas. Renombrar, reordenar, duplicar y exportar desde la lista. |
| Listas inteligentes y filtros con etiquetas | Vista previa de cinco coincidencias y total. Selectores a partir de la colección local. |
| Búsqueda agrupada e Inicio con accesos | Resultados de canciones, artistas y álbumes. Inicio permite continuar escuchando y ofrece listas y música añadida recientemente. |
| Copias SQLite y duplicados | Vista previa de copias con tamaño, fecha y número de pistas. Restauración al volver a abrir, con preservación de la biblioteca actual. Ocultación reversible de duplicados. |
| Ajustes y visualizador | Búsqueda por tema y restablecimiento por sección. El escenario completo tiene sus propios ajustes de estilo, sensibilidad y 24, 30 o 60 FPS, compartidos con Ajustes. Espectro local de 48 bandas. |
| Audio y cambios de dispositivo | Selector Core Audio reactivo con salida elegida y activa. Salida estándar del sistema como alternativa, opción de reproducción sin pausas y ReplayGain local. |

El cursor persistente de carpetas en el escaneo de Windows sigue pendiente. macOS vuelve a recorrer los directorios y reutiliza los metadatos ya importados. WASAPI, Miracast, Mica y Argos corresponden a Windows. macOS conserva Core Audio, AirPlay, Liquid Glass y Apple Translation.

| Función de Windows | Implementación en Mac |
| --- | --- |
| Revisión de etiquetas y posibles duplicados | Nuevo panel en Ajustes → Biblioteca. Agrupa etiquetas faltantes, variantes del álbum y coincidencias de etiquetas/duración; nunca borra archivos. Reconoce el marcador `—` utilizado por los lectores de Mac. |
| Edición por lotes y deshacer | Selección con ⌘/Mayús y menú contextual, o selección en la revisión. Vista previa de diez pistas, campos optativos, numeración y deshacer durante la sesión. |
| Correcciones por campo y recuperar original | Modelo persistente compatible con bibliotecas anteriores; conserva solamente los campos corregidos durante nuevas lecturas. Editor individual con artista del álbum, disco y pista. |
| Informe consultable y reintento selectivo | Panel nativo con búsqueda de ruta/mensaje, copiar ruta y reintentar uno o todos los archivos fallidos. Conserva las demás incidencias del informe. |
| Recuperación de importación NAS | Búsqueda incremental reutiliza pistas ya importadas después de una interrupción. Recorre nuevamente las carpetas; no guarda el cursor de carpetas de la implementación Windows. |
| Reubicar con verificación cancelable | Progreso de archivos, cancelación antes de aplicar y verificación de identidad del destino. Conserva listas, favoritos, correcciones y referencias de reproducción. |
| SQLite con copias e integridad | Comprobación al abrir, hasta siete copias diarias mediante la API online de SQLite y recuperación automática conservando los archivos dañados. No incluye audio ni carátulas. |
| Más reproducidas en artista | Cinco pistas según el contador local. Se añaden botones para ir a canciones/álbumes y se respeta el tamaño de portada elegido. |
| Exportación JSON y M3U8 | Ya disponible en Mac; la exportación JSON incorpora las nuevas correcciones por campo. Las bibliotecas no se importan automáticamente entre plataformas. |
| Actualizaciones, letras, retratos, mini, cola, EQ | Mac ya dispone de estas funciones; se conservan los servicios y ventanas nativos. |
| Idioma de destino de las letras | En las letras, **Traducir a** permite elegir entre los idiomas que ofrece Apple Translation. Guarda la elección y mantiene cada idioma en su propia caché. |
| Paneles en ventanas estrechas | Letras, Cola e Información se superponen a la biblioteca. En ventanas anchas quedan a su lado. Esc y pulsar fuera cierran el panel superpuesto. |
| Restauración de sesión | Mac conserva el orden de la cola, el modo aleatorio y la repetición. El ajuste de posición sigue controlando la pista y el tiempo de reanudación. |
| Reanudar pista y deshacer en la cola | Si el NAS ya está montado, se retoma la pista directamente con su posición y cola. Quitar una pista ofrece Deshacer. |
| Correcciones en Información del archivo | El panel muestra los campos que tienen correcciones locales. |
| WASAPI, Mica y Argos | Mac usa Core Audio, Liquid Glass y Apple Translation. |

Además se completa la búsqueda periódica de música nueva con la app abierta: intervalo nominal de 90 segundos, sin lecturas de etiquetas ya conocidas, dos lectores como máximo y pausa de cinco minutos antes de reintentar archivos fallidos. Se puede desactivar en Biblioteca. Las llamadas SMB del sistema pueden tardar en devolver el control; la cancelación evita continuar después de ellas.

La beta pública mantiene firma ad hoc. La firma Developer ID/notarización, certificación física del DAC y una matriz de receptores AirPlay siguen requiriendo validación independiente.
