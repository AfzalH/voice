import AppKit
import Carbon

// MARK: - LanguageOption

enum LanguageOption: String, CaseIterable, Codable {
    case afrikaans = "af"
    case albanian = "sq"
    case amharic = "am"
    case arabic = "ar"
    case armenian = "hy"
    case assamese = "as"
    case azerbaijani = "az"
    case bashkir = "ba"
    case basque = "eu"
    case belarusian = "be"
    case bengali = "bn"
    case bosnian = "bs"
    case breton = "br"
    case bulgarian = "bg"
    case catalan = "ca"
    case chinese = "zh"
    case croatian = "hr"
    case czech = "cs"
    case danish = "da"
    case dutch = "nl"
    case english = "en"
    case estonian = "et"
    case faroese = "fo"
    case finnish = "fi"
    case french = "fr"
    case galician = "gl"
    case georgian = "ka"
    case german = "de"
    case greek = "el"
    case gujarati = "gu"
    case haitianCreole = "ht"
    case hausa = "ha"
    case hawaiian = "haw"
    case hebrew = "he"
    case hindi = "hi"
    case hungarian = "hu"
    case icelandic = "is"
    case indonesian = "id"
    case italian = "it"
    case japanese = "ja"
    case javanese = "jw"
    case kannada = "kn"
    case kazakh = "kk"
    case khmer = "km"
    case korean = "ko"
    case lao = "lo"
    case latin = "la"
    case latvian = "lv"
    case lingala = "ln"
    case lithuanian = "lt"
    case luxembourgish = "lb"
    case macedonian = "mk"
    case malagasy = "mg"
    case malay = "ms"
    case malayalam = "ml"
    case maltese = "mt"
    case maori = "mi"
    case marathi = "mr"
    case mongolian = "mn"
    case myanmar = "my"
    case nepali = "ne"
    case norwegian = "no"
    case nynorsk = "nn"
    case occitan = "oc"
    case pashto = "ps"
    case persian = "fa"
    case polish = "pl"
    case portuguese = "pt"
    case punjabi = "pa"
    case romanian = "ro"
    case russian = "ru"
    case sanskrit = "sa"
    case serbian = "sr"
    case shona = "sn"
    case sindhi = "sd"
    case sinhala = "si"
    case slovak = "sk"
    case slovenian = "sl"
    case somali = "so"
    case spanish = "es"
    case sundanese = "su"
    case swahili = "sw"
    case swedish = "sv"
    case tagalog = "tl"
    case tajik = "tg"
    case tamil = "ta"
    case tatar = "tt"
    case telugu = "te"
    case thai = "th"
    case tibetan = "bo"
    case turkish = "tr"
    case turkmen = "tk"
    case ukrainian = "uk"
    case urdu = "ur"
    case uzbek = "uz"
    case vietnamese = "vi"
    case welsh = "cy"
    case wolof = "wo"
    case yiddish = "yi"
    case yoruba = "yo"

    var code: String { rawValue }

