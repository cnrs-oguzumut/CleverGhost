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
    
    // MARK: - Document Comparison

    /// Compare two documents semantically by chunking and comparing embeddings
    /// Returns similarity score from 0.0 (completely different) to 1.0 (identical)
    func compareDocuments(text1: String, text2: String, chunkSize: Int = 250) -> Double {
        // Chunk both documents
        let chunks1 = chunkText(text1, chunkSize: chunkSize)
        let chunks2 = chunkText(text2, chunkSize: chunkSize)

        guard !chunks1.isEmpty, !chunks2.isEmpty else { return 0.0 }

        // Compare first 5 chunks max for performance (covers ~1250 words)
        let maxChunks = 5
        let limitedChunks1 = Array(chunks1.prefix(maxChunks))
        let limitedChunks2 = Array(chunks2.prefix(maxChunks))

        // Count how many chunks from doc1 have a close match in doc2
        var matchCount = 0

        for chunk1 in limitedChunks1 {
            guard let vec1 = embeddingModel?.vector(for: chunk1) else { continue }

            var bestSimilarity = 0.0
            for chunk2 in limitedChunks2 {
                guard let vec2 = embeddingModel?.vector(for: chunk2) else { continue }
                let sim = cosineSimilarity(vec1, vec2)
                bestSimilarity = max(bestSimilarity, sim)
            }

            // Threshold: chunks are "similar" if cosine similarity > 0.85 (lowered for compressed/reformatted PDFs)
            if bestSimilarity > 0.85 {
                matchCount += 1
            }
        }

        // Return percentage of chunks that matched
        return Double(matchCount) / Double(limitedChunks1.count)
    }

    /// Helper: chunk text into overlapping segments
    private func chunkText(_ text: String, chunkSize: Int) -> [String] {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let overlap = 100

        var chunks: [String] = []
        var currentIndex = 0

        while currentIndex < words.count {
            let endIndex = min(currentIndex + chunkSize, words.count)
            let chunkWords = words[currentIndex..<endIndex]
            let chunkText = chunkWords.joined(separator: " ")

            if chunkText.count > 50 { // Only include meaningful chunks
                chunks.append(chunkText)
            }

            currentIndex += (chunkSize - overlap)
        }

        return chunks
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
