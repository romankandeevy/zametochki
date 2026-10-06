import AppKit
import XCTest
@testable import Zametki

final class RemindersTests: XCTestCase {
    /// Вторник, 6 октября 2026, 12:00.
    private let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 6; c.hour = 12; c.minute = 0
        return Calendar.current.date(from: c)!
    }()

    private func when(_ line: String) -> DateComponents? {
        guard let found = Reminders.find(in: line, now: now) else { return nil }
        return Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: found.date)
    }

    private func check(_ line: String, _ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, file: StaticString = #filePath, line l: UInt = #line) {
        let c = when(line)
        XCTAssertEqual(c?.year, y, line, file: file, line: l)
        XCTAssertEqual(c?.month, mo, line, file: file, line: l)
        XCTAssertEqual(c?.day, d, line, file: file, line: l)
        XCTAssertEqual(c?.hour, h, line, file: file, line: l)
        XCTAssertEqual(c?.minute, mi, line, file: file, line: l)
    }

    func testWords() {
        check("позвонить маме @завтра 10:00", 2026, 10, 7, 10, 0)
        check("@сегодня 18:30 спортзал", 2026, 10, 6, 18, 30)
        check("отчёт @послезавтра", 2026, 10, 8, 9, 0)
        check("встреча @завтра в 9:05", 2026, 10, 7, 9, 5)
        check("@Завтра 7:00", 2026, 10, 7, 7, 0)
    }

    func testTimeOnly() {
        check("созвон @18:30", 2026, 10, 6, 18, 30)
        // 9 утра уже прошло - значит, завтра.
        check("зарядка @9:00", 2026, 10, 7, 9, 0)
    }

    func testWeekdays() {
        check("@пт", 2026, 10, 9, 9, 0)
        check("@пн 8:15", 2026, 10, 12, 8, 15)
        // Сегодня вторник: время ещё впереди - сегодня, уже прошло - через неделю.
        check("@вт 15:00", 2026, 10, 6, 15, 0)
        check("@вт 10:00", 2026, 10, 13, 10, 0)
    }

    func testDates() {
        check("@15.10 9:30", 2026, 10, 15, 9, 30)
        check("@01.01", 2027, 1, 1, 9, 0)
        check("@3.11.2027 20:00", 2027, 11, 3, 20, 0)
        check("@3.11.27", 2027, 11, 3, 9, 0)
    }

    func testRejects() {
        XCTAssertNil(when("купить молоко"))
        XCTAssertNil(when("@завтрак с Сашей"))
        XCTAssertNil(when("@31.02"))
        XCTAssertNil(when("@25:00"))
        XCTAssertNil(when("почта: me@mail.ru"))
    }

    func testTokenRange() {
        let line = "позвонить @завтра 10:00 маме"
        let found = Reminders.find(in: line, now: now)
        XCTAssertEqual(found.map { (line as NSString).substring(with: $0.range) }, "@завтра 10:00")
    }
}

final class BoardTests: XCTestCase {
    func testMoveBetweenColumns() {
        var board = Board.empty
        board.columns[0].cards = [.init(text: "a"), .init(text: "b"), .init(text: "c")]
        let b = board.columns[0].cards[1].id
        board.move(b, to: board.columns[2].id)
        XCTAssertEqual(board.columns[0].cards.map(\.text), ["a", "c"])
        XCTAssertEqual(board.columns[2].cards.map(\.text), ["b"])
    }

    func testMoveBefore() {
        var board = Board.empty
        board.columns[0].cards = [.init(text: "a"), .init(text: "b"), .init(text: "c")]
        let a = board.columns[0].cards[0].id, c = board.columns[0].cards[2].id
        board.move(c, to: board.columns[0].id, before: a)
        XCTAssertEqual(board.columns[0].cards.map(\.text), ["c", "a", "b"])
    }

    func testJSONRoundTrip() {
        var board = Board.empty
        board.columns[1].cards = [.init(text: "в работе")]
        XCTAssertEqual(Board(json: board.json), board)
        XCTAssertEqual(Board(json: "мусор").columns.map(\.title), Board.empty.columns.map(\.title))
    }