    var displayName: String {
        switch self {
        case .afrikaans: return "🇿🇦 Afrikaans"
        case .albanian: return "🇦🇱 Albanian"
        case .amharic: return "🇪🇹 Amharic"
        case .arabic: return "🇸🇦 Arabic"
        case .armenian: return "🇦🇲 Armenian"
        case .assamese: return "🇮🇳 Assamese"
        case .azerbaijani: return "🇦🇿 Azerbaijani"
        case .bashkir: return "🇷🇺 Bashkir"
        case .basque: return "🇪🇸 Basque"
        case .belarusian: return "🇧🇾 Belarusian"
        case .bengali: return "🇧🇩 Bengali"
        case .bosnian: return "🇧🇦 Bosnian"
        case .breton: return "🇫🇷 Breton"
        case .bulgarian: return "🇧🇬 Bulgarian"
        case .catalan: return "🇪🇸 Catalan"
        case .chinese: return "🇨🇳 Chinese"
        case .croatian: return "🇭🇷 Croatian"
        case .czech: return "🇨🇿 Czech"
        case .danish: return "🇩🇰 Danish"
        case .dutch: return "🇳🇱 Dutch"
        case .english: return "🇺🇸 English"
        case .estonian: return "🇪🇪 Estonian"
        case .faroese: return "🇫🇴 Faroese"
        case .finnish: return "🇫🇮 Finnish"
        case .french: return "🇫🇷 French"
        case .galician: return "🇪🇸 Galician"
        case .georgian: return "🇬🇪 Georgian"
        case .german: return "🇩🇪 German"
        case .greek: return "🇬🇷 Greek"
        case .gujarati: return "🇮🇳 Gujarati"
        case .haitianCreole: return "🇭🇹 Haitian Creole"
        case .hausa: return "🇳🇬 Hausa"
        case .hawaiian: return "🇺🇸 Hawaiian"
        case .hebrew: return "🇮🇱 Hebrew"
        case .hindi: return "🇮🇳 Hindi"
        case .hungarian: return "🇭🇺 Hungarian"
        case .icelandic: return "🇮🇸 Icelandic"
        case .indonesian: return "🇮🇩 Indonesian"
        case .italian: return "🇮🇹 Italian"
        case .japanese: return "🇯🇵 Japanese"
        case .javanese: return "🇮🇩 Javanese"
        case .kannada: return "🇮🇳 Kannada"
        case .kazakh: return "🇰🇿 Kazakh"
        case .khmer: return "🇰🇭 Khmer"
        case .korean: return "🇰🇷 Korean"
        case .lao: return "🇱🇦 Lao"
        case .latin: return "🇻🇦 Latin"
        case .latvian: return "🇱🇻 Latvian"
        case .lingala: return "🇨🇩 Lingala"
        case .lithuanian: return "🇱🇹 Lithuanian"
        case .luxembourgish: return "🇱🇺 Luxembourgish"
        case .macedonian: return "🇲🇰 Macedonian"
        case .malagasy: return "🇲🇬 Malagasy"
        case .malay: return "🇲🇾 Malay"
        case .malayalam: return "🇮🇳 Malayalam"
        case .maltese: return "🇲🇹 Maltese"
        case .maori: return "🇳🇿 Maori"
        case .marathi: return "🇮🇳 Marathi"
        case .mongolian: return "🇲🇳 Mongolian"
        case .myanmar: return "🇲🇲 Myanmar"
        case .nepali: return "🇳🇵 Nepali"
        case .norwegian: return "🇳🇴 Norwegian"
        case .nynorsk: return "🇳🇴 Nynorsk"
        case .occitan: return "🇫🇷 Occitan"
        case .pashto: return "🇦🇫 Pashto"
        case .persian: return "🇮🇷 Persian"
        case .polish: return "🇵🇱 Polish"
        case .portuguese: return "🇵🇹 Portuguese"
        case .punjabi: return "🇮🇳 Punjabi"
        case .romanian: return "🇷🇴 Romanian"
        case .russian: return "🇷🇺 Russian"
        case .sanskrit: return "🇮🇳 Sanskrit"
        case .serbian: return "🇷🇸 Serbian"
        case .shona: return "🇿🇼 Shona"
        case .sindhi: return "🇵🇰 Sindhi"
        case .sinhala: return "🇱🇰 Sinhala"
        case .slovak: return "🇸🇰 Slovak"
        case .slovenian: return "🇸🇮 Slovenian"
        case .somali: return "🇸🇴 Somali"
        case .spanish: return "🇪🇸 Spanish"
        case .sundanese: return "🇮🇩 Sundanese"
        case .swahili: return "🇰🇪 Swahili"
        case .swedish: return "🇸🇪 Swedish"
        case .tagalog: return "🇵🇭 Tagalog"
        case .tajik: return "🇹🇯 Tajik"
        case .tamil: return "🇮🇳 Tamil"
        case .tatar: return "🇷🇺 Tatar"
        case .telugu: return "🇮🇳 Telugu"
        case .thai: return "🇹🇭 Thai"
        case .tibetan: return "🇨🇳 Tibetan"
        case .turkish: return "🇹🇷 Turkish"
        case .turkmen: return "🇹🇲 Turkmen"
        case .ukrainian: return "🇺🇦 Ukrainian"
        case .urdu: return "🇵🇰 Urdu"
        case .uzbek: return "🇺🇿 Uzbek"
        case .vietnamese: return "🇻🇳 Vietnamese"
        case .welsh: return "🏴󠁧󠁢󠁷󠁬󠁳󠁿 Welsh"
        case .wolof: return "🇸🇳 Wolof"
        case .yiddish: return "🇮🇱 Yiddish"
        case .yoruba: return "🇳🇬 Yoruba"
        }
    }

