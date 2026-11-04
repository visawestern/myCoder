import Foundation

/// A real graph relation encountered by the bounded impact traversal.
struct ImpactDependency: Equatable, Sendable {
    let name: String
    let kind: String
    let path: String
    let startLine: Int?
    let endLine: Int?
    let edge: CodeEdgeKind
    let confidence: CodeEdgeConfidence
    let depth: Int
    let isTest: Bool
    var sourceLabel: String = ""
    var targetLabel: String = ""
    var isOutgoing: Bool = false
}

struct ImpactFate: Equatable, Sendable {
    let dependency: ImpactDependency
    let question: String
}

/// Questions remain useful when the index has not located a seed or relation:
/// absence of graph evidence must never become a claim of no dependencies.
struct ImpactReport: Equatable, Sendable {
    let triggers: [String]
    let affected: [CodeSymbol]
    let dependents: [ImpactDependency]
    let fates: [ImpactFate]
    let order: [String]
    let questions: [String]
    let refs: [TaskReference]
    var depthLimit: Int = 2
    var relationLimit: Int = 12

    var isEmpty: Bool { dependents.isEmpty && questions.isEmpty }

    func section() -> ContextSection {
        var lines: [String] = []
        if !triggers.isEmpty {
            lines.append("Признаки изменения в запросе: \(triggers.joined(separator: ", ")).")
        }
        lines.append("Обход входящих и исходящих связей: глубина: \(depthLimit); лимит связей: \(relationLimit).")
        lines.append("Это ограниченный срез; полнота графа не гарантирована. За его границами продолжи поиск по коду и данным, прежде чем объявить работу завершённой.")
        if affected.isEmpty {
            lines.append("Ядро задачи не найдено в индексе — уточни символы поиском. Это не доказывает отсутствие зависимостей.")
        } else {
            lines.append("Кандидаты ядра (релевантность нужно проверить): " + affected.map {
                "\($0.path):\($0.startLine)-\($0.endLine) \($0.name)"
            }.joined(separator: "; "))
        }
        if dependents.isEmpty {
            lines.append("Подтверждённых связей в выбранном срезе нет. Это не доказывает отсутствие зависимостей: проверь вызовы, чтение/запись состояния, привязки UI, конфигурацию и документацию поиском.")
        }
        lines.append("")
        lines.append("Порядок работы, если запрос требует изменения кода:")
        lines += order.map { "  \($0)" }
        if !fates.isEmpty {
            lines.append("")
            lines.append("Связи и решение по каждой:")
            for fate in fates {
                let dependency = fate.dependency
                let relation: String
                if !dependency.sourceLabel.isEmpty && !dependency.targetLabel.isEmpty {
                    relation = "\(dependency.sourceLabel) → \(dependency.targetLabel)"
                } else {
                    let location = dependency.startLine.map { ":\($0)" } ?? ""
                    relation = "\(dependency.path)\(location) \(dependency.name)"
                }
                let confidence = dependency.confidence == .heuristic
                    ? "heuristic; гипотеза — проверь по исходникам"
                    : dependency.confidence.rawValue
                lines.append("  - \(relation) [\(dependency.edge.rawValue), \(confidence); глубина \(dependency.depth)]: \(fate.question)")
            }
        }
        lines.append("")
        lines.append("Вспомогательные вопросы (проверь доказательствами, не считай предположения фактами):")
        lines += questions.map { "  - \($0)" }
        return ContextSection(title: "Вопросы харнесса о зависимостях", body: lines.joined(separator: "\n"))
    }
}

/// The impact pass uses the same source extraction and relation builder as the
/// persisted code index; unresolved links never become context evidence.
struct ImpactGraph: Equatable, Sendable {
    let symbolsByID: [String: CodeSymbol]
    let edges: [CodeEdge]

    static let empty = ImpactGraph(symbolsByID: [:], edges: [])

    static func build(extractions: [CodeFileExtraction]) -> ImpactGraph {
        var symbols: [String: CodeSymbol] = [:]
        for extraction in extractions {
            for symbol in extraction.symbols { symbols[symbol.id] = symbol }
        }
        return ImpactGraph(symbolsByID: symbols, edges: CodeGraphBuilder.build(files: extractions))
    }
}

enum ImpactAnalyzer {
    /// These describe the request; they never gate the review itself.
    static let changeMarkers: [String] = [
        "удал", "убер", "убра", "замен", "передел", "перенес", "перееха", "перемест",
        "отказ", "больше не", "не нужен", "не нужна", "не нужно", "устарел", "мёртв", "мертв",
        "remove", "delete", "replace", "migrate", "refactor", "deprecat", "drop ", "rename"
    ]
    static let maxDepth = 3

    static func triggers(message: String, intent: LocalQueryIntent? = nil) -> [String] {
        let lower = message.lowercased()
        var result = changeMarkers.filter { lower.contains($0) }
        if intent == .refactor, result.isEmpty { result.append("намерение: refactor") }
        return result
    }

