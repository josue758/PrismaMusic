import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case es, en, pt
    var id: String { rawValue }
    var name: String { switch self { case .es: "Español"; case .en: "English"; case .pt: "Português" } }
}
enum Accent: String, CaseIterable, Identifiable {
    case violet, ocean, rose, mint, amber
    var id: String { rawValue }
    var color: Color { switch self { case .violet: Color(red: 0.62, green: 0.48, blue: 1); case .ocean: .cyan; case .rose: .pink; case .mint: .mint; case .amber: .orange } }
}
let translations: [String: [String]] = [
 "fileInfo": ["Información del archivo", "File information", "Informações do arquivo"],
 "format": ["Formato / códec", "Format / codec", "Formato / codec"],
 "bitrate": ["Bitrate estimado", "Estimated bitrate", "Bitrate estimado"],
 "fileSize": ["Tamaño", "File size", "Tamanho"],
 "sampleRate": ["Frecuencia de muestreo", "Sample rate", "Taxa de amostragem"],
 "channels": ["Canales", "Channels", "Canais"],
 "bitDepth": ["Profundidad de bits", "Bit depth", "Profundidade de bits"],
 "location": ["Ubicación", "Location", "Localização"],
 "duration": ["Duración", "Duration", "Duração"],
 "unavailable": ["No disponible", "Unavailable", "Indisponível"],
 "bitrateNote": ["El bitrate corresponde al flujo de audio y puede variar durante la canción. El tamaño corresponde al archivo completo.", "Bitrate describes the audio stream and may vary during the song. Size refers to the complete file.", "O bitrate descreve o fluxo de áudio e pode variar durante a música. O tamanho corresponde ao arquivo completo."],
 "tagline": ["TU MÚSICA. TU ESPACIO.", "YOUR SOUND. YOUR SPACE.", "SUA MÚSICA. SEU ESPAÇO."],
 "localAudio": ["AUDIO LOCAL", "LOCAL AUDIO", "ÁUDIO LOCAL"],
 "library": ["Biblioteca", "Library", "Biblioteca"], "songs": ["Canciones", "Songs", "Músicas"], "albums": ["Álbumes", "Albums", "Álbuns"],
 "artists": ["Artistas", "Artists", "Artistas"], "favorites": ["Favoritos", "Favorites", "Favoritos"], "sources": ["Ubicaciones", "Locations", "Locais"],
 "add": ["Añadir música", "Add music", "Adicionar músicas"], "search": ["Buscar canción, artista, álbum…", "Search song, artist, album…", "Buscar música, artista, álbum…"],
 "allArtists": ["Todos los artistas", "All artists", "Todos os artistas"], "allGenres": ["Todos los géneros", "All genres", "Todos os gêneros"], "allYears": ["Todos los años", "All years", "Todos os anos"],
 "title": ["Título", "Title", "Título"], "artist": ["Artista", "Artist", "Artista"], "album": ["Álbum", "Album", "Álbum"], "genre": ["Género", "Genre", "Gênero"], "year": ["Año", "Year", "Ano"],
 "play": ["Reproducir", "Play", "Reproduzir"], "pause": ["Pausar", "Pause", "Pausar"], "shuffle": ["Aleatorio", "Shuffle", "Aleatório"], "repeat": ["Repetir", "Repeat", "Repetir"],
 "lyrics": ["Letras", "Lyrics", "Letras"], "visualizer": ["Visualizador", "Visualizer", "Visualizador"], "settings": ["Ajustes", "Settings", "Ajustes"], "full": ["Pantalla completa", "Full screen", "Tela cheia"],
 "mini": ["Minirreproductor flotante", "Floating mini player", "Minirreprodutor flutuante"], "scan": ["Actualizar biblioteca", "Refresh library", "Atualizar biblioteca"],
 "demo": ["Sesiones Prisma · música de demostración", "Prisma Sessions · demo music", "Sessões Prisma · músicas de demonstração"],
 "demoNote": ["Tres piezas originales para probar. Añade tu música para empezar.", "Three original pieces to try. Add your music to get started.", "Três peças originais para testar. Adicione suas músicas para começar."],
 "empty": ["Tu próxima canción está aquí", "Your next song starts here", "Sua próxima música começa aqui"], "emptyNote": ["Añade una carpeta del Mac o un NAS montado en Finder.", "Add a Mac folder or a NAS mounted in Finder.", "Adicione uma pasta do Mac ou um NAS montado no Finder."],
 "noResults": ["Sin resultados", "No results", "Sem resultados"], "clear": ["Limpiar filtros", "Clear filters", "Limpar filtros"],
 "now": ["AHORA SUENA", "NOW PLAYING", "TOCANDO AGORA"], "choose": ["Elige una canción", "Choose a song", "Escolha uma música"],
 "noLyrics": ["No hay letras disponibles", "No lyrics available", "Letras indisponíveis"], "fetch": ["Buscar carátula y letras", "Find artwork and lyrics", "Buscar capa e letras"],
 "online": ["Completar desde internet", "Complete from the internet", "Completar pela internet"],
 "privacy": ["Al reproducir, envía título, artista, álbum y duración a iTunes y LRCLIB para buscar carátulas y letras faltantes. No sube archivos de audio.", "On playback, sends title, artist, album and duration to iTunes and LRCLIB to find missing artwork and lyrics. Audio files are never uploaded.", "Ao reproduzir, envia título, artista, álbum e duração ao iTunes e LRCLIB para buscar capas e letras ausentes. Não envia arquivos de áudio."],
 "appearance": ["Apariencia", "Appearance", "Aparência"], "language": ["Idioma", "Language", "Idioma"], "theme": ["Tema", "Theme", "Tema"], "system": ["Sistema", "System", "Sistema"], "dark": ["Oscuro", "Dark", "Escuro"], "light": ["Claro", "Light", "Claro"],
 "startScan": ["Leer etiquetas al iniciar", "Read tags on launch", "Ler etiquetas ao iniciar"], "connect": ["Conectar a un NAS…", "Connect to a NAS…", "Conectar a um NAS…"],
 "nasHelp": ["Introduce smb://servidor/recurso. Finder gestiona el acceso; después añade la carpeta montada.", "Enter smb://server/share. Finder handles access; then add the mounted folder.", "Digite smb://servidor/recurso. O Finder gerencia o acesso; depois adicione a pasta montada."],
 "cancel": ["Cancelar", "Cancel", "Cancelar"], "connectButton": ["Abrir en Finder", "Open in Finder", "Abrir no Finder"],
 "reveal": ["Mostrar en Finder", "Show in Finder", "Mostrar no Finder"], "remove": ["Quitar de la biblioteca", "Remove from library", "Remover da biblioteca"],
 "edit": ["Editar etiquetas de biblioteca", "Edit library tags", "Editar etiquetas da biblioteca"], "save": ["Guardar", "Save", "Salvar"],
 "tagNote": ["Los cambios se guardan en Prisma; no modifican el archivo original.", "Changes are saved in Prisma; the original file stays untouched.", "As alterações são salvas no Prisma; o arquivo original permanece intacto."],
 "ready": ["Biblioteca al día", "Library up to date", "Biblioteca atualizada"], "reading": ["Leyendo etiquetas…", "Reading tags…", "Lendo etiquetas…"],
 "offline": ["No se pudo acceder a una ubicación. Conecta el NAS en Finder y actualiza.", "A location is unavailable. Connect the NAS in Finder and refresh.", "Um local está indisponível. Conecte o NAS no Finder e atualize."],
 "networkError": ["Búsqueda incompleta: comprueba tu conexión e inténtalo de nuevo.", "Search incomplete: check your connection and try again.", "Busca incompleta: verifique a conexão e tente novamente."],
 "notFound": ["Sin coincidencia en internet. Puedes usar cover.jpg y archivos .lrc junto al audio.", "No online match. You can place cover.jpg and .lrc files beside the audio.", "Sem correspondência online. Use cover.jpg e arquivos .lrc junto ao áudio."],
 "finished": ["Metadatos actualizados", "Metadata updated", "Metadados atualizados"], "volume": ["Volumen", "Volume", "Volume"],
 "removeSource": ["Quitar ubicación", "Remove location", "Remover local"], "count": ["canciones", "songs", "músicas"],
 "version": ["Versión local 0.1 · Swift + SwiftUI", "Local version 0.1 · Swift + SwiftUI", "Versão local 0.1 · Swift + SwiftUI"],
 "autoTag": ["Etiquetas automáticas", "Automatic tags", "Etiquetas automáticas"], "autoTagNote": ["Lee título, artista, álbum, género y año del archivo. Los originales se conservan.", "Reads title, artist, album, genre and year from each file. Originals are preserved.", "Lê título, artista, álbum, gênero e ano de cada arquivo. Os originais são preservados."],
 "pipNote": ["Ventana flotante para audio, visible en todos los escritorios. No usa el PiP de vídeo de macOS.", "Floating audio window, visible on all desktops. Does not use macOS video PiP.", "Janela flutuante de áudio, visível em todas as mesas. Não usa o PiP de vídeo do macOS."],
 "next": ["Siguiente", "Next", "Próxima"], "previous": ["Anterior", "Previous", "Anterior"],
 "scanErrors": ["Algunos archivos no pudieron leerse", "Some files could not be read", "Alguns arquivos não puderam ser lidos"],
 "sort": ["Ordenar", "Sort", "Ordenar"], "added": ["Orden de importación", "Import order", "Ordem de importação"]
]