    var plainName: String {
        displayName.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) ?? code
    }

    var flag: String {
        displayName.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
    }

    /// Short uppercase code for compact chips (e.g. "EN").
    var shortCode: String { code.uppercased() }

    /// Languages the user has configured at the OS level, most preferred first.
    static var systemLanguages: [LanguageOption] {
        var seen = Set<LanguageOption>()
        return Locale.preferredLanguages.compactMap { identifier -> LanguageOption? in
            let base = identifier.split(separator: "-").first.map(String.init)?.lowercased() ?? identifier
            guard let option = LanguageOption(rawValue: base), !seen.contains(option) else { return nil }
            seen.insert(option)
            return option
        }
    }

    /// Fallback quick-pick list when the user has no language history yet:
    /// the OS languages first, then a few common ones.
    static var commonLanguages: [LanguageOption] {
        var result = systemLanguages
        for option in [LanguageOption.english, .german, .french, .spanish] where !result.contains(option) {
            result.append(option)
        }
        return result
    }
}

// MARK: - RecentLanguages

/// Most-recently-used languages (shared between the spoken-language hint and
/// translation targets), newest first.
enum RecentLanguagesStore {
    private static let key = "languages.recent"
    static let maxEntries = 6

    static func load() -> [LanguageOption] {
        guard let raw = UserDefaults.standard.stringArray(forKey: key) else { return [] }
        var seen = Set<LanguageOption>()
        return raw.compactMap { LanguageOption(rawValue: $0) }.filter { seen.insert($0).inserted }
    }

    static func save(_ languages: [LanguageOption]) {
        UserDefaults.standard.set(languages.prefix(maxEntries).map(\.rawValue), forKey: key)
    }

    /// Moves `language` to the front of `recents`, dropping duplicates and trimming.
    static func bump(_ language: LanguageOption, in recents: [LanguageOption]) -> [LanguageOption] {
        var result = recents.filter { $0 != language }
        result.insert(language, at: 0)
        return Array(result.prefix(maxEntries))
    }

    /// The languages to offer as quick picks: recents when available, otherwise
    /// the common/system fallback, padded with common languages up to `count`.
    static func quickPicks(from recents: [LanguageOption], count: Int) -> [LanguageOption] {
        var result = Array(recents.prefix(count))
        if result.count < count {
            for option in LanguageOption.commonLanguages where !result.contains(option) {
                result.append(option)
                if result.count == count { break }
            }
        }
        return result
    }
}

// MARK: - ModifierKey

/// A physical modifier key, identified by its hardware key code so that the left
/// and right variants can be told apart (macOS reports them with distinct codes
/// in `flagsChanged` events even though the generic modifier flag is the same).
enum ModifierKey: UInt32, CaseIterable, Codable {
    case leftCommand  = 55
    case rightCommand = 54
    case leftShift    = 56
    case rightShift   = 60
    case leftOption   = 58
    case rightOption  = 61
    case leftControl  = 59
    case rightControl = 62

    var isRight: Bool {
        switch self {
        case .rightCommand, .rightShift, .rightOption, .rightControl: return true
        default: return false
        }
    }

    var symbol: String {
        switch self {
        case .leftCommand, .rightCommand: return "⌘"
        case .leftShift, .rightShift:     return "⇧"
        case .leftOption, .rightOption:   return "⌥"
        case .leftControl, .rightControl: return "⌃"
        }
    }

    /// Carbon modifier mask this key contributes to.
    var carbonMask: UInt32 {
        switch self {
        case .leftCommand, .rightCommand: return UInt32(cmdKey)
        case .leftShift, .rightShift:     return UInt32(shiftKey)
        case .leftOption, .rightOption:   return UInt32(optionKey)
        case .leftControl, .rightControl: return UInt32(controlKey)
        }
    }

