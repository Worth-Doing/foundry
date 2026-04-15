import SwiftUI
import AppKit

/// Renders Markdown text as styled AttributedString with code blocks as separate views
struct MarkdownView: View {
    let text: String

    private var blocks: [MarkdownBlock] {
        MarkdownParser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let attributed):
                    Text(attributed)
                        .textSelection(.enabled)
                        .lineSpacing(3)

                case .heading(let level, let content):
                    Text(content)
                        .font(headingFont(level))
                        .fontWeight(.bold)
                        .padding(.top, level == 1 ? 8 : 4)
                        .textSelection(.enabled)

                case .codeBlock(let language, let code):
                    CodeBlockView(language: language, code: code)

                case .bulletList(let items):
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\u{2022}")
                                    .foregroundStyle(.secondary)
                                Text(MarkdownParser.inlineAttributed(item))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.leading, 4)

                case .numberedList(let items):
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(idx + 1).")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, alignment: .trailing)
                                Text(MarkdownParser.inlineAttributed(item))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.leading, 4)

                case .blockquote(let content):
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.accentColor.opacity(0.4))
                            .frame(width: 3)

                        Text(MarkdownParser.inlineAttributed(content))
                            .foregroundStyle(.secondary)
                            .italic()
                            .padding(.leading, 10)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)

                case .horizontalRule:
                    Divider()
                        .padding(.vertical, 4)

                case .table(let headers, let rows):
                    TableBlockView(headers: headers, rows: rows)
                }
            }
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .subheadline
        }
    }
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var isCopied = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            if !language.isEmpty {
                HStack {
                    Text(language)
                        .font(.system(.caption2, design: .monospaced, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                        isCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { isCopied = false }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                .font(.caption2)
                            Text(isCopied ? "Copied" : "Copy")
                                .font(.caption2)
                        }
                        .foregroundStyle(isCopied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(.thinMaterial)
            }

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(Spacing.md)
            }
        }
        .glassBackground(cornerRadius: CornerRadius.sm, shadow: false)
    }
}

// MARK: - Table View

struct TableBlockView: View {
    let headers: [String]
    let rows: [[String]]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    Text(header)
                        .font(.system(.caption, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.sm)
                }
            }
            .background(.ultraThinMaterial)

            Divider()

            // Data rows
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(.system(.caption))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                }
                .background(rowIdx % 2 == 0 ? Color.clear : Color(nsColor: .controlBackgroundColor).opacity(0.3))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Markdown Parser

enum MarkdownBlock {
    case paragraph(AttributedString)
    case heading(Int, String)
    case codeBlock(String, String)
    case bulletList([String])
    case numberedList([String])
    case blockquote(String)
    case horizontalRule
    case table([String], [[String]])
}

