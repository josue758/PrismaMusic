import AppKit

@MainActor
enum MenuLocalization {
    // Relabel the native commands in place so their actions and shortcuts stay with AppKit.
    static func apply(to mainMenu: NSMenu, language: AppLanguage) {
        for item in mainMenu.items {
            guard let menu = item.submenu else { continue }
            let titles = titlesByOriginal[item.title]
            if let title = titles?[language], title != item.title {
                menu.title = title
                item.title = title
            }
            localizeItems(in: menu, language: language)
        }
    }

    private static func localizeItems(in menu: NSMenu, language: AppLanguage) {
        for item in menu.items where !item.isSeparatorItem {
            // The Window menu can include user window titles. Only touch known system commands.
            if let titles = titlesByOriginal[item.title], item.action != NSSelectorFromString("makeKeyAndOrderFront:") {
                let title = titles[language]
                if title != item.title { item.title = title }
                if titles.en != "Services", let submenu = item.submenu {
                    submenu.title = title
                    localizeItems(in: submenu, language: language)
                }
            }
        }
    }

    private struct Titles {
        let en: String
        let es: String
        let pt: String

        subscript(language: AppLanguage) -> String {
            switch language {
            case .en: en
            case .es: es
            case .pt: pt
            }
        }

        init(_ en: String, _ es: String, _ pt: String) {
            self.en = en
            self.es = es
            self.pt = pt
        }
    }

    private static let titlesByOriginal: [String: Titles] = {
        let entries: [Titles] = [
            .init("File", "Archivo", "Arquivo"),
            .init("Edit", "Edición", "Editar"),
            .init("View", "Visualización", "Visualizar"),
            .init("Window", "Ventana", "Janela"),
            .init("Help", "Ayuda", "Ajuda"),
            .init("About Prisma Music", "Acerca de Prisma Music", "Sobre o Prisma Music"),
            .init("Services", "Servicios", "Serviços"),
            .init("Hide Prisma Music", "Ocultar Prisma Music", "Ocultar o Prisma Music"),
            .init("Hide Others", "Ocultar otras apps", "Ocultar Outros"),
            .init("Show All", "Mostrar todo", "Mostrar Tudo"),
            .init("Quit Prisma Music", "Salir de Prisma Music", "Encerrar o Prisma Music"),
            .init("New Prisma Music Window", "Nueva ventana de Prisma Music", "Nova janela do Prisma Music"),
            .init("New Window", "Nueva ventana", "Nova janela"),
            .init("Close", "Cerrar", "Fechar"),
            .init("Close All", "Cerrar todo", "Fechar Todas"),
            .init("Undo", "Deshacer", "Desfazer"),
            .init("Redo", "Rehacer", "Refazer"),
            .init("Cut", "Cortar", "Recortar"),
            .init("Copy", "Copiar", "Copiar"),
            .init("Paste", "Pegar", "Colar"),
            .init("Paste and Match Style", "Pegar con el mismo estilo", "Colar e Combinar Estilo"),
            .init("Delete", "Eliminar", "Apagar"),
            .init("Select All", "Seleccionar todo", "Selecionar Tudo"),
            .init("Find", "Buscar", "Buscar"),
            .init("Find…", "Buscar…", "Buscar…"),
            .init("Find and Replace…", "Buscar y reemplazar…", "Buscar e Substituir…"),
            .init("Find Next", "Buscar siguiente", "Buscar Seguinte"),
            .init("Find Previous", "Buscar anterior", "Buscar Anterior"),
            .init("Use Selection for Find", "Usar selección para buscar", "Usar Seleção para Buscar"),
            .init("Jump to Selection", "Ir a la selección", "Ir para a Seleção"),
            .init("Spelling and Grammar", "Ortografía y gramática", "Ortografia e Gramática"),
            .init("Show Spelling and Grammar", "Mostrar ortografía y gramática", "Mostrar Ortografia e Gramática"),
            .init("Check Document Now", "Revisar documento ahora", "Verificar Documento Agora"),
            .init("Check Spelling While Typing", "Revisar ortografía al escribir", "Verificar Ortografia ao Digitar"),
            .init(
                "Check Grammar With Spelling", "Revisar gramática y ortografía", "Verificar Gramática com Ortografia"),
            .init(
                "Correct Spelling Automatically", "Corregir ortografía automáticamente",
                "Corrigir Ortografia Automaticamente"),
            .init("Substitutions", "Sustituciones", "Substituições"),
            .init("Smart Copy/Paste", "Copiar y pegar de forma inteligente", "Copiar e Colar Inteligentes"),
            .init("Smart Quotes", "Comillas tipográficas", "Aspas Inteligentes"),
            .init("Smart Dashes", "Guiones inteligentes", "Traços Inteligentes"),
            .init("Smart Links", "Enlaces inteligentes", "Links Inteligentes"),
            .init("Data Detectors", "Detectores de datos", "Detectores de Dados"),
            .init("Text Replacement", "Reemplazo de texto", "Substituição de Texto"),
            .init("Show Substitutions", "Mostrar sustituciones", "Mostrar Substituições"),
            .init("Transformations", "Transformaciones", "Transformações"),
            .init("Make Upper Case", "Convertir a mayúsculas", "Usar Maiúsculas"),
            .init("Make Lower Case", "Convertir a minúsculas", "Usar Minúsculas"),
            .init("Capitalize", "Poner iniciales en mayúscula", "Usar Iniciais Maiúsculas"),
            .init("Speech", "Voz", "Fala"),
            .init("Start Speaking", "Iniciar locución", "Começar a Falar"),
            .init("Stop Speaking", "Detener locución", "Parar de Falar"),
            .init("AutoFill", "Autorrelleno", "Preenchimento Automático"),
            .init("Toggle Sidebar", "Mostrar u ocultar la barra lateral", "Mostrar ou ocultar a barra lateral"),
            .init("Start Dictation…", "Iniciar dictado…", "Iniciar Ditado…"),
            .init("Emoji & Symbols", "Emojis y símbolos", "Emojis e Símbolos"),
            .init("Enter Full Screen", "Activar pantalla completa", "Entrar em Tela Cheia"),
            .init("Exit Full Screen", "Salir de pantalla completa", "Sair da Tela Cheia"),
            .init("Minimize", "Minimizar", "Minimizar"),
            .init("Zoom", "Ampliar", "Zoom"),
            .init("Fill", "Llenar", "Preencher"),
            .init("Center", "Centrar", "Centralizar"),
            .init("Move & Resize", "Mover y redimensionar", "Mover e Redimensionar"),
            .init("Bring All to Front", "Traer todo al frente", "Trazer Tudo para Frente"),
            .init("Prisma Music Help", "Ayuda de Prisma Music", "Ajuda do Prisma Music"),
        ]
        var titles: [String: Titles] = [:]
        for entry in entries {
            for title in [entry.en, entry.es, entry.pt] { titles[title] = entry }
        }
        let alternatives = [
            "Ocultar otros": "Hide Others",
            "Ocultar outras aplicações": "Hide Others",
            "Fechar tudo": "Close All",
            "Ficheiro": "File",
            "Edição": "Edit",
            "Visualização": "View",
            "Aumentar/reduzir": "Zoom",
            "Maximizar": "Zoom",
        ]
        for (original, key) in alternatives { titles[original] = titles[key] }
        return titles
    }()
}
