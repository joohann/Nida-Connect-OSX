import SwiftUI

/// Back of the card: all settings, grouped like System Settings. Writes go through PrayerModel.
struct SettingsView: View {
    @ObservedObject var model: PrayerModel
    let l: Localizing
    let onDone: () -> Void
    @Environment(\.openWindow) private var openWindow

    @State var advanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(l.t("settings.title")).font(.headline)
                Spacer()
                if !model.needsConnection {
                    Button(l.t("action.done"), action: onDone).controlSize(.small).keyboardShortcut(.defaultAction)
                }
            }
            group("settings.sourceGroup") {
                sourceRow
                if model.needsConnection {
                    SettingsDivider()
                    ConnectionForm(model: model, l: l)
                }
            }
            group("settings.menuBar") {
                SettingsRow(symbol: "menubar.rectangle", tint: .indigo, title: l.t("settings.style")) {
                    Menu {
                        ForEach(MenuBarStyle.allCases, id: \.self) { style in
                            Button(l.t("style.\(style.rawValue)")) { model.update { $0.menuBarStyle = style } }
                        }
                    } label: {
                        Text(l.t("style.\(model.settings.menuBarStyle.rawValue)"))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(symbol: "paintpalette", tint: .orange, title: l.t("settings.alerts")) {
                    Text(alertsSummary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    changeButton(.alerts)
                }
            }
            group("settings.soundAndNotifications") {
                SettingsRow(symbol: "bell", tint: .orange, title: l.t("settings.notifications")) {
                    Text(preAdhanSummary).font(.caption).foregroundStyle(.secondary).monospacedDigit().fixedSize()
                    SettingsSwitch(isOn: Binding(get: { model.settings.notifiesPrayers },
                                                 set: { on in model.update { $0.notifiesPrayers = on } }))
                }
                SettingsDivider()
                if model.isStandalone {
                    SettingsRow(symbol: "speaker.wave.2", tint: .teal, title: l.t("settings.playOnMac")) {
                        Button(l.t(model.playing == nil ? "action.test" : "action.stop"), action: model.testSound)
                            .controlSize(.mini).fixedSize()
                        SettingsSwitch(isOn: Binding(get: { model.standalone.playSounds },
                                                     set: { on in model.updateStandalone { $0.playSounds = on } }))
                    }
                    SettingsDivider()
                    SettingsRow(symbol: "speaker.wave.1", tint: .teal, title: l.t("settings.volume")) {
                        Slider(value: Binding(get: { Double(model.standalone.volume(.adhan)) },
                                              set: { v in model.updateStandalone {
                                                  $0.volumes[NidaAudioSettings.Category.adhan.rawValue] = Int(v.rounded())
                                              } }),
                               in: 0...100, step: 5)
                            .controlSize(.mini)
                            .frame(width: 90)
                            .accessibilityLabel(l.t("sound.volume", l.t("sound.adhan")))
                        Text("\(model.standalone.volume(.adhan))%").font(.caption).monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                    }
                    .disabled(!model.standalone.playSounds)
                    .opacity(model.standalone.playSounds ? 1 : 0.5)
                } else {
                    SettingsRow(symbol: "speaker.wave.2", tint: .teal, title: l.t("settings.playback")) {
                        Menu {
                            ForEach([PlaybackMode.away, .always, .off], id: \.self) { mode in
                                Button(l.t("playback.\(mode.rawValue)")) { model.update { $0.playbackMode = mode } }
                            }
                        } label: {
                            Text(l.t("playback.\(model.settings.playbackMode.rawValue)"))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .controlSize(.small)
                    }
                }
            }
            if model.notificationsDenied && model.settings.wantsNotifications {
                Text(l.t("settings.notificationsDenied")).font(.caption).foregroundStyle(.orange)
                    .padding(.top, 6)
            }
            group("settings.general") {
                SettingsRow(symbol: "power", tint: .gray, title: l.t("settings.launchAtLogin")) {
                    SettingsSwitch(isOn: Binding(get: { model.launchAtLogin },
                                                 set: { _ in model.toggleLaunchAtLogin() }))
                }
                if model.config.updatesEnabled {
                    SettingsDivider()
                    SettingsRow(symbol: "arrow.down.circle", tint: .blue, title: l.t("settings.checkForUpdates")) {
                        Button(l.t("action.checkNow"), action: model.checkForUpdates).controlSize(.mini).fixedSize()
                        SettingsSwitch(isOn: binding(\.checkForUpdates))
                    }
                }
                SettingsDivider()
                SettingsRow(symbol: "wand.and.stars", tint: .purple, title: l.t("settings.runSetup")) {
                    Button(l.t("action.open")) { openSetup(.welcome) }.controlSize(.mini).fixedSize()
                }
            }
            advancedSection
            HStack {
                Text(l.t("settings.version", model.config.version)).font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button(l.t("action.quit", model.config.appName)) { NSApp.terminate(nil) }.controlSize(.small)
            }
            .padding(.top, 10)
        }
    }

    // MARK: Parts

    /// Where the times come from, in one line; Change opens that step of the setup.
    private var sourceRow: some View {
        VStack(spacing: 0) {
            SettingsRow(symbol: model.isStandalone ? "mappin.and.ellipse" : "house",
                        tint: model.isStandalone ? .green : .blue,
                        title: l.t("source.\(model.settings.source.rawValue)")) {
                Text(sourceDetail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if !model.needsConnection { changeButton(.connect) }
            }
            if model.isStandalone && model.standalone.manualPlace == nil && model.locationStatus != .authorized {
                HStack(spacing: 6) {
                    Text(l.t(model.locationStatus == .denied ? "place.denied" : "place.needsPermission"))
                        .font(.caption2).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if model.locationStatus == .denied {
                        Button(l.t("network.denied.open"), action: model.openLocationSettings).controlSize(.mini).fixedSize()
                    } else {
                        Button(l.t("action.allow"), action: model.requestLocationPermission).controlSize(.mini).fixedSize()
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 6)
            }
        }
    }

    private var sourceDetail: String {
        if model.isStandalone {
            return model.standalone.manualPlace?.name ?? model.timesPlaceName ?? l.t("place.automatic")
        }
        if model.needsConnection { return "" }
        return model.server?.display ?? ""
    }

    private var alertsSummary: String {
        let s = model.settings
        let on = [s.colorPreAdhan ? l.t("alert.color.short") : nil, s.prayerSignal ? l.t("alert.signal.short") : nil]
            .compactMap { $0 }
        return on.isEmpty ? l.t("state.off") : on.joined(separator: " · ")
    }

    private var preAdhanSummary: String {
        let p = model.preAdhan
        let minutes = [p.firstMinutes > 0 ? p.firstMinutes : nil, p.secondEnabled ? p.secondMinutes : nil].compactMap { $0 }
        return minutes.isEmpty ? "" : l.t("settings.minutesList", minutes.map(String.init).joined(separator: " · "))
    }

    private func changeButton(_ step: SetupView.Step) -> some View {
        Button(l.t("action.change")) { openSetup(step) }.controlSize(.mini).fixedSize()
    }

    private func openSetup(_ step: SetupView.Step) {
        model.setupEntry = step.rawValue
        openWindow(id: SetupLauncher.windowId)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The fine-grained settings, folded away until you look for them.
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { advanced.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(advanced ? 90 : 0))
                    Text(l.t("settings.advanced")).font(.caption)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .padding(.top, 12)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(l.t(advanced ? "state.on" : "state.off"))
            if advanced {
                if model.isStandalone {
                    group("settings.prayerTimes") {
                        StandaloneTimesSettings(model: model, l: l, showsPlace: false)
                    }
                    group("settings.sound") {
                        StandaloneSoundSettings(model: model, l: l, showsPlaySwitch: false)
                    }
                } else {
                    group("settings.away") {
                        AwaySettings(model: model, l: l, showsPlayback: false)
                    }
                }
                group("settings.menuBar") {
                    row("moon.stars.fill", .indigo, "settings.showIcon", \.showIcon, enabled: [.named, .precise].contains(model.settings.menuBarStyle))
                    SettingsDivider()
                    row("clock", .indigo, "settings.showSeconds", \.showSeconds,
                        enabled: !model.settings.showSecondsAlways && !model.settings.iconOnly
                                 && !model.settings.prayerTimeOnly)
                    SettingsDivider()
                    row("circle.dotted", .indigo, "settings.blinkColon", \.blinkColon, enabled: !model.settings.iconOnly)
                    SettingsDivider()
                    SettingsRow(symbol: "sparkles", tint: .yellow, title: l.t("settings.prayerSignal")) {
                        Menu {
                            ForEach(AppSettings.prayerSignalChoices, id: \.self) { minutes in
                                Button(l.t("settings.minutes", minutes)) {
                                    model.update { $0.prayerSignalMinutes = minutes }
                                }
                            }
                        } label: {
                            Text(l.t("settings.minutes", model.settings.prayerSignalMinutes))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .controlSize(.small)
                        .disabled(!model.settings.prayerSignal)
                        .opacity(model.settings.prayerSignal ? 1 : 0.4)
                    }
                    .help(l.t("settings.prayerSignalHelp"))
                }
                group("settings.notifications") {
                    row("bell", .orange, "settings.notifyPreAdhan1", \.notifyPreAdhan1,
                        detail: model.preAdhan.firstMinutes > 0 ? l.t("settings.minutes", model.preAdhan.firstMinutes)
                                                                  : l.t(model.isStandalone ? "state.off" : "settings.offInNida"))
                    SettingsDivider()
                    row("bell.badge", .red, "settings.notifyPreAdhan2", \.notifyPreAdhan2,
                        detail: model.preAdhan.secondEnabled ? l.t("settings.minutes", model.preAdhan.secondMinutes)
                                                             : l.t(model.isStandalone ? "state.off" : "settings.offInNida"))
                    SettingsDivider()
                    row("moon.stars", .green, "settings.notifyAtPrayer", \.notifyAtPrayer)
                    if model.config.updatesEnabled {
                        SettingsDivider()
                        row("sparkles", .blue, "settings.notifyUpdate", \.notifyUpdate,
                            enabled: model.settings.checkForUpdates)
                    }
                }
            }
        }
    }

    private func group<Content: View>(_ key: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l.t(key)).font(.caption).foregroundStyle(.secondary).padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        }
        .padding(.top, 10)
    }

    private func row(_ symbol: String, _ tint: Color, _ key: String, _ flag: WritableKeyPath<AppSettings, Bool>,
                     detail: String? = nil, enabled: Bool = true) -> some View {
        SettingsRow(symbol: symbol, tint: tint, title: l.t(key)) {
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit().fixedSize()
            }
            SettingsSwitch(isOn: binding(flag))
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }

    private func binding<T>(_ path: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { model.settings[keyPath: path] },
                set: { value in model.update { $0[keyPath: path] = value } })
    }
}

