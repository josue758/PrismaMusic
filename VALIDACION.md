# Validación de Prisma Music 0.8.0

8 de noviembre de 2026. Se ejecutaron **55 pruebas, sin omisiones ni fallos**, con internet, NAS SMB, inventario completo y dispositivos Core Audio habilitados. Los detalles personales de dispositivos y rutas quedan fuera del repositorio.

## Salidas y señal

Se enumeraron cinco salidas durante la prueba y se verificó que el AudioUnit del motor quedaba vinculado al identificador elegido. Esa comprobación no cambió la salida global, el volumen del sistema ni la frecuencia del dispositivo. Las preferencias migran con salida del sistema, modo directo desactivado y acceso exclusivo desactivado; la selección se guarda por UID persistente. Se comprueban elegibilidad de frecuencias y rechazo de rutas inalámbricas para modo directo.

El renderizado offline de una fuente PCM estéreo de 24 bits/48 kHz conservó exactamente los patrones de bits de 4.096 muestras decodificadas por canal. El EQ, balance, velocidad y volumen de Prisma se configuraron deliberadamente para alterar el audio: la ruta directa los omitió y mantuvo ganancia unitaria. Esta prueba acredita el grafo interno en esas condiciones. No certifica un DAC físico, su controlador, su profundidad real de salida ni ausencia de procesamiento del sistema. No se adquirió acceso exclusivo ni se alteró la frecuencia de un DAC físico durante esta validación.

La ruta directa solicita frecuencia nativa y, si se habilita, acceso exclusivo. Verifica la frecuencia y el propietario de la reserva antes de presentar su estado; intenta restaurar la frecuencia anterior y liberar la reserva al cambiar de ruta o cerrar. El soporte de cada controlador puede variar. Una salida seleccionada que desaparece pausa la reproducción y no se redirige automáticamente a otros altavoces.

## AirPlay

El selector nativo de AVKit se conecta a un AVPlayer real. Se comprobó la preparación de un FLAC de 24 bits/96 kHz del NAS como AVPlayerItem listo para reproducir. Una regresión comprueba que detener el transporte anterior no pausa la nueva canción y que el objeto antiguo no puede iniciar el nuevo elemento.

La ruta AirPlay no usa el EQ, balance ni modo directo del motor Core Audio. El panel distingue la ruta del sistema de una reproducción externa confirmada y permite volver a la salida local. En la revisión visual el menú nativo se abrió, pero solo mostró este Mac: **no se validó una transferencia a un receptor AirPlay físico**.

## Artistas y diseño

Se validaron biografías en español y fotografías con atribución y licencia para una banda y una solista mediante Wikipedia/Wikimedia; también se descargó una de las miniaturas reales. La selección rechaza nombres ambiguos o textos sin indicación musical. Se contemplan metadatos de licencia con valores numéricos ajenos a los campos de crédito y los servidores oficiales de miniaturas de Wikimedia.

Las colaboraciones etiquetadas con punto y coma se agrupan por participante; las fichas y filtros incluyen esas colaboraciones sin duplicar una pista dentro de una ficha. Se comprueba que la colección calculada se invalida al editar la biblioteca. Las consultas de artista se reutilizan entre actualizaciones del medidor de audio; no se descargan biografías para toda la cuadrícula.

La ficha integra una cabecera fotográfica amplia, fondo difuminado, paleta extraída de la foto, contraste para el texto y superficies de cristal. Los álbumes filtran sus canciones y desplazan la ficha a la lista. Se corrigen separadores de año vacío y singular de canción. El icono de Dispositivos de audio permanece fijo y separado de AirPlay, incluso cuando cambia la ruta. Se verificó en la app instalada la foto real de Adele, su biografía en español y el icono de altavoz mientras estaba abierto el menú nativo AirPlay. Las fotografías verticales se encuadran completas para no recortar el rostro.

## Distribución y límites

