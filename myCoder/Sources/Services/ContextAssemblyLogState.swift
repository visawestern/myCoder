import Foundation

/// App-state plumbing for the context-assembly log.
///
/// The composer status line is a spoiler over this log: every action keeps
/// what was requested, how it was processed and what came back. The send path
/// writes it through the pure logic, so the whole journal can be replayed in
/// tests without a UI.
extension AppState {

    func beginContextAssembly(message: String, projectRoot: String) {
        contextAssemblyLog = ContextAssemblyLogLogic.begin(
            message: message,
            projectRoot: projectRoot
        )
    }

    func startContextAction(key: String, title: String, request: String, processing: String) {
        contextAssemblyLog = ContextAssemblyLogLogic.start(
            key: key,
            title: title,
            request: request,
            processing: processing,
            in: contextAssemblyLog
        )
    }

    func finishContextAction(key: String,
                             result: String,
                             status: ContextAssemblyLogLogic.Status = .done) {
        contextAssemblyLog = ContextAssemblyLogLogic.finish(
            key: key,
            result: result,
            status: status,
            in: contextAssemblyLog
        )
    }

    func completeContextAssembly(_ facts: ContextAssemblyLogLogic.Facts) {
        contextAssemblyLog = ContextAssemblyLogLogic.finalize(
            log: contextAssemblyLog,
            facts: facts
        )
    }
}