struct MarkdownParser {

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty line
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Code block (``` or ~~~)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = trimmed.hasPrefix("```") ? "```" : "~~~"
                let lang = String(trimmed.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(lang, codeLines.joined(separator: "\n")))
                continue
            }

            // Heading
            if let headingMatch = parseHeading(trimmed) {
                blocks.append(.heading(headingMatch.0, headingMatch.1))
                i += 1
                continue
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            // Table
            if trimmed.contains("|") && i + 1 < lines.count {
                let nextTrimmed = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if nextTrimmed.contains("|") && nextTrimmed.contains("-") {
                    let (headers, rows, newI) = parseTable(lines, from: i)
                    if !headers.isEmpty {
                        blocks.append(.table(headers, rows))
                        i = newI
                        continue
                    }
                }
            }

            // Blockquote
            if trimmed.hasPrefix("> ") || trimmed == ">" {
                var quoteLines: [String] = []
                while i < lines.count {
                    let ql = lines[i].trimmingCharacters(in: .whitespaces)
                    if ql.hasPrefix("> ") {
                        quoteLines.append(String(ql.dropFirst(2)))
                    } else if ql == ">" {
                        quoteLines.append("")
                    } else {
                        break
                    }
                    i += 1
                }
                blocks.append(.blockquote(quoteLines.joined(separator: " ")))
                continue
            }

            // Bullet list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                var items: [String] = []
                while i < lines.count {
                    let ll = lines[i].trimmingCharacters(in: .whitespaces)
                    if ll.hasPrefix("- ") || ll.hasPrefix("* ") || ll.hasPrefix("+ ") {
                        items.append(String(ll.dropFirst(2)))
                    } else if ll.hasPrefix("  ") && !items.isEmpty {
                        items[items.count - 1] += " " + ll.trimmingCharacters(in: .whitespaces)
                    } else {
                        break
                    }
                    i += 1
                }
                blocks.append(.bulletList(items))
                continue
            }

            // Numbered list
            if let _ = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                var items: [String] = []
                while i < lines.count {
                    let ll = lines[i].trimmingCharacters(in: .whitespaces)
                    if let range = ll.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                        items.append(String(ll[range.upperBound...]))
                    } else if ll.hasPrefix("  ") && !items.isEmpty {
                        items[items.count - 1] += " " + ll.trimmingCharacters(in: .whitespaces)
                    } else {
                        break
                    }
                    i += 1
                }
                blocks.append(.numberedList(items))
                continue
            }

            // Regular paragraph - collect consecutive non-empty lines
            var paraLines: [String] = []
            while i < lines.count {
                let pl = lines[i]
                let pt = pl.trimmingCharacters(in: .whitespaces)
                if pt.isEmpty || pt.hasPrefix("```") || pt.hasPrefix("~~~") ||
                   pt.hasPrefix("# ") || pt.hasPrefix("## ") || pt.hasPrefix("### ") ||
                   pt.hasPrefix("- ") || pt.hasPrefix("* ") || pt.hasPrefix("> ") ||
                   pt == "---" || pt == "***" {
                    break
                }
                paraLines.append(pl)
                i += 1
            }

            if !paraLines.isEmpty {
                let fullText = paraLines.joined(separator: "\n")
                blocks.append(.paragraph(inlineAttributed(fullText)))
            }
        }

        return blocks
    }

    // MARK: - Inline Markdown -> AttributedString

    static func inlineAttributed(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(markdown: text, options: .init(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )) {
            var result = attributed
            for run in result.runs {
                if run.inlinePresentationIntent?.contains(.code) == true {
                    let range = run.range
                    result[range].font = .system(size: 12.5, design: .monospaced)
                    result[range].backgroundColor = Color(nsColor: .controlBackgroundColor)
                }
            }
            return result
        }

        return AttributedString(text)
    }

    // MARK: - Heading

    private static func parseHeading(_ line: String) -> (Int, String)? {
        if line.hasPrefix("#### ") { return (4, String(line.dropFirst(5))) }
        if line.hasPrefix("### ") { return (3, String(line.dropFirst(4))) }
        if line.hasPrefix("## ") { return (2, String(line.dropFirst(3))) }
        if line.hasPrefix("# ") { return (1, String(line.dropFirst(2))) }
        return nil
    }

    // MARK: - Table

    private static func parseTable(_ lines: [String], from start: Int) -> ([String], [[String]], Int) {
        var i = start

        // Header row
        let headerLine = lines[i].trimmingCharacters(in: .whitespaces)
        let headers = parseTableRow(headerLine)
        i += 1

        // Separator row
        if i < lines.count {
            i += 1 // skip separator
        }

        // Data rows
        var rows: [[String]] = []
        while i < lines.count {
            let rowLine = lines[i].trimmingCharacters(in: .whitespaces)
            if !rowLine.contains("|") || rowLine.isEmpty {
                break
            }
            rows.append(parseTableRow(rowLine))
            i += 1
        }

        return (headers, rows, i)
    }

    private static func parseTableRow(_ line: String) -> [String] {
        var cells = line.components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        // Remove empty first/last from leading/trailing pipes
        if cells.first?.isEmpty == true { cells.removeFirst() }
        if cells.last?.isEmpty == true { cells.removeLast() }

        return cells
    }
}