    /// Generic CGEvent flag for this modifier (same for both sides).
    var cgFlag: CGEventFlags {
        switch self {
        case .leftCommand, .rightCommand: return .maskCommand
        case .leftShift, .rightShift:     return .maskShift
        case .leftOption, .rightOption:   return .maskAlternate
        case .leftControl, .rightControl: return .maskControl
        }
    }

    /// Device-specific flag bit (from IOKit's IOLLEvent.h) that identifies the
    /// exact side. Not every keyboard sets these, so callers fall back to `cgFlag`.
    var deviceFlagBit: UInt64 {
        switch self {
        case .leftControl:  return 0x0000_0001
        case .leftShift:    return 0x0000_0002
        case .rightShift:   return 0x0000_0004
        case .leftCommand:  return 0x0000_0008
        case .rightCommand: return 0x0000_0010
        case .leftOption:   return 0x0000_0020
        case .rightOption:  return 0x0000_0040
        case .rightControl: return 0x0000_2000
        }
    }

    /// Display order used when rendering chords: ⌃ ⌥ ⇧ ⌘ (macOS convention).
    var sortOrder: Int {
        switch self {
        case .leftControl, .rightControl: return 0
        case .leftOption, .rightOption:   return 1
        case .leftShift, .rightShift:     return 2
        case .leftCommand, .rightCommand: return 3
        }
    }
}

// MARK: - HotKey

/// A global shortcut. Three shapes are supported:
///  - the bare fn/Globe key (`isFnKey`)
///  - one or more modifier keys with no regular key (`isModifierOnly`), optionally
///    pinned to a specific side via `modifierKeys` (e.g. right ⌘ only)
///  - a regular key plus modifiers, also optionally side-specific
struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    /// Generic Carbon modifier mask (side-agnostic). Always kept in sync with
    /// `modifierKeys` when those are present.
    var modifiers: UInt32
    var isFnKey: Bool
    var isModifierOnly: Bool
    /// Exact modifier keys (left/right aware). Empty for legacy shortcuts recorded
    /// before side tracking existed; those match either side.
    var modifierKeys: [ModifierKey]

    init(
        keyCode: UInt32,
        modifiers: UInt32,
        isFnKey: Bool = false,
        isModifierOnly: Bool = false,
        modifierKeys: [ModifierKey] = []
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isFnKey = isFnKey
        self.isModifierOnly = isModifierOnly
        self.modifierKeys = HotKey.sorted(modifierKeys)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt32.self, forKey: .keyCode)
        modifiers = try container.decode(UInt32.self, forKey: .modifiers)
        isFnKey = try container.decodeIfPresent(Bool.self, forKey: .isFnKey) ?? false
        isModifierOnly = try container.decodeIfPresent(Bool.self, forKey: .isModifierOnly) ?? false
        modifierKeys = HotKey.sorted(try container.decodeIfPresent([ModifierKey].self, forKey: .modifierKeys) ?? [])
    }

    static let fnKey = HotKey(keyCode: 63, modifiers: 0, isFnKey: true)
    static let rightCommand = HotKey(
        keyCode: 0,
        modifiers: UInt32(cmdKey),
        isModifierOnly: true,
        modifierKeys: [.rightCommand]
    )

    /// Default push-to-talk shortcut: hold fn.
    static let defaultPushToTalk = HotKey.fnKey
    /// Default handsfree shortcut: tap right ⌘ (never does anything on its own in macOS).
    static let defaultHandsfree = HotKey.rightCommand

    /// Kept for source compatibility with older call sites.
    static let defaultValue = HotKey.fnKey

    var isSideSpecific: Bool { !modifierKeys.isEmpty }

    /// Two shortcuts conflict when one would always fire alongside the other.
    func conflicts(with other: HotKey) -> Bool {
        if self == other { return true }
        if isFnKey || other.isFnKey { return isFnKey && other.isFnKey }
        guard keyCode == other.keyCode, isModifierOnly == other.isModifierOnly, modifiers == other.modifiers else {
            return false
        }
        // Same generic shape; a side-agnostic one overlaps with any side-specific one.
        return modifierKeys.isEmpty || other.modifierKeys.isEmpty
    }

    var displayString: String {
        if isFnKey { return "fn" }
        var pieces: [String] = []
        if modifierKeys.isEmpty {
            if modifiers & UInt32(controlKey) != 0 { pieces.append("⌃") }
            if modifiers & UInt32(optionKey) != 0 { pieces.append("⌥") }
            if modifiers & UInt32(shiftKey) != 0 { pieces.append("⇧") }
            if modifiers & UInt32(cmdKey) != 0 { pieces.append("⌘") }
        } else {
            let allRight = modifierKeys.allSatisfy(\.isRight)
            let allLeft = modifierKeys.allSatisfy { !$0.isRight }
            if allRight || allLeft {
                pieces.append((allRight ? "Right " : "Left ") + modifierKeys.map(\.symbol).joined())
            } else {
                pieces.append(modifierKeys.map { ($0.isRight ? "R" : "L") + $0.symbol }.joined(separator: "+"))
            }
        }
        if !isModifierOnly {
            pieces.append(KeyCodeMap.displayName(for: keyCode))
        }
        return pieces.joined(separator: pieces.count > 1 && isSideSpecific ? " " : "")
    }

    private static func sorted(_ keys: [ModifierKey]) -> [ModifierKey] {
        Array(Set(keys)).sorted { ($0.sortOrder, $0.isRight ? 1 : 0) < ($1.sortOrder, $1.isRight ? 1 : 0) }
    }
}

