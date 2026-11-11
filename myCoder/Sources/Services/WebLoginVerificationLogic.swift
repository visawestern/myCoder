import Foundation

/// Проверка входа веб-провайдера по ЖИВОЙ странице AntiBrowser (решение
/// владельца 11.11.2026).
///
/// Раньше вход подтверждался копированием cookie в `cookies.json` и
/// `session.json` на диск. Эти файлы дублировали то, что и так хранит
/// постоянный профиль AntiBrowser, и могли устареть. Теперь проверка читает
/// cookie текущей вкладки и текст страницы, а в конфигурации остаётся только
/// отметка «вход подтверждён» с временем проверки.
///
/// Устройство — чистая функция без сети и файлов, поэтому её легко тестировать:
/// 1. Экран входа на странице — всегда отказ (даже если осталась старая cookie).
/// 2. Нужна cookie авторизации конкретного сайта, а не любая аналитическая.
/// 3. Свой сайт подтверждается любой непустой cookie.
enum WebLoginVerificationLogic {

    /// Итог живой проверки вкладки.
    enum Verdict: Equatable {
        /// Вход подтверждён.
        case confirmed
        /// Cookie есть, но среди них нет ни одной авторизационной.
        case missingAuthCookie
        /// Страница показывает экран входа.
        case loginWall
    }

    /// Cookie, которые сайт ставит только после успешного входа. Список
    /// собран по живым сайтам (аудит 2026-09-08) и не является догадкой.
    ///
    /// Вход: сайт. Выход: имена cookie (совпадение по префиксу). Зависимости: нет.
    static func authCookieNames(for vendor: WebChatVendor) -> [String] {
        switch vendor {
        case .kimi: return ["kimi-auth", "access_token", "refresh_token"]
        case .qwen: return ["token", "chatqa_uat", "tongyi_sso_ticket"]
        case .chatgpt: return ["__Secure-next-auth.session-token"]
        case .claude: return ["sessionKey", "__Secure-next-auth.session-token", "kimi-auth"]
        case .custom: return []
        }
    }

    /// Есть ли среди cookie хотя бы одна авторизационная.
    ///
    /// Вход: сайт и cookie вкладки. Выход: true, если вход подтверждён cookie.
    /// Свой сайт (`custom`) подтверждается любой непустой cookie.
    /// Зависимости: нет.
    static func hasAuthCookie(vendor: WebChatVendor, cookies: [BrowserCookie]) -> Bool {
        guard !cookies.isEmpty else { return false }
        if vendor == .custom { return true }
        let required = authCookieNames(for: vendor)
        return cookies.contains { cookie in
            required.contains { cookie.name == $0 || cookie.name.hasPrefix($0) }
        }
    }

    /// Признаки экрана входа в тексте страницы. Только явные призывы войти:
    /// слово «вход» в обычном чате не должно блокировать подтверждение.
    ///
    /// Вход: текст страницы. Выход: true, если виден экран входа.
    /// Зависимости: нет.
    static func isLoginWall(pageText: String) -> Bool {
        let lower = pageText.lowercased()
        let markers = [
            "войдите в систему", "зарегистрироваться бесплатно", "войти в систему",
            "log in to continue", "sign up free", "create an account",
            "continue with google", "войти через google"
        ]
        return markers.contains { lower.contains($0) }
    }

    /// Полный вердикт по живой вкладке.
    ///
    /// Вход: сайт, cookie вкладки и текст страницы. Выход: вердикт.
    /// Зависимости: нет.
    static func verdict(vendor: WebChatVendor,
                        cookies: [BrowserCookie],
                        pageText: String) -> Verdict {
        if isLoginWall(pageText: pageText) { return .loginWall }
        if hasAuthCookie(vendor: vendor, cookies: cookies) { return .confirmed }
        return .missingAuthCookie
    }

    /// Понятное сообщение для интерфейса.
    ///
    /// Вход: вердикт. Выход: текст на русском. Зависимости: нет.
    static func message(for verdict: Verdict) -> String {
        switch verdict {
        case .confirmed:
            return "Вход подтверждён: страница вошла в аккаунт."
        case .missingAuthCookie:
            return "Вход не подтверждён: на странице нет cookie авторизации. Войдите в аккаунт и повторите проверку."
        case .loginWall:
            return "Страница показывает экран входа. Войдите в аккаунт и повторите проверку."
        }
    }
}
