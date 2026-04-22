import AppKit
import ApplicationServices

public struct AppContext {
    public let appName: String
    public let windowTitle: String?

    public var displayLabel: String {
        guard let title = windowTitle, !title.isEmpty else { return appName }
        switch appName {
        case "Slack":
            // "channel | Workspace | Slack" → "Slack · #channel"
            let parts = title.components(separatedBy: " | ")
            return "Slack · \(parts[0])"
        case "zoom.us":
            return title == "Zoom" ? "Zoom" : "Zoom · \(title)"
        case "Microsoft Teams", "Microsoft Teams (work or school)":
            return "Teams · \(title)"
        case "Google Chrome", "Safari", "Firefox", "Arc", "Brave Browser":
            // Browser tab title often contains "Meet · …" or "Slack" etc.
            return title
        default:
            return "\(appName) · \(title)"
        }
    }

    public var icon: String {
        switch appName {
        case "Slack":                                          return "number"
        case "zoom.us":                                        return "video.fill"
        case "Microsoft Teams", "Microsoft Teams (work or school)": return "person.3.fill"
        case "Google Chrome", "Safari", "Firefox", "Arc", "Brave Browser": return "globe"
        default:                                               return "app.fill"
        }
    }
}

public class ContextDetector {
    public static func currentContext() -> AppContext? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        let name = app.localizedName ?? "Unknown"
        let title = windowTitle(for: app.processIdentifier)
        return AppContext(appName: name, windowTitle: title)
    }

    private static func windowTitle(for pid: pid_t) -> String? {
        let axApp = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let window = ref else { return nil }
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String, !title.isEmpty else { return nil }
        return title
    }
}
