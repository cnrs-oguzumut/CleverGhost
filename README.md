# CleverGhost

**AI-Powered PDF Toolkit for macOS**

CleverGhost is an intelligent PDF processing application that combines powerful compression, research tools, and AI-driven document analysis in one beautiful macOS app.

## ✨ Features

### 🎨 Modern Design
- Beautiful gradient title with Apple's liquid design language
- Clean, intuitive interface optimized for macOS
- Dark mode support

### 🗜️ Compress PDF
- **Basic Mode**: Quick compression with preset quality levels (Screen, eBook, Printer, Prepress, Default)
- **Pro Mode**: Advanced control with custom DPI, image quality, and optimization settings

### 🛠️ PDF Tools
- **Merge PDFs**: Combine multiple PDFs into one
- **Split PDFs**: Extract specific pages or ranges
- **Security**: Password protection and encryption

### 🤖 AI Assistance (Requires macOS Tahoe/26.0+)
Powered by Apple's on-device FoundationModels API:

- **AI Chat**: Interactive Q&A with your PDF documents
- **Smart Finder**: Intelligent search across document content
- **Grammar Check**: Advanced grammar analysis with structured output
  - Page selection support (e.g., "1-5" or "1,3,5")
  - Multi-encoding support for international documents
  - Automatic text chunking for large pages
- **Multi-Document Intelligence**: Cross-paper analysis and synthesis
  - Compare insights across multiple papers
  - Synthesize information from multiple sources
  - Per-document contribution tracking
- **Cover Letter Generator**: Automatic academic cover letter generation for journal submissions

### 📚 Researcher Tools
- **BibTeX Extraction**: Extract bibliographic data from PDFs
  - AI-powered extraction (macOS 26.0+) with DOI/arXiv lookup
  - Hybrid mode: AI + online verification
  - Offline mode: Heuristic parsing
- **Reference Lookup**: CrossRef and arXiv integration
- **Smart Renaming**: Automatic file renaming based on metadata
- **BibTeX Formatting**: Clean, normalize, and format BibTeX entries
  - Author shortening (et al.)
  - Journal abbreviation
  - LaTeX escaping
  - Duplicate removal
  - Multiple citation styles (APA, MLA, Chicago, Harvard, IEEE)
- **Smart Library with Duplicate Detection**: AI-powered duplicate PDF detection
  - 4-tier detection pipeline for comprehensive coverage
  - Handles compressed, reformatted, and renamed duplicates
  - Semantic content analysis with text normalization

## 🎯 Requirements

- **macOS 13.0+** (Ventura or later)
- **Ghostscript** (automatically detected or install via Homebrew)
- **macOS 26.0+ (Tahoe)** for AI features (optional but recommended)

## 🚀 Installation

### Option 1: Download Release
1. Download the latest release from [Releases](https://github.com/cnrs-oguzumut/CleverGhost/releases)
2. Open the `.app` file
3. If macOS blocks it, go to System Settings → Privacy & Security → Allow

### Option 2: Build from Source
```bash
# Clone the repository
git clone https://github.com/cnrs-oguzumut/CleverGhost.git
cd CleverGhost

# Build the app
./build-beta.sh

# Open the built app
open "build-beta/CleverGhost Beta.app"
```

### Installing Ghostscript (Required)
```bash
brew install ghostscript
```

## 💡 Usage

### Compress PDFs
1. Launch CleverGhost
2. Select "Compress PDF" mode
3. Drag & drop PDF files
4. Choose quality preset or customize settings
5. Click "Compress"

### AI Features
1. Ensure you're running macOS 26.0+ (Tahoe)
2. Select "AI Assistance" mode
3. Drop your PDF and ask questions
4. Use Grammar Check for document proofreading
5. Generate cover letters for journal submissions

### Research Tools
1. Select "AI Assistance" mode
2. Navigate to the "Researcher" tab
3. Drop PDFs to extract BibTeX
4. Choose extraction mode:
   - **Hybrid**: AI extraction + online verification (recommended)
   - **Online**: CrossRef/arXiv lookup only
   - **Offline**: Local heuristic parsing

## 🔧 Build Scripts

### Beta Build (Development)
```bash
./build-beta.sh
```
- Outputs to `build-beta/CleverGhost Beta.app`
- Quick builds for testing and development

### Lite Build (Production)
```bash
./build-lite.sh
```
- Outputs to `build-lite/CleverGhost.app` and `dist/CleverGhost-1.0.0-Lite.dmg`
- Requires users to install Ghostscript via Homebrew
- Smaller download size (~4 MB)
- Signed with hardened runtime

### Bundled Build (Production)
```bash
./build-bundled-notarized.sh
```
- Outputs to `build-bundled/CleverGhost.app` and `dist/CleverGhost-1.1.0-Bundled.dmg`
- Includes Ghostscript and all dependencies (~63 MB)
- No external dependencies required
- Signed with hardened runtime
- Ready for notarization

### Mac App Store Build
```bash
./build-mas.sh
```
- Outputs to `build-mas/CleverGhost.app` and `dist/CleverGhost-1.1.0-MAS.pkg`
- Sandboxed build for Mac App Store submission
- Includes Ghostscript bundle (~56 MB PKG)
- Signed with Mac App Store certificates
- Ready for App Store Connect upload

## 📝 Technical Details

### Architecture
- Built with SwiftUI for native macOS performance
- Apple FoundationModels API for on-device AI
- PDFKit for document manipulation
- Ghostscript integration for compression

### AI Models
- Uses `@Generable` structs for structured AI output
- Temperature control for creativity adjustment
- Automatic retry logic for reliability
- Context window management with smart chunking

### BibTeX Extraction
- Multi-stage extraction pipeline
- DOI and arXiv ID detection
- CrossRef API integration
- Multiple text encoding support (UTF-8, ISO-8859-1, Windows-1252, etc.)

### Duplicate Detection Pipeline
CleverGhost uses a 4-tier detection system to catch duplicates with different levels of modifications:

**A. RAG Semantic Content Match** (First Check - Most Comprehensive)
- Compares first 2000 characters using semantic embeddings
- Detects duplicates even when compressed, reformatted, or OCR'd differently
- Uses Apple's NaturalLanguage framework for embeddings
- Text normalization: collapses whitespace, trims formatting
- Threshold: 60% similarity (0.85 cosine similarity per chunk)
- Requires macOS 26.0+

**B. Hash Match** (Exact Duplicates)
- SHA-256 hash comparison
- Catches byte-for-byte identical files
- Fastest method for exact matches

**C. Content Fingerprint** (Text-level Duplicates)
- Compares normalized text content
- Catches identical text with different metadata or minor formatting
- Same text normalization as RAG method
- Threshold: 95% similarity

**D. Title Similarity** (Fallback)
- Levenshtein distance on document titles
- Catches renamed files with similar titles
- Threshold: 85% similarity

This multi-tier approach ensures comprehensive duplicate detection while maintaining performance.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

[Add your license here]

## 🙏 Acknowledgments

- Built on top of Ghostscript for PDF processing
- Uses Apple's FoundationModels for AI capabilities
- CrossRef API for bibliographic data
- arXiv API for preprint metadata

## 📧 Contact

For questions or feedback, please open an issue on GitHub.

---

Made with ❤️ using Swift and SwiftUI
