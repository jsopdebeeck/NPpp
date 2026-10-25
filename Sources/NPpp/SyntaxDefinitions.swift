import Foundation

/// Grammaires des langages. Pour en ajouter un : une entrée dans `all`, une liste de règles
/// dans l'ordre de priorité (commentaires et chaînes d'abord).
enum SyntaxDefinitions {
    // Motifs communs
    static let dq = ##""(?:[^"\\\n]|\\.)*"?"##
    static let sq = ##"'(?:[^'\\\n]|\\.)*'?"##
    static let cComment = ##"//[^\n]*|/\*[\s\S]*?(?:\*/|\z)"##
    static let number = ##"\b(?:0[xX][\da-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)[uUlLfFdD]*\b"##
    static let call = ##"\b[A-Za-z_]\w*(?=\s*\()"##
    static let typeName = ##"\b[A-Z][A-Za-z0-9_]*\b"##

    static func kw(_ words: String) -> String {
        "\\b(?:" + words.split(separator: " ").joined(separator: "|") + ")\\b"
    }

    static let all: [SyntaxLanguage] = [
        shell, python, html, xml, css, javascript, typescript, json, yaml, toml,
        sql, swift, powershell, c, java, go, rust, dockerfile, makefile, diff,
    ]

    // MARK: Shell (Bash, Zsh, sh)

