import AppKit
import CryptoKit
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
        // Последняя, пустая задача тоже остаётся задачей.
        XCTAssertEqual(lines.last { !$0.0.isEmpty || $0.1 != .text }?.1, .todo)
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

final class TitleTests: XCTestCase {
    private func firstBlock(_ text: NSAttributedString) -> Block {
        Formatting.block(of: text.attributes(at: 0, effectiveRange: nil))
    }

    func testFirstLineIsAlwaysTitle() {
        let storage = NSTextStorage(attributedString: Formatting.attributed(.init(text: "Покупки\nмолоко")))
        Formatting.render(storage)
        XCTAssertEqual(firstBlock(storage), .title)
        XCTAssertEqual(Formatting.block(of: storage.attributes(at: 9, effectiveRange: nil)), .text)
    }

    func testTitleCannotBecomeList() {
        var doc = Formatting.Doc(text: "Покупки\nмолоко")
        doc.runs = [Formatting.Run(from: 0, length: 8, block: Block.bullet.rawValue)]
        let storage = NSTextStorage(attributedString: Formatting.attributed(doc))
        Formatting.render(storage)
        XCTAssertEqual(firstBlock(storage), .title)
    }

    func testObjectAtStartGetsTitleLineAbove() {
        let text = NSMutableAttributedString(attributedString: Formatting.object([.zTable: Table.empty.json, .zBlock: Block.table.rawValue]))
        XCTAssertTrue(Formatting.ensureTitleLine(text))
        XCTAssertEqual(text.string, "\n\u{FFFC}")
        let storage = NSTextStorage(attributedString: text)
        Formatting.render(storage)
        XCTAssertEqual(firstBlock(storage), .title)
        XCTAssertEqual(Formatting.block(of: storage.attributes(at: 1, effectiveRange: nil)), .table)
        XCTAssertFalse(Formatting.ensureTitleLine(NSMutableAttributedString(string: "Текст")))
    }
}

final class WhiteboardTests: XCTestCase {
    func testWhiteboardSurvivesSaveAndLoad() {
        let text = NSMutableAttributedString(string: "Схема\n")
        text.append(Formatting.object([.zWhiteboard: Whiteboard().json, .zBlock: Block.whiteboard.rawValue]))
        let back = Formatting.attributed(Formatting.doc(from: text))
        XCTAssertNotNil(back.attribute(.zWhiteboard, at: 6, effectiveRange: nil))
        XCTAssertEqual(Formatting.block(of: back.attributes(at: 6, effectiveRange: nil)), .whiteboard)
    }

    /// Доски из ранней сборки лежали под ключом канбана - при чтении они становятся белыми досками.
    func testOldWhiteboardUnderBoardKeyMigrates() {
        var doc = Formatting.Doc(text: "Схема\n\u{FFFC}")
        var run = Formatting.Run(from: 6, length: 1, block: Block.board.rawValue)
        run.board = Whiteboard().json
        doc.runs = [run]
        let text = Formatting.attributed(doc)
        XCTAssertNotNil(text.attribute(.zWhiteboard, at: 6, effectiveRange: nil))
        XCTAssertNil(text.attribute(.zBoard, at: 6, effectiveRange: nil))
        XCTAssertEqual(Formatting.block(of: text.attributes(at: 6, effectiveRange: nil)), .whiteboard)
    }

    func testKanbanStaysKanban() {
        var doc = Formatting.Doc(text: "План\n\u{FFFC}")
        var run = Formatting.Run(from: 5, length: 1, block: Block.board.rawValue)
        run.board = Board.empty.json
        doc.runs = [run]
        let text = Formatting.attributed(doc)
        XCTAssertNotNil(text.attribute(.zBoard, at: 5, effectiveRange: nil))
        XCTAssertEqual(Formatting.block(of: text.attributes(at: 5, effectiveRange: nil)), .board)
    }
}

final class SearchAndDailyTests: XCTestCase {
    private func note(_ text: String, daily: String? = nil, minutesAgo: Double = 0) -> Note {
        var doc = Formatting.Doc(text: text)
        doc.daily = daily
        return Note(id: UUID().uuidString, doc: doc, modified: Date().addingTimeInterval(-minutesAgo * 60))
    }

