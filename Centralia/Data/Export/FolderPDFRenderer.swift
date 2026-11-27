import CoreGraphics
import CoreText
import Foundation
import ImageIO
import os

nonisolated final class FolderPDFFile: Identifiable, Sendable {
    let url: URL
    var id: URL { url }

    fileprivate init(url: URL) {
        self.url = url
    }

    deinit {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

nonisolated enum FolderPDFRenderer {
    struct Short: Sendable {
        let title: String
        let creator: String
        let platform: String
        let savedAt: Date
        let sourceURL: URL
        let coverURL: URL?
    }

    enum Cover: Sendable {
        case encoded(Data)
        case decoded(CGImage)
    }

    struct Progress: Sendable {
        let completedPages: Int
        let totalPages: Int
    }

    enum ExportError: Error {
        case emptyFolder
        case cannotCreateDocument
    }

    private static let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    private static let cardsPerPage = 6
    private static let paper = CGColor(red: 0.988, green: 0.984, blue: 0.957, alpha: 1)
    private static let ink = CGColor(red: 0.11, green: 0.11, blue: 0.10, alpha: 1)
    private static let secondaryInk = CGColor(red: 0.32, green: 0.31, blue: 0.27, alpha: 1)
    private static let divider = CGColor(red: 0.84, green: 0.82, blue: 0.77, alpha: 1)

    @concurrent
    static func render(
        folderName: String,
        shorts: [Short],
        directory: URL = FileManager.default.temporaryDirectory,
        cachedCover: @Sendable (URL) async -> Cover? = { _ in nil },
        onProgress: @MainActor @Sendable (Progress) -> Void = { _ in }
    ) async throws -> FolderPDFFile {
        try Task.checkCancellation()
        guard !shorts.isEmpty else { throw ExportError.emptyFolder }

        let signposter = OSSignposter(subsystem: "Centralia", category: "Folder PDF")
        let interval = signposter.beginInterval("Render Folder PDF")
        defer { signposter.endInterval("Render Folder PDF", interval) }

        let sorted = shorts.sorted { $0.savedAt > $1.savedAt }
        let pageCount = (sorted.count - 1) / cardsPerPage + 1
        let outputDirectory = directory.appending(path: "Centralia-PDF-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let file = FolderPDFFile(url: outputDirectory.appending(path: fileName(for: folderName)))

        var mediaBox = page
        let metadata = [kCGPDFContextTitle as String: folderName, kCGPDFContextCreator as String: "Centralia"]
        guard let context = CGContext(file.url as CFURL, mediaBox: &mediaBox, metadata as CFDictionary) else {
            throw ExportError.cannotCreateDocument
        }

        do {
            defer { context.closePDF() }
            await onProgress(Progress(completedPages: 0, totalPages: pageCount))

            for pageIndex in 0..<pageCount {
                try Task.checkCancellation()
                let start = pageIndex * cardsPerPage
                let end = min(start + cardsPerPage, sorted.count)
                var covers: [CGImage?] = []

                for short in sorted[start..<end] {
                    try Task.checkCancellation()
                    if let url = short.coverURL, let cover = await cachedCover(url) {
                        covers.append(poster(from: cover))
                    } else {
                        covers.append(nil)
                    }
                }

                try Task.checkCancellation()
                context.beginPDFPage(nil)
                drawPage(
                    named: folderName,
                    index: pageIndex,
                    pageCount: pageCount,
                    shortCount: sorted.count,
                    in: context
                )
                for (index, short) in sorted[start..<end].enumerated() {
                    drawCard(short, cover: covers[index], at: index, in: context)
                }
                context.endPDFPage()
                await onProgress(Progress(completedPages: pageIndex + 1, totalPages: pageCount))
            }
        }

        try Task.checkCancellation()
        guard let size = try file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
            throw ExportError.cannotCreateDocument
        }
        return file
    }

    private static func drawPage(
        named name: String,
        index: Int,
        pageCount: Int,
        shortCount: Int,
        in context: CGContext
    ) {
        context.setFillColor(paper)
        context.fill(page)
        text("Centralia", font: font("Joan-Regular", fallback: "Georgia", size: 20),
             at: CGPoint(x: 42, y: 51), width: 528, in: context)
        text(name, font: font("InstrumentSerif-Regular", fallback: "Georgia", size: 36),
             at: CGPoint(x: 42, y: 95), width: 528, lines: 2, leading: 37, in: context)
        rule(at: 152, in: context)
        rule(at: 731, in: context)

        let footerFont = font("HelveticaNeue-Medium", size: 10)
        let countLabel = shortCount == 1 ? "1 saved short" : "\(shortCount) saved shorts"
        text(countLabel, font: footerFont, color: secondaryInk,
             at: CGPoint(x: 42, y: 752), width: 420, in: context)
        text("\(index + 1) / \(pageCount)", font: footerFont, color: secondaryInk,
             at: CGPoint(x: 465, y: 752), width: 105, rightAligned: true, in: context)
    }

    private static func drawCard(_ short: Short, cover: CGImage?, at index: Int, in context: CGContext) {
        let x = CGFloat(42 + (index % 2) * 272)
        let top = CGFloat(172 + (index / 2) * 182)
        let card = rect(x: x, top: top, width: 256, height: 162)
        let cardPath = CGPath(roundedRect: card, cornerWidth: 13, cornerHeight: 13, transform: nil)
        context.addPath(cardPath)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.setStrokeColor(divider)
        context.setLineWidth(0.65)
        context.drawPath(using: .fillStroke)

        let coverRect = rect(x: x + 10, top: top + 10, width: 80, height: 142)
        context.saveGState()
        context.addPath(CGPath(roundedRect: coverRect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.clip()
        if let cover {
            context.draw(cover, in: coverRect)
        } else {
            drawPlaceholder(in: coverRect, context: context)
        }
        context.restoreGState()

        let textX = x + 102
        let textWidth: CGFloat = 142
        text(short.platform, font: font("HelveticaNeue-Bold", size: 10), color: secondaryInk,
             at: CGPoint(x: textX, y: top + 29), width: textWidth, in: context)
        text(short.title, font: font("HelveticaNeue-Medium", size: 15),
             at: CGPoint(x: textX, y: top + 54), width: textWidth, lines: 3, leading: 18, in: context)
        text(short.creator, font: font("HelveticaNeue", size: 10), color: secondaryInk,
             at: CGPoint(x: textX, y: top + 114), width: textWidth, in: context)
        text("Open original", font: font("HelveticaNeue-Bold", size: 10),
             at: CGPoint(x: textX, y: top + 138), width: textWidth, underlined: true, in: context)
        context.setURL(short.sourceURL as CFURL, for: rect(x: textX, top: top + 123, width: textWidth, height: 23))
    }

    private static func drawPlaceholder(in bounds: CGRect, context: CGContext) {
        context.setFillColor(CGColor(red: 0.89, green: 0.87, blue: 0.82, alpha: 1))
        context.fill(bounds)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        context.setFillColor(paper)
        context.fillEllipse(in: CGRect(x: center.x - 15, y: center.y - 15, width: 30, height: 30))
        context.setFillColor(ink)
        context.move(to: CGPoint(x: center.x - 3, y: center.y - 5))
        context.addLine(to: CGPoint(x: center.x + 5, y: center.y))
        context.addLine(to: CGPoint(x: center.x - 3, y: center.y + 5))
        context.closePath()
        context.fillPath()
    }

    private static func poster(from cover: Cover) -> CGImage? {
        let image: CGImage
        switch cover {
        case let .decoded(value):
            image = value
        case let .encoded(data):
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 640
            ] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
            image = thumbnail
        }

        let width = 200
        let height = 355
        guard let bitmap = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        let scale = max(CGFloat(width) / CGFloat(image.width), CGFloat(height) / CGFloat(image.height))
        let scaledWidth = CGFloat(image.width) * scale
        let scaledHeight = CGFloat(image.height) * scale
        bitmap.setFillColor(paper)
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        bitmap.interpolationQuality = .high
        bitmap.draw(image, in: CGRect(
            x: (CGFloat(width) - scaledWidth) / 2,
            y: (CGFloat(height) - scaledHeight) / 2,
            width: scaledWidth,
            height: scaledHeight
        ))
        return bitmap.makeImage()
    }

    private static func text(
        _ value: String, font: CTFont, color: CGColor = ink, at origin: CGPoint, width: CGFloat,
        lines: Int = 1, leading: CGFloat = 0, rightAligned: Bool = false, underlined: Bool = false,
        in context: CGContext
    ) {
        let flattened = value.split(whereSeparator: \.isNewline).joined(separator: " ")
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        if underlined {
            attributes[NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)] = CTUnderlineStyle.single.rawValue
        }
        let text = NSAttributedString(string: flattened, attributes: attributes)
        let typesetter = CTTypesetterCreateWithAttributedString(text)
        var start = 0

        for row in 0..<lines where start < text.length {
            let remaining = text.length - start
            let length = row == lines - 1 ? remaining : CTTypesetterSuggestLineBreak(typesetter, start, width)
            let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: length))
            let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
            let fitted = CTLineCreateTruncatedLine(line, width, .end, ellipsis) ?? line
            let x = rightAligned ? origin.x + CTLineGetPenOffsetForFlush(fitted, 1, width) : origin.x
            context.textPosition = CGPoint(x: x, y: page.height - origin.y - CGFloat(row) * leading)
            CTLineDraw(fitted, context)
            start += length
        }
    }

    private static func font(_ name: String, fallback: String? = nil, size: CGFloat) -> CTFont {
        let requested = CTFontCreateWithName(name as CFString, size, nil)
        guard let fallback, CTFontCopyPostScriptName(requested) as String != name else { return requested }
        return CTFontCreateWithName(fallback as CFString, size, nil)
    }

    private static func rule(at top: CGFloat, in context: CGContext) {
        context.setFillColor(divider)
        context.fill(rect(x: 42, top: top, width: 528, height: 0.75))
    }

    private static func rect(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: x, y: page.height - top - height, width: width, height: height)
    }

    private static func fileName(for folderName: String) -> String {
        let unsafe = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:?%*|\"<>"))
        let safe = folderName.components(separatedBy: unsafe).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        let filename = String(safe.unicodeScalars.prefix(56))
        return filename.isEmpty ? "Centralia Folder.pdf" : "Centralia - \(filename).pdf"
    }
}