    func testSurvivesSaveAndLoad() {
        let text = NSMutableAttributedString(string: "Доска\n")
        text.append(Formatting.object([.zBoard: Board.empty.json, .zBlock: Block.board.rawValue]))
        let doc = Formatting.doc(from: text)
        let back = Formatting.attributed(doc)
        let at = (back.string as NSString).range(of: "\u{FFFC}").location
        XCTAssertNotEqual(at, NSNotFound)
        XCTAssertEqual(Formatting.block(of: back.attributes(at: at, effectiveRange: nil)), .board)
        XCTAssertNotNil(back.attribute(.attachment, at: at, effectiveRange: nil))
    }
}

final class TemplateTests: XCTestCase {
    private func blocks(_ doc: Formatting.Doc) -> [(String, Block)] {
        let text = Formatting.attributed(doc)
        let ns = text.string as NSString
        var out: [(String, Block)] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { line, _, enclosing, _ in
            let block = enclosing.length > 0 ? Formatting.block(of: text.attributes(at: NSMaxRange(enclosing) - 1, effectiveRange: nil)) : .text
            out.append((line ?? "", block))
        }
        return out
    }

    func testEveryTemplateHasTitleAndNoMarkup() {
        for template in Template.all {
            let lines = blocks(template.doc())
            XCTAssertEqual(lines.first?.1, .title, template.name)
            XCTAssertFalse(template.doc().text.contains("**"), template.name)
            XCTAssertFalse(template.doc().text.contains("[ ]"), template.name)
        }
    }

    func testMeetingHasTodo() {
        let lines = blocks(Template.all.first { $0.id == "meeting" }!.doc())
        XCTAssertTrue(lines.contains { $0.1 == .todo })
        XCTAssertTrue(lines.contains { $0.1 == .bullet })
    }

    func testWeekHasSevenDays() {
        let lines = blocks(Template.all.first { $0.id == "week" }!.doc())
        XCTAssertEqual(lines.filter { $0.1 == .heading }.count, 8) // «Главное» + 7 дней
    }

    func testKanbanTemplateEndsWithBoard() {
        let lines = blocks(Template.all.first { $0.id == "kanban" }!.doc())
        XCTAssertEqual(lines.last?.1, .board)
        // Заголовок над доской остаётся заголовком.
        XCTAssertEqual(lines.dropLast().last?.1, .heading)
    }
}

final class StatsTests: XCTestCase {
    func testCount() {
        XCTAssertEqual(EditorStats.count(""), 0)
        XCTAssertEqual(EditorStats.count("привет мир"), 2)
        XCTAssertEqual(EditorStats.count("  один\n\nдва  три "), 3)
        XCTAssertEqual(EditorStats.count("текст \u{FFFC} ещё"), 2)
    }

    func testReadingTime() {
        XCTAssertEqual(EditorStats.readingTime(0), "")
        XCTAssertEqual(EditorStats.readingTime(10), "1 мин чтения")
        XCTAssertEqual(EditorStats.readingTime(400), "3 мин чтения")
    }
}

final class InboxTests: XCTestCase {
    func testQuickNotesKeepTheirTypes() {
        let store = Store()
        store.appendToInbox("[] купить молоко @завтра 10:00")
        store.appendToInbox("просто мысль")
        store.appendToInbox("- пункт")
        let id = store.inboxID()
        let text = Formatting.attributed(store.note(id)!.doc)
        let ns = text.string as NSString
        var lines: [(String, Block)] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { line, _, enclosing, _ in
            let block = enclosing.length > 0 ? Formatting.block(of: text.attributes(at: NSMaxRange(enclosing) - 1, effectiveRange: nil)) : .text
            lines.append((line ?? "", block))
        }
        let tail = Array(lines.suffix(3))
        XCTAssertEqual(tail.map(\.0), ["купить молоко @завтра 10:00", "просто мысль", "пункт"])
        XCTAssertEqual(tail.map(\.1), [.todo, .text, .bullet])
        XCTAssertEqual(store.note(id)?.title, "Входящие")
        store.delete(id)
    }
}