    func testSearchNeedsAllWordsAnyOrder() {
        let notes = [note("Покупки\nмолоко и хлеб"), note("Работа\nотчёт")]
        XCTAssertEqual(NoteSearch.search("хлеб молоко", in: notes).count, 1)
        XCTAssertEqual(NoteSearch.search("хлеб отчёт", in: notes).count, 0)
        XCTAssertTrue(NoteSearch.search("", in: notes).isEmpty)
    }

    func testTitleMatchBeatsBodyMatch() {
        let notes = [note("Дневник\nидея про сад", minutesAgo: 0), note("Идея сада\nтекст", minutesAgo: 60)]
        XCTAssertEqual(NoteSearch.search("идея", in: notes).first?.note.title, "Идея сада")
    }

    func testSnippetKeepsContextAroundMatch() {
        let text = String(repeating: "слово ", count: 30) + "нужное" + String(repeating: " хвост", count: 30)
        let snippet = NoteSearch.snippet(text, around: "нужное")
        XCTAssertTrue(snippet.contains("нужное"))
        XCTAssertTrue(snippet.hasPrefix("…") && snippet.hasSuffix("…"))
    }

    func testDayKeyIsStable() {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 10; c.hour = 23
        XCTAssertEqual(Store.dayKey(Calendar.current.date(from: c)!), "2026-10-10")
    }

    func testPinnedAndDailyFieldsSurviveSaveAndLoad() throws {
        var doc = Formatting.Doc(text: "День")
        doc.pinned = true
        doc.daily = "2026-10-10"
        let back = try JSONDecoder().decode(Formatting.Doc.self, from: try JSONEncoder().encode(doc))
        XCTAssertEqual(back.pinned, true)
        XCTAssertEqual(back.daily, "2026-10-10")
        // Старые файлы без этих полей читаются как раньше.
        let old = try JSONDecoder().decode(Formatting.Doc.self, from: Data(#"{"text":"a","runs":[]}"#.utf8))
        XCTAssertNil(old.pinned)
    }
}

final class LinkTests: XCTestCase {
    func testLinkSurvivesSaveAndLoad() {
        let text = NSMutableAttributedString(string: "Смотри Покупки тут")
        text.addAttribute(.zLink, value: "abc", range: NSRange(location: 7, length: 7))
        let doc = Formatting.doc(from: text)
        XCTAssertEqual(doc.runs.first { $0.link == "abc" }?.length, 7)
        let back = Formatting.attributed(doc)
        XCTAssertEqual(back.attribute(.zLink, at: 7, effectiveRange: nil) as? String, "abc")
        XCTAssertNil(back.attribute(.zLink, at: 0, effectiveRange: nil))
    }

    func testLinkIsDrawnUnderlinedButKeepsText() {
        let look = Formatting.visual([.zLink: "abc"])
        XCTAssertNotNil(look[.underlineStyle])
        XCTAssertNotNil(look[.font])
    }
}

final class VaultTests: XCTestCase {
    func testSealAndOpenRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let run = Formatting.Run(from: 0, length: 3, block: Block.title.rawValue)
        let sealed = try XCTUnwrap(Vault.seal(.init(text: "Тайна", runs: [run]), key: key))
        XCTAssertFalse(sealed.contains("Тайна"))
        let back = try XCTUnwrap(Vault.open(sealed, key: key))
        XCTAssertEqual(back.text, "Тайна")
        XCTAssertEqual(back.runs, [run])
    }

    func testWrongKeyCannotOpen() throws {
        let sealed = try XCTUnwrap(Vault.seal(.init(text: "Тайна", runs: []), key: SymmetricKey(size: .bits256)))
        XCTAssertNil(Vault.open(sealed, key: SymmetricKey(size: .bits256)))
        XCTAssertNil(Vault.open("не base64 !!", key: SymmetricKey(size: .bits256)))
    }

    func testClosedNoteHidesTitleUntilUnlocked() {
        var doc = Formatting.Doc(text: "")
        doc.locked = true
        doc.sealed = "x"
        var note = Note(id: "n", doc: doc, modified: Date())
        XCTAssertTrue(note.isClosed)
        XCTAssertEqual(note.title, "Закрытая заметка")
        note.doc.text = "Дневник"
        note.unlocked = true
        XCTAssertFalse(note.isClosed)
        XCTAssertEqual(note.title, "Дневник")
    }
}
