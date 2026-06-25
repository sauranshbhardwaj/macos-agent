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
    private final class ProcessBox: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false

        func set(_ process: Process) {
            lock.lock()
            self.process = process
            let shouldTerminate = cancelled
            lock.unlock()

            if shouldTerminate {
                process.terminate()
            }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let process = process
            lock.unlock()

            process?.terminate()
        }

        var isCancelled: Bool {
            lock.lock()
            let value = cancelled
            lock.unlock()
            return value
        }
    }

    public static func run(
        executablePath: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil
    ) async throws -> ProcessResult {
        let box = ProcessBox()

        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.currentDirectoryURL = currentDirectoryURL
                process.arguments = arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                box.set(process)
                if box.isCancelled {
                    throw CancellationError()
                }

                try process.run()
                process.waitUntilExit()

                if box.isCancelled {
                    throw CancellationError()
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "<unreadable process output>"
                return ProcessResult(terminationStatus: process.terminationStatus, output: output)
            }.value
        } onCancel: {
            box.cancel()
        }
    }
}
