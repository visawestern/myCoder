import Foundation

enum MiMoCopy {
    static func promptPlaceholder(language: AppLanguage = .english) -> String {
        switch language {
        case .russian:
            return "Спросите myCoder, @ — файлы, / — команды, $ — skills, # — связанный диалог"
        case .spanish:
            return "Pregunta a myCoder, @ archivos, / comandos, $ skills, # conversación"
        case .french:
            return "Demandez à myCoder, @ fichiers, / commandes, $ skills, # conversation"
        case .german:
            return "Frag myCoder, @ Dateien, / Befehle, $ Skills, # Verlauf"
        case .chineseSimplified:
            return "向 myCoder 提问，@ 文件，/ 命令，$ 技能，# 相关对话"
        case .japanese:
            return "myCoder に質問、@ ファイル、/ コマンド、$ スキル、# 会話"
        case .korean:
            return "MyCoder에게 질문, @ 파일, / 명령, $ 스킬, # 대화"
        case .portuguese:
            return "Pergunte ao myCoder, @ arquivos, / comandos, $ skills, # conversa"
        case .arabic:
            return "اسأل myCoder، @ الملفات، / الأوامر، $ المهارات، # المحادثة"
        case .english:
            return "Ask myCoder anything, @ to add files, / for commands, $ for skills, # related conversation"
        }
    }

    static func followUpPlaceholder(language: AppLanguage = .english) -> String {
        switch language {
        case .russian: return "Попросите доработать результат"
        case .spanish: return "Pide cambios adicionales"
        case .french: return "Demandez des modifications"
        case .german: return "Weitere Änderungen anfordern"
        case .chineseSimplified: return "请求后续修改"
        case .japanese: return "追加の変更を依頼"
        case .korean: return "추가 변경 요청"
        case .portuguese: return "Peça mais alterações"
        case .arabic: return "اطلب تغييرات إضافية"
        case .english: return "Ask for follow-up changes"
        }
    }

    static let watermarkText = "mi"

    static func emptyStateSelectWorkspace(language: AppLanguage = .english) -> String {
        switch language {
        case .russian: return "Выберите проект"
        case .spanish: return "Selecciona un proyecto"
        case .french: return "Sélectionnez un projet"
        case .german: return "Projekt auswählen"
        case .chineseSimplified: return "选择一个项目"
        case .japanese: return "プロジェクトを選択"
        case .korean: return "프로젝트 선택"
        case .portuguese: return "Selecione um projeto"
        case .arabic: return "اختر مشروعًا"
        case .english: return "Select a project"
        }
    }

    static func emptyStateTitle(workspaceName: String, language: AppLanguage = .english) -> String {
        switch language {
        case .russian: return "Начните новую задачу в \(workspaceName)"
        case .spanish: return "Inicia una tarea en \(workspaceName)"
        case .french: return "Démarrez une tâche dans \(workspaceName)"
        case .german: return "Neue Aufgabe in \(workspaceName)"
        case .chineseSimplified: return "在 \(workspaceName) 开始新任务"
        case .japanese: return "\(workspaceName) で新しいタスクを開始"
        case .korean: return "\(workspaceName)에서 새 작업 시작"
        case .portuguese: return "Inicie uma tarefa em \(workspaceName)"
        case .arabic: return "ابدأ مهمة جديدة في \(workspaceName)"
        case .english: return "Start a new task in \(workspaceName)"
        }
    }
}
