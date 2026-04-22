import Foundation

struct AppConfig: SwiftAIAppConfig {
    static let appName = "ToLang"
    static let trigger = Trigger.hotkey

    // Not used in ToLang — translation is always PT→EN via speech
    static let actions: [Action] = []
}