// MARK: - KeyCodeMap

enum KeyCodeMap {
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        return value
    }

    static func displayName(for keyCode: UInt32) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 50: return "`"
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "⎋"
        case 76: return "⌤"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 114: return "Help"
        case 115: return "↖"
        case 116: return "⇞"
        case 117: return "⌦"
        case 118: return "F4"
        case 119: return "↘"
        case 120: return "F2"
        case 121: return "⇟"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "Key\(keyCode)"
        }
    }
}

// MARK: - RecordingMode

/// How the current recording was started. Each mode has its own shortcut, so this
/// is per-session state rather than a user setting.
enum RecordingMode: String, CaseIterable, Codable {
    case pushToTalk = "pushToTalk"
    case handsfree  = "handsfree"

    var displayName: String {
        switch self {
        case .pushToTalk: return "Push to Talk"
        case .handsfree:  return "Handsfree"
        }
    }
}

// MARK: - GeminiModel

enum GeminiModel: String, CaseIterable, Codable {
    case gemini35Flash = "gemini-3.5-flash"
    case gemini31FlashLite = "gemini-3.1-flash-lite"

    static let defaultValue: GeminiModel = .gemini31FlashLite

    var displayName: String {
        switch self {
        case .gemini35Flash: return "Gemini 3.5"
        case .gemini31FlashLite: return "Gemini 3.1"
        }
    }

    var modelID: String { rawValue }
}

// MARK: - TranscriptionOutputMode

enum TranscriptionOutputMode: String, CaseIterable, Codable {
    case asIs = "asIs"
    case corrected = "corrected"
    case customPrompt = "customPrompt"
    case translated = "translated"
    case originalAndTranslation = "originalAndTranslation"

    var displayName: String {
        switch self {
        case .asIs: return "As is"
        case .corrected: return "Correct things"
        case .customPrompt: return "Custom prompt"
        case .translated: return "Translate to target language"
        case .originalAndTranslation: return "Original + target translation"
        }
    }

    var requiresTargetLanguage: Bool {
        switch self {
        case .asIs, .corrected, .customPrompt: return false
        case .translated, .originalAndTranslation: return true
        }
    }

    static let defaultCustomPrompt = "Transcribe the speech into clean, grammatically correct sentences. Remove filler sounds and hesitation words such as um, uh, ah, er, hmm, like, and you know when they do not add meaning. Remove stutters, repeated words, false starts, mumbling artifacts, and partial phrases. Correct obvious transcription errors, grammar, punctuation, capitalization, and formatting. Preserve the speaker's intended meaning, language, and tone. Return only polished final sentences."
}

// MARK: - DictationHistory

/// A single past dictation, shown in the History tab and copyable on click.
struct DictationHistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let date: Date

    init(id: UUID = UUID(), text: String, date: Date = Date()) {
        self.id = id
        self.text = text
        self.date = date
    }
}

