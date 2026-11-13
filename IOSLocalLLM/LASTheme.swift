import SwiftUI

// MARK: - Appearance

/// The appearance choices this product exposes. `KoduTheme` only understands
/// "light", "dark", and "oled"; `system` is resolved against the device setting
/// before a theme is built, so the shared palette file stays untouched.
enum LASAppearance: String, CaseIterable, Identifiable {
    case system, light, dark, oled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        case .oled:   return "OLED"
        }
    }

    var detail: String {
        switch self {
        case .system: return "Follow iOS"
        case .light:  return "Pearl canvas"
        case .dark:   return "Smoked glass"
        case .oled:   return "True black"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon.stars"
        case .oled:   return "moonphase.new.moon"
        }
    }

    /// Window-level override. `system` returns nil so iOS keeps control.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark, .oled: return .dark
        }
    }

    /// The `appearance` string `KoduTheme.make` expects. `system` needs the
    /// device's resolved scheme, which only the view layer knows.
    func koduAppearance(systemPrefersDark: Bool) -> String {
        switch self {
        case .system: return systemPrefersDark ? "dark" : "light"
        case .light:  return "light"
        case .dark:   return "dark"
        case .oled:   return "oled"
        }
    }
}

extension AppSettings {
    var lasAppearance: LASAppearance {
        get { LASAppearance(rawValue: appearance) ?? .system }
        set { appearance = newValue.rawValue }
    }

    var lasAccent: KoduTheme.KoduAccent {
        get { KoduTheme.KoduAccent(rawValue: themeAccent) ?? KoduTheme.appAccent }
        set { themeAccent = newValue.rawValue }
    }

    var lasCanvas: KoduTheme.KoduCanvas {
        get { KoduTheme.KoduCanvas(rawValue: canvasTint) ?? .neutral }
        set { canvasTint = newValue.rawValue }
    }
}

// MARK: - Theme host

/// Resolves the stored appearance + accent into a `KoduTheme` and injects it,
/// the matching window color scheme, and the accent tint.
///
/// Sheets and navigation destinations get the environment for free, but a
/// `.preferredColorScheme` set on the presenting view does not always reach a
/// presented sheet's own window. Apply `.lasTheme()` at the root of any
/// modally presented surface so its chrome matches the rest of the app.
struct LASThemeHost<Content: View>: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var deviceColorScheme

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let appearance = settings.lasAppearance
        let theme = KoduTheme.make(
            appearance: appearance.koduAppearance(
                systemPrefersDark: deviceColorScheme == .dark
            ),
            accent: settings.lasAccent,
            canvas: settings.lasCanvas
        )

        content
            .koduTheme(theme)
            .tint(theme.accentStrong)
            .preferredColorScheme(appearance.colorScheme)
            .koduScaledType()
    }
}

extension View {
    /// Applies the selected LAS appearance and accent to this view tree.
    func lasTheme() -> some View {
        LASThemeHost { self }
    }
}

// MARK: - Theme picker

