import Foundation

/// Таксономия бэкендов, с которыми работают интеграционные тесты.
///
/// Классы (по именам Suite, фильтрация через `swift test --filter`):
/// - `LiveLocalOllamaModelTests` — локальная модель (Ollama) на этой машине;
/// - `LiveOpenAICompatibleModelTests` — удалённый OpenAI-совместимый провайдер;
/// - `LiveAPIIntegrationTests` — локальный `opencode serve`;
/// - `LiveIntegrationTests` — MiMo Serve;
/// - `LiveClipboardProbeTests`, `LiveImageSendVerificationTests` — системные;
/// - все остальные — unit (без внешних зависимостей).
///
/// STRATA сознательно НЕ поддержана (пользователь: «мой ноутбук не потянет»).
enum BackendKind {
    static let localModel = "backend.localModel"
    static let openAICompatible = "backend.openAICompatible"
    static let webProvider = "backend.webProvider"
    static let openCodeServe = "backend.openCodeServe"
    static let mimoServe = "backend.mimoServe"
    static let system = "backend.system"
    static let requiresNetwork = "backend.requiresNetwork"
}

/// Единый opt-in-флаг для живых интеграционных тестов.
/// Запуск: MIMO_LIVE_TESTS=1 swift test
var liveTestsEnabled: Bool {
    ["MIMO_LIVE_TESTS", "MYCODER_LIVE_TESTS"].contains {
        ProcessInfo.processInfo.environment[$0] == "1"
    }
}

/// Доступность модели на Ollama (порт 11434). Локальная модель может быть
/// не загружена — тест честно сообщает об этом вместо провала.
func ollamaReachable(modelContaining fragment: String) -> Bool {
    guard let url = URL(string: "http://127.0.0.1:11434/api/tags"),
          let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let models = json["models"] as? [[String: Any]] else {
        return false
    }
    return models.contains { (($0["name"] as? String) ?? "").contains(fragment) }
}
