import Foundation

struct CourseOCRLine {
    var text: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var centerY: Double { y + height / 2 }
}

struct CourseImportResult {
    var courses: [Course] = []
    var warnings: [String] = []
}

/// New schools implement this protocol and register one adapter below; UI/storage stay unchanged.
protocol SchoolCourseImportAdapter {
    var id: String { get }
    var name: String { get }
    func parse(text: String) -> CourseImportResult
    func parse(html: String) -> CourseImportResult
    func parse(lines: [CourseOCRLine]) -> CourseImportResult
}

enum CourseImportParser {
    static let adapters: [any SchoolCourseImportAdapter] = [PKUCourseImportAdapter()]
    static var schools: [(id: String, title: String)] { adapters.map { ($0.id, $0.name) } }
    static func parse(text: String, schoolID: String = "pku") -> CourseImportResult {
        guard let adapter = adapters.first(where: { $0.id == schoolID }) else { return unsupported() }
        return adapter.parse(text: text)
    }
    static func parse(html: String, schoolID: String = "pku") -> CourseImportResult {
        guard let adapter = adapters.first(where: { $0.id == schoolID }) else { return unsupported() }
        return adapter.parse(html: html)
    }
    static func parse(lines: [CourseOCRLine], schoolID: String = "pku") -> CourseImportResult {
        guard let adapter = adapters.first(where: { $0.id == schoolID }) else { return unsupported() }
        return adapter.parse(lines: lines)
    }
    private static func unsupported() -> CourseImportResult {
        CourseImportResult(warnings: ["暂未适配这所学校，请切换学校或手动添加课程。"])
    }
}

struct PKUCourseImportAdapter: SchoolCourseImportAdapter {
    let id = "pku"
    let name = "北京大学"
    private let rejected = ["未选上", "候补", "退选", "未选中", "已退"]

    func parse(html: String) -> CourseImportResult {
        let rows = matches("(?is)<tr\\b[^>]*>(.*?)</tr\\s*>", in: html).map { row in
            matches("(?is)<t[dh]\\b[^>]*>(.*?)</t[dh]\\s*>", in: row[1]).map { htmlText($0[1]) }
        }
        var result = CourseImportResult()
        var headers: [String] = []
        for row in rows {
            if row.contains(where: { $0.contains("课程号") }) && row.contains(where: { $0.contains("课程名") }) {
                headers = row
                continue
            }
            guard !headers.isEmpty else { continue }
            func field(_ names: [String]) -> String? {
                guard let index = headers.firstIndex(where: { h in names.contains(where: { h.contains($0) }) }), row.indices.contains(index) else { return nil }
                return row[index]
            }
            guard let number = field(["课程号"]), !matches("^\\d{8}$", in: number).isEmpty,
                  let title = field(["课程名"]), !title.isEmpty else { continue }
            let status = field(["选课结果", "选课状态"])
            if let status, rejected.contains(where: { status.contains($0) }) { continue }
            guard let schedule = field(["教室信息", "上课时间", "时间地点"]) else {
                result.warnings.append("\(title)：未找到上课时间列，请手动补充。")
                continue
            }
            append(number: number, title: title, teacher: field(["教师"]) ?? "", schedule: schedule, status: status, to: &result)
        }
        if headers.isEmpty { return parsePlainText(htmlText(html)) }
        return finish(result)
    }

    func parse(text: String) -> CourseImportResult {
        if text.range(of: "<tr", options: .caseInsensitive) != nil { return parse(html: text) }
        return parsePlainText(text)
    }

    private func parsePlainText(_ text: String) -> CourseImportResult {
        let text = normalize(text)
        let starts = matches("(?m)^\\s*(\\d{8})(?!\\d)", in: text, includeRange: true)
        var result = CourseImportResult()
        for (index, match) in starts.enumerated() {
            let start = Int(match[2])!, end = index + 1 < starts.count ? Int(starts[index + 1][2])! : (text as NSString).length
            let block = (text as NSString).substring(with: NSRange(location: start, length: end - start))
            if rejected.contains(where: { block.contains($0) }) { continue }
            let lines = block.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let first = lines.first ?? ""
            var title = first.replacingOccurrences(of: "^\\s*\\d{8}\\s*", with: "", options: .regularExpression)
            let cells = title.components(separatedBy: "\t").filter { !$0.isEmpty }
            title = cells.first ?? title
            title = title.components(separatedBy: "  ").first ?? title
            if let category = title.range(of: "\\s+(?:任选|任必|限选|必修|任修|通识课|全校必修)", options: .regularExpression) {
                title = String(title[..<category.lowerBound])
            }
            // OCR may put the course number on its own line.
            if title.isEmpty, lines.count > 1 { title = lines[1].components(separatedBy: "\t").first ?? "" }
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !title.contains("周周"), title.count < 100 else {
                result.warnings.append("课程 \(match[1]) 的名称无法确认，请手动补充。")
                continue
            }
            append(number: match[1], title: title, teacher: "", schedule: block,
                   status: block.contains("已选上") ? "已选上" : nil, to: &result)
        }
        return finish(result)
    }