final class AudioTests: XCTestCase {
    func testSaveAndRead() {
        // Секунда синуса, громкость нарастает.
        let samples = (0..<16_000).map { i in Float(sin(Double(i) * 0.1) * Double(i) / 16_000) }
        guard let name = VoiceRecording.save(samples) else { return XCTFail("запись не сохранилась") }
        defer { try? FileManager.default.removeItem(at: Assets.url(name)) }
        let info = VoiceRecording.info(name)
        XCTAssertEqual(info.duration, 1, accuracy: 0.15)
        XCTAssertFalse(info.peaks.isEmpty)
        XCTAssertGreaterThan(info.peaks.last ?? 0, info.peaks.first ?? 1)
        XCTAssertEqual(VoiceRecording.time(65), "1:05")
    }
}

/// Рисует страницу со всеми новыми блоками в PNG и PDF - картинки уходят в артефакты сборки, чтобы на них посмотреть.
final class ExportTests: XCTestCase {
    override class func setUp() {
        let font = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/Caveat.ttf").standardized
        CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
    }

    private var output: URL {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ZAMETKI_ARTIFACTS"] ?? NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func sample(style: PageStyle) -> Note {
        let meeting = Template.all.first { $0.id == "meeting" }!.doc()
        let text = NSMutableAttributedString(attributedString: Formatting.attributed(meeting))
        text.append(NSAttributedString(string: "\n"))
        func line(_ s: String, _ block: Block) {
            text.append(NSAttributedString(string: s + "\n", attributes: block == .text ? [:] : [.zBlock: block.rawValue]))
        }
        line("позвонить в студию @завтра 10:00", .todo)
        line("уже сделано", .done)
        line("Голос и доска", .heading)
        var board = Board.empty
        board.columns[0].cards = [.init(text: "Сайт"), .init(text: "Иконка")]
        board.columns[1].cards = [.init(text: "Канбан")]
        board.columns[2].cards = [.init(text: "Шаблоны"), .init(text: "Экспорт"), .init(text: "Фокус")]
        text.append(Formatting.object([.zBoard: board.json, .zBlock: Block.board.rawValue]))
        text.append(NSAttributedString(string: "\n", attributes: [.zBlock: Block.board.rawValue]))
        let samples = (0..<48_000).map { i in Float(sin(Double(i) * 0.05) * (0.3 + 0.7 * abs(sin(Double(i) / 3000)))) }
        if let audio = VoiceRecording.save(samples) {
            text.append(Formatting.object([.zAudio: audio, .zBlock: Block.audio.rawValue]))
            text.append(NSAttributedString(string: "\n", attributes: [.zBlock: Block.audio.rawValue]))
        }
        line("Расшифровка голосовой заметки встаёт строкой под плеером.", .text)
        line("Тихая мысль в цитате", .quote)
        var doc = Formatting.doc(from: text)
        doc.style = style
        return Note(id: "export-test", doc: doc, modified: Date())
    }

    func testRenderBlue() throws {
        let note = sample(style: PageStyle())
        let png = try XCTUnwrap(PageExport.png(note))
        try png.write(to: output.appendingPathComponent("export-blue.png"))
        let image = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(image.pixelsWide, Int(PageExport.width * 2))
        XCTAssertGreaterThan(image.pixelsHigh, 1200)
        let pdf = PageExport.pdf(note)
        XCTAssertGreaterThan(pdf.count, 1000)
        try pdf.write(to: output.appendingPathComponent("export-blue.pdf"))
    }

    func testRenderGradientSystemFont() throws {
        var style = PageStyle()
        style.font = .system
        style.background = .gradient("sunset")
        let png = try XCTUnwrap(PageExport.png(sample(style: style)))
        try png.write(to: output.appendingPathComponent("export-sunset.png"))
    }
}
