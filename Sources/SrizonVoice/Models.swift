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
}

// MARK: - HotKey

struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let defaultValue = HotKey(
        keyCode: 6, // Z
        modifiers: UInt32(optionKey)
    )

    var displayString: String {
        var pieces: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { pieces.append("⌘") }
        if modifiers & UInt32(shiftKey) != 0 { pieces.append("⇧") }
        if modifiers & UInt32(optionKey) != 0 { pieces.append("⌥") }
        if modifiers & UInt32(controlKey) != 0 { pieces.append("⌃") }
        pieces.append(KeyCodeMap.displayName(for: keyCode))
        return pieces.joined(separator: "")
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
        default: return "Key\(keyCode)"
        }
    }
}

// MARK: - UserSettings

final class UserSettings {
    private enum Key {
        static let apiKey = "gladia.apiKey"
        static let hotKey = "app.hotKey"
        static let language = "dictation.language"
        static let secondaryLanguage = "dictation.secondaryLanguage"
    }

    var apiKey = ""
    var hotKey = HotKey.defaultValue
    var language: LanguageOption = .english
    var secondaryLanguage: LanguageOption?

    func load() {
        let defaults = UserDefaults.standard
        apiKey = defaults.string(forKey: Key.apiKey) ?? ""

        if let data = defaults.data(forKey: Key.hotKey),
           let decoded = try? JSONDecoder().decode(HotKey.self, from: data)
        {
            hotKey = decoded
        }
        if let raw = defaults.string(forKey: Key.language),
           let option = LanguageOption(rawValue: raw)
        {
            language = option
        }
        if let raw = defaults.string(forKey: Key.secondaryLanguage),
           let option = LanguageOption(rawValue: raw)
        {
            secondaryLanguage = option
        }
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(apiKey, forKey: Key.apiKey)
        defaults.set(language.rawValue, forKey: Key.language)
        if let secondary = secondaryLanguage {
            defaults.set(secondary.rawValue, forKey: Key.secondaryLanguage)
        } else {
            defaults.removeObject(forKey: Key.secondaryLanguage)
        }
        if let data = try? JSONEncoder().encode(hotKey) {
            defaults.set(data, forKey: Key.hotKey)
        }
    }
}

// MARK: - DictationError

enum DictationError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidAPIKey
    case sessionInitializationFailed
    case audioFormatCreationFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL."
        case .invalidResponse: return "Invalid network response."
        case .invalidAPIKey: return "Invalid API key. Check Settings."
        case .sessionInitializationFailed: return "Could not start a Gladia session."
        case .audioFormatCreationFailed: return "Could not configure audio capture."
        }
    }
}
