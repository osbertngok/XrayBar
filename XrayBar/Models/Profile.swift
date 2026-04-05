import Foundation

struct Profile: Identifiable, Hashable {
    let id: String   // filename without .json
    let name: String // display name
    let url: URL     // full path to JSON file

    init(url: URL) {
        let filename = url.deletingPathExtension().lastPathComponent
        self.id = filename
        self.name = filename
        self.url = url
    }
}
