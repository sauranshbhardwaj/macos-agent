import Foundation

@MainActor
public protocol DocumentConverting {
    var isAvailable: Bool { get }
    var modeName: String { get }
    func convert(_ records: [DocxRecord], log: @escaping (String) -> Void) async throws -> [DocxRecord]
}

public enum DocumentConversionError: Error, LocalizedError, Equatable {
    case wordUnavailable
    case conversionFailed(String)
    case mockWriteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .wordUnavailable:
            return "Microsoft Word is unavailable. Set MAC_AGENT_MOCK_DOCX=1 to create clearly marked mock PDF placeholders."
        case .conversionFailed(let detail):
            return "DOCX conversion failed: \(detail)"
        case .mockWriteFailed(let detail):
            return "Mock DOCX conversion failed: \(detail)"
        }
    }
}

public struct MicrosoftWordDocumentConverter: DocumentConverting {
    private let fileManager: FileManager
    private let wordAppPath: String

    public init(
        fileManager: FileManager = .default,
        wordAppPath: String = "/Applications/Microsoft Word.app"
    ) {
        self.fileManager = fileManager
        self.wordAppPath = wordAppPath
    }

    public var isAvailable: Bool {
        fileManager.fileExists(atPath: wordAppPath)
    }

    public var modeName: String {
        "Microsoft Word AppleScript"
    }

    public func convert(_ records: [DocxRecord], log: @escaping (String) -> Void) async throws -> [DocxRecord] {
        guard isAvailable else {
            throw DocumentConversionError.wordUnavailable
        }

        var converted: [DocxRecord] = []
        for record in records where !record.skippedBecausePDFExists {
            log("Converting \(record.sourceURL.lastPathComponent) to \(record.destinationURL.lastPathComponent)")
            try runAppleScript(source: record.sourceURL, destination: record.destinationURL)
            converted.append(record)
        }
        return converted
    }

    private func runAppleScript(source: URL, destination: URL) throws {
        let script = """
        tell application "Microsoft Word"
            set sourceFile to POSIX file "\(Self.escapeAppleScript(source.path))"
            set outputFile to "\(Self.escapeAppleScript(destination.path))"
            open sourceFile
            set activeDoc to active document
            save as activeDoc file name outputFile file format format PDF
            close activeDoc saving no
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

        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "<unreadable osascript output>"
            throw DocumentConversionError.conversionFailed(output)
        }
    }

    private static func escapeAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

public struct MockDocumentConverter: DocumentConverting {
    public init() {}

    public var isAvailable: Bool {
        ProcessInfo.processInfo.environment["MAC_AGENT_MOCK_DOCX"] == "1"
    }

    public var modeName: String {
        "Mock DOCX placeholder"
    }

    public func convert(_ records: [DocxRecord], log: @escaping (String) -> Void) async throws -> [DocxRecord] {
        guard isAvailable else {
            throw DocumentConversionError.wordUnavailable
        }

        var converted: [DocxRecord] = []
        for record in records where !record.skippedBecausePDFExists {
            log("Writing mock placeholder \(record.destinationURL.lastPathComponent)")
            let markdown = """
            Mock PDF placeholder
            Source DOCX: \(record.sourceURL.path)
            Created by MacAgent because Microsoft Word was unavailable and MAC_AGENT_MOCK_DOCX=1 was set.
            """
            do {
                try markdown.data(using: .utf8)?.write(to: record.destinationURL, options: .atomic)
            } catch {
                throw DocumentConversionError.mockWriteFailed(error.localizedDescription)
            }
            converted.append(record)
        }
        return converted
    }
}

public struct AutoDocumentConverter: DocumentConverting {
    private let word: MicrosoftWordDocumentConverter
    private let mock: MockDocumentConverter

    public init(
        word: MicrosoftWordDocumentConverter = MicrosoftWordDocumentConverter(),
        mock: MockDocumentConverter = MockDocumentConverter()
    ) {
        self.word = word
        self.mock = mock
    }

    public var isAvailable: Bool {
        word.isAvailable || mock.isAvailable
    }

    public var modeName: String {
        word.isAvailable ? word.modeName : mock.modeName
    }

    public func convert(_ records: [DocxRecord], log: @escaping (String) -> Void) async throws -> [DocxRecord] {
        if word.isAvailable {
            return try await word.convert(records, log: log)
        }
        return try await mock.convert(records, log: log)
    }
}
