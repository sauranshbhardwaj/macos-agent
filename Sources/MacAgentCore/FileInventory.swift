import Foundation

public struct FileRecord: Equatable, Sendable {
    public var url: URL
    public var byteCount: Int64

    public init(url: URL, byteCount: Int64) {
        self.url = url
        self.byteCount = byteCount
    }

    public var displaySize: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

public struct DocxRecord: Equatable, Sendable {
    public var sourceURL: URL
    public var destinationURL: URL
    public var skippedBecausePDFExists: Bool
    public var isMockDestination: Bool

    public init(
        sourceURL: URL,
        destinationURL: URL,
        skippedBecausePDFExists: Bool,
        isMockDestination: Bool
    ) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.skippedBecausePDFExists = skippedBecausePDFExists
        self.isMockDestination = isMockDestination
    }
}

public struct FileInventory {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func largestFiles(in folder: URL, count: Int) throws -> [FileRecord] {
        try regularFiles(in: folder)
            .sorted { first, second in
                if first.byteCount == second.byteCount {
                    return first.url.path < second.url.path
                }
                return first.byteCount > second.byteCount
            }
            .prefix(max(count, 0))
            .map { $0 }
    }

    public func docxFiles(in folder: URL, outputFolder: URL? = nil, mockDestinations: Bool = false) throws -> [DocxRecord] {
        try regularFiles(in: folder)
            .filter { record in
                record.url.pathExtension.lowercased() == "docx" &&
                !record.url.lastPathComponent.hasPrefix("~$")
            }
            .sorted { $0.url.path < $1.url.path }
            .map { record in
                let basename = record.url.deletingPathExtension().lastPathComponent
                let destinationFolder = outputFolder ?? record.url.deletingLastPathComponent()
                let destinationName = mockDestinations ? "\(basename).mock.pdf" : "\(basename).pdf"
                let destination = destinationFolder.appendingPathComponent(destinationName)
                return DocxRecord(
                    sourceURL: record.url,
                    destinationURL: destination,
                    skippedBecausePDFExists: fileManager.fileExists(atPath: destination.path),
                    isMockDestination: mockDestinations
                )
            }
    }

    private func regularFiles(in folder: URL) throws -> [FileRecord] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey
        ]

        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var records: [FileRecord] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true {
                continue
            }
            guard values.isRegularFile == true else {
                continue
            }

            let size = Int64(values.fileSize ?? values.totalFileAllocatedSize ?? 0)
            records.append(FileRecord(url: url, byteCount: size))
        }
        return records
    }
}

public extension URL {
    func pathRelative(to baseURL: URL) -> String {
        let base = baseURL.standardizedFileURL.path
        let full = standardizedFileURL.path
        if full == base {
            return lastPathComponent
        }
        if full.hasPrefix(base + "/") {
            return String(full.dropFirst(base.count + 1))
        }
        return full
    }
}
