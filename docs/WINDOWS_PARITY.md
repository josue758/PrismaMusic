# Adaptación de Windows a macOS · 0.14.0

Referencia examinada: PrismaMusic-Windows 0.62.9, commit `f27806f` (rama main). Se revisaron README, historial y código de revisión/edición de etiquetas, exportación, escaneo, audio y navegación.

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
| WASAPI, Mica y Argos | Se mantienen Core Audio, Liquid Glass y Apple Translation. La traducción de Mac continúa destinada al español. Los mecanismos propios de Windows no se trasladan. |

Además se completa la búsqueda periódica de música nueva con la app abierta: intervalo nominal de 90 segundos, sin lecturas de etiquetas ya conocidas, dos lectores como máximo y pausa de cinco minutos antes de reintentar archivos fallidos. Se puede desactivar en Biblioteca. Las llamadas SMB del sistema pueden tardar en devolver el control; la cancelación evita continuar después de ellas.

La beta pública mantiene firma ad hoc. La firma Developer ID/notarización, certificación física del DAC y una matriz de receptores AirPlay siguen requiriendo validación independiente.
