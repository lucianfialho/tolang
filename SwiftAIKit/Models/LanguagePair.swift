import Foundation

public struct Language: Codable, Hashable, Identifiable {
    public let id: String         // locale identifier, e.g. "pt-BR"
    public let name: String       // display name, e.g. "Português"
    public let flag: String

    public static let all: [Language] = [
        Language(id: "pt-BR", name: "Português",   flag: "🇧🇷"),
        Language(id: "en-US", name: "English",      flag: "🇺🇸"),
        Language(id: "es-ES", name: "Español",      flag: "🇪🇸"),
        Language(id: "fr-FR", name: "Français",     flag: "🇫🇷"),
        Language(id: "de-DE", name: "Deutsch",      flag: "🇩🇪"),
        Language(id: "it-IT", name: "Italiano",     flag: "🇮🇹"),
        Language(id: "ja-JP", name: "日本語",        flag: "🇯🇵"),
        Language(id: "zh-CN", name: "中文",          flag: "🇨🇳"),
        Language(id: "ko-KR", name: "한국어",        flag: "🇰🇷"),
        Language(id: "ar-SA", name: "العربية",      flag: "🇸🇦"),
    ]

    public static let portuguese = all[0]
    public static let english    = all[1]
}

public struct LanguagePair: Codable, Hashable {
    public var source: Language
    public var target: Language
    public var bidirectional: Bool   // auto-swap when other person speaks

    public var label: String { "\(source.flag) → \(target.flag)" }

    public static let `default` = LanguagePair(
        source: .portuguese,
        target: .english,
        bidirectional: true
    )

    // Common presets shown in menu
    public static let presets: [LanguagePair] = [
        LanguagePair(source: .portuguese, target: .english,    bidirectional: true),
        LanguagePair(source: .english,    target: .portuguese, bidirectional: true),
        LanguagePair(source: Language(id: "es-ES", name: "Español",  flag: "🇪🇸"), target: .english, bidirectional: true),
        LanguagePair(source: Language(id: "fr-FR", name: "Français", flag: "🇫🇷"), target: .english, bidirectional: true),
        LanguagePair(source: Language(id: "de-DE", name: "Deutsch",  flag: "🇩🇪"), target: .english, bidirectional: true),
        LanguagePair(source: Language(id: "ja-JP", name: "日本語",   flag: "🇯🇵"), target: .english, bidirectional: true),
        LanguagePair(source: Language(id: "zh-CN", name: "中文",     flag: "🇨🇳"), target: .english, bidirectional: true),
    ]
}
