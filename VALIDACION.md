# Validación de Prisma Music 0.1.0

Fecha: 7 de noviembre de 2026. Entorno: macOS 27.2, Apple Silicon, Xcode 27.2, Swift 6.4.2.

## Resultado

- Compilación de producción completada.
- Aplicación instalada y abierta desde `/Applications/Prisma Music.app`, con recursos del paquete instalado.
- Firma ad hoc verificada mediante `codesign --verify --deep --strict`: válida en disco.
- Instalador DMG verificado mediante `hdiutil verify`: checksum válido. Binario arm64.
- `PRISMA_LIVE_NETWORK=1 swift test`: **6 pruebas ejecutadas, 0 fallos**, incluida la consulta real a iTunes y LRCLIB. Las letras obtenidas durante la prueba no se incluyen en los entregables.

## Verificación en interfaz nativa

Se observó la aplicación instalada y se probaron reproducción con avance temporal, visualizador y apertura/cierre del minirreproductor flotante. Se abrió el panel de información y se comprobaron los datos reales de la canción demo Horizonte: M4A/AAC, aproximadamente 67 kb/s, 204 KB / 203.577 bytes, 22,05 kHz, mono. Se observaron las tres canciones con título, artista, álbum, género y año extraídos del archivo. También se observó el panel de letras LRC locales.

## Pruebas automatizadas

1. Filtros combinados, múltiples palabras, búsqueda sin distinción de acentos y favoritos.
2. LRC con múltiples marcas por línea, orden temporal y fracciones de segundo.
3. Lectura de tres archivos M4A reales y preparación de decodificación con AVAudioPlayer. Verifica títulos, años, géneros, duración, formato/códec, bitrate, tamaño exacto, frecuencia, canales y letras locales.
4. Persistencia de etiquetas editadas y favoritos tras reescaneo y reapertura; una ubicación desconectada conserva la biblioteca y un archivo eliminado de una ubicación accesible se retira.
5. Codificación de consultas con signos y caracteres especiales, y normalización de coincidencias.
6. Consulta real a iTunes y LRCLIB para una canción pública conocida; confirma recepción de una carátula y letras sin imprimir su contenido.

## Pendiente de validación con el usuario

- NAS real: autenticación, reconexión, latencia y tamaño de la biblioteca en sus servidores.
- Compatibilidad de todos los códecs y variantes de etiquetas de la colección personal.
- Funcionamiento en otros Mac y versiones mínimas del sistema.
- Firma Developer ID y notarización para distribución pública.

El minirreproductor es un NSPanel flotante para audio. No implementa PiP de vídeo del sistema. La edición de etiquetas se limita a la biblioteca; no modifica los originales. El visualizador representa geometría reactiva al nivel RMS, no un espectro FFT.
