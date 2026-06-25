import Foundation
import Testing
@testable import MacAgentCore

@Suite
struct PathWhitelistTests {
    @Test
    func allowsDirectoryInsideRoot() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let child = root.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        let whitelist = PathWhitelist(roots: [root])
        let validated = try whitelist.validateExistingDirectory(child.path)

        #expect(validated.path == child.standardizedFileURL.path)
    }

    @Test
    func rejectsPathOutsideRoot() throws {
        let root = try makeDirectory()
        let outside = try makeDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let whitelist = PathWhitelist(roots: [root])

        do {
            _ = try whitelist.validateExistingDirectory(outside.path)
            Issue.record("Expected outside whitelist error")
        } catch PathValidationError.outsideWhitelist {
        } catch {
            Issue.record("Expected outside whitelist error, got \(error)")
        }
    }

    @Test
    func rejectsSymlinkResolvingOutsideRoot() throws {
        let root = try makeDirectory()
        let outside = try makeDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let link = root.appendingPathComponent("outside-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        let whitelist = PathWhitelist(roots: [root])

        do {
            _ = try whitelist.validateExistingDirectory(link.path)
            Issue.record("Expected outside whitelist error")
        } catch PathValidationError.outsideWhitelist {
        } catch {
            Issue.record("Expected outside whitelist error, got \(error)")
        }
    }

    @Test
    func validatesOutputParentAndRejectsMissingParent() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let whitelist = PathWhitelist(roots: [root])
        let output = root.appendingPathComponent("nested/out.zip")

        do {
            _ = try whitelist.validateOutputPath(output.path)
            Issue.record("Expected parent missing error")
        } catch PathValidationError.parentMissing {
        } catch {
            Issue.record("Expected parent missing error, got \(error)")
        }
    }
}

func makeDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacAgentTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