Compilación arm64 para macOS 26 o posterior, con firma ad hoc. Todavía no tiene Developer ID ni notarización. No hay certificación general bit-perfect ni garantía de compatibilidad con todos los DAC o receptores. Los informes, UID de dispositivos, rutas del NAS y música personal no se distribuyen. Las llamadas del sistema a NAS y controladores pueden tardar; el procesamiento principal de apertura y consulta se realiza fuera de la interfaz.

## Verificaciones de versiones anteriores

### Prisma Music 0.7.1

8 de noviembre de 2026. Se ejecutaron **46 pruebas, sin omisiones ni fallos**, con NAS, inventario completo e internet activados. La compilación de pruebas no emitió advertencias del compilador. Se mantienen los resultados de validación de la colección descritos más abajo.

## Respuesta durante la carga de audio

Se trasladó la apertura de AVAudioFile a un actor dedicado, con una apertura simultánea como máximo. El archivo abierto se entrega exclusivamente al reproductor; la construcción y el control del motor siguen en el hilo principal. Una prueba comprueba que la apertura real se ejecuta fuera de ese hilo.

Cuatro regresiones de carga verifican que la búsqueda responde mientras una apertura está suspendida; un error de una solicitud antigua no reemplaza el de la última selección; cancelar o salir rechaza incluso una respuesta tardía exitosa; Siguiente avanza desde la selección pendiente; y restaurar una sesión no contacta el audio hasta solicitar reproducir. La posición restaurada se conserva y se ignoran saltos no finitos. Otra regresión comprueba que, al terminar una pista y fallar la siguiente, el estado no quede atascado en «reproduciendo».

La prueba real por SMB utilizó el nuevo cargador, decodificó un FLAC de 24 bits/96 kHz y comprobó seek, pausa y reanudación. La apertura de ese archivo tardó 0,036 segundos en esa ejecución con las cachés ya utilizadas. No representa una medición en frío ni garantiza ese tiempo para otros archivos o estados del servidor. El recorrido volvió a coincidir exactamente con los 7.854 archivos de referencia, en 32,5 segundos.

Las llamadas bloqueantes del sistema no se interrumpen por la fuerza al cancelar. La interfaz descarta sus respuestas y limita la concurrencia; otra apertura puede esperar a que termine la operación anterior. No se garantiza ausencia de cortes bajo toda condición de red ni se mide aquí reproducción sin separación entre pistas.

## Formato real y revisión instalada

Se detectó una incidencia adicional durante el escaneo incremental: un archivo con extensión FLAC tenía contenido M4A/AAC válido, verificado independientemente con AudioToolbox. El lector rápido anterior lo rechazaba. Ahora se identifica el contenedor y se proporciona el MIME correcto a AVFoundation, conservando el nombre y los bytes del original. Una regresión usa una copia M4A con extensión FLAC y también se activó con el archivo real del NAS; ambos se identificaron como M4A · AAC, con duración válida y sin la insignia de audio sin pérdida. El reintento sobre la biblioteca real recuperó esta incidencia: 1 archivo actualizado, 7.812 sin cambios y 41 fallos previos, manteniendo las 7.813 canciones. La clasificación utiliza el códec, no la aparición de «FLAC» en la extensión o el texto del contenedor.

En la app instalada se inició un FLAC del NAS mientras se escaneaba la colección, se pulsó Siguiente dos veces seguidas y se verificó que quedó reproduciendo la tercera pista. Se abrió la información técnica durante la reproducción y se comprobó la pausa. La etiqueta Recientes aparece completa en la barra lateral. Una muestra puntual tras pausar indicó 288 MiB residentes y 0,2 % de CPU; no es una medición de pico ni un límite garantizado.

## Pruebas automatizadas

En la validación 0.7.0: 40 pruebas aprobadas, 0 omitidas, 0 fallos, con `PRISMA_LIVE_NETWORK=1`, un FLAC de un NAS SMB montado y un inventario independiente como referencia. Las tres comprobaciones externas se omiten en una ejecución sin esas opciones. No se publican nombres ni rutas de la colección personal.

El recorrido nativo encontró exactamente los mismos 7.854 archivos que el inventario independiente: 7.487 FLAC y 367 M4A. No hubo diferencias de conjuntos ni errores de directorio en esa prueba. Tiempo de recorrido en la ejecución final: 50,7 segundos; depende del servidor y sus cachés.

