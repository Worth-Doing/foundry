import Foundation

/// Computes line-by-line diffs between two text contents
struct DiffEngine {

    /// Compute a diff between old and new content
    static func diff(old: String, new: String) -> [DiffLine] {
        let oldLines = old.components(separatedBy: .newlines)
        let newLines = new.components(separatedBy: .newlines)
        return computeDiff(oldLines: oldLines, newLines: newLines)
    }

    /// Parse a unified diff string into DiffLines
    static func parseUnifiedDiff(_ diffText: String) -> [DiffLine] {
        var result: [DiffLine] = []
        let lines = diffText.components(separatedBy: .newlines)

        var oldLine = 0
        var newLine = 0

        for line in lines {
            if line.hasPrefix("@@") {
                // Parse hunk header
                result.append(DiffLine(type: .header, content: line))
                // Extract line numbers from @@ -oldStart,count +newStart,count @@
                if let range = parseHunkHeader(line) {
                    oldLine = range.oldStart
                    newLine = range.newStart
                }
            } else if line.hasPrefix("+") && !line.hasPrefix("+++") {
                result.append(DiffLine(
                    type: .addition,
                    content: String(line.dropFirst()),
                    newLineNumber: newLine
                ))
                newLine += 1
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                result.append(DiffLine(
                    type: .deletion,
                    content: String(line.dropFirst()),
                    oldLineNumber: oldLine
                ))
                oldLine += 1
            } else if line.hasPrefix(" ") {
                result.append(DiffLine(
                    type: .context,
                    content: String(line.dropFirst()),
                    oldLineNumber: oldLine,
                    newLineNumber: newLine
                ))
                oldLine += 1
                newLine += 1
            } else if line.hasPrefix("diff ") || line.hasPrefix("index ") ||
                      line.hasPrefix("---") || line.hasPrefix("+++") {
                result.append(DiffLine(type: .header, content: line))
            }
        }

        return result
    }

    // MARK: - Private

    private struct HunkRange {
        let oldStart: Int
        let newStart: Int
    }

    private static func parseHunkHeader(_ header: String) -> HunkRange? {
        // Parse @@ -oldStart[,count] +newStart[,count] @@
        let pattern = #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)) else {
            return nil
        }

        guard let oldRange = Range(match.range(at: 1), in: header),
              let newRange = Range(match.range(at: 2), in: header),
              let oldStart = Int(header[oldRange]),
              let newStart = Int(header[newRange]) else {
            return nil
        }

        return HunkRange(oldStart: oldStart, newStart: newStart)
    }

    /// Simple Myers-like diff algorithm (simplified)
    private static func computeDiff(oldLines: [String], newLines: [String]) -> [DiffLine] {
        var result: [DiffLine] = []

        // Build LCS table
        let m = oldLines.count
        let n = newLines.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...max(m, 1) {
            for j in 1...max(n, 1) {
                guard i <= m, j <= n else { continue }
                if oldLines[i - 1] == newLines[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to produce diff
        var i = m
        var j = n
        var tempResult: [DiffLine] = []

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && oldLines[i - 1] == newLines[j - 1] {
                tempResult.append(DiffLine(
                    type: .context,
                    content: oldLines[i - 1],
                    oldLineNumber: i,
                    newLineNumber: j
                ))
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                tempResult.append(DiffLine(
                    type: .addition,
                    content: newLines[j - 1],
                    newLineNumber: j
                ))
                j -= 1
            } else if i > 0 {
                tempResult.append(DiffLine(
                    type: .deletion,
                    content: oldLines[i - 1],
                    oldLineNumber: i
                ))
                i -= 1
            }
        }

        result = tempResult.reversed()
        return result
    }
}