    /// Every nonblank project request receives questions. A model's intent or
    /// a keyword can describe the review, but neither can suppress it.
    static func analyze(message: String,
                        seeds: [CodeSymbol],
                        graph: ImpactGraph,
                        intent: LocalQueryIntent? = nil,
                        depth: Int = 2,
                        maxDependents: Int = 12) -> ImpactReport? {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var seedIDs = Set<String>()
        let affected = seeds.filter { seedIDs.insert($0.id).inserted }
        let hops = max(0, min(depth, maxDepth))
        let cap = max(0, maxDependents)
        // Import relations connect file nodes rather than function symbols.
        // Include each seed's file as a root without treating all declarations
        // in that file as callers or callees.
        var frontier: [String] = []
        var visited = Set<String>()
        for seed in affected {
            for id in [seed.id, CodeNode.file(seed.path)] where visited.insert(id).inserted {
                frontier.append(id)
            }
        }
        var found: [ImpactDependency] = []
        var seenRelations = Set<String>()
        var currentDepth = 0
        while currentDepth < hops, !frontier.isEmpty, found.count < cap {
            currentDepth += 1
            var next: [String] = []
            for nodeID in frontier {
                let relations = graph.edges.filter {
                    ($0.from == nodeID || $0.to == nodeID)
                        && $0.kind != .declares && $0.kind != .contains
                        && $0.confidence != .unresolved
                }.sorted(by: edgeOrder)
                for edge in relations {
                    let key = "\(edge.kind.rawValue)|\(edge.from)|\(edge.to)"
                    guard seenRelations.insert(key).inserted else { continue }
                    let otherID = edge.from == nodeID ? edge.to : edge.from
                    guard let other = node(otherID, graph: graph),
                          let source = node(edge.from, graph: graph),
                          let target = node(edge.to, graph: graph) else { continue }
                    found.append(ImpactDependency(
                        name: other.name, kind: other.kind, path: other.path,
                        startLine: other.startLine, endLine: other.endLine,
                        edge: edge.kind, confidence: edge.confidence, depth: currentDepth,
                        isTest: CodeIndexExtractor.isTestPath(other.path),
                        sourceLabel: source.label, targetLabel: target.label,
                        isOutgoing: edge.from == nodeID
                    ))
                    if visited.insert(otherID).inserted { next.append(otherID) }
                    if found.count >= cap { break }
                }
                if found.count >= cap { break }
            }
            frontier = next
        }
        let fates = found.map {
            ImpactFate(dependency: $0, question: "обновить / удалить / оставить — реши явно и обоснуй исходниками; удаляй только после проверки всех потребителей")
        }
        return ImpactReport(
            triggers: triggers(message: message, intent: intent),
            affected: affected, dependents: found, fates: fates,
            order: changeOrder(core: affected), questions: questions(for: found),
            refs: references(for: found, seeds: affected),
            depthLimit: hops, relationLimit: cap
        )
    }

    static func changeOrder(core: [CodeSymbol]) -> [String] {
        let names = core.isEmpty ? "найденный механизм" : core.map(\.name).joined(separator: ", ")
        return [
            "1. Сначала тест на требуемое поведение и последствия для потребителей; выполни его и зафиксируй красный результат.",
            "2. Уточни контракт и совместимость: входы, выходы, состояние, хранение и миграцию данных.",
            "3. Измени ядро: \(names), опираясь на новый контракт и тест.",
            "4. Пройди каждую входящую и исходящую связь; проверь вызывающий код и вызываемые функции, реши: обновить / удалить / оставить.",
            "5. Проверь UI/настройки, старые параметры и мёртвый код; удаляй только то, чья ненужность подтверждена по всем потребителям.",
            "6. Получи зелёные тесты, выполни регрессию затронутой цепочки и обнови документацию; отдельно назови непроверенные границы."
        ]
    }

    static func questions(for dependents: [ImpactDependency]) -> [String] {
        var result = [
            "Нужны ли правки по запросу, или достаточно объяснения? Для вопроса об устройстве кода выполни анализ без изменения файлов.",
            "Как изменится контракт и что произойдёт с вызывающим кодом и вызываемыми функциями по всей цепочке? Какие связи требуют обновления, удаления или сохранения?",
            "Проведи поиск ссылок в UI и настройках, включая чтение/запись состояния и привязки, которые граф вызовов может не видеть. Если путь хранения или выбор папки теряет смысл, остались ли экспорт, кэш, резервное копирование или другие потребители? Пока это не доказано, не объявляй настройку ненужной.",
            "Нужны ли миграция сохранённых настроек/данных, очистка старого формата, совместимость API и изменение обработки ошибок?",
            "Какие тесты докажут новое поведение и отсутствие регрессий во всей затронутой цепочке? Какую документацию, примеры и подсказки нужно обновить?"
        ]
        let uiPaths = uniquePaths(dependents.filter {
            let path = $0.path.lowercased()
            return path.contains("view") || path.contains("ui/") || path.contains("setting") || $0.name.lowercased().hasSuffix("view")
        })
        if !uiPaths.isEmpty {
            result.append("Какие разделы UI/настроек связаны с механизмом и сохраняют смысл? Проверь конкретные файлы: " + uiPaths.joined(separator: ", "))
        }
        let testPaths = uniquePaths(dependents.filter(\.isTest))
        if !testPaths.isEmpty {
            result.append("Какие существующие тесты нужно дополнить перед правками? Проверь: " + testPaths.joined(separator: ", "))
        }
        if dependents.contains(where: { $0.kind == "var" }) {
            result.append("Кто ещё читает или пишет это состояние? Проверь каждое чтение и каждую запись.")
        }
        return result
    }

