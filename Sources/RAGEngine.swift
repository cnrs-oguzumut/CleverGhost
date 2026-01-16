import Foundation
import NaturalLanguage

@available(macOS 26.0, *)
class RAGEngine {
    static let shared = RAGEngine()
    
    struct TextChunk {
        let text: String
        let sourceName: String
        let pageIndex: Int
        let embedding: [Double]?
        let id: UUID = UUID()
    }
    
    private var chunks: [TextChunk] = []
    private let embeddingModel = NLEmbedding.sentenceEmbedding(for: .english)
    
    // MARK: - Ingestion
    
    /// Clear existing index
    func clearIndex() {
        chunks = []
    }
    
    /// Process and index a document
    func indexDocument(text: String, sourceName: String, pageIndex: Int, chunkSize: Int = 250) async {
        // Simple overlapping chunker
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let overlap = 100
        
        var currentIndex = 0
        while currentIndex < words.count {
            let endIndex = min(currentIndex + chunkSize, words.count)
            let chunkWords = words[currentIndex..<endIndex]
            let chunkText = chunkWords.joined(separator: " ")
            
            // Compute embedding
            let vector = embeddingModel?.vector(for: chunkText)
            
            let chunk = TextChunk(
                text: chunkText,
                sourceName: sourceName,
                pageIndex: pageIndex,
                embedding: vector
            )
            
            chunks.append(chunk)
            
            currentIndex += (chunkSize - overlap)
        }
    }
    
    // MARK: - Retrieval
    
    /// Find most relevant chunks for a question
    func retrieveRelevantChunks(question: String, limit: Int = 5) -> [TextChunk] {
        guard let questionVector = embeddingModel?.vector(for: question) else { return [] }
        
        // Calculate cosine similarity for all chunks
        let scoredChunks = chunks.map { chunk -> (TextChunk, Double) in
            guard let chunkVector = chunk.embedding else { return (chunk, 0.0) }
            return (chunk, cosineSimilarity(questionVector, chunkVector))
        }
        
        // Sort by similarity descending
        let sorted = scoredChunks.sorted { $0.1 > $1.1 }
        
        // Return top N
        return sorted.prefix(limit).map { $0.0 }
    }
    
    /// Cosine Similarity
    private func cosineSimilarity(_ v1: [Double], _ v2: [Double]) -> Double {
        guard v1.count == v2.count else { return 0.0 }
        
        var dotProduct = 0.0
        var mag1 = 0.0
        var mag2 = 0.0
        
        for i in 0..<v1.count {
            dotProduct += v1[i] * v2[i]
            mag1 += v1[i] * v1[i]
            mag2 += v2[i] * v2[i]
        }
        
        if mag1 == 0 || mag2 == 0 { return 0.0 }
        return dotProduct / (sqrt(mag1) * sqrt(mag2))
    }
}
