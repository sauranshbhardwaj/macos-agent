import Foundation
import Testing
@testable import MacAgentCore

@Suite
struct CapabilityRegistryTests {
    @Test
    func defaultRegistryCoversAllExecutableOperations() throws {
        let actual = CapabilityRegistry.default.metadata
            .flatMap(\.operations)
            .map(\.rawValue)
            .sorted()
        let expected = AgentOperation.allCases
            .filter { $0 != .unsupported }
            .map(\.rawValue)
            .sorted()

        #expect(actual == expected)
    }

    @Test
    func defaultRegistryRoutesOperationsToStableCapabilityIDs() throws {
        let registry = CapabilityRegistry.default

        #expect(try registry.adapter(for: .scanSelectLargestFiles).metadata.id == "local.files.largest-files-zip")
        #expect(try registry.adapter(for: .createZip).metadata.id == "local.files.largest-files-zip")
        #expect(try registry.adapter(for: .convertDocxToPDF).metadata.id == "local.documents.docx-to-pdf")
        #expect(try registry.adapter(for: .writeMarkdown).metadata.id == "local.web.hacker-news-markdown")
        #expect(try registry.adapter(for: .openURL).metadata.id == "local.browser.open-url")
        #expect(try registry.adapter(for: .openApp).metadata.id == "local.apps.open-allowlisted-app")
        #expect(throws: CapabilityRegistryError.unsupportedOperation(.unsupported)) {
            _ = try registry.adapter(for: .unsupported)
        }
    }

    @Test
    func defaultRegistryMetadataIsComplete() {
        for metadata in CapabilityRegistry.default.metadata {
            #expect(metadata.id.hasPrefix("local."))
            #expect(!metadata.displayName.isEmpty)
            #expect(!metadata.description.isEmpty)
            #expect(metadata.version == "1.0")
            #expect(!metadata.operations.isEmpty)
            #expect(!metadata.plannerTools.isEmpty)
            #expect(metadata.executorLocation == .localMac)
            #expect(CapabilityRiskTier.allCases.contains(metadata.defaultRiskTier))
            #expect(metadata.operations.map(\.rawValue).sorted() == metadata.plannerTools.map(\.operation.rawValue).sorted())

            for tool in metadata.plannerTools {
                #expect(!tool.name.isEmpty)
                #expect(!tool.description.isEmpty)
                #expect(!tool.dryRunBehavior.isEmpty)
            }
        }
    }

    @Test
    func permissionsMetadataIsDescriptiveOnlyForNow() throws {
        for metadata in CapabilityRegistry.default.metadata {
            #expect(metadata.requiredPermissions.allSatisfy { $0.enforcement == .descriptiveOnly })
        }

        let docx = try #require(CapabilityRegistry.default.metadata.first { $0.id == "local.documents.docx-to-pdf" })
        #expect(docx.requiredPermissions.map(\.requirement).contains(.desktopDocumentsAccess))
        #expect(docx.requiredPermissions.map(\.requirement).contains(.wordAutomation))

        let readiness = try #require(CapabilityRegistry.default.metadata.first { $0.id == "local.permissions.readiness" })
        #expect(readiness.defaultRiskTier == .tier0)
        #expect(readiness.requiredPermissions.isEmpty)
    }

    @Test
    func registryRejectsDuplicateCapabilityIDs() {
        #expect(throws: CapabilityRegistryError.duplicateCapabilityID("local.test.duplicate")) {
            _ = try CapabilityRegistry(adapters: [
                MetadataOnlyCapabilityAdapter(metadata: testMetadata(id: "local.test.duplicate", operation: .openURL)),
                MetadataOnlyCapabilityAdapter(metadata: testMetadata(id: "local.test.duplicate", operation: .openApp))
            ])
        }
    }

    @Test
    func registryRejectsDuplicateOperations() {
        #expect(throws: CapabilityRegistryError.duplicateOperation(.openURL, "local.test.first", "local.test.second")) {
            _ = try CapabilityRegistry(adapters: [
                MetadataOnlyCapabilityAdapter(metadata: testMetadata(id: "local.test.first", operation: .openURL)),
                MetadataOnlyCapabilityAdapter(metadata: testMetadata(id: "local.test.second", operation: .openURL))
            ])
        }
    }

    private func testMetadata(id: String, operation: AgentOperation) -> CapabilityMetadata {
        CapabilityMetadata(
            id: id,
            displayName: "Test capability",
            description: "Test capability.",
            operations: [operation],
            plannerTools: [
                AgentTool(
                    operation: operation,
                    name: "Test tool",
                    description: "Test tool.",
                    requiredFields: [],
                    sideEffects: [],
                    dryRunBehavior: "Preview test tool."
                )
            ],
            defaultRiskTier: .tier0
        )
    }
}
