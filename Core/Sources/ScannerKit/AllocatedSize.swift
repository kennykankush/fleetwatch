import Foundation

/// Honest sizing: allocated bytes on disk, symlinks never followed, file
/// contents never read (iCloud dataless files stay dataless).
public enum AllocatedSize {
    public static func measure(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
        ]

        let values = try? url.resourceValues(forKeys: keys)
        if values?.isSymbolicLink == true { return 0 }
        guard values?.isDirectory == true else {
            return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let v = try? fileURL.resourceValues(forKeys: keys),
                  v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }
}
