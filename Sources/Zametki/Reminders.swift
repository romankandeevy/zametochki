import AppKit
import UserNotifications

/// Напоминания у задач: «[] позвонить маме @завтра 10:00» - в это время придёт уведомление macOS.
/// Понимает @сегодня, @завтра, @послезавтра, дни недели (@пн … @вс), даты (@15.10, @15.10.2026)
/// и время (@18:30 или после дня: @пт 9:00). Без времени - в 9:00. Отмеченная задача напоминание снимает.
enum Reminders {
    static let defaultHour = 9

    private static let pattern = try! NSRegularExpression(
        pattern: #"@(?:(сегодня|завтра|послезавтра|пн|вт|ср|чт|пт|сб|вс|\d{1,2}\.\d{1,2}(?:\.\d{2,4})?)(?![\p{L}\d])(?:\s+(?:в\s+)?(\d{1,2}):(\d{2}))?|(\d{1,2}):(\d{2}))"#,
        options: [.caseInsensitive])

    private static let weekdays = ["вс": 1, "пн": 2, "вт": 3, "ср": 4, "чт": 5, "пт": 6, "сб": 7]

    /// Первая отметка времени в строке: где она стоит и на когда. nil - отметки нет или дата непонятная.
    static func find(in line: String, now: Date = Date()) -> (range: NSRange, date: Date)? {
        let ns = line as NSString
        guard let match = pattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> String? {
            let r = match.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r).lowercased()
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var hour = defaultHour, minute = 0
        if let h = group(2).flatMap(Int.init), let m = group(3).flatMap(Int.init) { hour = h; minute = m }
        if let h = group(4).flatMap(Int.init), let m = group(5).flatMap(Int.init) { hour = h; minute = m }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }

        func at(_ day: Date) -> Date? { calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) }

        var date: Date?
        if let word = group(1) {
            switch word {
            case "сегодня": date = at(today)
            case "завтра": date = calendar.date(byAdding: .day, value: 1, to: today).flatMap(at)
            case "послезавтра": date = calendar.date(byAdding: .day, value: 2, to: today).flatMap(at)
            default:
                if let weekday = weekdays[word] {
                    // Ближайший такой день; сегодня - только если время ещё не прошло.
                    let current = calendar.component(.weekday, from: today)
                    var ahead = (weekday - current + 7) % 7
                    if ahead == 0, let candidate = at(today), candidate <= now { ahead = 7 }
                    date = calendar.date(byAdding: .day, value: ahead, to: today).flatMap(at)
                } else {
                    let parts = word.split(separator: ".").compactMap { Int($0) }
                    guard parts.count >= 2 else { return nil }
                    var components = DateComponents()
                    components.day = parts[0]
                    components.month = parts[1]
                    components.hour = hour
                    components.minute = minute
                    if parts.count == 3 {
                        components.year = parts[2] < 100 ? 2000 + parts[2] : parts[2]
                        date = calendar.date(from: components)
                    } else {
                        // Без года: ближайшая такая дата впереди.
                        components.year = calendar.component(.year, from: now)
                        date = calendar.date(from: components)
                        if let d = date, d <= now {
                            components.year = (components.year ?? 0) + 1
                            date = calendar.date(from: components)
                        }
                    }
                    // 31.02 и подобное календарь «переносит» - такую дату не принимаем.
                    if let d = date, calendar.component(.day, from: d) != parts[0] { return nil }
                }
            }
        } else {
            // Только время: сегодня, а если уже прошло - завтра.
            date = at(today)
            if let d = date, d <= now { date = calendar.date(byAdding: .day, value: 1, to: today).flatMap(at) }
        }
        guard let date else { return nil }
        return (match.range, date)
    }

    // MARK: подсветка в тексте

    static let tint = NSColor(srgbRed: 1, green: 0.86, blue: 0.45, alpha: 1)

    /// Отметка времени в задаче видна сразу: тёплым цветом и подложкой. Только внешний вид - в файл не идёт.
    static func highlight(_ storage: NSTextStorage) {
        let ns = storage.string as NSString
        guard ns.range(of: "@").location != NSNotFound else { return }
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs]) { text, range, enclosing, _ in
            guard let text, text.contains("@"), enclosing.length > 0,
                  Formatting.block(of: storage.attributes(at: NSMaxRange(enclosing) - 1, effectiveRange: nil)) == .todo,
                  let found = find(in: text) else { return }
            let token = NSRange(location: range.location + found.range.location, length: found.range.length)
            storage.addAttribute(.foregroundColor, value: tint, range: token)
            storage.addAttribute(.backgroundColor, value: tint.withAlphaComponent(0.16), range: token)
        }
    }

    // MARK: уведомления

    private static var pending: DispatchWorkItem?
    private static var asked = false
    static let prefix = "zametki|"

    /// Пересобрать уведомления по всем заметкам - не на каждую букву, а через секунду тишины.
    static func sync(_ store: Store) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak store] in
            guard let store else { return }
            schedule(collect(store))
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private struct Item {
        let id: String
        let note: String
        let title: String
        let subtitle: String
        let date: Date
    }

    private static func collect(_ store: Store) -> [Item] {
        let now = Date()
        var items: [Item] = []
        for note in store.notes where note.text.contains("@") {
            let storage = Formatting.attributed(note.doc)
            let ns = storage.string as NSString
            ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs]) { text, _, enclosing, _ in
                guard let text, text.contains("@"), enclosing.length > 0,
                      Formatting.block(of: storage.attributes(at: NSMaxRange(enclosing) - 1, effectiveRange: nil)) == .todo,
                      let found = find(in: text, now: now), found.date > now else { return }
                let task = (text as NSString).replacingCharacters(in: found.range, with: "")
                    .replacingOccurrences(of: "  ", with: " ")
                    .trimmingCharacters(in: .whitespaces)
                let id = prefix + note.id + "|" + String(Int(found.date.timeIntervalSince1970)) + "|" + task
                items.append(Item(id: id, note: note.id, title: task.isEmpty ? "Напоминание" : task,
                                  subtitle: note.title, date: found.date))
            }
        }
        return items
    }

    private static func schedule(_ items: [Item]) {
        // Уведомления есть только у настоящего .app (не у «swift run» и тестов) - иначе система роняет процесс.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let center = UNUserNotificationCenter.current()
        let wanted = Set(items.map(\.id))
        center.getPendingNotificationRequests { requests in
            let existing = Set(requests.map(\.identifier).filter { $0.hasPrefix(prefix) })
            let stale = existing.subtracting(wanted)
            if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: Array(stale)) }
            let fresh = items.filter { !existing.contains($0.id) }
            guard !fresh.isEmpty else { return }
            DispatchQueue.main.async {
                // Разрешение спрашиваем один раз - когда появилось первое напоминание.
                let add = {
                    for item in fresh {
                        let content = UNMutableNotificationContent()
                        content.title = item.title
                        content.subtitle = item.subtitle
                        content.sound = .default
                        content.userInfo = ["note": item.note]
                        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
                        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                        center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
                    }
                }
                if asked { return add() }
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    DispatchQueue.main.async {
                        asked = true
                        if granted { add() } else { AppDelegate.store?.say("Напоминания выключены в настройках уведомлений macOS") }
                    }
                }
            }
        }
    }
}
