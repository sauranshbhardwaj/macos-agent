import Foundation

public enum FinderSelectionResolver {
    public static func whitelistedSelection(
        whitelist: PathWhitelist,
        finderContextReader: any FinderContextReading
    ) throws -> [URL] {
        try finderContextReader.selectedItems().map { url in
            try whitelist.validateInsideWhitelist(url.path)
        }
    }

    public static func selectedDirectoryPath(
        primary: String?,
        secondary: String?,
        contextSource: FinderContextSource?,
        whitelist: PathWhitelist,
        finderContextReader: any FinderContextReading
    ) throws -> String? {
        if let path = primary ?? secondary,
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return path
        }

        guard contextSource == .finderSelection else {
            return nil
        }

        let selection = try whitelistedSelection(
            whitelist: whitelist,
            finderContextReader: finderContextReader
        )
        guard selection.count == 1 else {
            throw FinderContextError.noDirectorySelection
        }

        let url = selection[0]
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
            throw FinderContextError.noDirectorySelection
        }
        return url.path
    }
}