/// Server address and sign-in. Signing in through Home Assistant's login page is the default;
/// a long-lived token is the alternative. Credentials go straight to the Keychain.
struct ConnectionForm: View {
    @ObservedObject var model: PrayerModel
    let l: Localizing
    @State private var address = ""
    @State private var token = ""
    @State private var useToken = false
    @State private var editing = false
    @State private var error: String?
    @State private var manualEntry = false

    var body: some View {
        if model.server != nil && model.signIn != nil && !editing {
            SettingsRow(symbol: "house", tint: .blue, title: l.t("settings.server")) {
                Text(model.server?.display ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Button(l.t("action.change")) {
                    address = model.server?.baseURL.absoluteString ?? ""
                    token = ""
                    useToken = model.signIn == .token
                    editing = true
                }
                .controlSize(.mini)
            }
            SettingsDivider()
            SettingsRow(symbol: model.signIn == .token ? "key" : "person.crop.circle.badge.checkmark",
                        tint: .gray, title: l.t(model.signIn == .token ? "settings.signedInToken" : "settings.signedInLogin")) {
                EmptyView()
            }
            if !knownRoutes.isEmpty {
                SettingsDivider()
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(knownRoutes, id: \.0) { kind, address in
                        HStack(spacing: 6) {
                            Image(systemName: PrayerFront.routeSymbol(kind)).frame(width: 14)
                            Text(l.t(PrayerFront.routeKey(kind)))
                            Spacer(minLength: 4)
                            Text(address.display).lineLimit(1).truncationMode(.middle)
                            if model.activeRoute == address && model.connection == .connected {
                                Image(systemName: "checkmark").foregroundStyle(.green)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Text(l.t("settings.routesHelp")).font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            if model.server?.isEncrypted == false && model.endpoints.cloudURL == nil && model.endpoints.externalURL == nil {
                notice("lock.open", .orange, l.t("settings.insecure"))
            }
            if model.localNetworkDenied {
                localNetworkNotice
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if model.localNetworkDenied {
                    localNetworkNotice.padding(.horizontal, -8)
                } else {
                    discoveredList
                }
                if showsAddressField {
                    TextField(l.t("settings.serverPlaceholder"), text: $address)
                        .textFieldStyle(.roundedBorder)
                        .environment(\.layoutDirection, .leftToRight)
                }
                if let parsed = ServerAddress(address), !parsed.isEncrypted {
                    Text(l.t("settings.insecure")).font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if useToken {
                    tokenFields
                } else {
                    loginButton
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    if model.signIn != nil {
                        Button(l.t("action.forget"), role: .destructive) {
                            model.forgetConnection()
                            address = ""
                            token = ""
                            editing = false
                        }
                        .controlSize(.small)
                    }
                    Spacer()
                    if editing {
                        Button(l.t("action.cancel")) {
                            model.cancelLogin()
                            editing = false
                            error = nil
                        }
                        .controlSize(.small)
                    }
                }
            }
            .padding(8)
            .onAppear {
                if address.isEmpty { address = model.server?.baseURL.absoluteString ?? model.discovered.first?.address ?? "" }
                model.startDiscovery()
            }
            .onDisappear { model.stopDiscovery() }
            .onChange(of: model.discovered) { found in
                // Pick the first Home Assistant found when nothing is chosen yet, and switch an
                // IP address to its host name as soon as the network lookup has found one.
                if address.isEmpty, let first = found.first { address = first.address }
                for server in found {
                    guard let ip = server.ipAddress, let current = ServerAddress(address),
                          current.baseURL.host == ip else { continue }
                    address = server.address
                }
            }
            .onChange(of: model.loginError) { value in
                error = value.map(loginMessage)
            }
            .onChange(of: model.signIn) { value in
                if value != nil && !model.isLoggingIn { editing = false }
            }
        }
    }

    private var loginButton: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.isLoggingIn {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(l.t("login.waiting")).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(l.t("action.cancel"), action: model.cancelLogin).controlSize(.small)
                }
            } else {
                Button {
                    error = nil
                    guard ServerAddress(address) != nil else {
                        error = l.t("settings.invalidServer")
                        return
                    }
                    model.login(address: address)
                } label: {
                    Label(l.t("action.loginWithHA"), systemImage: "person.crop.circle")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .disabled(address.isEmpty)
            }
            Button(l.t("settings.useToken")) { useToken = true; error = nil }
                .buttonStyle(.link).font(.caption)
        }
    }

    private var tokenFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            SecureField(model.signIn == .token ? l.t("settings.tokenKeep") : l.t("settings.tokenPlaceholder"),
                        text: $token)
                .textFieldStyle(.roundedBorder)
                .environment(\.layoutDirection, .leftToRight)
            Text(l.t("settings.tokenHelp")).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(l.t("settings.useLogin")) { useToken = false; error = nil }
                    .buttonStyle(.link).font(.caption)
                Spacer()
                Button(l.t("action.connect"), action: saveToken)
                    .controlSize(.small)
                    .disabled(address.isEmpty || (token.isEmpty && model.signIn != .token))
            }
        }
    }

    /// Every known address with its kind, in the order the app tries them.
    private var knownRoutes: [(RouteKind, ServerAddress)] {
        guard let server = model.server else { return [] }
        let routes = model.endpoints.routes(primary: server)
        guard routes.count > 1 else { return [] }
        return routes.map { address in
            (model.endpoints.isCloud(address) ? .nabuCasa : (address.isLocal ? .home : .external), address)
        }
    }

    /// The address field shows only when nothing was found, the user asks for it,
    /// or the current address is not one of the found instances (for example an external URL).
    private var showsAddressField: Bool {
        if manualEntry || model.discovered.isEmpty { return true }
        guard !address.isEmpty else { return false }
        return !model.discovered.contains { ServerAddress($0.address) == ServerAddress(address) }
    }

    /// Found Home Assistant instances; a click fills in the address.
    @ViewBuilder
    private var discoveredList: some View {
        HStack(spacing: 6) {
            Text(l.t("settings.discovered")).font(.caption).foregroundStyle(.secondary)
            if model.discovered.isEmpty {
                ProgressView().controlSize(.mini)
                Text(l.t("settings.searching")).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if !model.discovered.isEmpty {
                // The pencil opens the address field for a manual address, for example an external URL.
                Button {
                    manualEntry.toggle()
                    if !manualEntry, !model.discovered.contains(where: { ServerAddress($0.address) == ServerAddress(address) }),
                       let first = model.discovered.first {
                        address = first.address
                    }
                } label: {
                    Image(systemName: manualEntry ? "pencil.circle.fill" : "pencil")
                        .font(.system(size: 13))
                        .foregroundStyle(manualEntry ? Color.accentColor : .secondary)
                        .frame(width: 22, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(l.t("settings.manualAddress"))
                .accessibilityLabel(l.t("settings.manualAddress"))
            }
        }
        ForEach(model.discovered) { server in
            let selected = ServerAddress(address) == ServerAddress(server.address)
            Button {
                address = server.address
                error = nil
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "house")
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(server.name).lineLimit(1)
                        Text([ServerAddress(server.address)?.display ?? server.address, server.ipAddress]
                                .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let version = server.version {
                        Text(version).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .padding(6)
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04)))
            }
            .buttonStyle(.plain)
        }
    }

    /// Local network access is blocked in System Settings; the button opens that page.
    private var localNetworkNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "network.slash").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.t("network.denied.title")).font(.caption.weight(.semibold))
                    Text(l.t("network.denied.body", model.config.appName)).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(l.t("network.denied.open"), action: model.openLocalNetworkSettings).controlSize(.small)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.1)))
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private func notice(_ symbol: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(.caption2).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private func loginMessage(_ error: AuthError) -> String {
        switch error {
        case .rejected: return l.t("login.error.rejected")
        case .timedOut: return l.t("login.error.timedOut")
        case .denied: return l.t("login.error.denied")
        case .stateMismatch, .cancelled: return l.t("login.error.rejected")
        case .unreachable: return l.t("login.error.unreachable")
        }
    }

    private func saveToken() {
        guard ServerAddress(address) != nil else {
            error = l.t("settings.invalidServer")
            return
        }
        if model.saveConnection(address: address, token: token) {
            token = ""
            error = nil
            editing = false
        } else {
            error = l.t("settings.saveFailed")
        }
    }
}

/// One line in a settings group: a coloured icon, a title and trailing controls.
struct SettingsRow<Trailing: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5).fill(tint))
            Text(title).lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
    }
}

/// A small macOS switch without a label.
struct SettingsSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.mini)
    }
}

/// Hairline between rows, aligned with the titles.
struct SettingsDivider: View {
    var body: some View { Divider().padding(.leading, 36) }
}
