import AppKit

/// Язык блока кода: выбран вручную или угадан по тексту («Авто»).
enum CodeLanguage: String, CaseIterable {
    case swift, python, javascript, typescript, html, css, json, bash, sql, go, rust, kotlin, java, c, cpp, ruby, php, plain

    var name: String {
        switch self {
        case .swift: "Swift"
        case .python: "Python"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .html: "HTML"
        case .css: "CSS"
        case .json: "JSON"
        case .bash: "Bash"
        case .sql: "SQL"
        case .go: "Go"
        case .rust: "Rust"
        case .kotlin: "Kotlin"
        case .java: "Java"
        case .c: "C"
        case .cpp: "C++"
        case .ruby: "Ruby"
        case .php: "PHP"
        case .plain: "Текст"
        }
    }

    /// Угадать язык по тексту - простые приметы, без сети и моделей.
    static func detect(_ code: String) -> CodeLanguage {
        let t = code
        func has(_ s: String) -> Bool { t.contains(s) }
        if has("import SwiftUI") || has("import Foundation") || has("import Playgrounds") || (has("func ") && (has("let ") || has("var ")) && has("{")) || has("guard let") { return .swift }
        if has("<html") || has("<div") || has("</") && has(">") && has("<") { return .html }
        if has("#include") { return has("std::") || has("cout") || has("class ") ? .cpp : .c }
        if has("<?php") { return .php }
        if has("fn ") && (has("let mut") || has("->") || has("println!")) { return .rust }
        if has("package main") || (has("func ") && has(":=")) { return .go }
        if has("fun ") && (has("val ") || has("println(")) { return .kotlin }
        if has("public class") || has("System.out") || has("public static void") { return .java }
        if has("def ") && has(":") || has("import ") && !has("{") && !has(";") || has("print(") && !has("{") { return .python }
        if has("interface ") && has(": ") || has(": string") || has(": number") { return .typescript }
        if has("const ") || has("=>") || has("function ") || has("console.log") || has("let ") && has(";") { return .javascript }
        if has("SELECT ") || has("select ") && has(" from ") || has("INSERT INTO") || has("CREATE TABLE") { return .sql }
        if has("#!/bin/") || has("echo ") || has("$ ") || has("sudo ") || has("brew ") || has("cd ") && !has("{") { return .bash }
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")) && has("\":") { return .json }
        if has("{") && has(":") && has(";") && !has("(") { return .css }
        if has("end") && has("def ") || has("puts ") { return .ruby }
        return .plain
    }

    var keywords: Set<String> {
        switch self {
        case .swift: ["func", "let", "var", "if", "else", "guard", "return", "struct", "class", "enum", "case", "switch", "for", "in", "while", "import", "private", "public", "static", "self", "Self", "true", "false", "nil", "init", "extension", "protocol", "some", "any", "async", "await", "throws", "try", "do", "catch", "where", "override", "final", "lazy", "weak", "default", "break", "continue", "repeat", "inout", "mutating"]
        case .python: ["def", "class", "if", "elif", "else", "for", "while", "in", "return", "import", "from", "as", "with", "try", "except", "finally", "raise", "lambda", "yield", "pass", "break", "continue", "and", "or", "not", "is", "None", "True", "False", "async", "await", "global", "self"]
        case .javascript, .typescript: ["const", "let", "var", "function", "return", "if", "else", "for", "while", "of", "in", "new", "class", "extends", "import", "from", "export", "default", "async", "await", "try", "catch", "throw", "this", "true", "false", "null", "undefined", "typeof", "switch", "case", "break", "interface", "type", "implements", "enum", "public", "private", "readonly"]
        case .go: ["func", "package", "import", "var", "const", "type", "struct", "interface", "map", "chan", "go", "defer", "return", "if", "else", "for", "range", "switch", "case", "default", "nil", "true", "false", "break", "continue", "select"]
        case .rust: ["fn", "let", "mut", "pub", "struct", "enum", "impl", "trait", "use", "mod", "match", "if", "else", "for", "in", "while", "loop", "return", "self", "Self", "true", "false", "as", "ref", "move", "async", "await", "where", "const", "static", "crate"]
        case .kotlin: ["fun", "val", "var", "class", "object", "interface", "if", "else", "when", "for", "while", "return", "import", "package", "private", "public", "override", "null", "true", "false", "this", "in", "is", "data", "suspend"]
        case .java: ["public", "private", "protected", "class", "interface", "static", "final", "void", "int", "long", "double", "boolean", "new", "return", "if", "else", "for", "while", "import", "package", "extends", "implements", "this", "null", "true", "false", "try", "catch", "throw", "throws"]
        case .c, .cpp: ["int", "char", "float", "double", "void", "long", "short", "unsigned", "const", "static", "struct", "return", "if", "else", "for", "while", "do", "switch", "case", "break", "continue", "include", "define", "typedef", "sizeof", "class", "public", "private", "namespace", "using", "new", "delete", "template", "auto", "nullptr", "true", "false", "std"]
        case .ruby: ["def", "end", "class", "module", "if", "elsif", "else", "unless", "do", "while", "return", "require", "self", "nil", "true", "false", "puts", "yield", "and", "or", "not", "attr_accessor"]
        case .php: ["function", "echo", "return", "if", "else", "foreach", "as", "class", "public", "private", "new", "array", "null", "true", "false", "use", "namespace"]
        case .sql: ["select", "from", "where", "insert", "into", "values", "update", "set", "delete", "create", "table", "drop", "alter", "join", "left", "right", "inner", "on", "and", "or", "not", "null", "order", "by", "group", "having", "limit", "as", "primary", "key", "distinct", "count"]
        case .bash: ["if", "then", "else", "fi", "for", "do", "done", "while", "case", "esac", "function", "return", "export", "echo", "cd", "sudo", "brew", "git", "npm", "local", "in"]
        case .css: ["important"]
        case .html, .json, .plain: []
        }
    }

    var lineComment: String? {
        switch self {
        case .python, .bash, .ruby: "#"
        case .sql: "--"
        case .html, .json, .plain, .css: nil
        default: "//"
        }
    }
}

