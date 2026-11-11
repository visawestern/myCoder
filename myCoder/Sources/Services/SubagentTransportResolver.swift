import Foundation

/// Решает транспорт субагента по правилам маршрутизации моделей (M1).
///
/// - Одиночный режим («одна модель для всего»): субагент **наследует**
///   транспорт вызывающей модели — тот же провайдер/модель, что у родительского
///   чата.
/// - Режим маршрутов (per-role): субагент — исследовательская работа и
///   выполняется на роли `ModelRole.research`; если её назначение даёт прямую
///   OpenAI-совместимую модель — используется она. Любой другой транспорт
///   (веб, serve, ACP, неразрешённый) — явный `.unsupported` с причиной,
///   никогда не подмена другим провайдером.
///
/// Чистый тип без зависимостей от UI: переносим, тестируем и держится в
/// отдельном файле (модульность).
enum SubagentTransportResolver {

    /// Роль, которая задаёт модель субагента в режиме маршрутов.
    static let role = ModelRole.research

    /// Возвращает транспорт субагента по конфигурации маршрутов.
    ///
    /// Вход: конфигурация маршрутов, первичное назначение композера, снимок
    /// каталога провайдеров, транспорт родителя (fallback). Выход: транспорт
    /// субагента. Зависимости: `ModelRouteResolver`, `RoleTransportResolver`.
    static func transport(configuration: ModelRoutingConfiguration,
                          primary: ModelAssignment,
                          context: RoleTransportContext,
                          fallback: SubagentRunner.Transport) -> SubagentRunner.Transport {
        guard configuration.mode == .perRole else { return fallback }
        let resolver = ModelRouteResolver(configuration: configuration, primary: primary)
        guard let assignment = resolver.assignment(for: role),
              case .openAICompatible(let baseURL, let apiKey, let model) =
                RoleTransportResolver.kind(for: assignment, context: context),
              let url = URL(string: baseURL) else {
            return .unsupported(reason: "Субагентам в режиме маршрутов нужна прямая OpenAI-совместимая модель для роли «Context research». Текущее назначение роли не поддерживает такой транспорт.")
        }
        return .openAICompatible(baseURL: url, apiKey: apiKey ?? "", model: model)
    }
}
