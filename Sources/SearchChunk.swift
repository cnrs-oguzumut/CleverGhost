import Foundation
import SwiftData

@Model
final class SearchChunk {
    @Attribute(.unique) var id: UUID
    var text: String
    var embedding: [Double]
    var pageIndex: Int
    var chunkIndex: Int
    var sourceName: String
    var pdf: GhostPDF?
    
    init(text: String, embedding: [Double], pageIndex: Int, chunkIndex: Int, sourceName: String, pdf: GhostPDF? = nil) {
        self.id = UUID()
        self.text = text
        self.embedding = embedding
        self.pageIndex = pageIndex
        self.chunkIndex = chunkIndex
        self.sourceName = sourceName
        self.pdf = pdf
    }

}
