import AppKit

@MainActor
enum MainMenu {
    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             _ mods: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.tag = tag
        return i
    }

    private static func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let m = NSMenu(title: title)
        items.forEach(m.addItem)
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.submenu = m
        return i
    }

    private static var sep: NSMenuItem { .separator() }

    /// Raccourci caché (ex. ⌘= en plus de ⌘+).
    private static func alternate(_ action: Selector, _ key: String) -> NSMenuItem {
        let i = item("", action, key)
        i.isHidden = true
        i.allowsKeyEquivalentWhenHidden = true
        return i
    }

    static func build() -> NSMenu {
        let main = NSMenu()
        typealias E = EditorController
        typealias A = AppDelegate

        main.addItem(menu("NPpp", [
            item("À propos de NPpp", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            sep,
            item("Masquer NPpp", #selector(NSApplication.hide(_:)), "h"),
            item("Masquer les autres", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Tout afficher", #selector(NSApplication.unhideAllApplications(_:))),
            sep,
            item("Quitter NPpp", #selector(NSApplication.terminate(_:)), "q"),
        ]))

        main.addItem(menu("Fichier", [
            item("Nouvel onglet", #selector(A.newTab(_:)), "t"),
            item("Nouveau", #selector(A.newTab(_:)), "n"),
            item("Ouvrir…", #selector(A.openDocument(_:)), "o"),
            item("Rouvrir l'onglet fermé", #selector(A.reopenClosedTab(_:)), "t", [.command, .shift]),
            sep,
            item("Fermer l'onglet", #selector(NSWindow.performClose(_:)), "w"),
            item("Enregistrer", #selector(E.saveDocument(_:)), "s"),
            item("Enregistrer sous…", #selector(E.saveDocumentAs(_:)), "s", [.command, .shift]),
            sep,
            item("Afficher dans le Finder", #selector(E.revealInFinder(_:)), "r", [.command, .shift]),
        ]))

        let find = NSTextFinder.Action.self
        _ = find
        main.addItem(menu("Édition", [
            item("Annuler", Selector(("undo:")), "z"),
            item("Rétablir", Selector(("redo:")), "z", [.command, .shift]),
            sep,
            item("Couper", #selector(NSText.cut(_:)), "x"),
            item("Copier", #selector(NSText.copy(_:)), "c"),
            item("Coller", #selector(NSText.paste(_:)), "v"),
            item("Tout sélectionner", #selector(NSText.selectAll(_:)), "a"),
            sep,
            item("Rechercher…", #selector(E.showFind(_:)), "f"),
            item("Rechercher et remplacer…", #selector(E.showReplace(_:)), "f", [.command, .option]),
            item("Occurrence suivante", #selector(E.findNext(_:)), "g"),
            item("Occurrence précédente", #selector(E.findPrevious(_:)), "g", [.command, .shift]),
            item("Rechercher la sélection", #selector(E.useSelectionForFind(_:)), "e"),
            sep,
            menu("Lignes", [
                item("Dupliquer", #selector(E.duplicateLine(_:)), "d"),
                item("Monter", #selector(E.moveLineUp(_:)), String(UnicodeScalar(NSUpArrowFunctionKey)!), [.command, .option]),
                item("Descendre", #selector(E.moveLineDown(_:)), String(UnicodeScalar(NSDownArrowFunctionKey)!), [.command, .option]),
                item("Supprimer", #selector(E.deleteLine(_:)), "k", [.command, .shift]),
                sep,
                item("Trier (A → Z)", #selector(E.sortLinesAscending(_:))),
                item("Trier (Z → A)", #selector(E.sortLinesDescending(_:))),
                item("Inverser l'ordre", #selector(E.reverseLines(_:))),
                item("Supprimer les doublons", #selector(E.removeDuplicateLines(_:))),
            ]),
            menu("Paragraphes", [
                item("Joindre les lignes", #selector(E.joinLines(_:)), "j"),
                item("Dérouler les paragraphes (retirer les retours internes)", #selector(E.unwrapParagraphs(_:)), "j", [.command, .shift]),
                item("Séparer chaque ligne par une ligne vide", #selector(E.separateParagraphs(_:))),
                sep,
                item("Supprimer les lignes vides", #selector(E.removeBlankLines(_:))),
                item("Réduire les lignes vides multiples", #selector(E.collapseBlankLines(_:))),
            ]),
            menu("Espaces", [
                item("Supprimer les espaces en fin de ligne", #selector(E.trimTrailingWhitespace(_:))),
                item("Tabulations → espaces", #selector(E.tabsToSpaces(_:))),
                item("Espaces en début de ligne → tabulations", #selector(E.leadingSpacesToTabs(_:))),
            ]),
            menu("Casse", [
                item("MAJUSCULES", #selector(E.makeUppercase(_:)), "u", [.command, .shift]),
                item("minuscules", #selector(E.makeLowercase(_:)), "u", [.command, .option]),
                item("Majuscule À Chaque Mot", #selector(E.makeTitlecase(_:))),
                item("Majuscule en début de phrase", #selector(E.makeSentencecase(_:))),
            ]),
        ]))

        let endings = LineEnding.allCases.map { le -> NSMenuItem in
            let i = item(le.menuTitle, #selector(E.setLineEnding(_:)))
            i.representedObject = le.rawValue
            return i
        }
        let encodings = TextEncoding.all.enumerated().map { (n, e) -> NSMenuItem in
            let i = item(e.name, #selector(E.setEncoding(_:)))
            i.representedObject = n
            return i
        }
        let reopen = TextEncoding.all.enumerated().map { (n, e) -> NSMenuItem in
            let i = item(e.name, #selector(E.reopenWithEncoding(_:)))
            i.representedObject = n
            return i
        }
        main.addItem(menu("Format", [
            item("Gras", #selector(E.toggleBold(_:)), "b"),
            item("Italique", #selector(E.toggleItalic(_:)), "i"),
            item("Barré", #selector(E.toggleStrike(_:)), "x", [.command, .shift]),
            item("Code", #selector(E.toggleCode(_:)), "c", [.command, .shift]),
            item("Lien", #selector(E.insertLink(_:)), "k"),
            item("Titre (# → ## → ###)", #selector(E.cycleHeading(_:)), "h", [.command, .shift]),
            item("Case à cocher", #selector(E.toggleTask(_:)), "l", [.command, .shift]),
            sep,
            menu("Fins de ligne (conversion)", endings),
            menu("Encodage (conversion à l'enregistrement)", encodings),
            menu("Relire avec l'encodage", reopen),
        ]))

        func lang(_ title: String, _ id: String) -> NSMenuItem {
            let i = item(title, #selector(E.setLanguage(_:)))
            i.representedObject = id
            return i
        }
        main.addItem(menu("Langage", [
            lang("Automatique (extension, #!)", "auto"),
            sep,
            lang("Texte brut", "plain"),
            lang("Markdown", "markdown"),
            sep,
        ] + Syntax.languages.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }.map { lang($0.name, $0.id) }))

        main.addItem(menu("Présentation", [
            item("Texte", #selector(E.setTextMode(_:)), "1"),
            item("Côte à côte", #selector(E.setSplitMode(_:)), "2"),
            item("Aperçu", #selector(E.setPreviewMode(_:)), "3"),
            sep,
            item("Retour à la ligne automatique", #selector(A.toggleWrap(_:)), "w", [.command, .option]),
            item("Afficher les caractères invisibles", #selector(A.toggleInvisibles(_:)), "i", [.command, .option]),
            sep,
            item("Agrandir le texte", #selector(A.biggerFont(_:)), "+"),
            alternate(#selector(A.biggerFont(_:)), "="),
            item("Réduire le texte", #selector(A.smallerFont(_:)), "-"),
            item("Taille réelle", #selector(A.resetFont(_:)), "0"),
            sep,
            item("Afficher la barre d'onglets", #selector(NSWindow.toggleTabBar(_:))),
            item("Afficher tous les onglets", #selector(NSWindow.toggleTabOverview(_:)), "\\", [.command, .shift]),
            item("Plein écran", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ]))

        let windowMenu = menu("Fenêtre", [
            item("Placer dans le Dock", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Réduire / agrandir", #selector(NSWindow.performZoom(_:))),
            sep,
            item("Tout ramener au premier plan", #selector(NSApplication.arrangeInFront(_:))),
        ])
        main.addItem(windowMenu)
        NSApp.windowsMenu = windowMenu.submenu
        return main
    }
}
