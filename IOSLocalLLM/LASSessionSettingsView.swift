import SwiftUI

// MARK: - LASSessionSettingsView
//
// Session screen: how the app keeps itself alive for long on-device work.
//
// Everything here is opt-in and reversible in one tap. The location keep-alive
// is described in the same words the Info.plist usage string uses, because the
// permission prompt will quote that string and the two must not disagree.

struct LASSessionSettingsView: View {

    // `@AppStorage` rather than reach-through writes: it is the pattern the rest
    // of the app's control surfaces use, and it repaints the toggles reliably.
    @AppStorage("keepAwakeMode") private var keepAwakeModeRaw = KeepAwakeMode.off.rawValue
    @AppStorage("keepAwakeDuringGeneration") private var keepAwakeDuringGeneration = true
    @AppStorage("keepAwakeLocationArmed") private var keepAwakeLocationArmed = true
    @AppStorage("localAPIKeepScreenAwake") private var localAPIKeepScreenAwake = true

    @ObservedObject private var keepAwake = KeepAwakeService.shared
    @ObservedObject private var reachability = NetworkReachability.shared
    @ObservedObject private var localAPI = LocalAPIManager.shared
    @Environment(\.koduTheme) private var T

    private let columns = [GridItem(.adaptive(minimum: 148), spacing: LASDesignTokens.row)]

    private var selectedMode: KeepAwakeMode {
        KeepAwakeMode(rawValue: keepAwakeModeRaw) ?? .off
    }

    var body: some View {
        VStack(spacing: 0) {
            LASDetailHeader("Session") {
                LASEmptyHeaderSlot()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: LASDesignTokens.component) {
                    statusCard

                    VStack(alignment: .leading, spacing: LASDesignTokens.row) {
                        LASSectionLabel(
                            title: "KEEP AWAKE",
                            trailing: selectedMode.title.uppercased()
                        )

                        LazyVGrid(columns: columns, spacing: LASDesignTokens.row) {
                            ForEach(KeepAwakeMode.allCases) { mode in
                                tile(mode)
                            }
                        }
                    }
                    .lasCard()

                    VStack(alignment: .leading, spacing: LASDesignTokens.row) {
                        LASSectionLabel(title: "WHEN TO HOLD")

                        Toggle(isOn: $keepAwakeDuringGeneration) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("While generating")
                                    .font(.subheadline.weight(.semibold))
                                Text("A long reply or API request keeps the app alive.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(T.accentStrong)

                        Divider().overlay(T.rule)

                        Toggle(isOn: Binding(
                            get: { localAPIKeepScreenAwake },
                            set: { newValue in
                                localAPIKeepScreenAwake = newValue
                                localAPI.refreshIdleTimerPolicy()
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("While the local API runs")
                                    .font(.subheadline.weight(.semibold))
                                Text("The server's own keep-awake switch, unchanged.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(T.accentStrong)
                    }
                    .lasCard()

                    if selectedMode.usesLocation {
                        locationCard
                    }

                    privacyCard
                }
                .padding(.horizontal, LASDesignTokens.pageInset)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background(LASPageBackground())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { keepAwake.reconcile() }
        .onChange(of: keepAwakeModeRaw) { _, _ in
            keepAwake.setMode(selectedMode)
        }
        .onChange(of: keepAwakeDuringGeneration) { _, _ in
            KeepAwakeGenerationLease.shared.refresh()
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: LASDesignTokens.row) {
            LASSectionLabel(
                title: "STATUS",
                trailing: keepAwake.isHoldingAwake ? "HELD" : "RELEASED"
            )

            HStack(spacing: LASDesignTokens.row) {
                Image(systemName: keepAwake.isHoldingAwake ? "lock.open" : "lock")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(keepAwake.isHoldingAwake ? T.accentStrong : T.ink3)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(keepAwake.statusLine)
                        .font(.subheadline.weight(.semibold))
                    Text("Network node · \(reachability.interfaceLabel)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            if !keepAwake.activeLeases.isEmpty {
                HStack(spacing: LASDesignTokens.tight) {
                    ForEach(keepAwake.activeLeases.sorted(), id: \.self) { lease in
                        Text(lease.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.8)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(T.accentSoft, in: Capsule())
                            .foregroundStyle(T.accentStrong)
                    }
                    Spacer(minLength: 0)
                }
            }

            if let error = keepAwake.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(T.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .lasCard()
    }

    private func tile(_ mode: KeepAwakeMode) -> some View {
        let isSelected = selectedMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                keepAwakeModeRaw = mode.rawValue
            }
            keepAwake.setMode(mode)
        } label: {
            VStack(alignment: .leading, spacing: LASDesignTokens.tight) {
                HStack {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 18, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(isSelected ? T.accentStrong : T.ink4)
                }

                Text(mode.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(mode.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LASDesignTokens.row)
            .frame(minHeight: 104)
            .background(
                isSelected ? T.accentSoft : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: LASDesignTokens.tileRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: LASDesignTokens.tileRadius, style: .continuous)
                    .stroke(
                        isSelected ? T.accentStrong.opacity(0.55) : LASDesignTokens.hairline,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.title) keep awake")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Location

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: LASDesignTokens.row) {
            LASSectionLabel(
                title: "BACKGROUND",
                trailing: keepAwake.locationStatusLabel.uppercased()
            )

            HStack(spacing: LASDesignTokens.row) {
                Image(systemName: "location.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(keepAwake.locationPermissionMissing ? T.warn : T.good)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(keepAwake.locationPermissionMissing
                         ? "Location access needed"
                         : "Background keep-alive ready")
                        .font(.subheadline.weight(.semibold))
                    Text("A coarse session (three-kilometer accuracy) keeps the app running with the screen off. No coordinate is stored, logged, or sent anywhere.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Toggle(isOn: Binding(
                get: { keepAwakeLocationArmed },
                set: { newValue in
                    keepAwakeLocationArmed = newValue
                    keepAwake.reconcile()
                }
            )) {
                Text("Arm background keep-alive")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(T.accentStrong)

            Button {
                keepAwake.requestLocationAuthorization()
            } label: {
                Label(
                    keepAwake.locationPermissionDenied
                        ? "Open iOS Settings"
                        : "Allow location access",
                    systemImage: "location.badge.clock"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(LASSecondaryButtonStyle())
            .disabled(!keepAwake.locationPermissionMissing && !keepAwake.locationPermissionDenied)

            Text("iOS only honors a background location session when the app declares it, and it costs battery. Leave this off unless a generation or the local API has to survive the screen locking.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .lasCard()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: LASDesignTokens.tight) {
            LASSectionLabel(title: "PRIVACY")
            Text("Keep-awake changes only how long this app may run. Inference stays on this device. With Screen + background, iOS is told the app is using location services so it is not suspended; the requested accuracy is coarse, and the app discards every update instead of recording it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lasCard()
    }
}

// MARK: - KeepAwakeService presentation
//
// The stored values are raw strings so an old build's unknown value degrades to
// a safe default (`KeepAwakeMode(rawValue:)` returns nil → `.off`) instead of
// crashing on decode.

extension KeepAwakeService {
    var locationStatusLabel: String {
        switch locationStatus {
        case .notDetermined:      return "Not requested"
        case .restricted:         return "Restricted"
        case .denied:             return "Denied"
        case .authorizedAlways:   return "Always"
        case .authorizedWhenInUse:return "When in use"
        @unknown default:         return "Unknown"
        }
    }
}
