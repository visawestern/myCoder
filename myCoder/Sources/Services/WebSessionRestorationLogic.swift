import Foundation

struct WebSessionRestorationPayload: Equatable {
    let cookies: [BrowserCookie]
    let localStorage: [String: String]
}

enum WebSessionRestorationStep: Equatable {
    case setCookies
    case navigateToTarget
    case setLocalStorage
    case reloadTarget
}

enum WebSessionRestorationLogic {
    static func payload(from store: WebSessionStore) -> WebSessionRestorationPayload {
        WebSessionRestorationPayload(cookies: store.cookies, localStorage: store.localStorage)
    }

    static func steps(from store: WebSessionStore) -> [WebSessionRestorationStep] {
        var steps: [WebSessionRestorationStep] = [.setCookies, .navigateToTarget]
        if !store.localStorage.isEmpty {
            steps.append(.setLocalStorage)
            steps.append(.reloadTarget)
        }
        return steps
    }
}
