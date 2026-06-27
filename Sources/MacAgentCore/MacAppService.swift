import AppKit
import Foundation

public struct MacApp: Equatable, Sendable {
    public var displayName: String
    public var bundleIdentifier: String
    public var aliases: [String]

    public init(displayName: String, bundleIdentifier: String, aliases: [String] = []) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.aliases = aliases
    }
}

public enum MacAppCatalogError: Error, LocalizedError, Equatable {
    case missingAppName
    case appNotAllowed(String)

    public var errorDescription: String? {
        switch self {
        case .missingAppName:
            return "Opening an app requires an app name."
        case .appNotAllowed(let appName):
            return "\(appName) is not in the allowlisted app catalog."
        }
    }
}

public struct MacAppCatalog: Equatable, Sendable {
    public var apps: [MacApp]

    public init(apps: [MacApp] = Self.default.apps) {
        self.apps = apps
    }

    public static let `default` = MacAppCatalog(apps: [
        MacApp(displayName: "Safari", bundleIdentifier: "com.apple.Safari"),
        MacApp(displayName: "Chrome", bundleIdentifier: "com.google.Chrome", aliases: ["Google Chrome"]),
        MacApp(displayName: "Finder", bundleIdentifier: "com.apple.finder"),
        MacApp(displayName: "Notes", bundleIdentifier: "com.apple.Notes"),
        MacApp(displayName: "Calendar", bundleIdentifier: "com.apple.iCal"),
        MacApp(displayName: "Mail", bundleIdentifier: "com.apple.mail"),
        MacApp(displayName: "Messages", bundleIdentifier: "com.apple.MobileSMS", aliases: ["iMessage"]),
        MacApp(displayName: "Apple Music", bundleIdentifier: "com.apple.Music", aliases: ["Music", "iTunes"]),
        MacApp(displayName: "Spotify", bundleIdentifier: "com.spotify.client"),
        MacApp(displayName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap"),
        MacApp(displayName: "VS Code", bundleIdentifier: "com.microsoft.VSCode", aliases: ["Visual Studio Code", "Code"]),
        MacApp(displayName: "Terminal", bundleIdentifier: "com.apple.Terminal")
    ])

    public func resolve(_ rawName: String?) throws -> MacApp {
        guard let rawName, !rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MacAppCatalogError.missingAppName
        }

        let normalizedName = Self.normalize(rawName)
        if let app = apps.first(where: { app in
            Self.normalize(app.displayName) == normalizedName ||
                app.aliases.contains(where: { Self.normalize($0) == normalizedName })
        }) {
            return app
        }

        throw MacAppCatalogError.appNotAllowed(rawName)
    }

    public var displayList: String {
        apps.map(\.displayName).joined(separator: ", ")
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }
}

@MainActor
public protocol AppOpening {
    func open(bundleIdentifier: String) async throws
}

public enum AppOpeningError: Error, LocalizedError, Equatable {
    case appNotInstalled(String)
    case failedToOpen(String)

    public var errorDescription: String? {
        switch self {
        case .appNotInstalled(let bundleIdentifier):
            return "No installed app was found for bundle identifier \(bundleIdentifier)."
        case .failedToOpen(let detail):
            return "Could not open app: \(detail)"
        }
    }
}

public struct WorkspaceAppOpener: AppOpening {
    public init() {}

    @MainActor
    public func open(bundleIdentifier: String) async throws {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw AppOpeningError.appNotInstalled(bundleIdentifier)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: AppOpeningError.failedToOpen(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
