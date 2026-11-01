import Foundation
import SwiftData

extension UserStateStore {
    /// Every favourite, resume point, watched mark, hidden title and category choice of every profile, for
    /// "Clear synced data". The profile list itself is not in these rows and stays.
    func deleteEverything() {
        for row in (try? context.fetch(FetchDescriptor<UserContentState>())) ?? [] {
            context.delete(row)
        }
        for row in (try? context.fetch(FetchDescriptor<CategoryPreference>())) ?? [] {
            context.delete(row)
        }
        commit()
    }
}
