import SwiftUI
import UIKit
import ImageIO

/// A read-only snapshot of the whole set, independent of the current search/filter.
struct MissingCardReport: Identifiable, Sendable {
    struct Item: Identifiable, Sendable {
        let card: CatalogCard
        let missingSlots: Int
        let printings: String
        var id: String { card.id }
    }
    let id = UUID()
    let set: CatalogSet
    let goal: CollectionGoal
    let createdAt: Date
    let items: [Item]
    var missingSlots: Int { items.reduce(0) { $0 + $1.missingSlots } }

    static func make(set: CatalogSet, cards: [CatalogCard], preference: SetCollectionPreference,
                     variants: [String: Set<CatalogVariantKind>], printings: [String: [CatalogPrinting]],
                     broad: [CollectionVariantEntry], exact: [CollectionPrintingEntry], date: Date = .now) throws -> Self {
        let included = cards.filter { CollectionProgressCalculator.includes(card: $0, set: set, preference: preference) }
        guard preference.goal == .normal || included.allSatisfy({ variants[$0.id]?.isEmpty == false }) else {
            throw ExportError.printingsUnavailable
        }
        let progress = CollectionProgressCalculator.progressByCardID(cards: included, set: set, preference: preference,
            availableVariants: variants, ownedEntries: broad, availablePrintings: printings, exactOwnedEntries: exact)
        let rows = included.sorted { $0.localID.localizedStandardCompare($1.localID) == .orderedAscending }.compactMap { card -> Item? in
            guard let count = progress[card.id], count.completedSlots < count.requiredSlots else { return nil }
            let missing = count.requiredSlots - count.completedSlots
            if preference.goal == .normal {
                return Item(card: card, missingSlots: 1, printings: "Any printing")
            }
            let options = printings[card.id] ?? []
            let ownedExact = exact.filter { $0.cardID == card.id && $0.quantity > 0 }
            let ownedBroad = broad.filter { $0.cardID == card.id && $0.quantity > 0 }
            // Do not guess a missing exact identity when a provider ID changed.
            if ownedExact.contains(where: { entry in !options.contains { $0.providerID == entry.printingID } }) {
                return Item(card: card, missingSlots: missing,
                    printings: "\(missing) missing · exact printing needs review")
            }
            let required = preference.visibleVariants(in: variants[card.id] ?? [])
            var labels: [String] = []
            for variant in CatalogVariantKind.allCases where required.contains(variant) {
                let matching = options.filter { $0.kind == variant }
                let ownedIDs = Set(ownedExact.map(\.printingID))
                let remaining = matching.filter { !ownedIDs.contains($0.providerID) }
                let hasBroad = ownedBroad.contains { $0.variant == variant }
                if matching.isEmpty {
                    if !hasBroad && !ownedExact.contains(where: { $0.variant == variant }) { labels.append(variant.displayName) }
                } else if hasBroad {
                    if remaining.count > 1 {
                        labels.append("\(variant.displayName): \(remaining.count - 1) missing (printing unspecified)")
                    }
                } else {
                    labels.append(contentsOf: remaining.map(\.displayName))
                }
            }
            return Item(card: card, missingSlots: missing, printings: labels.joined(separator: "; "))
        }
        return Self(set: set, goal: preference.goal, createdAt: date, items: rows)
    }

    enum ExportError: LocalizedError {
        case printingsUnavailable, imageEncoding
        var errorDescription: String? {
            switch self {
            case .printingsUnavailable: "Printing information is still unavailable for some cards. Finish loading the set or refresh it before exporting."
            case .imageEncoding: "The checklist image couldn’t be created. Please try again."
            }
        }
    }
}

enum MissingCardExportFormat: String, CaseIterable, Identifiable {
    case images, pdf
    var id: String { rawValue }
    var title: String { self == .images ? "Images" : "PDF" }
}