    func parse(lines: [CourseOCRLine]) -> CourseImportResult {
        let sorted = lines.sorted { $0.centerY > $1.centerY }
        // The exam column also contains eight-digit dates. Anchor only in the leftmost code column.
        let rawAnchors = sorted.filter { $0.x < 0.2 && !matches("^\\s*(\\d{8})(?!\\d)(.*)$", in: normalize($0.text)).isEmpty }
        let codeX = rawAnchors.map(\.x).min() ?? 0
        let anchors = rawAnchors.filter { abs($0.x - codeX) < 0.04 }
        guard !anchors.isEmpty else {
            var result = parse(text: sorted.map(\.text).joined(separator: "\n"))
            result.warnings.insert("截图未能定位完整课程行。建议裁剪上方选课结果表、提高分辨率，或导入网页。", at: 0)
            return result
        }
        var result = CourseImportResult()
        for (index, anchor) in anchors.enumerated() {
            guard let anchorParts = matches("^\\s*(\\d{8})(?!\\d)(.*)$", in: normalize(anchor.text)).first else { continue }
            let top = index == 0 ? anchor.centerY + 0.055 : (anchors[index - 1].centerY + anchor.centerY) / 2
            let bottom = index + 1 == anchors.count ? anchor.centerY - 0.055 : (anchors[index + 1].centerY + anchor.centerY) / 2
            let row = sorted.filter { $0.centerY <= top && $0.centerY > bottom }
            let block = row.map(\.text).joined(separator: "\n")
            if rejected.contains(where: { block.contains($0) }) { continue }
            let candidates = row.filter {
                $0.x >= anchor.x + anchor.width - 0.003 && $0.x < 0.38
                    && abs($0.centerY - anchor.centerY) < max(anchor.height, $0.height) * 1.3
                    && !["任选", "任必", "限选", "必修", "通识", "全校", "课程"].contains(normalize($0.text))
                    && $0.text.range(of: "[\\p{L}]", options: .regularExpression) != nil
            }.sorted { $0.x < $1.x }
            // Name is the first column to the right of the course number. Subsequent columns are ignored.
            var mergedTitle = anchorParts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            mergedTitle = mergedTitle.components(separatedBy: "\t").first ?? mergedTitle
            if let category = mergedTitle.range(of: "\\s+(?:任选|任必|限选|必修|任修|通识课|全校必修)", options: .regularExpression) {
                mergedTitle = String(mergedTitle[..<category.lowerBound])
            }
            let title = (mergedTitle.isEmpty ? candidates.first?.text ?? "" : mergedTitle).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                result.warnings.append("课程 \(anchor.text) 的名称无法定位，请手动补充。")
                continue
            }
            append(number: anchorParts[1], title: title, teacher: "",
                   schedule: block, status: block.contains("已选上") ? "已选上" : nil, to: &result)
        }
        result.warnings.insert("截图识别可能遗漏或串行；请逐项核对课程、周次、单双周、节次和选课状态。", at: 0)
        return finish(result)
    }

    private func append(number: String, title: String, teacher: String, schedule: String, status: String?, to result: inout CourseImportResult) {
        var warnings: [String] = []
        let meetings = parseMeetings(schedule, warnings: &warnings)
        result.warnings += warnings.map { "\(title)：\($0)" }
        guard !meetings.isEmpty else {
            result.warnings.append("\(title)：未识别到有效的上课周次/星期/节次，未导入；可手动添加。")
            return
        }
        if status == nil || status?.contains("已选上") != true {
            result.warnings.append("\(title)：无法确认已选上，请核对后再保存。")
        }
        if let existing = result.courses.firstIndex(where: { $0.number == number }) {
            for meeting in meetings where !result.courses[existing].meetings.contains(where: { sameMeeting($0, meeting) }) {
                result.courses[existing].meetings.append(meeting)
            }
        } else {
            result.courses.append(Course(title: title, number: number, teacher: teacher, meetings: meetings))
        }
    }

    private func parseMeetings(_ raw: String, warnings: inout [String]) -> [CourseMeeting] {
        let text = normalize(raw)
        let range = "\\d{1,2}(?:\\s*[-~至]\\s*\\d{1,2})?"
        let weekPrefix = "(?<!\\d)(?:第\\s*)?(" + range + "(?:\\s*[,、]\\s*" + range + ")*)\\s*周\\s*(每周|单周|双周)?\\s*(?:星期|周)"
        let pattern = weekPrefix + "\\s*([一二三四五六日天1-7])\\s*(?:第\\s*)?(\\d{1,2})(?:\\s*[-~至]\\s*(\\d{1,2}))?\\s*节"
        let found = matches(pattern, in: text, includeRange: true)
        var result: [CourseMeeting] = []
        for (index, groups) in found.enumerated() {
            var weeks: [Int] = []
            var validWeeks = true
            for part in groups[1].components(separatedBy: CharacterSet(charactersIn: ",、")) {
                let numbers = matches("\\d+", in: part).compactMap { Int($0[0]) }
                guard let first = numbers.first, let last = numbers.last, (1...52).contains(first), (first...52).contains(last) else {
                    validWeeks = false; continue
                }
                weeks += Array(first...last)
            }
            guard validWeeks, let first = weeks.min(), let last = weeks.max(), let startPeriod = Int(groups[4]) else {
                warnings.append("周次超出 1–52 或范围颠倒，已跳过该上课安排。")
                continue
            }
            let endPeriod = Int(groups[5]) ?? startPeriod
            let weekday = Int(groups[3]) ?? (["一", "二", "三", "四", "五", "六", "日"].firstIndex(of: groups[3]).map { $0 + 1 } ?? 7)
            let matchStart = Int(groups[6])!, matchLength = Int(groups[7])!
            let end = index + 1 < found.count ? Int(found[index + 1][6])! : (text as NSString).length
            var location = (text as NSString).substring(with: NSRange(location: matchStart + matchLength, length: end - matchStart - matchLength))
            location = location.components(separatedBy: "\n").first ?? ""
            location = location.components(separatedBy: "考试").first ?? ""
            // A location may only appear in a note (e.g. '(备注:地学楼208)'). Preserve it for review.
            // Text imports can include status/IP columns following the classroom.
            location = location.components(separatedBy: "\t").first ?? ""
            location = location.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ";；")))
            let meeting = CourseMeeting(weekday: weekday, startPeriod: startPeriod, endPeriod: endPeriod,
                                        startWeek: first, endWeek: last, kind: groups[2] == "单周" ? .odd : groups[2] == "双周" ? .even : .all,
                                        weeks: groups[1].contains(",") || groups[1].contains("、") ? Array(Set(weeks)).sorted() : [], location: location)
            if !meeting.isValid { warnings.append("星期或节次无效，已跳过该上课安排。"); continue }
            if !result.contains(where: { sameMeeting($0, meeting) }) { result.append(meeting) }
        }
        if matches(weekPrefix, in: text).count > found.count {
            warnings.append("部分上课安排不完整或无法识别，已识别的安排仅供预览；请补充遗漏的时间。")
        }
        if found.count == 0 && text.contains("周") && text.contains("节") { warnings.append("时间格式不完整，未猜测缺失内容。") }
        return result
    }

    private func sameMeeting(_ a: CourseMeeting, _ b: CourseMeeting) -> Bool {
        a.weekday == b.weekday && a.startPeriod == b.startPeriod && a.endPeriod == b.endPeriod
            && a.startWeek == b.startWeek && a.endWeek == b.endWeek && a.kind == b.kind
            && a.weeks == b.weeks && a.location == b.location
    }
    private func finish(_ initial: CourseImportResult) -> CourseImportResult {
        var result = initial
        if result.courses.isEmpty { result.warnings.append("未找到可导入课程。请提供含课程号、课程名和完整教室信息的选课结果表。") }
        result.warnings = Array(NSOrderedSet(array: result.warnings)) as? [String] ?? result.warnings
        return result
    }
    private func normalize(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "～", with: "~").replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
    }
    private func htmlText(_ text: String) -> String {
        var output = text.replacingOccurrences(of: "(?is)<(?:script|style)\\b[^>]*>.*?</(?:script|style)>", with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: "(?i)<br\\s*/?>|</(?:p|div|tr)>", with: "\n", options: .regularExpression)
        output = output.replacingOccurrences(of: "(?s)<[^>]+>", with: "", options: .regularExpression)
        for (entity, value) in ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"] {
            output = output.replacingOccurrences(of: entity, with: value)
        }
        // Numeric entities are common in saved academic-system pages.
        for match in matches("&#(x[0-9a-fA-F]+|[0-9]+);", in: output) {
            let number = match[1].hasPrefix("x") ? UInt32(match[1].dropFirst(), radix: 16) : UInt32(match[1])
            if let number, let scalar = UnicodeScalar(number) { output = output.replacingOccurrences(of: match[0], with: String(scalar)) }
        }
        return normalize(output).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Arrays contain full match, captures, and optionally UTF-16 location/length.
    private func matches(_ pattern: String, in text: String, includeRange: Bool = false) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            var values = (0..<match.numberOfRanges).map { i in
                match.range(at: i).location == NSNotFound ? "" : ns.substring(with: match.range(at: i))
            }
            if includeRange { values += [String(match.range.location), String(match.range.length)] }
            return values
        }
    }
}
