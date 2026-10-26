import Foundation

/// Режим работы с MiMo Serve
enum MimoServeMode {
    case required      // Legacy: всё зависит от сервера
    case optional      // Новый: БД локально, сервер только для tool execution
    case offline       // Полностью offline режим
}

/// Менеджер состояния подключения к MiMo Serve
/// Теперь сервер опциональный — только для tool execution
class MimoServeConnectionManager: ObservableObject {
    @Published var isConnected = false
    @Published var mode: MimoServeMode = .optional
    @Published var lastConnectionAttempt: Date?
    @Published var connectionError: String?
    
    private let client: MimoServeClient
    private var reconnectTask: Task<Void, Never>?
    
    init(client: MimoServeClient) {
        self.client = client
    }
    
    /// Проверить доступность сервера (без блокировки UI)
    func checkAvailability() async {
        lastConnectionAttempt = Date()
        
        do {
            let health = try await client.health()
            await MainActor.run {
                self.isConnected = health.healthy
                self.connectionError = nil
            }
        } catch {
            await MainActor.run {
                self.isConnected = false
                self.connectionError = error.localizedDescription
            }
        }
    }
    
    /// Попытка подключения (но не блокирует работу приложения)
    func attemptConnection() {
        reconnectTask?.cancel()
        reconnectTask = Task {
            await checkAvailability()
        }
    }
    
    /// Проверить нужен ли сервер для операции
    func isRequiredForOperation(_ operation: ServerDependentOperation) -> Bool {
        switch mode {
        case .required:
            return true
        case .optional:
            // Только tool execution требует сервер
            return operation == .toolExecution
        case .offline:
            return false
        }
    }
    
    /// Получить статус для отображения в UI
    func statusMessage() -> String {
        if isConnected {
            return "Connected to the local agent"
        } else if mode == .offline {
            return "Offline mode"
        } else {
            return "Local agent unavailable (tool execution disabled)"
        }
    }
    
    deinit {
        reconnectTask?.cancel()
    }
}

/// Операции, которые могут зависеть от сервера
enum ServerDependentOperation {
    case loadProjects       // Теперь из БД
    case loadSessions       // Теперь из БД
    case loadMessages       // Теперь из БД
    case toolExecution      // ТРЕБУЕТ сервер
    case modelsList         // Опционально (можно из БД)
}

/// Адаптер для миграции с server-зависимой архитектуры на локальную БД
class ServerToLocalMigrationAdapter {
    private let db = DatabaseBridge.shared
    private let client: MimoServeClient
    
    init(client: MimoServeClient) {
        self.client = client
    }
    
    /// Загрузить проекты: сначала из БД, затем опционально синхронизировать с сервером
    func loadProjects() async -> [Workspace] {
        // 1. Загрузить из локальной БД (всегда доступно)
        let localProjects = db.loadProjects()
        
        // 2. Попытаться получить данные с сервера (не блокирует если недоступен)
        if let serverProject = try? await client.projectCurrent() {
            // Обновить git info из сервера если доступен
            let projectId = serverProject.worktree
            db.upsertProject(
                id: projectId,
                name: (projectId as NSString).lastPathComponent,
                path: serverProject.worktree
            )
        }
        
        return localProjects
    }
    
    /// Загрузить сессии: сначала из БД, затем опционально синхронизировать
    func loadSessions(projectId: String) async -> [ChatSession] {
        // 1. Загрузить из локальной БД
        let localSessions = db.loadSessions(projectId: projectId)
        
        // 2. Опционально синхронизировать с сервером
        if let serverSessions = try? await client.sessions() {
            // Merge: добавить новые сессии из сервера в БД
            for serverSession in serverSessions {
                let exists = localSessions.contains { $0.id == serverSession.id }
                if !exists {
                    db.createSession(
                        id: serverSession.id,
                        projectId: projectId,
                        title: serverSession.title,
                        directory: serverSession.directory,
                        branch: nil
                    )
                }
            }
            
            // Перезагрузить из БД после sync
            return db.loadSessions(projectId: projectId)
        }
        
        return localSessions
    }
    
    /// Загрузить сообщения: всегда из БД, сервер не нужен
    func loadMessages(sessionId: String) -> [Message] {
        return db.loadMessages(sessionId: sessionId, limit: nil)
    }
    
    /// Отправить сообщение: ТРЕБУЕТ сервер для tool execution
    func sendMessage(
        sessionId: String,
        parts: [[String: Any]],
        options: MessageSendOptions
    ) async throws -> [MimoMessageResponse] {
        // Tool execution ТРЕБУЕТ сервер
        return try await client.sendMessage(
            sessionID: sessionId,
            parts: parts,
            options: options
        )
    }
    
    /// Проверить доступен ли tool execution
    func isToolExecutionAvailable() async -> Bool {
        do {
            let health = try await client.health()
            return health.healthy
        } catch {
            return false
        }
    }
}