@MainActor
struct MissingCardExportView: View {
    let report: MissingCardReport
    @Environment(\.dismiss) private var dismiss
    @State private var format = MissingCardExportFormat.images
    @State private var preview: UIImage?
    @State private var artwork: [String: Data] = [:]
    @State private var loading = true
    @State private var exporting = false
    @State private var files: [URL] = []
    @State private var directory: URL?
    @State private var sharing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if report.items.isEmpty {
                    ContentUnavailableView("Nothing Missing", systemImage: "checkmark.seal",
                        description: Text("Your selected set goal is complete."))
                } else {
                    ScrollView {
                        VStack(spacing: 18) {
                            VStack(spacing: 4) {
                                Text(report.set.name).font(.headline)
                                Text("\(report.items.count) cards · \(report.missingSlots) missing goal slots · \(report.goal.displayName)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("missing.summary")
                            }
                            Picker("Format", selection: $format) {
                                ForEach(MissingCardExportFormat.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented).accessibilityIdentifier("missing.format")
                            if let preview {
                                Image(uiImage: preview).resizable().scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                                    .accessibilityLabel("First page preview")
                                    .accessibilityIdentifier("missing.preview")
                            }
                            if loading { ProgressView("Loading artwork…") }
                            Text(format == .images ? "9 cards per image · printing summary" : "A4 checklist · full printing details")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Export Missing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.disabled(exporting)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        Task { await export() }
                    } label: {
                        if exporting { ProgressView() }
                        else { Label("Share \(format.title)", systemImage: "square.and.arrow.up") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(loading || exporting || report.items.isEmpty)
                    .accessibilityIdentifier("missing.share")
                }
            }
        }
        .task {
            defer { loading = false }
            updatePreview()
            // Bounded thumbnail work: never hydrate card details or ownership here.
            for chunkStart in stride(from: 0, to: report.items.count, by: 4) {
                guard !Task.isCancelled else { return }
                let chunk = Array(report.items[chunkStart..<min(chunkStart + 4, report.items.count)])
                let loaded = await withTaskGroup(of: (String, Data?).self) { group in
                    for item in chunk {
                        group.addTask {
                            let raw = try? await CatalogArtworkCache.shared.bestAvailableData(for: item.card.thumbnailArtworkReferences)
                            return (item.id, raw.flatMap(MissingCardRenderer.thumbnail))
                        }
                    }
                    var result: [String: Data] = [:]
                    for await (id, data) in group { if let data { result[id] = data } }
                    return result
                }
                artwork.merge(loaded, uniquingKeysWith: { _, new in new })
                if chunkStart == 0 { updatePreview() }
            }
            guard !Task.isCancelled else { return }
            updatePreview()
        }
        .onChange(of: format) { _, _ in updatePreview() }
        .interactiveDismissDisabled(exporting)
        .sheet(isPresented: $sharing, onDismiss: { cleanup() }) { MissingExportShareSheet(files: files) }
        .alert("Export Unavailable", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .onDisappear { if !sharing { cleanup() } }
    }

    private func updatePreview() {
        guard !report.items.isEmpty else { return }
        preview = MissingCardRenderer.preview(report: report, format: format, artwork: artwork)
    }

    private func export() async {
        exporting = true
        defer { exporting = false }
        cleanup()
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("TallyDex-Missing-\(UUID().uuidString)", isDirectory: true)
        directory = target
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            files = try await MissingCardRenderer.write(report: report, format: format, artwork: artwork, directory: target)
            sharing = true
        } catch { self.error = error.localizedDescription; cleanup() }
    }

    private func cleanup() {
        // Only this sheet's newly created UUID directory, never an imported path.
        if let directory, directory.deletingLastPathComponent().standardizedFileURL == FileManager.default.temporaryDirectory.standardizedFileURL,
           directory.lastPathComponent.hasPrefix("TallyDex-Missing-") {
            try? FileManager.default.removeItem(at: directory)
        }
        directory = nil
        files = []
    }
}

@MainActor
enum MissingCardRenderer {
    private struct PDFRow {
        let item: MissingCardReport.Item
        let printing: String
        let height: CGFloat
    }
    private static let navy = UIColor(red: 0.043, green: 0.082, blue: 0.153, alpha: 1)
    private static let tile = UIColor(red: 0.078, green: 0.129, blue: 0.216, alpha: 1)
    private static let blue = UIColor(red: 0, green: 0.58, blue: 1, alpha: 1)
    private static let muted = UIColor(red: 0.69, green: 0.76, blue: 0.85, alpha: 1)
    private static let logo: UIImage? = {
        guard let original = UIImage(named: "TallyDexLogo") else { return nil }
        let configuration = UIGraphicsImageRendererFormat()
        configuration.scale = 2
        return UIGraphicsImageRenderer(size: CGSize(width: 160, height: 48), format: configuration).image { _ in
            image(original, in: CGRect(x: 0, y: 0, width: 160, height: 48))
        }
    }()

    nonisolated static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 420
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.85)
    }

    static func pageCount(items: Int, format: MissingCardExportFormat) -> Int {
        let perPage = format == .images ? 9 : 10
        return max(1, (items + perPage - 1) / perPage)
    }

    private static func imageSize(_ report: MissingCardReport, page: Int) -> CGSize {
        let count = min(9, max(0, report.items.count - page * 9))
        let rows = max(1, (count + 2) / 3)
        return CGSize(width: 720, height: 250 + CGFloat(rows) * 254 + 108)
    }

