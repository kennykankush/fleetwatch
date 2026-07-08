import Foundation

/// The only deletion primitive in Fleetwatch. Nothing is ever `rm`'d —
/// items go to the Trash, recoverable, and the caller records it in the
/// Ledger.
public enum TrashAction {
    /// Moves the item to the Trash. Returns the path it landed at.
    @discardableResult
    public static func moveToTrash(path: String) throws -> String {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resulting)
        return resulting?.path ?? "Trash"
    }
}
