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

        let result = try await AsyncProcessRunner.run(
            executablePath: "/usr/bin/zip",
            arguments: ["-q", outputURL.path] + files.map { $0.pathRelative(to: sourceFolder) },
            currentDirectoryURL: sourceFolder
        )

        guard result.terminationStatus == 0 else {
            throw ZipArchiverError.failed(result.terminationStatus, result.output)
        }
    }
}