La prueba de reproducción abrió un FLAC real directamente por SMB, decodificó audio con AVAudioEngine, comprobó energía, salto temporal a 30 segundos, pausa y reanudación. El archivo de prueba era estéreo, 24 bits/96 kHz, con bitrate estimado de 2.960.172 bit/s. Se renderizó sin activar los altavoces. Esto no certifica cada muestra de audio de la colección.

La bienvenida tiene pruebas de migración y persistencia, finalización, reapertura desde Ajustes y conservación del ecualizador al aplicar estilos. El reintento selectivo recupera un audio de prueba reparado y conserva registros ajenos al reintento, incluso si sus originales ya no están presentes.

También se cubren importación paralela de 48 archivos, omisión de archivos sin cambios, edición y favoritos durante la lectura, concurrencia configurable, cancelación, cierre durante la carga inicial, carpetas inaccesibles, fuentes superpuestas, cambios de identidad, paquetes/enlaces/ocultos, archivos auxiliares sin distinguir mayúsculas, comentarios Vorbis Unicode, fechas, letras e imágenes FLAC, rechazo de cabeceras llenas de ceros, corrupción SQLite/JSON, migración, imágenes deduplicadas, escritura incremental, filtros, playlists, cola, EQ renderizado, balance, velocidad, temporizador, paletas, contraste, reloj visual y Deshacer.

La prueba de escritura inicial de 10.000 registros tardó aproximadamente 0,05 segundos en una ejecución local. No mide importación de audio ni latencia de red. Las cachés usan objetivos orientativos de 8 MiB comprimidos y 32 MiB de imágenes decodificadas; no son un límite de RAM total.

## Biblioteca personal

La lectura completa inicial incorporó 7.813 de 7.854 archivos. Las 41 entradas restantes coincidían exactamente con las rutas del informe de errores; no hubo entradas adicionales. Al menos un archivo que falló contenía una cabecera llena de ceros y fue rechazado también por AVFoundation. No se modificaron los audios originales. El reintento selectivo confirmó las mismas 41 incidencias y no eliminó ninguna de las 7.813 canciones: 18 rutas listadas por el NAS no se pudieron abrir porque el sistema devolvió archivo inexistente, 17 archivos tenían sus primeros 16 bytes a cero y 6 devolvieron lectura vacía. Estos resultados se comprobaron además con lecturas independientes de solo lectura. No se sustituyeron ni borraron archivos del servidor.

## Revisión instalada

Se instaló y abrió la 0.7.0 con la biblioteca personal. Se verificaron la bienvenida, el cambio inmediato entre español, inglés y portugués, su reapertura desde Ajustes, el acceso al editor de etiquetas y al formulario NAS, la biblioteca con 7.813 canciones y el progreso de escaneo. Se amplió la barra lateral para evitar recortar «Canciones» junto al contador y se actualizó la identificación visual de versión.

Una muestra puntual durante la exploración con la colección completa indicó unos 296 MiB de memoria residente y 12,8 % de CPU. Es una observación de ese instante, no una garantía de consumo ni una medición de pico. Las pruebas automatizadas cubren los estilos y su conservación de los ajustes de sonido; no se comprobó cada control en todas sus combinaciones.

## Límites de la distribución

El instalador es arm64, requiere macOS 26 o posterior y usa firma ad hoc. Falta Developer ID y notarización. No hay pruebas Intel ni garantía de ausencia de errores. La apertura inicial del decodificador y algunas llamadas SMB pueden tardar si el servidor no responde, incluso después de solicitar cancelación. No se expulsó el volumen durante la reproducción para simular una desconexión.

Las correcciones de etiquetas se guardan en Prisma sin escribir en el audio original. Los informes y las copias JSON contienen rutas personales; no se incluyen en el repositorio ni en el instalador. El informe conserva hasta 500 detalles de error, además de los contadores completos. No hay restauración guiada de copias desde la interfaz.