    static let shellVar = SyntaxRule(##"\$\{[^}\n]*\}|\$[A-Za-z_]\w*|\$[@*#?$!0-9-]"##, .variable)

    static let shell = SyntaxLanguage(
        id: "shell", name: "Shell (Bash, Zsh)",
        extensions: ["sh", "bash", "zsh", "ksh", "command", "tool"],
        fileNames: [".bashrc", ".bash_profile", ".bash_login", ".bash_logout", ".profile", ".zshrc", ".zprofile",
                    ".zshenv", ".zlogin", ".zlogout", ".kshrc", ".envrc"],
        shebangs: ["bash", "sh", "zsh", "ksh", "dash"],
        aliases: ["bash", "sh", "zsh", "shell", "console", "shellscript", "ksh"],
        rules: [
            SyntaxRule(##"(?<![\w$#{\\])#[^\n]*"##, .comment),
            SyntaxRule(##"<<-?[ \t]*['"]?(?<hd>[A-Za-z_]\w*)['"]?[^\n]*\n[\s\S]*?^[ \t]*\k<hd>$"##, .string),
            SyntaxRule(##""(?:[^"\\]|\\[\s\S])*"?"##, .string, inner: [
                shellVar, SyntaxRule(##"\$\([^)\n]*\)"##, .variable),
            ]),
            SyntaxRule(##"'[^']*'?"##, .string),
            SyntaxRule(##"`[^`]*`?"##, .meta),
            shellVar,
            SyntaxRule(##"(?<=\bfunction[ \t])[\w.:-]+|^[ \t]*[A-Za-z_][\w.:-]*(?=[ \t]*\(\))"##, .function),
            SyntaxRule(kw("if then else elif fi case esac for while until do done in function select time return exit break continue local export readonly declare typeset unset source alias unalias set shift trap eval exec let coproc"), .keyword),
            SyntaxRule(kw("echo printf read cd pushd popd pwd test true false kill wait jobs bg fg type which command builtin getopts ulimit umask mkdir rmdir rm cp mv ls cat grep egrep sed awk find chmod chown curl wget git sudo ssh scp rsync tar zip unzip tee sort uniq head tail xargs cut tr wc date sleep touch ln brew open defaults launchctl osascript autoload compinit setopt unsetopt bindkey zstyle print python3 python pip pip3 node npm npx docker kubectl make"), .function),
            SyntaxRule(##"\b[A-Za-z_]\w*(?=\+?=)"##, .variable),
            SyntaxRule(##"(?<=[ \t])--?[A-Za-z][\w-]*"##, .attribute),
            SyntaxRule(##"\b\d+\b"##, .number),
        ])

    // MARK: Python

    static let python = SyntaxLanguage(
        id: "python", name: "Python",
        extensions: ["py", "pyw", "pyi", "pyx"],
        shebangs: ["python", "python3", "python2"],
        aliases: ["py", "python3", "py3"],
        rules: [
            SyntaxRule(##"#[^\n]*"##, .comment),
            SyntaxRule(##"(?:\b[rRbBuUfF]{1,2})?(?:"""[\s\S]*?(?:"""|\z)|'''[\s\S]*?(?:'''|\z))"##, .string),
            SyntaxRule(##"(?:\b[rRbBuUfF]{1,2})?(?:"(?:[^"\\\n]|\\.)*"?|'(?:[^'\\\n]|\\.)*'?)"##, .string, inner: [
                SyntaxRule(##"\{[^{}\n]*\}"##, .variable),
            ]),
            SyntaxRule(##"^[ \t]*@[\w.]+"##, .meta),
            SyntaxRule(##"(?<=\bdef )\w+"##, .function),
            SyntaxRule(##"(?<=\bclass )\w+"##, .type),
            SyntaxRule(kw("and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case"), .keyword),
            SyntaxRule(kw("True False None"), .constant),
            SyntaxRule(kw("self cls"), .variable),
            SyntaxRule(kw("print len range open int str float list dict set tuple bool type isinstance enumerate zip map filter sorted sum min max abs round input super property staticmethod classmethod repr hash id iter next any all format getattr setattr hasattr"), .function),
            SyntaxRule(call, .function),
            SyntaxRule(typeName, .type),
            SyntaxRule(number + "j?", .number),
        ])

    // MARK: HTML / XML

    static let tagRule = SyntaxRule(##"</?[A-Za-z][\w:.-]*(?:[^<>"']|"[^"]*"|'[^']*')*/?>?"##, .tag, inner: [
        SyntaxRule(##""[^"]*"|'[^']*'"##, .string),
        SyntaxRule(##"(?<=\s)[^\s"'<>/=]+"##, .attribute),
    ])

    static let html = SyntaxLanguage(
        id: "html", name: "HTML",
        extensions: ["html", "htm", "xhtml", "shtml", "vue", "svelte"],
        aliases: ["xhtml"],
        embeds: [
            SyntaxEmbed(pattern: ##"<script\b[^>]*>([\s\S]*?)(?=</script>|\z)"##, contentGroup: 1, languageGroup: nil, languageID: "javascript"),
            SyntaxEmbed(pattern: ##"<style\b[^>]*>([\s\S]*?)(?=</style>|\z)"##, contentGroup: 1, languageGroup: nil, languageID: "css"),
        ],
        rules: [
            SyntaxRule(##"<!--[\s\S]*?(?:-->|\z)"##, .comment),
            SyntaxRule(##"<![A-Za-z][^>]*>"##, .meta),
            tagRule,
            SyntaxRule(##"&(?:#\d+|#[xX][\da-fA-F]+|\w+);"##, .constant),
        ])

    static let xml = SyntaxLanguage(
        id: "xml", name: "XML",
        extensions: ["xml", "plist", "svg", "xsd", "xsl", "xslt", "rss", "atom", "xib", "storyboard", "csproj", "config", "xaml"],
        aliases: ["svg", "plist"],
        rules: [
            SyntaxRule(##"<!--[\s\S]*?(?:-->|\z)"##, .comment),
            SyntaxRule(##"<!\[CDATA\[[\s\S]*?(?:\]\]>|\z)"##, .string),
            SyntaxRule(##"<\?[\s\S]*?(?:\?>|\z)"##, .meta),
            SyntaxRule(##"<![A-Za-z][^>]*>"##, .meta),
            tagRule,
            SyntaxRule(##"&(?:#\d+|#[xX][\da-fA-F]+|\w+);"##, .constant),
        ])

    // MARK: CSS

    static let css = SyntaxLanguage(
        id: "css", name: "CSS",
        extensions: ["css", "scss", "sass", "less"],
        aliases: ["scss", "less"],
        rules: [
            SyntaxRule(##"/\*[\s\S]*?(?:\*/|\z)|(?<![:\w])//[^\n]*"##, .comment),
            SyntaxRule(dq + "|" + sq, .string),
            SyntaxRule(##"@[\w-]+"##, .keyword),
            SyntaxRule(##"!important\b"##, .keyword),
            SyntaxRule(##"--[\w-]+|\$[\w-]+"##, .variable),
            SyntaxRule(##"(?<![\w-])[a-z-]+(?=\s*:(?!:)[^;{}\n]*(?:;|\}|$))"##, .attribute),
            SyntaxRule(##"(?<=[\s:,(])#[\da-fA-F]{3,8}\b(?![\w-])"##, .number),
            SyntaxRule(##"[.#][A-Za-z_][\w-]*"##, .type),
            SyntaxRule(##"::?[a-z-]+"##, .meta),
            SyntaxRule(##"[\w-]+(?=\()"##, .function),
            SyntaxRule(##"-?(?<![\w.])(?:\d+\.?\d*|\.\d+)(?:[a-z]+|%)?"##, .number),
        ])

    // MARK: JavaScript / TypeScript / JSON

    static let jsKeywords = "break case catch class const continue debugger default delete do else export extends finally for from function if import in instanceof let new of return static super switch throw try typeof var void while with yield async await get set"

    static func jsRules(extraKeywords: String = "", extraTypes: String = "") -> [SyntaxRule] {
        var rules = [
            SyntaxRule(cComment, .comment),
            SyntaxRule(##"`(?:[^`\\]|\\[\s\S])*`?"##, .string, inner: [SyntaxRule(##"\$\{[^}]*\}"##, .variable)]),
            SyntaxRule(dq + "|" + sq, .string),
            SyntaxRule(##"@[\w.]+"##, .meta),
            SyntaxRule(##"(?<=\bfunction )\w+|(?<=\bclass )\w+"##, .type),
            SyntaxRule(kw(jsKeywords + (extraKeywords.isEmpty ? "" : " " + extraKeywords)), .keyword),
            SyntaxRule(kw("true false null undefined NaN Infinity this"), .constant),
        ]
        if !extraTypes.isEmpty { rules.append(SyntaxRule(kw(extraTypes), .type)) }
        rules += [
            SyntaxRule(call, .function),
            SyntaxRule(typeName, .type),
            SyntaxRule(number + "n?", .number),
        ]
        return rules
    }

    static let javascript = SyntaxLanguage(
        id: "javascript", name: "JavaScript",
        extensions: ["js", "mjs", "cjs", "jsx"],
        shebangs: ["node", "deno", "bun"],
        aliases: ["js", "jsx", "node"],
        rules: jsRules())

    static let typescript = SyntaxLanguage(
        id: "typescript", name: "TypeScript",
        extensions: ["ts", "tsx", "mts", "cts"],
        aliases: ["ts", "tsx"],
        rules: jsRules(extraKeywords: "type interface enum implements declare namespace module readonly private public protected abstract keyof infer as satisfies is",
                       extraTypes: "string number boolean any unknown never void object bigint symbol"))

    static let json = SyntaxLanguage(
        id: "json", name: "JSON",
        extensions: ["json", "jsonc", "json5", "geojson", "webmanifest", "ipynb"],
        aliases: ["jsonc", "json5"],
        rules: [
            SyntaxRule(cComment, .comment),
            SyntaxRule(##""(?:[^"\\\n]|\\.)*"(?=\s*:)"##, .attribute),
            SyntaxRule(dq, .string),
            SyntaxRule(kw("true false null"), .constant),
            SyntaxRule(##"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"##, .number),
        ])

    // MARK: YAML, TOML / INI

    static let yaml = SyntaxLanguage(
        id: "yaml", name: "YAML",
        extensions: ["yml", "yaml"],
        aliases: ["yml"],
        rules: [
            SyntaxRule(##"(?<!\S)#[^\n]*"##, .comment),
            SyntaxRule(##"^(?:---|\.\.\.)[ \t]*$"##, .meta),
            SyntaxRule(dq + "|" + sq, .string),
            SyntaxRule(##"[\w$./-][\w $./-]*?(?=:(?:[ \t]|$))"##, .attribute),
            SyntaxRule(##"^[ \t]*-(?=[ \t]|$)"##, .keyword),
            SyntaxRule(##"[&*][\w-]+"##, .variable),
            SyntaxRule(##"!!?[\w/]+"##, .meta),
            SyntaxRule(##"[|>][-+]?(?=[ \t]*$)"##, .meta),
            SyntaxRule(kw("true false yes no on off null True False Yes No On Off Null TRUE FALSE NULL") + "|~", .constant),
            SyntaxRule(##"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"##, .number),
        ])

    static let toml = SyntaxLanguage(
        id: "ini", name: "INI / TOML / conf",
        extensions: ["ini", "cfg", "conf", "toml", "properties", "env", "editorconfig", "gitconfig", "service", "desktop", "reg", "inf"],
        fileNames: [".env", ".gitconfig", ".gitattributes", ".editorconfig", ".npmrc", ".curlrc", ".wgetrc"],
        aliases: ["toml", "conf", "cfg", "dosini", "properties", "env", "dotenv"],
        rules: [
            SyntaxRule(##"^[ \t]*[#;][^\n]*"##, .comment),
            SyntaxRule(##"^[ \t]*\[\[?[^\]\n]*\]\]?"##, .keyword),
            SyntaxRule(##"^[ \t]*(?:export[ \t]+)?[\w.\-"]+(?=[ \t]*[=:])"##, .attribute),
            SyntaxRule(##""""[\s\S]*?(?:"""|\z)"## + "|" + dq + "|" + sq, .string),
            SyntaxRule(##"\$\{?\w+\}?|%\w+%"##, .variable),
            SyntaxRule(kw("true false yes no on off"), .constant),
            SyntaxRule(##"-?\b\d[\d_.:-]*\b"##, .number),
        ])

    // MARK: SQL

    static let sql = SyntaxLanguage(
        id: "sql", name: "SQL",
        extensions: ["sql", "ddl", "dml", "psql", "pgsql"],
        aliases: ["mysql", "postgres", "postgresql", "sqlite", "plsql", "tsql"],
        caseInsensitive: true,
        rules: [
            SyntaxRule(##"--[^\n]*|/\*[\s\S]*?(?:\*/|\z)|^[ \t]*#[^\n]*"##, .comment),
            SyntaxRule(##"'(?:[^']|'')*'?"##, .string),
            SyntaxRule(##""[^"\n]*"|`[^`\n]*`|\[[^\]\n]+\]"##, .variable),
            SyntaxRule(kw("select from where insert into values update set delete create table alter drop index view join inner left right outer full cross on and or not null is in between like ilike as order by group having limit offset union all distinct case when then else end primary key foreign references default constraint unique check exists begin commit rollback transaction with returning if replace grant revoke database schema procedure function trigger declare cast asc desc top fetch next rows only over partition add column rename to truncate explain analyze vacuum use show describe go exec execute return returns language"), .keyword),
            SyntaxRule(kw("int integer bigint smallint tinyint varchar nvarchar char nchar text date datetime datetime2 timestamp timestamptz time interval boolean bool bit decimal numeric float real double money serial bigserial uuid json jsonb xml blob clob bytea"), .type),
            SyntaxRule(kw("true false"), .constant),
            SyntaxRule(call, .function),
            SyntaxRule(##"[:@$]\w+|\?"##, .variable),
            SyntaxRule(number, .number),
        ])

    // MARK: Swift

    static let swift = SyntaxLanguage(
        id: "swift", name: "Swift",
        extensions: ["swift"],
        shebangs: ["swift"],
        rules: [
            SyntaxRule(cComment, .comment),
            SyntaxRule(##""""[\s\S]*?(?:"""|\z)"##, .string),
            SyntaxRule(dq, .string, inner: [SyntaxRule(##"\\\([^)\n]*\)"##, .variable)]),
            SyntaxRule(##"@\w+|#\w+"##, .meta),
            SyntaxRule(kw("associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private precedencegroup protocol public rethrows static struct subscript typealias var break case catch continue default defer do else fallthrough for guard if in repeat return throw throws switch where while as is try await async actor nonisolated isolated some any final lazy mutating override required convenience weak unowned didSet willSet get set"), .keyword),
            SyntaxRule(kw("true false nil self Self super"), .constant),
            SyntaxRule(call, .function),
            SyntaxRule(typeName, .type),
            SyntaxRule(number, .number),
        ])

    // MARK: PowerShell

    static let psVar = SyntaxRule(##"\$(?:\{[^}\n]+\}|[\w:]+|[$?^_])"##, .variable)

    static let powershell = SyntaxLanguage(
        id: "powershell", name: "PowerShell",
        extensions: ["ps1", "psm1", "psd1"],
        shebangs: ["pwsh", "powershell"],
        aliases: ["ps1", "pwsh", "ps"],
        caseInsensitive: true,
        rules: [
            SyntaxRule(##"<#[\s\S]*?(?:#>|\z)"##, .comment),
            SyntaxRule(##"#[^\n]*"##, .comment),
            SyntaxRule(##"@"[\s\S]*?^"@|@'[\s\S]*?^'@"##, .string),
            SyntaxRule(##""(?:[^"`]|`[\s\S])*"?"##, .string, inner: [psVar]),
            SyntaxRule(##"'(?:[^']|'')*'?"##, .string),
            psVar,
            SyntaxRule(##"\[[\w.\[\]]+\]"##, .type),
            SyntaxRule(##"-(?:eq|ne|gt|ge|lt|le|like|notlike|match|notmatch|contains|notcontains|in|notin|and|or|not|xor|replace|split|join|is|isnot|as|f|band|bor)\b"##, .keyword),
            SyntaxRule(kw("begin break catch class continue data define do dynamicparam else elseif end exit filter finally for foreach from function if in param process return switch throw trap try until using var while workflow"), .keyword),
            SyntaxRule(##"\b[A-Za-z]+-[A-Za-z]+\b"##, .function),
            SyntaxRule(##"(?<=\s)-[A-Za-z]\w*"##, .attribute),
            SyntaxRule(number, .number),
        ])

    // MARK: Famille C

    static let c = SyntaxLanguage(
        id: "c", name: "C / C++ / Objective-C",
        extensions: ["c", "h", "cpp", "cc", "cxx", "hpp", "hh", "hxx", "m", "mm", "ino", "cs"],
        aliases: ["cpp", "c++", "objc", "objective-c", "csharp", "c#", "arduino"],
        rules: [
            SyntaxRule(cComment, .comment),
            SyntaxRule(##"^[ \t]*#[ \t]*\w+(?:[ \t]+<[^>\n]*>)?"##, .meta),
            SyntaxRule("@?" + dq, .string),
            SyntaxRule(##"'(?:[^'\\\n]|\\.){1,8}'"##, .string),
            SyntaxRule(##"@\w+"##, .meta),
            SyntaxRule(kw("auto break case catch class const constexpr continue default delete do else enum explicit extern for friend goto if inline mutable namespace new noexcept operator private protected public register return sizeof static static_cast dynamic_cast reinterpret_cast struct switch template this throw try typedef typename union using virtual volatile while override final using namespace async await var foreach in out ref readonly sealed abstract interface get set"), .keyword),
            SyntaxRule(kw("int char float double void long short unsigned signed bool size_t ssize_t string uint8_t uint16_t uint32_t uint64_t int8_t int16_t int32_t int64_t id instancetype BOOL"), .type),
            SyntaxRule(kw("true false NULL nullptr nil YES NO"), .constant),
            SyntaxRule(call, .function),
            SyntaxRule(typeName, .type),
            SyntaxRule(number, .number),
        ])

    static let java = SyntaxLanguage(
        id: "java", name: "Java / Kotlin",
        extensions: ["java", "kt", "kts", "groovy", "gradle", "scala"],
        aliases: ["kotlin", "kt", "groovy", "scala"],
        rules: [
            SyntaxRule(cComment, .comment),
            SyntaxRule(##""""[\s\S]*?(?:"""|\z)"##, .string),
            SyntaxRule(dq, .string),
            SyntaxRule(##"'(?:[^'\\\n]|\\.){1,8}'"##, .string),
            SyntaxRule(##"@\w+"##, .meta),
            SyntaxRule(kw("abstract assert break case catch class const continue default do else enum extends final finally for goto if implements import instanceof interface native new package private protected public return static strictfp super switch synchronized this throw throws transient try volatile while var val fun object companion data sealed when is in out override open internal lateinit suspend record yield"), .keyword),
            SyntaxRule(kw("int long short byte char float double boolean void"), .type),
            SyntaxRule(kw("true false null"), .constant),
            SyntaxRule(call, .function),
            SyntaxRule(typeName, .type),
            SyntaxRule(number, .number),
        ])

    static let go = SyntaxLanguage(
        id: "go", name: "Go",
        extensions: ["go"],
        aliases: ["golang"],
        rules: [
            SyntaxRule(cComment, .comment),
            SyntaxRule(dq + "|`[^`]*`?", .string),
            SyntaxRule(##"'(?:[^'\\\n]|\\.){1,8}'"##, .string),
            SyntaxRule(kw("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var"), .keyword),
            SyntaxRule(kw("bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr any"), .type),
            SyntaxRule(kw("true false nil iota"), .constant),
            SyntaxRule(call, .function),
            SyntaxRule(typeName, .type),
            SyntaxRule(number, .number),
        ])

    static let rust = SyntaxLanguage(
        id: "rust", name: "Rust",
        extensions: ["rs"],
        aliases: ["rs"],
        rules: [
            SyntaxRule(cComment, .comment),
            SyntaxRule(##"#!?\[[^\]\n]*\]"##, .meta),
            SyntaxRule(##"b?r#*"[\s\S]*?"#*|b?"(?:[^"\\]|\\[\s\S])*"?"##, .string),
            SyntaxRule(##"b?'(?:[^'\\\n]|\\.){1,8}'"##, .string),
            SyntaxRule(##"'[A-Za-z_]\w*"##, .meta),
            SyntaxRule(##"\b\w+!"##, .meta),
            SyntaxRule(##"(?<=\bfn )\w+"##, .function),
            SyntaxRule(kw("as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait type unsafe use where while"), .keyword),
            SyntaxRule(kw("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Result Box"), .type),
            SyntaxRule(kw("true false None Some Ok Err"), .constant),
            SyntaxRule(call, .function),
            SyntaxRule(typeName, .type),
            SyntaxRule(number, .number),
        ])

    // MARK: Dockerfile, Makefile, Diff

    static let dockerfile = SyntaxLanguage(
        id: "dockerfile", name: "Dockerfile",
        extensions: ["dockerfile", "containerfile"],
        fileNames: ["dockerfile", "containerfile"],
        aliases: ["docker"],
        rules: [
            SyntaxRule(##"^[ \t]*#[^\n]*"##, .comment),
            SyntaxRule(##"(?i:^[ \t]*(?:FROM|RUN|CMD|LABEL|MAINTAINER|EXPOSE|ENV|ADD|COPY|ENTRYPOINT|VOLUME|USER|WORKDIR|ARG|ONBUILD|STOPSIGNAL|HEALTHCHECK|SHELL)\b)"##, .keyword),
            SyntaxRule(##"(?i:\bAS\b)"##, .keyword),
            SyntaxRule(dq + "|" + sq, .string),
            shellVar,
            SyntaxRule(##"(?<=[ \t])--?[A-Za-z][\w-]*"##, .attribute),
            SyntaxRule(##"\b\d+\b"##, .number),
        ])

    static let makefile = SyntaxLanguage(
        id: "makefile", name: "Makefile",
        extensions: ["mk", "mak", "make"],
        fileNames: ["makefile", "gnumakefile", "bsdmakefile"],
        aliases: ["make", "mk"],
        rules: [
            SyntaxRule(##"(?<!\\)#[^\n]*"##, .comment),
            SyntaxRule(kw("ifeq ifneq ifdef ifndef else endif include define endef export unexport override vpath"), .keyword),
            SyntaxRule(##"^[\w.%/$() -]+(?=:(?!=))"##, .function),
            SyntaxRule(##"^[ \t]*[\w.]+(?=[ \t]*[:+?!]?=)"##, .variable),
            SyntaxRule(##"\$[({][^)}\n]*[)}]|\$[@<^*?%]"##, .variable),
            SyntaxRule(dq + "|" + sq, .string),
        ])

    static let diff = SyntaxLanguage(
        id: "diff", name: "Diff / Patch",
        extensions: ["diff", "patch", "rej"],
        aliases: ["patch", "udiff"],
        rules: [
            SyntaxRule(##"^(?:diff|index|---|\+\+\+|similarity|rename|new file|deleted file)[^\n]*"##, .keyword),
            SyntaxRule(##"^@@[^\n]*"##, .meta),
            SyntaxRule(##"^\+[^\n]*"##, .inserted),
            SyntaxRule(##"^-[^\n]*"##, .deleted),
        ])
}
