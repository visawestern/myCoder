import Foundation

extension SpecWizardSession {
    @discardableResult
    func updateNodeStatus(nodeID: String, status: String) -> Bool {
        guard Self.allowedNodeStatuses.contains(status) else {
            errorMessage = "Unknown node status \(status)"
            return false
        }
        guard let revision = latestRevision,
              nodes.contains(where: { $0.id == nodeID }) else {
            errorMessage = "Node not found in the latest revision"
            return false
        }
        if status == "running", nextRunnableNode()?.id != nodeID {
            errorMessage = "Only the next runnable task can start"
            return false
        }
        do {
            let now = Int64(Date().timeIntervalSince1970)
            guard try store.updateNodeStatus(nodeID: nodeID, status: status, updatedAt: now) else {
                errorMessage = "Node not found"
                return false
            }
            nodes = try store.nodes(revisionID: revision.id)
            appendHistory(action: "node_status_changed",
                          entityType: "node",
                          entityID: nodeID,
                          payloadJSON: "{\"status\":\"\(status)\",\"revision\":\(revision.version)}")
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func nextRunnableNode() -> ProjectSpecNode? {
        guard let revision = latestRevision else { return nil }
        return try? store.nextRunnableNode(revisionID: revision.id)
    }

    func canStartCoding(nodeID: String) -> Bool {
        guard latestRevision != nil,
              let node = nodes.first(where: { $0.id == nodeID }),
              node.status == "pending" else { return false }
        return nextRunnableNode()?.id == nodeID
    }

    func codingPrompt(for nodeID: String) -> String? {
        guard let node = nodes.first(where: { $0.id == nodeID }) else {
            errorMessage = "Node not found in the latest revision"
            return nil
        }
        return SpecNodeExecutionLogic.codingPrompt(
            node: node,
            specification: specification,
            projectPath: projectPath
        )
    }

    /// Starts the next runnable task: marks it running, links the chat session
    /// and returns the coder prompt. The caller creates and sends into the chat.
    @discardableResult
    func startCoding(nodeID: String, sessionID: String) -> String? {
        guard let prompt = codingPrompt(for: nodeID) else { return nil }
        guard canStartCoding(nodeID: nodeID) else {
            errorMessage = "Only the next runnable task can start"
            return nil
        }
        guard updateNodeStatus(nodeID: nodeID, status: "running") else { return nil }
        guard linkSession(sessionID, toNode: nodeID, state: "active") else {
            _ = updateNodeStatus(nodeID: nodeID, status: "pending")
            return nil
        }
        appendHistory(
            action: "node_coding_started",
            entityType: "node",
            entityID: nodeID,
            payloadJSON: "{\"sessionId\":\"\(sessionID)\"}"
        )
        return prompt
    }

    /// Manual verification result. Done/skipped unlocks dependents; failed or
    /// blocked keeps them locked until the user retries.
    @discardableResult
    func finishNode(nodeID: String, status: String) -> Bool {
        guard ["done", "failed", "blocked", "skipped"].contains(status) else {
            errorMessage = "Unsupported completion status \(status)"
            return false
        }
        guard updateNodeStatus(nodeID: nodeID, status: status) else { return false }
        let now = Int64(Date().timeIntervalSince1970)
        for link in nodeSessions(for: nodeID) where link.state == "active" {
            _ = try? store.updateNodeSessionState(
                nodeID: nodeID,
                sessionID: link.sessionID,
                state: status,
                updatedAt: now
            )
        }
        appendHistory(
            action: "node_finished",
            entityType: "node",
            entityID: nodeID,
            payloadJSON: "{\"status\":\"\(status)\"}"
        )
        return true
    }

    @discardableResult
    func retryNode(nodeID: String) -> Bool {
        guard let node = nodes.first(where: { $0.id == nodeID }),
              ["failed", "blocked"].contains(node.status) else {
            errorMessage = "Only a failed or blocked task can be retried"
            return false
        }
        return updateNodeStatus(nodeID: nodeID, status: "pending")
    }

    @discardableResult
    func linkSession(_ sessionID: String, toNode nodeID: String, state: String = "active") -> Bool {
        guard let revision = latestRevision,
              nodes.contains(where: { $0.id == nodeID }) else {
            errorMessage = "Node not found in the latest revision"
            return false
        }
        let now = Int64(Date().timeIntervalSince1970)
        let link = ProjectSpecNodeSession(
            id: UUID().uuidString,
            projectID: projectID,
            nodeID: nodeID,
            sessionID: sessionID,
            state: state,
            createdAt: now,
            updatedAt: now
        )
        do {
            try store.linkNodeSession(link)
            appendHistory(action: "node_session_linked",
                          entityType: "node",
                          entityID: nodeID,
                          payloadJSON: "{\"sessionId\":\"\(sessionID)\",\"revision\":\(revision.version)}")
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func nodeSessions(for nodeID: String) -> [ProjectSpecNodeSession] {
        (try? store.nodeSessions(nodeID: nodeID)) ?? []
    }

    func revisionHistory() -> [ProjectSpecRevision] {
        (try? store.revisions(projectID: projectID)) ?? []
    }
}
