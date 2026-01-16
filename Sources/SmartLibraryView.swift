import SwiftUI
import SwiftData

struct SmartLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GhostPDF.createdAt, order: .reverse) private var allPDFs: [GhostPDF]
    @StateObject private var libraryManager = GhostLibraryManager.shared

    @State private var isTargeted = false
    @State private var models = GhostLibraryManager.shared
    @State private var selectedPDFIDs = Set<UUID>() // Multi-selection state
    @State private var lastSelectedID: UUID? // For shift-click range selection
    @State private var searchText = ""
    @AppStorage("isDarkMode_v2") private var isDarkMode = true
    @AppStorage("libraryAITemperature") private var libraryAITemperature: Double = 0.7
    @State private var showingSettings = false

    @State private var showingDuplicateAlert = false
    @State private var duplicateCount = 0
    @State private var showingNoDuplicatesAlert = false
    @State private var duplicateIDs = Set<UUID>() // IDs of all files marked as duplicates
    @State private var duplicateMap: [UUID: Int] = [:] // Map [ID: GroupIndex] for fast O(1) lookup call

    // Group PDFs by category
    private var groupedPDFs: [(category: String, pdfs: [GhostPDF])] {
        let filtered = filteredPDFs
        let grouped = Dictionary(grouping: filtered) { $0.category ?? "Document" }
        return grouped.map { (category: $0.key, pdfs: $0.value) }
            .sorted { $0.category < $1.category }
    }

    private var filteredPDFs: [GhostPDF] {
        if searchText.isEmpty {
            return allPDFs
        }
        return allPDFs.filter { pdf in
            pdf.displayName.localizedCaseInsensitiveContains(searchText) ||
            pdf.category?.localizedCaseInsensitiveContains(searchText) == true ||
            pdf.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            // Search bar
            searchBar

            // Stats bar
            statsBar

            Divider()

            // Content
            if allPDFs.isEmpty {
                emptyStateView
            } else {
                libraryContentView
            }

            // Processing indicator
            if libraryManager.isProcessing {
                processingIndicator
            }
        }
        .background(isDarkMode ? Color.black : Color.white)
        // Global Keyboard Shortcuts
        .focusable()
        .onKeyPress("a", action: {
            if NSEvent.modifierFlags.contains(.command) {
                selectAll()
                return .handled
            }
            return .ignored
        })
        .onDeleteCommand {
            deleteSelected()
        }
        .onAppear {
            libraryManager.aiTemperature = libraryAITemperature
        }
        .onChange(of: libraryAITemperature) { oldValue, newValue in
            libraryManager.aiTemperature = newValue
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "brain.head.profile")
                .font(.title2)
                .foregroundColor(.purple)

            Text("Smart Library")
                .font(.title2)
                .bold()

            Spacer()
            
            Button(action: {
                importFiles()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Import")
                }
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue)
                .cornerRadius(16)
            }
            .buttonStyle(.plain)
            
            Button(action: {
                checkForDuplicates()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                    Text("Find Duplicates")
                }
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange)
                .cornerRadius(16)
            }
            .buttonStyle(.plain)

            // Show Clean Duplicates button when duplicates are found
            if !duplicateIDs.isEmpty {
                Button(action: {
                    cleanDuplicates()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Clean \(duplicateCount) Duplicates")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red)
                    .cornerRadius(16)
                    .buttonStyle(.plain)
                }
                
                // Debug Map Status
                if !duplicateMap.isEmpty {
                    Text("Map: \(duplicateMap.count) items")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.leading, 4)
                }
                }

            Text("\(allPDFs.count) PDFs")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            // Settings button
            Button(action: {
                showingSettings.toggle()
            }) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("AI Analysis Settings")
                        .font(.headline)

                    temperatureSlider(
                        value: $libraryAITemperature,
                        label: "AI Temperature",
                        description: "Controls creativity in document analysis"
                    )
                }
                .padding()
                .frame(width: 300)
            }
        }
        .padding()
        .alert("Found Duplicates", isPresented: $showingDuplicateAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Found \(duplicateCount) duplicate files. They are now highlighted in red.\n\nYou can manually delete them or use the 'Clean Duplicates' button.\n\n" + duplicateReport)
        }
        .alert("No Duplicates Found", isPresented: $showingNoDuplicatesAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your library is clean! No duplicate files were found.")
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search library...", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(8)
        .background(isDarkMode ? Color(NSColor.controlBackgroundColor) : Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 16) {
            StatChip(icon: "doc.fill", count: allPDFs.count, label: "Total")
            StatChip(icon: "checkmark.circle.fill", count: allPDFs.filter { $0.isProcessed }.count, label: "Analyzed")
            StatChip(icon: "clock.fill", count: allPDFs.filter { $0.status == .analyzing }.count, label: "Processing")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(isTargeted ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                    .frame(height: 300)

                VStack(spacing: 16) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)

                    Text("Drop PDFs here to build your Smart Library")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("AI will automatically categorize and name your documents")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            .padding(.horizontal, 40)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }

            Spacer()
        }
    }

    // MARK: - Library Content


    
    private var libraryContentView: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                    pdfListContent
                }
                .padding()
            }
            
            // Drop target overlay
            if isTargeted {
                Color.blue.opacity(0.1)
                    .edgesIgnoringSafeArea(.all)
                    .overlay(
                        VStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.largeTitle)
                                .foregroundColor(.blue)
                            Text("Drop to Add")
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                    )
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }
    
    private var pdfListContent: some View {
        Group {
            // Persistent header drop zone
            Button(action: {
                importFiles()
            }) {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Drag more files here or click to import")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [10]))
                        .foregroundColor(.secondary.opacity(0.3))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)

            ForEach(groupedPDFs, id: \.category) { group in
                Section {
                    ForEach(group.pdfs) { pdf in
                        pdfRow(for: pdf)
                    }
                } header: {
                    CategoryHeader(category: group.category, count: group.pdfs.count)
                }
            }
        }
    }

    private func pdfRow(for pdf: GhostPDF) -> some View {
        GhostPDFRow(
            pdf: pdf,
            isSelected: selectedPDFIDs.contains(pdf.id),
            duplicateGroupIndex: duplicateGroupIndex(for: pdf.id),
            duplicateColor: duplicateGroupIndex(for: pdf.id).map { colorForGroup($0) },
            onDelete: { deletePDF(pdf) }
        )
        .onTapGesture {
            handleTap(on: pdf)
        }
        .contextMenu {
            Button("Open PDF") {
                openPDF(pdf)
            }
            Button("Re-analyze") {
                Task {
                    await libraryManager.reanalyzeGhostPDF(pdf, context: modelContext)
                }
            }
            Divider()
            Button("Show in Finder") {
                revealInFinder(pdf)
            }
            Button("Copy Original Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pdf.originalFilename, forType: .string)
            }
            Button("Rename File to Match Title") {
                libraryManager.renameFileToMatchTitle(pdf, context: modelContext)
            }
            Divider()
            Button("Delete from Library", role: .destructive) {
                deletePDF(pdf)
            }
        }
    }

    // MARK: - Processing Indicator

    private var processingIndicator: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Analyzing PDFs...")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ProgressView(value: libraryManager.processingProgress)
                        .progressViewStyle(.linear)
                }

                Spacer()

                Button(action: {
                    libraryManager.cancelProcessing()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                        Text("Stop")
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(isDarkMode ? Color(NSColor.controlBackgroundColor) : Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Actions

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        Task {
            var urls: [URL] = []

            for provider in providers {
                if let url = await loadURL(from: provider) {
                    urls.append(url)
                }
            }

            let pdfURLs = urls.filter { $0.pathExtension.lowercased() == "pdf" }

            if !pdfURLs.isEmpty {
                try? await libraryManager.ingestPDFs(urls: pdfURLs, context: modelContext)
            }
        }

        return true
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, error in
                if let data = data as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func importFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf]
        
        panel.begin { response in
            if response == .OK {
                Task {
                    try? await libraryManager.ingestPDFs(urls: panel.urls, context: modelContext)
                }
            }
        }
    }

    private func openPDF(_ pdf: GhostPDF) {
        let url = URL(fileURLWithPath: pdf.realFilePath)
        NSWorkspace.shared.open(url)
    }

    private func revealInFinder(_ pdf: GhostPDF) {
        let url = URL(fileURLWithPath: pdf.realFilePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    // MARK: - Selection Logic
    
    private func handleTap(on pdf: GhostPDF) {
        let isCommand = NSEvent.modifierFlags.contains(.command)
        let isShift = NSEvent.modifierFlags.contains(.shift)
        
        if isCommand {
            // Toggle selection
            if selectedPDFIDs.contains(pdf.id) {
                selectedPDFIDs.remove(pdf.id)
            } else {
                selectedPDFIDs.insert(pdf.id)
                lastSelectedID = pdf.id
            }
        } else if isShift, let lastID = lastSelectedID, let lastIndex = filteredPDFs.firstIndex(where: { $0.id == lastID }), let currentIndex = filteredPDFs.firstIndex(where: { $0.id == pdf.id }) {
            // Range selection
            let range = min(lastIndex, currentIndex)...max(lastIndex, currentIndex)
            let idsToSelect = filteredPDFs[range].map { $0.id }
            selectedPDFIDs.formUnion(idsToSelect)
        } else {
            // Single selection
            selectedPDFIDs = [pdf.id]
            lastSelectedID = pdf.id
        }
    }
    
    private func selectAll() {
        selectedPDFIDs = Set(filteredPDFs.map { $0.id })
    }
    
    private func deleteSelected() {
        withAnimation {
            let selectedDocs = allPDFs.filter { selectedPDFIDs.contains($0.id) }
            for pdf in selectedDocs {
                try? libraryManager.deleteGhostPDF(pdf, context: modelContext)
            }
            selectedPDFIDs.removeAll()
            lastSelectedID = nil
        }
    }
    
    private func deletePDF(_ pdf: GhostPDF) {
        withAnimation {
            try? libraryManager.deleteGhostPDF(pdf, context: modelContext)
            selectedPDFIDs.remove(pdf.id)
        }
    }
    
    @State private var duplicateReport = ""

    // MARK: - Duplicate Management
    

    private func checkForDuplicates() {
        Task {
            do {
                let (count, report, _, allIDs, groups) = try libraryManager.scanForDuplicates(context: modelContext)
                
                await MainActor.run {
                    duplicateCount = count
                    duplicateReport = report
                    duplicateIDs = allIDs 
                    
                    // Convert groups [[UUID]] to [UUID: Int] map
                    var newMap: [UUID: Int] = [:]
                    for (index, group) in groups.enumerated() {
                        for id in group {
                            newMap[id] = index
                        }
                    }
                    duplicateMap = newMap

                    print("🔍 Check complete. Map size: \(newMap.count)")
                    if count > 0 {
                        showingDuplicateAlert = true
                    } else {
                        showingNoDuplicatesAlert = true
                    }
                }
            } catch {
                print("Failed to scan: \(error)")
            }
        }
    }
    
    private func cleanDuplicates() {
        do {
            let cleanedCount = try libraryManager.cleanDuplicates(context: modelContext)
            duplicateIDs.removeAll()
            duplicateMap.removeAll()
            // success animation or toast could go here
        } catch {
            print("Failed to clean duplicates: \(error)")
        }
    }

    // Get the group index for a PDF (for color coding)
    private func duplicateGroupIndex(for pdfID: UUID) -> Int? {
        return duplicateMap[pdfID]
    }

    // Get color for duplicate group
    private func colorForGroup(_ groupIndex: Int) -> Color {
        let colors: [Color] = [
            .red, .orange, .yellow, .green, .blue, .purple, .pink, .cyan
        ]
        return colors[groupIndex % colors.count]
    }

    // Temperature slider
    private func temperatureSlider(value: Binding<Double>, label: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AI Creativity:")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                Spacer()
                Text("\(value.wrappedValue, specifier: "%.1f")")
                    .foregroundColor(.primary)
                    .font(.subheadline.monospacedDigit())
            }

            Slider(value: value, in: 0.0...1.0, step: 0.1) {
                Text(label)
            } minimumValueLabel: {
                VStack(spacing: 2) {
                    Text("0.0")
                        .font(.caption2)
                    Text("Precise")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } maximumValueLabel: {
                VStack(spacing: 2) {
                    Text("1.0")
                        .font(.caption2)
                    Text("Creative")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Category Header

struct CategoryHeader: View {
    let category: String
    let count: Int
    @AppStorage("isDarkMode_v2") private var isDarkMode = true

    private var emoji: String {
        PDFCategory.from(name: category)?.emoji ?? "📄"
    }

    var body: some View {
        HStack {
            Text("\(emoji) \(category)")
                .font(.headline)
                .foregroundColor(isDarkMode ? .white : .black)

            Spacer()

            Text("\(count)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(8)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isDarkMode ? Color(NSColor.controlBackgroundColor) : Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - PDF Row

struct GhostPDFRow: View {
    @Bindable var pdf: GhostPDF
    var isSelected: Bool
    var duplicateGroupIndex: Int? = nil
    var duplicateColor: Color? = nil
    var onDelete: () -> Void // Callback for deletion
    @AppStorage("isDarkMode_v2") private var isDarkMode = true
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Emolji with standard non-wiggling
            Text(pdf.displayEmoji)
                .font(.system(size: 28))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(pdf.status == .analyzing ? Color.blue.opacity(0.1) : Color.clear)
                )
                .scaleEffect(pdf.status == .analyzing ? 0.95 : 1.0)
                .scaleEffect(pdf.status == .analyzing ? 0.95 : 1.0)
                // Static icon, pulse only once on change effectively handled by view updates or define explicit non-repeating
                .animation(.easeInOut(duration: 0.5), value: pdf.status) // Removed repeatForever

            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(pdf.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isDarkMode ? .white : .black)
                    .lineLimit(1)

                // Metadata
                HStack(spacing: 8) {
                    // Original filename (if different)
                    if pdf.ghostTitle != nil && pdf.ghostTitle != pdf.originalFilename {
                        Text(pdf.originalFilename)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    // Tags
                    if !pdf.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(pdf.tags.prefix(5), id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
            }

            Spacer()

            // Duplicate group badge
            if let groupIndex = duplicateGroupIndex, let color = duplicateColor {
                Text("Group \(groupIndex + 1)")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color)
                    .cornerRadius(8)
            }

            // File size
            Text(formatFileSize(pdf.fileSize))
                .font(.caption)
                .foregroundColor(.secondary)

            // Trash button
            Button(action: {
                deletePDF()
            }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .opacity(isHovering ? 1.0 : 0.0) // Only show on hover

            // Duplicate Warning
            if duplicateGroupIndex != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.title2)
                    .help("This file is a duplicate")
            }

            // Status indicator
            statusIcon
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }


    private var backgroundFill: Color {
        if let color = duplicateColor {
            return color.opacity(0.5) // Much stronger
        } else if isSelected {
            return Color.blue.opacity(0.2)
        } else if isHovering {
            return Color.secondary.opacity(0.1)
        } else {
            return Color.clear
        }
    }

    private var borderColor: Color {
        if let color = duplicateColor {
            return color // Full opacity border
        } else if isSelected {
            return Color.blue.opacity(0.6)
        } else if isHovering {
            return Color.blue.opacity(0.4)
        } else {
            return Color.clear
        }
    }

    private var borderWidth: CGFloat {
        duplicateColor != nil ? 3 : 1 // Increased from 2 for thicker border
    }

    private var statusIcon: some View {
        Group {
            switch pdf.status {
            case .pending:
                Image(systemName: "clock")
                    .foregroundColor(.orange)
            case .analyzing:
                ProgressView()
                    .scaleEffect(0.7)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
            }
        }
        .font(.caption)
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func deletePDF() {
        onDelete()
    }
}

// MARK: - Stat Chip

struct StatChip: View {
    let icon: String
    let count: Int
    let label: String
    @AppStorage("isDarkMode_v2") private var isDarkMode = true

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text("\(count)")
                .font(.caption)
                .bold()
            Text(label)
                .font(.caption2)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isDarkMode ? Color(NSColor.controlBackgroundColor) : Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
    }
}

// MARK: - Preview

#Preview {
    SmartLibraryView()
        .modelContainer(for: GhostPDF.self, inMemory: true)
}
