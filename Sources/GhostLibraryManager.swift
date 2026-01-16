import Foundation
import SwiftData
import PDFKit
import FoundationModels
import NaturalLanguage

@available(macOS 26.0, *)
@Generable
struct LibraryDocumentMetadata {
    @Guide(description: "The most appropriate category. STRICTLY choose from: 'Scientific Paper', 'Receipt', 'Invoice', 'Contract', 'Manual', 'Book', 'Slides', 'Financial', 'Medical', 'Other'.")
    let category: String
    
    @Guide(description: "A descriptive title inferred from content. MAX 6 words. For papers use actual title. For receipts use 'Store - Amount'.")
    let title: String
    
    @Guide(description: "A single emoji representing the category (e.g., 📚, 🧾, 💵).")
    let emoji: String
    
    @Guide(description: "5 relevant topic tags.")
    let tags: [String]
    
    @Guide(description: "Confidence score between 0.0 and 1.0.")
    let confidence: Double
}

@MainActor
class GhostLibraryManager: ObservableObject {
    static let shared = GhostLibraryManager()

    @Published var isProcessing = false
    @Published var processingProgress: Double = 0.0
    @Published var aiTemperature: Double = 0.7 // AI temperature for analysis
    private var isCancelled = false

    private let fileManager = FileManager.default
    private var processingQueue: [GhostPDF] = []

    // Storage location
    private var libraryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("CleverGhost", isDirectory: true)
        let libraryFolder = appFolder.appendingPathComponent("SmartLibrary", isDirectory: true)
        let filesFolder = libraryFolder.appendingPathComponent("files", isDirectory: true)

        // Create directories if they don't exist
        try? fileManager.createDirectory(at: filesFolder, withIntermediateDirectories: true)