/// Persists dictation history to UserDefaults, newest first, capped so it can't
/// grow without bound.
enum DictationHistoryStore {
    private static let key = "dictation.history"
    static let maxEntries = 200

    static func load() -> [DictationHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([DictationHistoryEntry].self, from: data)
        else { return [] }
        return decoded
    }

    static func save(_ entries: [DictationHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - PostProcessing

struct CustomPostProcessingPrompt: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var prompt: String

    init(id: UUID = UUID(), title: String, prompt: String) {
        self.id = id
        self.title = title
        self.prompt = prompt
    }
}

enum PostProcessingAction {
    case cleanUp
    case translate(LanguageOption)
    case addEmoji
    case makeCasual
    case makeFormal
    case makeTechnical
    case makeCompact
    case custom(title: String?, prompt: String)

    var displayName: String {
        switch self {
        case .cleanUp:              return "Clean up"
        case .translate(let lang):  return "Translate to \(lang.plainName)"
        case .addEmoji:             return "Add emoji"
        case .makeCasual:           return "Make casual"
        case .makeFormal:           return "Make formal"
        case .makeTechnical:        return "Make technical"
        case .makeCompact:          return "Make compact"
        case .custom(let title, _):
            let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "Custom prompt" : trimmed
        }
    }

    var instruction: String {
        switch self {
        case .cleanUp:
            return "Clean up the transcript into grammatically correct, natural sentences. Remove filler words, stutters, false starts, repeated words, and obvious transcription artifacts. Preserve the original language, meaning, and tone."
        case .translate(let language):
            return "Translate the transcript to \(language.plainName) (\(language.code)). Return only the translated text."
        case .addEmoji:
            return "Add tasteful, relevant emoji where they improve clarity or tone. Keep the original language and wording mostly intact. Do not overuse emoji."
        case .makeCasual:
            return "Rewrite the transcript in a casual, conversational style. Preserve the original language and intended meaning."
        case .makeFormal:
            return "Rewrite the transcript in a polished, formal style. Preserve the original language and intended meaning."
        case .makeTechnical:
            return "Rewrite the transcript so it sounds precise and technical. Preserve the original language and intended meaning, and do not invent technical details."
        case .makeCompact:
            return "Rewrite the transcript to be compact and concise. Preserve the original language, meaning, and important details. Remove redundancy and unnecessary words."
        case .custom(_, let prompt):
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? PostProcessingAction.cleanUp.instruction : trimmed
        }
    }
}

// MARK: - UserSettings

final class UserSettings {
    private enum Key {
        static let apiKey              = "gemini.apiKey"
        static let geminiModel         = "gemini.model"
        static let legacyHotKey        = "app.hotKey"
        static let pushToTalkHotKey    = "app.pushToTalkHotKey"
        static let handsfreeHotKey     = "app.handsfreeHotKey"
        static let spokenLanguage      = "dictation.spokenLanguage"
        static let outputMode          = "dictation.outputMode"
        static let customPrompt        = "dictation.customPrompt"
        static let customPostPrompts   = "postProcessing.customPrompts"
        static let postProcessingEnabled = "postProcessing.enabled"
        static let copyToClipboard     = "insertion.copyToClipboard"
        static let historyEnabled      = "history.enabled"
        static let translationLanguage = "dictation.translationLanguage"
        static let favoriteTranslationLanguage1 = "postProcessing.favoriteTranslationLanguage1"
        static let favoriteTranslationLanguage2 = "postProcessing.favoriteTranslationLanguage2"
        static let legacyRecordingMode = "app.recordingMode"
        static let handsfreeMaxSeconds = "app.handsfreeMaxSeconds"
        static let legacyHandsfreeMaxMinutes = "app.handsfreeMaxMinutes"
    }

    static let minHandsfreeSeconds = 30
    static let maxHandsfreeSeconds = 7 * 60
    static let defaultHandsfreeSeconds = 60

    var apiKey = ""
    var geminiModel: GeminiModel = .defaultValue
    /// Hold to record, release to insert. `nil` disables push-to-talk.
    var pushToTalkHotKey: HotKey? = HotKey.defaultPushToTalk
    /// Tap to start, tap again (or Esc) to stop. `nil` disables handsfree.
    var handsfreeHotKey: HotKey? = HotKey.defaultHandsfree
    /// Language the user says they are speaking; `nil` lets Gemini auto-detect.
    var spokenLanguage: LanguageOption?
    var outputMode: TranscriptionOutputMode = .corrected
    var customPrompt: String = TranscriptionOutputMode.defaultCustomPrompt
    var customPostProcessingPrompts: [CustomPostProcessingPrompt] = []
    var postProcessingEnabled = false
    var copyToClipboard = false
    var historyEnabled = true
    var translationLanguage: LanguageOption = .english
    var favoriteTranslationLanguage1: LanguageOption = .english
    var favoriteTranslationLanguage2: LanguageOption = .german
    var handsfreeMaxSeconds: Int = UserSettings.defaultHandsfreeSeconds

    func load() {
        let defaults = UserDefaults.standard
        apiKey = defaults.string(forKey: Key.apiKey) ?? ""
        if let raw = defaults.string(forKey: Key.geminiModel),
           let model = GeminiModel(rawValue: raw)
        {
            geminiModel = model
        } else {
            geminiModel = .defaultValue
        }

        loadHotKeys(from: defaults)
        if let raw = defaults.string(forKey: Key.spokenLanguage) {
            spokenLanguage = LanguageOption(rawValue: raw)
        }
        if let raw = defaults.string(forKey: Key.outputMode),
           let mode = TranscriptionOutputMode(rawValue: raw)
        {
            outputMode = mode
        }
        customPrompt = defaults.string(forKey: Key.customPrompt) ?? TranscriptionOutputMode.defaultCustomPrompt
        if customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            customPrompt = TranscriptionOutputMode.defaultCustomPrompt
        }
        if let data = defaults.data(forKey: Key.customPostPrompts),
           let decoded = try? JSONDecoder().decode([CustomPostProcessingPrompt].self, from: data)
        {
            customPostProcessingPrompts = Self.normalizedCustomPostProcessingPrompts(decoded)
        } else {
            customPostProcessingPrompts = []
        }
        if customPostProcessingPrompts.isEmpty,
           customPrompt != TranscriptionOutputMode.defaultCustomPrompt,
           !customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            customPostProcessingPrompts = [
                CustomPostProcessingPrompt(title: "Saved custom prompt", prompt: customPrompt)
            ]
        }
        if defaults.object(forKey: Key.postProcessingEnabled) != nil {
            postProcessingEnabled = defaults.bool(forKey: Key.postProcessingEnabled)
        }
        if defaults.object(forKey: Key.copyToClipboard) != nil {
            copyToClipboard = defaults.bool(forKey: Key.copyToClipboard)
        }
        if defaults.object(forKey: Key.historyEnabled) != nil {
            historyEnabled = defaults.bool(forKey: Key.historyEnabled)
        }
        if let raw = defaults.string(forKey: Key.translationLanguage),
           let option = LanguageOption(rawValue: raw)
        {
            translationLanguage = option
        }
        if let raw = defaults.string(forKey: Key.favoriteTranslationLanguage1),
           let option = LanguageOption(rawValue: raw)
        {
            favoriteTranslationLanguage1 = option
        }
        if let raw = defaults.string(forKey: Key.favoriteTranslationLanguage2),
           let option = LanguageOption(rawValue: raw)
        {
            favoriteTranslationLanguage2 = option
        }
        if defaults.object(forKey: Key.handsfreeMaxSeconds) != nil {
            handsfreeMaxSeconds = Self.clampHandsfreeSeconds(defaults.integer(forKey: Key.handsfreeMaxSeconds))
        } else if defaults.object(forKey: Key.legacyHandsfreeMaxMinutes) != nil {
            handsfreeMaxSeconds = Self.clampHandsfreeSeconds(defaults.integer(forKey: Key.legacyHandsfreeMaxMinutes) * 60)
        }
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(apiKey, forKey: Key.apiKey)
        defaults.set(geminiModel.rawValue, forKey: Key.geminiModel)
        defaults.set(outputMode.rawValue, forKey: Key.outputMode)
        defaults.set(customPrompt, forKey: Key.customPrompt)
        customPostProcessingPrompts = Self.normalizedCustomPostProcessingPrompts(customPostProcessingPrompts)
        if let data = try? JSONEncoder().encode(customPostProcessingPrompts) {
            defaults.set(data, forKey: Key.customPostPrompts)
        }
        defaults.set(postProcessingEnabled, forKey: Key.postProcessingEnabled)
        defaults.set(copyToClipboard, forKey: Key.copyToClipboard)
        defaults.set(historyEnabled, forKey: Key.historyEnabled)
        defaults.set(translationLanguage.rawValue, forKey: Key.translationLanguage)
        defaults.set(favoriteTranslationLanguage1.rawValue, forKey: Key.favoriteTranslationLanguage1)
        defaults.set(favoriteTranslationLanguage2.rawValue, forKey: Key.favoriteTranslationLanguage2)
        defaults.set(Self.clampHandsfreeSeconds(handsfreeMaxSeconds), forKey: Key.handsfreeMaxSeconds)
        Self.store(pushToTalkHotKey, forKey: Key.pushToTalkHotKey, in: defaults)
        Self.store(handsfreeHotKey, forKey: Key.handsfreeHotKey, in: defaults)
        defaults.set(spokenLanguage?.rawValue, forKey: Key.spokenLanguage)
    }

