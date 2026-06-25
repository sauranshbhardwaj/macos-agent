import Foundation

public struct ProcessResult: Sendable, Equatable {
    public var terminationStatus: Int32
    public var output: String

    public init(terminationStatus: Int32, output: String) {
        self.terminationStatus = terminationStatus
        self.output = output
    }
}

public enum AsyncProcessRunner {
    public static func run(
        executablePath: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil
    ) async throws -> ProcessResult {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.currentDirectoryURL = currentDirectoryURL
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "<unreadable process output>"
            return ProcessResult(terminationStatus: process.terminationStatus, output: output)
        }.value
    }
}