/// Appearance and accent picker. This product has no general Settings screen,
/// so the theme lives on its own sheet reached from the home header.
struct LASThemeSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.koduTheme) private var T

    private let columns = [GridItem(.adaptive(minimum: 148), spacing: LASDesignTokens.row)]

    var body: some View {
        VStack(spacing: 0) {
            LASDetailHeader("Theme") {
                LASEmptyHeaderSlot()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: LASDesignTokens.component) {
                    preview

                    VStack(alignment: .leading, spacing: LASDesignTokens.row) {
                        LASSectionLabel(
                            title: "APPEARANCE",
                            trailing: settings.lasAppearance.title.uppercased()
                        )

                        LazyVGrid(columns: columns, spacing: LASDesignTokens.row) {
                            ForEach(LASAppearance.allCases) { mode in
                                LASAppearanceTile(
                                    mode: mode,
                                    isSelected: settings.lasAppearance == mode
                                ) {
                                    select(mode)
                                }
                            }
                        }
                    }
                    .lasCard()

                    VStack(alignment: .leading, spacing: LASDesignTokens.row) {
                        LASSectionLabel(
                            title: "ACCENT",
                            trailing: settings.lasAccent.displayName.uppercased()
                        )

                        LASAccentSwatchRow(
                            selected: settings.lasAccent,
                            isDark: T.isDark
                        ) { accent in
                            select(accent)
                        }

                        Text("The accent tints primary actions, status glyphs, and the ambient field behind the glass. Backgrounds and the semantic red/amber/green stay fixed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .lasCard()

                    VStack(alignment: .leading, spacing: LASDesignTokens.row) {
                        LASSectionLabel(
                            title: "PAGE",
                            trailing: canvasLocked
                                ? "LOCKED · OLED"
                                : settings.lasCanvas.displayName.uppercased()
                        )

                        LASCanvasRow(
                            selected: settings.lasCanvas,
                            isDark: T.isDark,
                            isLocked: canvasLocked
                        ) { canvas in
                            select(canvas)
                        }

                        Text(canvasLocked
                             ? "The OLED appearance keeps its true-black page, so the canvas tint waits until you choose Light or Dark."
                             : "The canvas tints the page behind the glass. Ink, borders, and the semantic red/amber/green stay fixed, so contrast never changes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .lasCard()

                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            settings.lasAppearance = .system
                            settings.lasAccent = KoduTheme.appAccent
                            settings.lasCanvas = .neutral
                        }
                    } label: {
                        Label("Reset to defaults", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LASSecondaryButtonStyle())
                }
                .padding(.horizontal, LASDesignTokens.pageInset)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background(LASPageBackground())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: LASDesignTokens.row) {
            LASSectionLabel(title: "PREVIEW")

            HStack(spacing: LASDesignTokens.row) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(T.accentStrong)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Local API Server")
                        .font(.headline)
                    Text("Ready · 11434")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text("READY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(T.accentSoft, in: Capsule())
                    .foregroundStyle(T.accentStrong)
            }

            HStack(spacing: LASDesignTokens.row) {
                Text("Load model")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        T.accentStrong,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )

                Text("Choose")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        Color.primary.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            }
        }
        .lasCard()
        .accessibilityHidden(true)
    }

    private func select(_ mode: LASAppearance) {
        guard settings.lasAppearance != mode else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            settings.lasAppearance = mode
        }
    }

    private func select(_ accent: KoduTheme.KoduAccent) {
        guard settings.lasAccent != accent else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            settings.lasAccent = accent
        }
    }

    private func select(_ canvas: KoduTheme.KoduCanvas) {
        guard settings.lasCanvas != canvas else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            settings.lasCanvas = canvas
        }
    }

    /// The OLED appearance owns a true-black page; a tint would defeat it.
    private var canvasLocked: Bool { settings.lasAppearance == .oled }
}

private struct LASAppearanceTile: View {
    let mode: LASAppearance
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.koduTheme) private var T

    var body: some View {
        Button(action: action) {
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
                Text(mode.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LASDesignTokens.row)
            .frame(minHeight: 92)
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
        .accessibilityLabel("\(mode.title) appearance")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct LASAccentSwatchRow: View {
    let selected: KoduTheme.KoduAccent
    let isDark: Bool
    let onSelect: (KoduTheme.KoduAccent) -> Void

    private let columns = [GridItem(.adaptive(minimum: 52), spacing: LASDesignTokens.row)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: LASDesignTokens.row) {
            ForEach(KoduTheme.KoduAccent.allCases) { accent in
                Button {
                    onSelect(accent)
                } label: {
                    Circle()
                        .fill(accent.swatchColor(dark: isDark))
                        .frame(width: 30, height: 30)
                        .overlay {
                            Circle().stroke(LASDesignTokens.hairline, lineWidth: 1)
                        }
                        .overlay {
                            if accent == selected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                            }
                        }
                        .padding(6)
                        .overlay {
                            if accent == selected {
                                Circle()
                                    .stroke(accent.swatchColor(dark: isDark), lineWidth: 2)
                            }
                        }
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(accent.displayName) accent")
                .accessibilityAddTraits(accent == selected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

// MARK: - Canvas picker

/// Page-canvas swatches. Each tile paints the real page color it selects, so the
/// choice is legible without applying it first.
private struct LASCanvasRow: View {
    let selected: KoduTheme.KoduCanvas
    let isDark: Bool
    let isLocked: Bool
    let onSelect: (KoduTheme.KoduCanvas) -> Void

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: LASDesignTokens.row)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: LASDesignTokens.row) {
            ForEach(KoduTheme.KoduCanvas.allCases) { canvas in
                Button {
                    onSelect(canvas)
                } label: {
                    VStack(spacing: LASDesignTokens.tight) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(canvas.page(dark: isDark))
                            .frame(height: 52)
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(LASDesignTokens.hairline, lineWidth: 1)
                            }
                            .overlay {
                                if canvas == selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(isDark ? Color.white : Color.black.opacity(0.75))
                                }
                            }

                        Text(canvas.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(canvas == selected ? Color.primary : .secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isLocked)
                .opacity(isLocked ? 0.45 : 1)
                .accessibilityLabel("\(canvas.displayName) page canvas")
                .accessibilityAddTraits(canvas == selected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}
