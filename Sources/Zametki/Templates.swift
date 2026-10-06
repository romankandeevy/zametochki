import AppKit

/// Шаблоны страниц: «/шаблон» в тексте или «Новая из шаблона» в меню.
/// Пишутся старой разметкой («# », «- », «[ ] », **жирный**) - она сразу превращается в блоки.
struct Template: Identifiable {
    let id: String
    let name: String
    let symbol: String
    /// В конце - пустая канбан-доска.
    var board = false
    let markdown: (Date) -> String

    func doc(on date: Date = Date()) -> Formatting.Doc {
        // Пустые пункты «-» и «[ ]» без пробела в конце разметкой не считаются - добавляем его.
        let source = markdown(date).split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0 == "-" || $0 == "[ ]" ? String($0) + " " : String($0) }
            .joined(separator: "\n")
        // Тип строки живёт на её переносе: без последнего переноса пустая задача в конце стала бы текстом.
        let doc = Formatting.fromMarkdown(source + "\n")
        guard board else { return doc }
        let text = NSMutableAttributedString(attributedString: Formatting.attributed(doc))
        text.append(Formatting.object([.zBoard: Board.empty.json, .zBlock: Block.board.rawValue]))
        return Formatting.doc(from: text)
    }

    static let all: [Template] = [
        Template(id: "meeting", name: "Встреча", symbol: "person.2") { date in
            """
            # Встреча · \(ruDate(date, "d MMMM"))
            **Кто:**
            **Зачем:**
            ## Обсудили
            -
            ## Решили
            -
            ## Задачи
            [ ]
            """
        },
        Template(id: "week", name: "План недели", symbol: "calendar") { date in
            let calendar = Calendar(identifier: .iso8601)
            let monday = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
            let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
            let header = "# Неделя \(ruDate(monday, "d MMM")) – \(ruDate(days.last ?? monday, "d MMM"))\n## Главное на неделе\n[ ] \n"
            let body = days.map { "## \(ruDate($0, "EEEE, d").capitalized)\n[ ] " }.joined(separator: "\n")
            return header + body
        },
        Template(id: "idea", name: "Идея проекта", symbol: "lightbulb") { _ in
            """
            # Идея:
            > Одним предложением - что это и для кого
            ## Зачем
            -
            ## Как сделать
            -
            ## Первые шаги
            [ ]
            ## Что может пойти не так
            -
            """
        },
        Template(id: "diary", name: "Дневник дня", symbol: "book") { date in
            """
            # \(ruDate(date, "d MMMM, EEEE"))
            ## Что было хорошего
            -
            ## Что понял
            -
            ## Спасибо за
            -
            ## Завтра
            [ ]
            """
        },
        Template(id: "shopping", name: "Список покупок", symbol: "cart") { _ in
            """
            # Покупки
            ## Продукты
            [ ]
            ## Для дома
            [ ]
            """
        },
        Template(id: "kanban", name: "Проект с доской", symbol: "rectangle.split.3x1", board: true) { _ in
            """
            # Проект
            > Цель и срок
            ## Доска
            """
        },
    ]
}

/// Дата по-русски в нужном виде: «6 октября», «понедельник, 6».
private func ruDate(_ date: Date, _ format: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateFormat = format
    return formatter.string(from: date)
}
