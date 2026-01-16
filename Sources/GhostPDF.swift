import Foundation
import SwiftData

@Model
class GhostPDF {
    @Attribute(.unique) var id: UUID
    var realFilePath: String           // "SmartLibrary/files/{uuid}.pdf"
    var originalFilename: String        // "scan_099.pdf"
    var ghostEmoji: String?             // "📚"
    var ghostTitle: String?             // "Gene Editing Study"
    var category: String?               // "Scientific Paper"
    var tags: [String]                  // ["biology", "genetics", "research"]
    var status: ProcessingStatus
    var createdAt: Date
    var fileSize: Int64
    var textPreview: String?            // First 2 pages of text
    var confidence: Double              // 0.0 - 1.0
    var fileHash: String?               // SHA256 hash for duplicate detection

    init(id: UUID = UUID(),
         realFilePath: String,
         originalFilename: String,
         fileSize: Int64,
         fileHash: String? = nil) {
        self.id = id
        self.realFilePath = realFilePath
        self.originalFilename = originalFilename
        self.fileSize = fileSize
        self.fileHash = fileHash
        self.status = .pending
        self.createdAt = Date()
        self.tags = []
        self.confidence = 0.0
    }

    enum ProcessingStatus: String, Codable {
        case pending      // Just added, waiting to be analyzed
        case analyzing    // Currently being processed by AI
        case done         // Successfully analyzed
        case error        // Failed to analyze
    }

    // Computed property for display
    var displayName: String {
        ghostTitle ?? originalFilename
    }

    var displayEmoji: String {
        ghostEmoji ?? "📄"
    }

    var isProcessed: Bool {
        status == .done
    }
}

// MARK: - PDF Categories
enum PDFCategory: String, CaseIterable {
    // Academic/Research
    case scientificPaper = "📚 Scientific Paper"
    case researchArticle = "🔬 Research Article"
    case thesis = "🎓 Thesis"
    case textbook = "📖 Textbook"
    case academicPoster = "🖼️ Academic Poster"

    // Financial
    case receipt = "🧾 Receipt"
    case invoice = "💵 Invoice"
    case bankStatement = "🏦 Bank Statement"
    case taxDocument = "📊 Tax Document"
    case contract = "📋 Contract"
    case financialReport = "💰 Financial Report"

    // Medical
    case labResults = "🧪 Lab Results"
    case prescription = "💊 Prescription"
    case medicalReport = "🏥 Medical Report"
    case insurance = "🩺 Insurance"
    case medicalImaging = "📷 Medical Imaging"

    // Legal
    case legalContract = "⚖️ Legal Contract"
    case agreement = "📜 Agreement"
    case certificate = "🏅 Certificate"
    case legalBrief = "📋 Legal Brief"

    // Work/Business
    case businessProposal = "💼 Business Proposal"
    case presentation = "📊 Presentation"
    case memo = "📝 Memo"
    case businessReport = "📈 Business Report"
    case whitepaper = "📑 Whitepaper"

    // Personal
    case letter = "✉️ Letter"
    case travelDocument = "✈️ Travel Document"
    case ticket = "🎫 Ticket"
    case manual = "📘 Manual"
    case recipe = "🍳 Recipe"
    case form = "📋 Form"
    case newsletter = "📰 Newsletter"
    case ebook = "📕 E-Book"

    // Technical
    case technicalSpec = "⚙️ Technical Specification"
    case dataSheet = "📄 Data Sheet"
    case blueprint = "📐 Blueprint"

    // Fallback
    case unknown = "📄 Document"

    var emoji: String {
        String(rawValue.prefix(2)).trimmingCharacters(in: .whitespaces)
    }

    var name: String {
        String(rawValue.dropFirst(3))
    }

    // Get category from string name
    static func from(name: String) -> PDFCategory? {
        PDFCategory.allCases.first { category in
            category.name.lowercased() == name.lowercased()
        }
    }
}
