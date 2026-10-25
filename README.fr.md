# NPpp

Éditeur de texte et de Markdown minimaliste pour macOS, inspiré de Notepad++.
Application native (Swift / AppKit), sans dépendance. Xcode n'est pas nécessaire : les Command Line Tools suffisent.

## Compiler

```bash
./build.sh            # produit dist/NPpp.app
./build.sh install    # copie aussi l'app dans ~/Applications
```

## Fonctions

**Onglets et session**
- Onglets natifs macOS : ⌘T nouvel onglet, ⌘W fermer, ⇧⌘T rouvrir le dernier onglet fermé, ⌃Tab onglet suivant.
- Au lancement, NPpp rouvre les onglets de la session précédente, y compris les modifications non enregistrées et les onglets « Sans titre ».
- Quitter (⌘Q) ne pose aucune question : tout est conservé.
- Un fichier modifié par une autre application (Dropbox, autre éditeur) est rechargé automatiquement. Si vous avez aussi des modifications non enregistrées, NPpp vous demande quelle version garder.

**Affichage** (⌘1, ⌘2, ⌘3)
- Texte, côte à côte (avec défilement synchronisé) ou aperçu Markdown formaté.
- L'aperçu gère les titres, listes et cases à cocher, tableaux, citations, callouts `> [!NOTE]`, code, liens, `[[wikilinks]]`, images relatives, front matter YAML, `==surlignage==` et le mode sombre.
- Un clic sur un lien vers un `.md` l'ouvre dans un nouvel onglet.

**Coloration syntaxique**

Langages reconnus :
- Shell (Bash, Zsh, sh)
- Python
- HTML, avec le CSS et le JavaScript intégrés
- XML
- CSS et SCSS
- JavaScript et TypeScript
- JSON
- YAML
- INI, TOML et `.conf`
- SQL
- Swift
- PowerShell
- C, C++ et Objective-C
- Java et Kotlin
- Go
- Rust
- Dockerfile
- Makefile
- Diff

Le langage est détecté par l'extension, par le nom du fichier (`.zshrc`, `Dockerfile`…) ou par la ligne `#!`. Le menu **Langage** permet de le forcer, et ce choix est mémorisé avec l'onglet.

Dans le Markdown, les blocs ` ```python `, ` ```bash `… sont colorés dans l'éditeur comme dans l'aperçu.

Pour ajouter un langage : `Sources/NPpp/SyntaxDefinitions.swift`.

**Rechercher / Remplacer** (⌘F, ⌥⌘F)
- `Aa` respecte la casse, `Mot` cherche le mot entier, `.*` active les expressions régulières, `\n` active le mode étendu.
- En regex, `\1` ou `$1` dans le remplacement, et `\n` / `\t` sont acceptés.
- Toutes les occurrences sont surlignées avec un compteur. ↩ passe à la suivante, ⇧↩ à la précédente.
- « Tout remplacer » s'annule en une seule fois avec ⌘Z. `Sél.` limite le remplacement à la sélection.

**Format**
- Fins de ligne : conversion entre LF, CRLF et CR. La fin de ligne du fichier est détectée et affichée dans la barre d'état.
- Encodage : UTF-8 (avec ou sans BOM), UTF-16, ISO-8859-1, Windows-1252, Mac Roman. « Relire avec l'encodage » corrige les accents mal décodés.
- Paragraphes :
  - joindre les lignes (⌘J)
  - dérouler les paragraphes, c'est-à-dire retirer les retours à la ligne internes (⇧⌘J)
  - séparer les lignes par une ligne vide
  - supprimer ou réduire les lignes vides
- Lignes :
  - dupliquer (⌘D)
  - monter ou descendre (⌥⌘↑ / ⌥⌘↓)
  - supprimer (⇧⌘K)
  - trier, inverser, supprimer les doublons
- Espaces : supprimer les espaces en fin de ligne, tabulations ↔ espaces.
- Casse : MAJUSCULES, minuscules, Titre, Phrase.
- Markdown :
  - gras (⌘B), italique (⌘I), code (⇧⌘C), lien (⌘K)
  - titre (⇧⌘H, passe de # à ## à ###)
  - case à cocher (⇧⌘L)

**Présentation**
- Caractères invisibles (⌥⌘I) : espaces ·, tabulations →, et étiquettes LF / CRLF / CR en fin de ligne.
- Retour à la ligne automatique (⌥⌘W) et taille du texte (⌘+, ⌘−, ⌘0).

## Emplacements

- Code : `Sources/NPpp/`
- Session : `~/Library/Application Support/NPpp/session.json`
