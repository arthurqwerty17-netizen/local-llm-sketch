import Foundation
import Combine

// MARK: - KeepAwakeGenerationLease
//
// Bridges the model runtime's state into a keep-awake lease, so the Session
// screen's "While generating" preference actually holds while a reply or a
// local API request is generated.
//
// This file belongs to the app target only: the Core AI edition ships its own
// `CodingAssistantService` with a different state machine and no session UI, so
// it takes no generation lease.

@MainActor
final class KeepAwakeGenerationLease {

    static let shared = KeepAwakeGenerationLease()

    private var cancellables = Set<AnyCancellable>()
    private var started = false

    private init() {}

    /// Idempotent. Call once, early in launch.
    func activate() {
        guard !started else { return }
        started = true

        // `state` is `private(set)`, so observe the object's change signal and
        // read the value on the next run-loop turn, once the mutation has
        // landed. `receive(on: RunLoop.main)` does that hop for us.
        CodingAssistantService.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.sync() }
            }
            .store(in: &cancellables)

        sync()
    }

    /// Re-applies the stored preference after the toggle changes.
    func refresh() {
        sync()
    }

    private func sync() {
        guard AppSettings.shared.keepAwakeDuringGeneration else {
            KeepAwakeService.shared.end(KeepAwakeService.Lease.generation)
            return
        }
        switch CodingAssistantService.shared.state {
        case .loading, .generating:
            KeepAwakeService.shared.begin(KeepAwakeService.Lease.generation)
        case .unloaded, .ready, .failed:
            KeepAwakeService.shared.end(KeepAwakeService.Lease.generation)
        }
    }
}