    /// Loads both shortcuts, migrating from the single pre-3.5 shortcut + mode
    /// setting the first time. A stored empty value means "disabled".
    private func loadHotKeys(from defaults: UserDefaults) {
        let hasNewKeys = defaults.object(forKey: Key.pushToTalkHotKey) != nil
            || defaults.object(forKey: Key.handsfreeHotKey) != nil
        if hasNewKeys {
            pushToTalkHotKey = Self.hotKey(forKey: Key.pushToTalkHotKey, in: defaults)
            handsfreeHotKey = Self.hotKey(forKey: Key.handsfreeHotKey, in: defaults)
            return
        }

        // Migration from the single-shortcut era.
        pushToTalkHotKey = HotKey.defaultPushToTalk
        handsfreeHotKey = HotKey.defaultHandsfree
        guard let data = defaults.data(forKey: Key.legacyHotKey),
              let legacy = try? JSONDecoder().decode(HotKey.self, from: data),
              !legacy.isFnKey // fn stays the push-to-talk default
        else { return }
        let legacyMode = defaults.string(forKey: Key.legacyRecordingMode).flatMap(RecordingMode.init(rawValue:)) ?? .handsfree
        switch legacyMode {
        case .handsfree:
            handsfreeHotKey = legacy
        case .pushToTalk:
            pushToTalkHotKey = legacy
            if legacy.conflicts(with: HotKey.defaultHandsfree) { handsfreeHotKey = nil }
        }
    }

