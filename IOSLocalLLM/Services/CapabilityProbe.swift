import Foundation
import Darwin

// MARK: - CapabilityProbe
//
// What this build can actually do, checked at runtime instead of assumed.
//
// This app ships by sideload only, so its entitlements file carries JIT and the
// extended memory limits. Whether a *given install* kept them depends on the
// signer, so the app asks the running process rather than trusting the file.
//
// `mmap` with MAP_JIT and PROT_EXEC is the honest test: if the kernel hands back
// executable memory, JIT is live in this process. If it refuses, the signing
// path dropped the entitlement, and anything needing JIT can say so up front
// instead of failing later in a way nobody can read.

enum CapabilityProbe {

    /// True when this process may allocate executable memory at runtime.
    static private(set) lazy var jitAvailable: Bool = probeJIT()

    private static func probeJIT() -> Bool {
        let length = Int(getpagesize())
        let address = mmap(
            nil,
            length,
            PROT_READ | PROT_WRITE | PROT_EXEC,
            MAP_PRIVATE | MAP_ANONYMOUS | MAP_JIT,
            -1,
            0
        )
        guard address != MAP_FAILED, let address else { return false }
        munmap(address, length)
        return true
    }

    /// One line for the Session screen and for the agent's brief.
    static var summary: String {
        jitAvailable
            ? "JIT available in this install"
            : "JIT unavailable — this signature dropped the entitlement"
    }
}
