import Foundation
import SwiftData

@Model
final class NarfBundle {
    var id: UUID
    var title: String?
    var author: String?
    var fileType: String?
    var createdAt: Date 
    var lastOpened: Date 

    init(title: String? = nil, author: String? = nil, fileType: String? = nil) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.fileType = fileType
        self.createdAt = Date()
        self.lastOpened = Date()
    }
}
