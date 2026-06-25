import Foundation

@MainActor
public protocol ZipArchiving {
    func createArchive(sourceFolder: URL, files: [URL], outputURL: URL) async throws
}

public enum ZipArchiverError: Error, LocalizedError, Equatable {
    case noFiles
    case failed(Int32, String)

    public var errorDescription: String? {
        switch self {
        case .noFiles:
            return "No files were available to zip."
        case .failed(let code, let output):
            return "zip failed with exit code \(code): \(output)"
        }
    }
}

public struct ProcessZipArchiver: ZipArchiving {
    public init() {}

    public func createArchive(sourceFolder: URL, files: [URL], outputURL: URL) async throws {
        guard !files.isEmpty else {
            throw ZipArchiverError.noFiles
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = sourceFolder
        process.arguments = ["-q", outputURL.path] + files.map { $0.pathRelative(to: sourceFolder) }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "<unreadable output>"
            throw ZipArchiverError.failed(process.terminationStatus, output)
        }
    }
}