        return filesFolder
    }

    // MARK: - File Ingestion

    func ingestPDFs(urls: [URL], context: ModelContext) async throws -> [GhostPDF] {
        var ghostPDFs: [GhostPDF] = []

        for url in urls {
            // Ensure we have access to the file
            guard url.startAccessingSecurityScopedResource() else {
                print("❌ Cannot access file: \(url.path)")
                continue
            }
            defer { url.stopAccessingSecurityScopedResource() }

            // Get file size
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            
            // Calculate hash
            let fileHash = calculateFileHash(url: url)
            
            if let hash = fileHash, let existing = checkForDuplicate(fileHash: hash, context: context) {
                 print("⚠️ Duplicate ingested: \(url.lastPathComponent) (matches \(existing.displayName))")
                 // We ALLOW duplicates now so the "Find Duplicates" feature is useful
                 // continue 
            }

            // Generate unique filename
            let uuid = UUID()
            let destinationURL = libraryURL.appendingPathComponent("\(uuid.uuidString).pdf")

            // Copy file to library
            try fileManager.copyItem(at: url, to: destinationURL)

            // Create database record
            let ghostPDF = GhostPDF(
                id: uuid,
                realFilePath: destinationURL.path,
                originalFilename: url.lastPathComponent,
                fileSize: fileSize,
                fileHash: fileHash
            )

            context.insert(ghostPDF)
            ghostPDFs.append(ghostPDF)

            print("✅ Ingested: \(url.lastPathComponent) → \(uuid.uuidString).pdf")
        }

        // Save to database
        try context.save()

        // Start processing queue
        await processQueue(ghostPDFs: ghostPDFs, context: context)

        return ghostPDFs
    }

    // MARK: - Duplicate Detection
    
    private func calculateFileHash(url: URL) -> String? {
        // Simple hash based on first 4KB + file size for speed
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fileHandle.close() }
        
        let firstBlock = (try? fileHandle.read(upToCount: 4096)) ?? Data()
        
        // Read last 4KB too (crucial for PDF incremental updates)
        try? fileHandle.seekToEnd()
        let fileLength = (try? fileHandle.offsetInFile) ?? 0
        let startOfTail = max(0, fileLength - 4096)
        try? fileHandle.seek(toFileOffset: startOfTail)
        let lastBlock = (try? fileHandle.read(upToCount: 4096)) ?? Data()
        
        // Append file size
        var combinedData = firstBlock
        combinedData.append(lastBlock)
        combinedData.append(contentsOf: withUnsafeBytes(of: fileLength) { Data($0) })
        
        // Simple hex string representation
        return combinedData.map { String(format: "%02hhx", $0) }.joined()
    }
    
    func checkForDuplicate(fileHash: String, context: ModelContext) -> GhostPDF? {
        // Find existing PDF with same hash
        var descriptor = FetchDescriptor<GhostPDF>(predicate: #Predicate { $0.fileHash == fileHash })
        return try? context.fetch(descriptor).first
    }

    // MARK: - Text Extraction

    private func extractTextPreview(from pdfURL: URL) -> String? {
        guard let document = PDFDocument(url: pdfURL) else {
            print("❌ Failed to open PDF: \(pdfURL.lastPathComponent)")
            return nil
        }

        var extractedText = ""
        let pagesToExtract = min(2, document.pageCount) // First 2 pages

        for pageIndex in 0..<pagesToExtract {
            if let page = document.page(at: pageIndex),
               let pageText = page.string {
                extractedText += pageText + "\n"
            }
        }

        // Limit text length to ~3000 characters for AI processing
        let preview = String(extractedText.prefix(3000))
        print("✓ Extracted \(preview.count) characters from \(pdfURL.lastPathComponent)")

        return preview.isEmpty ? nil : preview
    }

    // MARK: - AI Processing Queue

    func cancelProcessing() {
        isCancelled = true
    }

    private func processQueue(ghostPDFs: [GhostPDF], context: ModelContext) async {
        print("📊 Starting processing queue with \(ghostPDFs.count) PDFs")
        await MainActor.run {
            isProcessing = true
            processingProgress = 0.0
            isCancelled = false
        }
        print("✅ isProcessing set to TRUE")

        for (index, ghostPDF) in ghostPDFs.enumerated() {
            print("📄 Processing PDF \(index + 1)/\(ghostPDFs.count): \(ghostPDF.originalFilename)")

            // Check for cancellation
            if isCancelled {
                print("🛑 Processing cancelled by user")
                break
            }

            await processGhostPDF(ghostPDF, context: context)

            print("✓ Finished processing PDF \(index + 1)/\(ghostPDFs.count)")

            await MainActor.run {
                processingProgress = Double(index + 1) / Double(ghostPDFs.count)
            }
            print("📊 Progress updated to \(processingProgress)")
        }

        print("🏁 All PDFs processed, setting isProcessing to FALSE")
        await MainActor.run {
            isProcessing = false
            isCancelled = false
        }
    }

    private func processGhostPDF(_ ghostPDF: GhostPDF, context: ModelContext) async {
        // Update status
        await MainActor.run {
            ghostPDF.status = .analyzing
        }

        // Extract text
        let pdfURL = URL(fileURLWithPath: ghostPDF.realFilePath)
        
        var textContent: String? = nil
        
        // 1. Try Ghostscript extraction first (Robust)
        // Extract first 3 pages combined
        var gsText = ""
        for i in 0..<3 {
            if let pageText = await extractTextWithGS(url: pdfURL, pageIndex: i) {
                gsText += pageText + "\n"
            }
        }
        
        if !gsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textContent = gsText
            print("✓ Extracted \(gsText.count) chars using Ghostscript")
        } else {
            // 2. Fallback to PDFKit (Fast but fragile)
            print("⚠️ Ghostscript extraction empty, falling back to PDFKit")
            textContent = extractTextPreview(from: pdfURL)
        }

        guard let textPreview = textContent else {
            await MainActor.run {
                ghostPDF.status = .error
                ghostPDF.ghostEmoji = "📄"
                ghostPDF.ghostTitle = ghostPDF.originalFilename
                ghostPDF.category = "Document"
                try? context.save()
            }
            return
        }

        await MainActor.run {
            ghostPDF.textPreview = textPreview
        }

        // Analyze with AI
        let analysis: (emoji: String, title: String, category: String, tags: [String], confidence: Double)
        
        if #available(macOS 26.0, *) {
            analysis = await analyzeWithAI(text: textPreview)
        } else {
            analysis = performMockAnalysis(text: textPreview)
        }

        let (emoji, title, category, tags, confidence) = analysis

        // Update database
        await MainActor.run {
            ghostPDF.ghostEmoji = emoji
            ghostPDF.ghostTitle = title
            ghostPDF.category = category
            ghostPDF.tags = tags
            ghostPDF.confidence = confidence
            ghostPDF.status = .done

            try? context.save()

            print("✅ Processed: \(ghostPDF.displayName) [\(emoji)] - \(category)")
        }
    }

    // MARK: - AI Analysis

    @available(macOS 26.0, *)
    private func analyzeWithAI(text: String) async -> (emoji: String, title: String, category: String, tags: [String], confidence: Double) {
        let prompt = """
        Analyze the following document text and provide the metadata.
        
        TEXT PREVIEW:
        \(text.prefix(3000))
        
        CRITICAL INSTRUCTIONS:
        1. **Detect Scientific Papers**: Look for "Abstract", "Introduction", "References", "DOI". If found, categorize as "Scientific Paper" (📚).
        2. **RENAME**: Infer a descriptive title. NEVER use "Document" or "Scan".
        3. **Classify**: Choose the most specific category.
        """
        
        do {
            let session = LanguageModelSession()
            // NOTE: Temperature control via aiTemperature property is stored but
            // LanguageModelSession API doesn't currently expose temperature parameter
            // When Apple adds it, we'll integrate it here
            let response = try await session.respond(to: prompt, generating: LibraryDocumentMetadata.self)

            print("🔍 AI Structured Response: \(response.content)")
            print("🌡️  Temperature setting: \(aiTemperature)")

            let meta = response.content
            return (meta.emoji, meta.title, meta.category, meta.tags, meta.confidence)
            
        } catch {
            print("❌ AI Analysis failed: \(error)")
        }

        // Fallback to mock analysis if AI fails
        return performMockAnalysis(text: text)
    }

    // Temporary fallback analysis
    private func performMockAnalysis(text: String) -> (String, String, String, [String], Double) {
        let lowercased = text.lowercased()

        // Simple keyword-based detection for now
        if lowercased.contains("abstract") && lowercased.contains("introduction") {
            return ("📚", "Scientific Paper", "Scientific Paper", ["research", "academic"], 0.7)
        } else if lowercased.contains("receipt") || lowercased.contains("total") {
            return ("🧾", "Receipt", "Receipt", ["purchase"], 0.6)
        } else {
            let lines = text.components(separatedBy: .newlines)
            let title = lines.first(where: { !$0.isEmpty })?.prefix(30) ?? "Document"
            return ("📄", String(title), "Document", ["general"], 0.5)
        }
    }

    // MARK: - Library Management

    func deleteGhostPDF(_ ghostPDF: GhostPDF, context: ModelContext) throws {
        // Delete physical file
        let fileURL = URL(fileURLWithPath: ghostPDF.realFilePath)
        try? fileManager.removeItem(at: fileURL)

        // Delete from database
        context.delete(ghostPDF)
        try context.save()

        print("🗑️ Deleted: \(ghostPDF.displayName)")
    }

    func reanalyzeGhostPDF(_ ghostPDF: GhostPDF, context: ModelContext) async {
        await processGhostPDF(ghostPDF, context: context)
    }

    func renameFileToMatchTitle(_ ghostPDF: GhostPDF, context: ModelContext) {
        guard let title = ghostPDF.ghostTitle else { return }
        
        // 1. Sanitize title to be filesystem safe
        let safeTitle = title.replacingOccurrences(of: "/", with: "-")
                             .replacingOccurrences(of: ":", with: "-")
                             .replacingOccurrences(of: "\\", with: "")
                             .components(separatedBy: .controlCharacters)
                             .joined()
                             .prefix(50) // Limit length
                             .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let newFilename = "\(safeTitle).pdf"
        let oldURL = URL(fileURLWithPath: ghostPDF.realFilePath)
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newFilename)
        
        // 2. Rename file
        do {
            if fileManager.fileExists(atPath: newURL.path) {
                print("⚠️ File already exists at \(newURL.path)")
                return
            }
            try fileManager.moveItem(at: oldURL, to: newURL)
            
            // 3. Update Model
            ghostPDF.realFilePath = newURL.path
            ghostPDF.originalFilename = newFilename
            try context.save()
            
            print("✅ Renamed file to: \(newFilename)")
        } catch {
            print("❌ Failed to rename file: \(error)")
        }
    }
    
    // Returns (count of duplicates to delete, report string, list of duplicates, allDuplicateIDs, groupedIDs)
    func scanForDuplicates(context: ModelContext) throws -> (count: Int, report: String, list: [GhostPDF], allIDs: Set<UUID>, groups: [[UUID]]) {
        // Fetch all PDFs
        let descriptor = FetchDescriptor<GhostPDF>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        let allPDFs = try context.fetch(descriptor)
        
        // Data structures for highlighting
        var allDuplicateIDs = Set<UUID>()
        var duplicateGroupsList: [[UUID]] = []
        
        // 1. Force Recalculate Hashes for ALL files to ensure consistency
        // (This fixes issues where old files have "Hash V1" and new have "Hash V2")
        var updatedCount = 0
        for pdf in allPDFs {
            let url = URL(fileURLWithPath: pdf.realFilePath)
            if let newHash = calculateFileHash(url: url) {
                if pdf.fileHash != newHash {
                    pdf.fileHash = newHash
                    updatedCount += 1
                }
            } else {
                print("⚠️ Could not calculate hash for: \(pdf.realFilePath)")
            }
        }
        
        if updatedCount > 0 {
            try? context.save()
            print("🔄 Updated hashes for \(updatedCount) files.")
        }
        
        // 2. Group by Hash
        var duplicatesToDelete: [GhostPDF] = []
        var duplicateGroups: [String: [GhostPDF]] = [:]
        
        for pdf in allPDFs {
            guard let hash = pdf.fileHash, !hash.isEmpty else { continue }
            duplicateGroups[hash, default: []].append(pdf)
        }
        
        // 3. Identify Duplicates (Keep oldest/first in list)
        var summaryLines: [String] = []
        var processedIDs = Set<UUID>()
        
        // A. Hash Duplicates (Strict)
        for (_, pdfs) in duplicateGroups {
            if pdfs.count > 1 {
                 let sorted = pdfs.sorted { ($0.createdAt ?? Date.distantPast) < ($1.createdAt ?? Date.distantPast) }
                 
                 let toDelete = Array(sorted.dropFirst())
                 duplicatesToDelete.append(contentsOf: toDelete)
                 toDelete.forEach { processedIDs.insert($0.id) }
                 
                 let keeper = sorted.first!

                 // Add this group to the groups list
                 duplicateGroupsList.append(pdfs.map { $0.id })

                 summaryLines.append("- [Exact Match] \"\(keeper.ghostTitle ?? keeper.originalFilename)\" has \(toDelete.count) copies")
            }
        }
        
        // B. Semantic Duplicates (Smart) - "Apple AI" Style
        // Group remaining PDFs by (Title + FileSize) to catch re-saved files
        var potentialSemanticDupes: [String: [GhostPDF]] = [:]
        
        for pdf in allPDFs {
            if processedIDs.contains(pdf.id) { continue }
            
            // Key = Title + Size (within 100 bytes tolerance usually, but simplified to exact size for now or loose string)
            // Let's use Title as primary key
            if let title = pdf.ghostTitle {
               potentialSemanticDupes[title, default: []].append(pdf)
            }
        }
        
        for (title, pdfs) in potentialSemanticDupes {
            if pdfs.count > 1 {
                // Check if they are actually similar size (e.g., within 5%)
                // This prevents "Invoice 001" and "Invoice 002" (same title structure but different content) from being nuked
                // But users usually have distinct titles.
                // Let's group by FileSize variance.
                
                let sorted = pdfs.sorted { ($0.createdAt ?? Date.distantPast) < ($1.createdAt ?? Date.distantPast) }
                // For safety, only auto-delete if file size is very close
                
                // We won't auto-delete semantic duplicates yet, just report them?
                // OR we strictly check file size.
                
                // Simple heuristic: If Title is identical AND File Size is within 1KB.
                var sizeGroups: [Int64: [GhostPDF]] = [:]
                for pdf in sorted {
                    // Round to nearest KB
                    let kb = pdf.fileSize / 1024
                    sizeGroups[kb, default: []].append(pdf)
                }
                
                for (_, similarPDFs) in sizeGroups {
                    if similarPDFs.count > 1 {
                         let sorted = similarPDFs.sorted { ($0.createdAt) < ($1.createdAt) }

                         let toDelete = Array(sorted.dropFirst())
                         duplicatesToDelete.append(contentsOf: toDelete)
                         toDelete.forEach { processedIDs.insert($0.id) }

                         let keeper = similarPDFs.first!
                         processedIDs.insert(keeper.id)

                         // Mark ALL files in this group as duplicates
                         similarPDFs.forEach { allDuplicateIDs.insert($0.id) }

                         // Add this group to the groups list
                         duplicateGroupsList.append(similarPDFs.map { $0.id })

                         summaryLines.append("- [Smart Match] \"\(title)\" has \(toDelete.count) copies")
                    }
                }
            }
        }
        
        // C. Apple AI Semantic Match (NLEmbedding)
        // Checks leftovers against ALL files (including already processed ones) to catch stragglers
        
        let leftovers = allPDFs.filter { !processedIDs.contains($0.id) }
        var visitedTitles = Set<UUID>()
        
        if let embedding = NLEmbedding.sentenceEmbedding(for: .english) {
            
            for pdfA in leftovers {
                if visitedTitles.contains(pdfA.id) { continue }
                guard let titleA = pdfA.ghostTitle, !titleA.isEmpty else { continue }
                
                // Compare against ALL other PDFs (keepers and leftovers)
                // We want to find if 'pdfA' is a semantic duplicate of ANY existing file
                
                var bestMatch: GhostPDF? = nil
                var bestDistance: Double = 1.0
                
                for pdfB in allPDFs {
                    if pdfA.id == pdfB.id { continue } // Don't match self
                    
                    // Optimization: if pdfB is a 'toDelete' duplicate, skip it. We want to match against Keepers.
                    // But effectively we just want to find a group.
                    
                    guard let titleB = pdfB.ghostTitle, !titleB.isEmpty else { continue }
                    
                    // Fast path
                    if titleA.lowercased() == titleB.lowercased() {
                        bestMatch = pdfB
                        bestDistance = 0.0
                        break
                    }
                    
                    let distance = embedding.distance(between: titleA, and: titleB)
                    if distance < 0.6 && distance < bestDistance { // Stricter 0.6 threshold
                         bestMatch = pdfB
                         bestDistance = distance
                    }
                }
                
                if let match = bestMatch {
                    // We found a match!
                    // pdfA is a duplicate of match.
                    // Mark pdfA to delete.
                    duplicatesToDelete.append(pdfA)
                    processedIDs.insert(pdfA.id)
                    allDuplicateIDs.insert(pdfA.id)
                    visitedTitles.insert(pdfA.id)
                    
                    // We need to visually group them.
                    // If 'match' is already in a group, we should ideally add 'pdfA' to that group.
                    // For simplicity, we'll just create a new visual pair [match, pdfA].
                    // The UI handles overlapping groups by picking the first one.
                    
                    allDuplicateIDs.insert(match.id) // Ensure match is highlighted
                    duplicateGroupsList.append([match.id, pdfA.id])
                    
                    summaryLines.append("- [Semantic Match] \"\(titleA)\" is similar to \"\(match.ghostTitle ?? "")\"")
                }
            }
        }
        
        // Report logic
        let finalReport = """
        Scanned \(allPDFs.count) files.
        Found \(duplicateGroupsList.count) groups.
        \(summaryLines.joined(separator: "\n"))
        """
        
        return (duplicatesToDelete.count, finalReport, duplicatesToDelete, allDuplicateIDs, duplicateGroupsList)
    }
    
    func cleanDuplicates(context: ModelContext) throws -> Int {
        // Reuse the exact same logic as scan to ensure we delete exactly what we reported
        let (_, _, toDelete, _, _) = try scanForDuplicates(context: context)
        
        var deletedCount = 0
        for pdf in toDelete {
            try deleteGhostPDF(pdf, context: context)
            deletedCount += 1
        }
        
        return deletedCount
    }
}