    /// Keep a same-file caller's symbol: the seed's materialized block may not
    /// contain it. Only an exact seed symbol/range is already represented.
    static func references(for dependents: [ImpactDependency],
                           seeds: [CodeSymbol],
                           limit: Int = 8) -> [TaskReference] {
        guard limit > 0 else { return [] }
        var result: [TaskReference] = []
        var seen = Set<String>()
        for dependency in dependents {
            if seeds.contains(where: {
                $0.path == dependency.path && $0.name == dependency.name
                    && $0.startLine == dependency.startLine && $0.endLine == dependency.endLine
            }) { continue }
            let key = "\(dependency.path)|\(dependency.name)|\(dependency.startLine ?? 0)|\(dependency.endLine ?? 0)"
            guard seen.insert(key).inserted else { continue }
            result.append(TaskReference(
                path: dependency.path, symbol: dependency.kind == "file" ? nil : dependency.name,
                startLine: dependency.kind == "file" ? 1 : dependency.startLine,
                endLine: dependency.endLine, why: "зависимость: \(dependency.edge.rawValue), \(dependency.confidence.rawValue)"
            ))
            if result.count >= limit { break }
        }
        return result
    }

    /// Refresh first: a snapshot read before indexing is empty on the first
    /// send and stale on later sends. Semantic terms widen, never replace,
    /// the user's deterministic query.
    static func report(projectPath: String,
                       message: String,
                       query: String,
                       records: [FileIndexRecord],
                       intent: LocalQueryIntent? = nil,
                       semanticTerms: [String] = [],
                       depth: Int = 2,
                       maxDependents: Int = 12) throws -> ImpactReport? {
        guard !projectPath.isEmpty,
              !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let store = try CodeIndexStore.open(projectPath: projectPath)
        // Live API audit 2026-11-04: re-indexing the entire project on every
        // turn made `context-preview` take ~20 s just here (and the planner's
        // graph call another ~20 s). The store is maintained by the FSEvents
        // watcher / explicit ensureIndexed; a read-only impact analysis only
        // needs a first build when the store is completely empty.
        if (try? store.counts().symbols == 0) == true {
            _ = try CodeIndexService.ensureIndexed(projectPath: projectPath, records: records)
        }
        let graph = ImpactGraph.build(extractions: try store.allActiveExtractions())
        let searchQuery = ([query] + semanticTerms).joined(separator: " ")
        let seeds = try store.search(query: searchQuery, limit: 6)
        return analyze(message: message, seeds: seeds, graph: graph, intent: intent, depth: depth, maxDependents: maxDependents)
    }

    private struct GraphNode {
        let name: String
        let kind: String
        let path: String
        let startLine: Int?
        let endLine: Int?
        var label: String {
            guard let startLine, let endLine else { return "\(path) \(name)" }
            return "\(path):\(startLine)-\(endLine) \(name)"
        }
    }

    private static func node(_ id: String, graph: ImpactGraph) -> GraphNode? {
        if let symbol = graph.symbolsByID[id] {
            return GraphNode(name: symbol.name, kind: symbol.kind, path: symbol.path,
                             startLine: symbol.startLine, endLine: symbol.endLine)
        }
        if let path = CodeNode.filePath(of: id) {
            return GraphNode(name: (path as NSString).lastPathComponent, kind: "file", path: path,
                             startLine: nil, endLine: nil)
        }
        return nil
    }

    private static func edgeOrder(_ left: CodeEdge, _ right: CodeEdge) -> Bool {
        if left.confidence.rank != right.confidence.rank { return left.confidence.rank > right.confidence.rank }
        if left.kind.rawValue != right.kind.rawValue { return left.kind.rawValue < right.kind.rawValue }
        if left.from != right.from { return left.from < right.from }
        return left.to < right.to
    }

    private static func uniquePaths(_ dependencies: [ImpactDependency]) -> [String] {
        var result: [String] = []
        for dependency in dependencies where !result.contains(dependency.path) { result.append(dependency.path) }
        return result
    }
}