    private static func pdfPages(_ report: MissingCardReport) -> [[PDFRow]] {
        var pages: [[PDFRow]] = [[]]
        var used: CGFloat = 0
        for item in report.items {
            // Each missing printing gets its own row, so a long variant list is
            // never silently truncated into an incomplete printable checklist.
            for label in item.printings.components(separatedBy: "; ") {
                let labelHeight = (label as NSString).boundingRect(with: CGSize(width: 209, height: 10000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: UIFont.systemFont(ofSize: 10)], context: nil).height
                let nameHeight = (item.card.name as NSString).boundingRect(with: CGSize(width: 193, height: 10000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold)], context: nil).height
                let height = max(49, ceil(max(labelHeight, nameHeight)) + 14)
                if used + height > 490 && !pages[pages.count - 1].isEmpty { pages.append([]); used = 0 }
                pages[pages.count - 1].append(PDFRow(item: item, printing: label, height: height))
                used += height
            }
        }
        return pages
    }

    static func preview(report: MissingCardReport, format: MissingCardExportFormat, artwork: [String: Data]) -> UIImage {
        let size = format == .images ? imageSize(report, page: 0) : CGSize(width: 595, height: 842)
        let configuration = UIGraphicsImageRendererFormat()
        configuration.scale = 1
        configuration.opaque = true
        return UIGraphicsImageRenderer(size: size, format: configuration).image { _ in
            draw(report: report, page: 0, format: format, artwork: artwork)
        }
    }

    static func write(report: MissingCardReport, format: MissingCardExportFormat, artwork: [String: Data], directory: URL) async throws -> [URL] {
        let stem = report.set.name.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-").prefix(80)
        let count = format == .pdf ? pdfPages(report).count : pageCount(items: report.items.count, format: format)
        if format == .pdf {
            let url = directory.appendingPathComponent("\(stem)-Missing.pdf")
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
            try renderer.writePDF(to: url) { context in
                for page in 0..<count {
                    context.beginPage()
                    draw(report: report, page: page, format: .pdf, artwork: artwork)
                }
            }
            return [url]
        }
        var urls: [URL] = []
        let configuration = UIGraphicsImageRendererFormat()
        configuration.scale = 2
        configuration.opaque = true
        for page in 0..<count {
            try Task.checkCancellation()
            try autoreleasepool {
                let image = UIGraphicsImageRenderer(size: imageSize(report, page: page), format: configuration).image { _ in
                    draw(report: report, page: page, format: .images, artwork: artwork)
                }
                guard let data = image.pngData() else { throw MissingCardReport.ExportError.imageEncoding }
                let url = directory.appendingPathComponent("\(stem)-Missing-\(page + 1).png")
                try data.write(to: url, options: .atomic)
                urls.append(url)
            }
            await Task.yield()
        }
        return urls
    }

    private static func text(_ value: String, _ rect: CGRect, size: CGFloat, color: UIColor,
                             bold: Bool = false, alignment: NSTextAlignment = .left, wrap: Bool = false) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = wrap ? .byWordWrapping : .byTruncatingTail
        paragraph.alignment = alignment
        (value as NSString).draw(in: rect, withAttributes: [
            .font: UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular),
            .foregroundColor: color, .paragraphStyle: paragraph
        ])
    }

    private static func image(_ image: UIImage, in rect: CGRect) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
    }

    private static func art(_ item: MissingCardReport.Item, in rect: CGRect, artwork: [String: Data], light: Bool = false) {
        if let data = artwork[item.id], let card = UIImage(data: data) { image(card, in: rect) }
        else {
            (light ? UIColor.systemGray5 : tile).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 8).fill()
            text("#\(item.card.localID)", CGRect(x: rect.minX, y: rect.midY - 10, width: rect.width, height: 25),
                 size: 12, color: light ? .darkGray : muted, alignment: .center)
        }
    }

    private static func draw(report: MissingCardReport, page: Int, format: MissingCardExportFormat, artwork: [String: Data]) {
        let isImage = format == .images
        let width: CGFloat = isImage ? 720 : 595
        let height: CGFloat = isImage ? imageSize(report, page: page).height : 842
        (isImage ? navy : UIColor.white).setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: height)).fill()
        let ink: UIColor = isImage ? .white : UIColor(red: 0.08, green: 0.14, blue: 0.22, alpha: 1)
        let secondary: UIColor = isImage ? muted : .darkGray
        if let logo {
            image(logo, in: CGRect(x: 36, y: 20, width: isImage ? 160 : 120, height: 48))
        }
        text("\(report.goal.displayName.uppercased()) GOAL", CGRect(x: width - 205, y: 34, width: 169, height: 20),
             size: 11, color: isImage ? muted : blue, bold: true, alignment: .right)
        text(isImage ? "MISSING FROM MY COLLECTION" : "MISSING-CARD CHECKLIST",
             CGRect(x: 36, y: isImage ? 88 : 80, width: width - 72, height: 20), size: 11, color: blue, bold: true)
        text(report.set.name, CGRect(x: 36, y: isImage ? 117 : 105, width: width - 72, height: 82),
             size: isImage ? 36 : 28, color: ink, bold: true)
        text("\(report.items.count) cards · \(report.missingSlots) missing goal slots",
             CGRect(x: 36, y: isImage ? 196 : 180, width: width - 72, height: 26), size: isImage ? 16 : 11, color: secondary)
        let perPage = isImage ? 9 : 10
        let start = page * perPage
        let slice = Array(report.items.dropFirst(start).prefix(perPage))
        if isImage {
            let tileWidth: CGFloat = 206.66
            for (index, item) in slice.enumerated() {
                let x = 36 + CGFloat(index % 3) * (tileWidth + 14)
                let y = 250 + CGFloat(index / 3) * 254
                tile.setFill()
                UIBezierPath(roundedRect: CGRect(x: x, y: y, width: tileWidth, height: 240), cornerRadius: 16).fill()
                art(item, in: CGRect(x: x + 36, y: y + 10, width: 134, height: 170), artwork: artwork)
                text(item.card.name, CGRect(x: x + 12, y: y + 183, width: tileWidth - 24, height: 23), size: 16, color: ink, bold: true)
                let printingSummary = item.printings.count > 65 ? "\(item.missingSlots) missing printings · see PDF" : item.printings
                text("#\(item.card.localID) · \(printingSummary)", CGRect(x: x + 12, y: y + 207, width: tileWidth - 24, height: 30),
                     size: 10, color: secondary)
            }
        } else {
            for (label, x) in [("Got it", CGFloat(36)), ("No.", 106), ("Card", 145), ("Printing", 350)] {
                text(label, CGRect(x: x, y: 219, width: 150, height: 16), size: 9, color: secondary, bold: true)
            }
            var y: CGFloat = 245
            for row in pdfPages(report)[page] {
                let item = row.item
                UIColor.lightGray.setStroke()
                UIBezierPath(roundedRect: CGRect(x: 38, y: y + 13, width: 12, height: 12), cornerRadius: 2).stroke()
                art(item, in: CGRect(x: 69, y: y + 2, width: 26, height: 36), artwork: artwork, light: true)
                text(item.card.localID, CGRect(x: 106, y: y + 13, width: 35, height: 18), size: 10, color: secondary)
                text(item.card.name, CGRect(x: 145, y: y + 5, width: 193, height: row.height - 10), size: 12, color: ink, bold: true, wrap: true)
                text(row.printing, CGRect(x: 350, y: y + 5, width: 209, height: row.height - 10), size: 10, color: ink, wrap: true)
                UIColor(white: 0.9, alpha: 1).setStroke()
                let rule = UIBezierPath()
                rule.move(to: CGPoint(x: 36, y: y + row.height - 5)); rule.addLine(to: CGPoint(x: 559, y: y + row.height - 5))
                rule.lineWidth = 0.5; rule.stroke()
                y += row.height
            }
        }
        let footerY: CGFloat = isImage ? height - 80 : 780
        (isImage ? tile : UIColor.lightGray).setStroke()
        let line = UIBezierPath()
        line.move(to: CGPoint(x: 36, y: footerY)); line.addLine(to: CGPoint(x: width - 36, y: footerY))
        line.lineWidth = 0.6; line.stroke()
        text("MISSING-CARD CHECKLIST", CGRect(x: 36, y: footerY + 16, width: 300, height: 18), size: 10, color: secondary, bold: true)
        let count = isImage ? pageCount(items: report.items.count, format: format) : pdfPages(report).count
        text("\(page + 1) / \(count)",
             CGRect(x: width - 110, y: footerY + 16, width: 74, height: 18), size: 10, color: secondary, alignment: .right)
        text(report.createdAt.formatted(date: .abbreviated, time: .omitted),
             CGRect(x: 36, y: footerY + 37, width: width - 72, height: 18), size: 9, color: secondary)
    }
}

private struct MissingExportShareSheet: UIViewControllerRepresentable {
    let files: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: files, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
