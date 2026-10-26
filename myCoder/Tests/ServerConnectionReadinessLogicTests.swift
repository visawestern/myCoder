import Foundation
import Testing
@testable import myCoder

/// Round 49: the startup chain must derive AppState readiness from the completed
/// connection-manager result. A manager can be online while the old AppState
/// boolean is still false; that race prevented server model loading and made the
/// first screen appear unusable even though the local agent was healthy.
@Suite("APP-01: startup connection readiness")
struct ServerConnectionReadinessLogicTests {
    @Test("completed health result is copied into AppState connection state")
    func completedHealthResultSynchronizesAppState() {
        #expect(ServerConnectionReadinessLogic.appStateConnectionState(isConnected: false, healthHealthy: true) == true)
        #expect(ServerConnectionReadinessLogic.appStateConnectionState(isConnected: true, healthHealthy: false) == false)
    }

    @Test("a missing or cancelled health result fails closed")
    func missingHealthResultDoesNotClaimConnected() {
        #expect(ServerConnectionReadinessLogic.appStateConnectionState(isConnected: false, healthHealthy: nil) == false)
        #expect(ServerConnectionReadinessLogic.appStateConnectionState(isConnected: true, healthHealthy: nil) == false)
    }

    @Test("model loading is allowed only after the same health result marks the server online")
    func modelLoadingRequiresCompletedOnlineState() {
        #expect(ServerConnectionReadinessLogic.shouldLoadServerModels(isConnected: true, healthHealthy: true))
        #expect(!ServerConnectionReadinessLogic.shouldLoadServerModels(isConnected: false, healthHealthy: true))
        #expect(!ServerConnectionReadinessLogic.shouldLoadServerModels(isConnected: true, healthHealthy: nil))
        #expect(!ServerConnectionReadinessLogic.shouldLoadServerModels(isConnected: true, healthHealthy: false))
    }
}