/// Раскраска кода: ключевые слова, строки, числа, комментарии, типы. Цвета мягкие - под тёмную подложку.
enum CodeHighlight {
    static let keyword = NSColor(srgbRed: 1.0, green: 0.48, blue: 0.72, alpha: 1)
    static let string = NSColor(srgbRed: 0.98, green: 0.80, blue: 0.48, alpha: 1)
    static let number = NSColor(srgbRed: 0.74, green: 0.62, blue: 1.0, alpha: 1)
    static let comment = NSColor(white: 1, alpha: 0.42)
    static let type = NSColor(srgbRed: 0.45, green: 0.86, blue: 0.96, alpha: 1)
    static let tag = NSColor(srgbRed: 1.0, green: 0.55, blue: 0.55, alpha: 1)

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let strings = regex(#""(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`"#)
    private static let numbers = regex(#"\b\d+(?:\.\d+)?\b"#)
    private static let words = regex(#"\b[A-Za-z_][A-Za-z0-9_]*\b"#)
    private static let blockComments = regex(#"/\*[\s\S]*?\*/|<!--[\s\S]*?-->"#)
    private static let tags = regex(#"</?[A-Za-z][A-Za-z0-9-]*|/?>"#)
    private static let cssProps = regex(#"[a-z-]+(?=\s*:)"#)

    /// Покрасить кусок текста (весь блок кода) в storage.
    static func apply(_ storage: NSTextStorage, range: NSRange, language: CodeLanguage) {
        guard range.length > 0, language != .plain else { return }
        let text = (storage.string as NSString).substring(with: range) as NSString
        func paint(_ r: NSRange, _ color: NSColor) {
            storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: range.location + r.location, length: r.length))
        }
        let all = NSRange(location: 0, length: text.length)
        let keywords = language.keywords
        let caseInsensitive = language == .sql
        if language == .html {
            tags.enumerateMatches(in: text as String, range: all) { m, _, _ in if let m { paint(m.range, tag) } }
        }
        if language == .css {
            cssProps.enumerateMatches(in: text as String, range: all) { m, _, _ in if let m { paint(m.range, type) } }
        }
        words.enumerateMatches(in: text as String, range: all) { m, _, _ in
            guard let m else { return }
            let word = text.substring(with: m.range)
            if keywords.contains(caseInsensitive ? word.lowercased() : word) {
                paint(m.range, keyword)
            } else if let first = word.first, first.isUppercase, language != .sql, language != .json {
                paint(m.range, type)
            }
        }
        numbers.enumerateMatches(in: text as String, range: all) { m, _, _ in if let m { paint(m.range, number) } }
        // Строки и комментарии - поверх всего остального.
        strings.enumerateMatches(in: text as String, range: all) { m, _, _ in if let m { paint(m.range, string) } }
        if let line = language.lineComment {
            let pattern = NSRegularExpression.escapedPattern(for: line) + ".*$"
            regex(pattern, [.anchorsMatchLines]).enumerateMatches(in: text as String, range: all) { m, _, _ in
                if let m { paint(m.range, comment) }
            }
        }
        blockComments.enumerateMatches(in: text as String, range: all) { m, _, _ in if let m { paint(m.range, comment) } }
    }
}
