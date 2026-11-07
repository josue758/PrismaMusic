# Validación de Prisma Music 0.2.0

Fecha: 7 de noviembre de 2026. Entorno: macOS 27.2, Apple Silicon, Xcode 27.2, Swift 6.4.2.

## Resultado

- Compilación de producción completada; aplicación 0.2.0 instalada y abierta desde `/Applications/Prisma Music.app`.
- Firma ad hoc e instalador DMG verificados.
- Once pruebas funcionales verificadas: seis de biblioteca/proveedores y cinco de escucha/DSP. Los proveedores en internet se verificaron con la ejecución opt-in; las pruebas de escucha se repitieron después de corregir el motor.
- El renderizado de audio de las pruebas es offline; no activa los altavoces.

## Revisión visual de la aplicación instalada

Después de desbloquear el Mac se revisaron la portada de la colección, la barra lateral flotante, los álbumes y la barra de reproducción. Se corrigió la composición del cristal y se verificó que el contenido desplazable no invadiera la barra inferior.

Se abrió el panel de Sonido con sus diez bandas, presets, preamplificación, compensación de realces, balance y salida. Se observó la activación del EQ y el cambio de acento de color. Se comprobó la apertura del panel completo mediante `⌘,` y su recorte al desplazarse.

Se inició reproducción real desde la app instalada. Se observaron el avance de posición, la cola de tres canciones, el paso de Horizonte a Luz de agua y Órbita y la detención al terminar la cola. No se observaron errores de inicio del nuevo motor de audio.

## Pruebas de biblioteca y proveedores

1. Filtros combinados, múltiples palabras, acentos y favoritos.
2. LRC con múltiples marcas por línea y fracciones de segundo.
3. Metadatos y preparación de decodificación de tres M4A reales: título, artista, álbum, año, género, formato, bitrate, tamaño exacto, frecuencia, canales y letras locales.
4. Persistencia de edición y favoritos; una ubicación desconectada conserva la biblioteca, y un archivo eliminado de una ubicación accesible se retira.
5. Codificación de consultas con signos y caracteres especiales y normalización de coincidencias.
6. Consulta real a iTunes y LRCLIB: recepción de carátula y letras sin imprimir ni incluir letras ajenas en los entregables.

## Pruebas de escucha y migración

1. Presets, límites de los controles, compensación de ganancia y serialización de preferencias.
2. Playlists sin duplicados, persistencia de ajustes y listas, operaciones de cola, aleatorio sin duplicación, clasificación sin pérdida y temporizador.
3. Migración de un JSON de biblioteca 0.1 conservando favoritos y etiquetas editadas.
4. EQ real: renderiza una señal de 1 kHz y verifica que el resultado con una atenuación de 12 dB tenga menos de la mitad del RMS de la señal con EQ desactivado.
5. M4A/AAC real, mono y 22,05 kHz: pasa por el motor a 1,25× con EQ activo, convierte a salida estéreo, comprueba que el balance atenúe el canal izquierdo, verifica el salto a cinco segundos y prueba pausa, reanudación y detención.

La última prueba detectó y permitió corregir dos problemas: el control de pan de los mezcladores no alteraba la señal en esta ruta y el reloj del reproductor adelantaba la posición por el preprocesamiento. El balance utiliza ahora una Audio Unit interna con ganancias por canal y el tiempo utiliza el reloj del mezclador de salida. El control de balance se comunica con el renderizador mediante una variable atómica; no asigna memoria por muestra.

## Límites y comprobaciones pendientes

- NAS real: autenticación, latencia, reconexión y bibliotecas grandes en los servidores del usuario.
- Todos los códecs y variantes de etiquetas de la colección personal; las pruebas reales incluidas usan M4A/AAC y WAV/PCM.
- Otros Mac y versiones mínimas del sistema; el binario entregado es arm64 y requiere macOS 26+.
- Firma Developer ID y notarización antes de distribución pública.
- No incluye modo exclusivo, garantía de salida bit-perfect, crossfade, ReplayGain ni reproducción sin pausas garantizada.

Los visualizadores representan geometría reactiva al RMS, no un espectro FFT. El minirreproductor es una ventana flotante para audio, no el PiP de vídeo del sistema. La edición de etiquetas se limita a la biblioteca y no modifica los originales. La exportación JSON no tiene todavía una función de restauración automática.