    private static func hotKey(forKey key: String, in defaults: UserDefaults) -> HotKey? {
        guard let data = defaults.data(forKey: key), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(HotKey.self, from: data)
    }

    private static func store(_ hotKey: HotKey?, forKey key: String, in defaults: UserDefaults) {
        if let hotKey, let data = try? JSONEncoder().encode(hotKey) {
            defaults.set(data, forKey: key)
        } else {
            defaults.set(Data(), forKey: key) // explicit "disabled" marker
        }
    }

    static func clampHandsfreeSeconds(_ seconds: Int) -> Int {
        min(max(seconds, minHandsfreeSeconds), maxHandsfreeSeconds)
    }

    static func normalizedCustomPostProcessingPrompts(_ prompts: [CustomPostProcessingPrompt]) -> [CustomPostProcessingPrompt] {
        prompts.compactMap { prompt in
            let title = prompt.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = prompt.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            return CustomPostProcessingPrompt(
                id: prompt.id,
                title: title.isEmpty ? "Custom prompt" : title,
                prompt: body
            )
        }
    }
}

// MARK: - DictationError

enum DictationError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidAPIKey
    case audioFormatCreationFailed
    case transcriptionFailed
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:                return "Invalid API URL."
        case .invalidResponse:           return "Invalid network response."
        case .invalidAPIKey:             return "Invalid API key. Check Settings."
        case .audioFormatCreationFailed: return "Could not configure audio capture."
        case .transcriptionFailed:       return "Transcription failed."
        case .serverError(let message):  return message
        }
    }
}
