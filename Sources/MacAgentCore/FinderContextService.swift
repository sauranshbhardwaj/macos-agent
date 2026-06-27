import Foundation

public enum FinderContextError: Error, LocalizedError, Equatable {
    case noSelection
    case noDirectorySelection
    case appleScriptFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noSelection:
            return "Finder has no selected items."
        case .noDirectorySelection:
            return "Select one folder in Finder first."
        case .appleScriptFailed(let detail):
            return "Could not read Finder selection: \(detail)"
        }
    }
}

public protocol FinderContextReading: Sendable {
    func selectedItems() throws -> [URL]
}

public struct AppleScriptFinderContextReader: FinderContextReading {
    public init() {}

    public func selectedItems() throws -> [URL] {
        let script = """
        tell application id "com.apple.finder"
            set selectedItems to selection
            if (count of selectedItems) is 0 then return ""
            set output to ""
            repeat with selectedItem in selectedItems
                set output to output & POSIX path of (selectedItem as alias) & linefeed
            end repeat
            return output
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw FinderContextError.appleScriptFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let urls = output
            .split(whereSeparator: \.isNewline)
            .map { URL(fileURLWithPath: String($0)) }

        guard !urls.isEmpty else {
            throw FinderContextError.noSelection
        }

        return urls
    }
}

public enum FinderContextSource: String, Codable, Sendable {
    case finderSelection = "finder_selection"
}
