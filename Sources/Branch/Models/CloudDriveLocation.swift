import Foundation

struct CloudDriveLocation: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let symbol: String

    var id: URL { url }
}
