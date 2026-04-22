import OSLog

public enum ToLangLogger {
    static let speech      = Logger(subsystem: "com.yourname.tolang", category: "speech")
    static let translation = Logger(subsystem: "com.yourname.tolang", category: "translation")
    static let audio       = Logger(subsystem: "com.yourname.tolang", category: "audio")
    static let capture     = Logger(subsystem: "com.yourname.tolang", category: "capture")
}
