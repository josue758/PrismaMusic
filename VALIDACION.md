# Validación de Prisma Music 0.5.0

7 de noviembre de 2026. Apple Silicon, macOS 27.2, Xcode 27.2, Swift 6.4.2.

## Resultado

Compilación de producción, empaquetado DMG y verificación de firma ad hoc completados. Actualizada en `/Applications/Prisma Music.app`.

22 pruebas aprobadas, 0 omitidas y 0 fallos con `PRISMA_LIVE_NETWORK=1 swift test`. Incluye consultas reales de carátula a iTunes y letras a LRCLIB; su disponibilidad futura depende de esos proveedores.

## Correcciones verificadas

- Biblioteca SQLite incremental: una modificación de favorito cambia un solo registro en una biblioteca de 100 canciones. Transacciones y guardado serial en segundo plano; consolidación de cambios pendientes. El cierre espera el guardado y avisa si falla.
- Migración de JSON con carátulas embebidas: conserva canciones y favoritos, crea una copia del JSON original y comparte un solo archivo de imagen entre las 100 canciones que usan la misma carátula. Los registros cargados no conservan los bytes de imagen.
- Una biblioteca JSON corrupta genera un error y conserva exactamente sus bytes originales. La app bloquea el guardado automático de biblioteca tras un fallo de carga.
- Pruebas de carpeta incompleta, cancelación, ruta inexistente, cambio de identidad y límite de subcarpetas. Una ubicación local desconectada conserva la biblioteca; eliminar un audio de una ubicación disponible permite retirarlo de la colección.
- Persistencia de 10.000 registros y 20 cambios consecutivos: al recargar aparecen 10.000 canciones y el último cambio. Escritura inicial aproximada de 0,10 s en una ejecución de desarrollo; no incluye lectura de audio ni red y no es un SLA.
- Cachés compartidas con objetivos de 8 MiB de datos comprimidos y 32 MiB de imágenes; miniaturas de hasta 1024 px. NSCache administra estos objetivos de forma orientativa. Filtros, agrupaciones y estadísticas se invalidan cuando cambian los datos correspondientes.

## Comprobación de interfaz instalada

Se abrió la biblioteca migrada con las tres demos existentes; se reprodujo Órbita y se observó el avance temporal. El panel de información mostró M4A/AAC, aproximadamente 70 kb/s, 212.948 bytes, 22,05 kHz y mono. Se escribió «Prisma Sessions» con espacio y se obtuvo una canción; se limpió la búsqueda. Se abrieron Ajustes → Sonido y Biblioteca y se ejecutó la relectura de etiquetas. Se cerró la app sin alerta de error.

Medición puntual con `ps` tras estas acciones y con la app en reposo: RSS 177.824 KiB (~174 MiB), CPU 0,3 %. Durante reproducción y efectos el consumo aumenta. No se ha medido una biblioteca real grande del usuario ni se garantiza ese consumo en otros equipos.

Las pruebas conservadas cubren audio renderizado con EQ, balance estéreo, velocidad y seek; filtros y acentos; LRC; metadatos; favoritos; edición; playlists; cola; temporizador; migraciones; paletas y contraste; reloj visual y Deshacer. No constituyen una comprobación exhaustiva de cada botón en cada estado.

## NAS pendiente

No se encontró un volumen SMB/AFP/NFS montado ni se recibió dirección del servidor. La exploración SMB únicamente mostró este Mac. Las pruebas de desconexión usan carpetas locales y no acreditan reproducción desde un NAS real.

Para completar la prueba:

1. Finder → Ir → Conectarse al servidor (`⌘K`), introducir `smb://servidor/carpeta` e iniciar sesión en Finder sin compartir contraseñas en el chat.
2. En Prisma, Añadir música → elegir la carpeta montada en Ubicaciones.
3. Reproducir archivos de varios formatos, avanzar y retroceder, saltar de pista y comprobar las propiedades.
4. Desconectar la ubicación, volver a leer y comprobar que las canciones existentes se conservan; reconectar y repetir reproducción y lectura.

## Alcance de publicación

El código se puede compartir como beta con estas limitaciones documentadas. No se publicó un remoto GitHub. El DMG es arm64 y está firmado ad hoc; falta Developer ID y notarización para distribución pública convencional. La apertura inicial del decodificador y llamadas del sistema pueden tardar ante un servidor que no responde. No hay garantía de cero errores, validación de NAS real, pruebas en Intel ni batería completa de accesibilidad/teclado en todos los estados. Las etiquetas editadas se guardan en Prisma, no modifican los audios originales. Las copias JSON exportadas contienen metadatos, carátulas y rutas, no audio; no existe restauración guiada desde la interfaz.
