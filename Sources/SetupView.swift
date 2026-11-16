import SwiftUI

/// First-launch setup in five steps: welcome, find and sign in to Home Assistant, menu bar,
/// notifications and sound, done. Display only; every change goes through PrayerModel.
struct SetupView: View {
    enum Step: Int, CaseIterable {
        case welcome, connect, menuBar, alerts, away, done
    }

    @ObservedObject var model: PrayerModel
    let l: Localizing
    let onClose: () -> Void
    @State var step: Step = .welcome
    @State private var launchAtLogin = true

    var body: some View {
        VStack(spacing: 16) {
            Group {
                switch step {
                case .welcome: welcome
                case .connect: connect
                case .menuBar: menuBar
                case .alerts: alerts
                case .away: awayStep
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .frame(width: 420, height: 560)
        .environment(\.layoutDirection, l.isRightToLeft ? .rightToLeft : .leftToRight)
        .onDisappear { model.finishSetup() }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text(l.t("setup.welcome.title", model.config.appName)).font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(l.t("setup.welcome.body")).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 30)
    }

    private var connect: some View {
        VStack(alignment: .leading, spacing: 10) {
            title("setup.connect.title", "setup.connect.body")
            ConnectionForm(model: model, l: l)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            if model.signIn != nil {
                HStack(spacing: 6) {
                    Image(systemName: model.connection == .connected ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                        .foregroundStyle(model.connection == .connected ? .green : .secondary)
                    Text(l.t(model.connection == .connected ? "connection.connected" : "connection.connecting"))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var menuBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            title("setup.menuBar.title", "setup.menuBar.body")
            HStack {
                Spacer()
                MenuBarLabel(model: model, l: l)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                Spacer()
            }
            .padding(.vertical, 6)
            VStack(spacing: 0) {
                toggle("moon.stars.fill", .indigo, "settings.showIcon", \.showIcon)
                SettingsDivider()
                toggle("textformat", .indigo, "settings.showPrayerName", \.showPrayerName)
                SettingsDivider()
                toggle("clock.badge", .indigo, "settings.showSecondsAlways", \.showSecondsAlways)
                SettingsDivider()
                toggle("circle.dotted", .indigo, "settings.blinkColon", \.blinkColon)
                SettingsDivider()
                toggle("paintpalette", .orange, "settings.colorPreAdhan", \.colorPreAdhan)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            PreAdhanColorExample(model: model, l: l)
        }
    }

    private var alerts: some View {
        VStack(alignment: .leading, spacing: 10) {
            title("setup.alerts.title", "setup.alerts.body")
            VStack(spacing: 0) {
                SettingsRow(symbol: "bell", tint: .orange, title: l.t("setup.alerts.notifications")) {
                    SettingsSwitch(isOn: Binding(
                        get: { model.settings.notifyPreAdhan1 || model.settings.notifyPreAdhan2 || model.settings.notifyAtPrayer },
                        set: { on in
                            model.update { $0.notifyPreAdhan1 = on; $0.notifyPreAdhan2 = on; $0.notifyAtPrayer = on }
                            if on { model.requestNotificationPermission() }
                        }))
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            if model.notificationsDenied {
                Text(l.t("settings.notificationsDenied")).font(.caption).foregroundStyle(.orange)
            }
        }
        .onAppear {
            if model.settings.wantsNotifications { model.requestNotificationPermission() }
        }
    }

    /// Away from home: location for the right prayer times, and the adhan on the Mac.
    private var awayStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            title("setup.away.title", "setup.away.body")
            AwaySettings(model: model, l: l)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        }
        .onAppear { model.requestLocationPermission() }
    }

    private var done: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(.green)
                .padding(.top, 20)
            Text(l.t("setup.done.title")).font(.title2.weight(.semibold))
            if let next = model.upcoming {
                Text(l.t("setup.done.next", l.t(next.prayer.localizationKey),
                         Formatters.time.string(from: next.date), Formatters.fullCountdown(next.remaining(at: model.now))))
                    .font(.callout.monospacedDigit()).multilineTextAlignment(.center)
            }
            Text(l.t("setup.done.body")).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            SettingsRow(symbol: "power", tint: .gray, title: l.t("settings.launchAtLogin")) {
                SettingsSwitch(isOn: $launchAtLogin)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        }
    }

    // MARK: Parts

    private var footer: some View {
        VStack(spacing: 12) {
            HStack {
                if step != .welcome && step != .done {
                    Button(l.t("setup.back")) { go(-1) }
                }
                Spacer()
                if step == .connect && model.signIn == nil {
                    Button(l.t("setup.later")) { go(1) }.buttonStyle(.link)
                }
                Button(primaryTitle, action: primaryAction)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .disabled(step == .connect && model.signIn == nil)
            }
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Circle().fill(s == step ? Color.accentColor : Color.primary.opacity(0.2)).frame(width: 6, height: 6)
                }
            }
        }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return l.t("setup.start")
        case .done: return l.t("setup.finish")
        default: return l.t("setup.next")
        }
    }

    private func primaryAction() {
        if step == .done {
            model.setLaunchAtLogin(launchAtLogin)
            model.finishSetup()
            onClose()
        } else {
            go(1)
        }
    }

    private func go(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        withAnimation(.easeInOut(duration: 0.15)) { step = next }
    }

    private func title(_ titleKey: String, _ bodyKey: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l.t(titleKey)).font(.title3.weight(.semibold))
            Text(l.t(bodyKey)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toggle(_ symbol: String, _ tint: Color, _ key: String, _ flag: WritableKeyPath<AppSettings, Bool>) -> some View {
        SettingsRow(symbol: symbol, tint: tint, title: l.t(key)) {
            SettingsSwitch(isOn: Binding(get: { model.settings[keyPath: flag] },
                                         set: { value in model.update { $0[keyPath: flag] = value } }))
        }
    }
}

/// Opens the setup window once, at the first launch.
struct SetupLauncher: View {
    static let windowId = "setup"
    @ObservedObject var model: PrayerModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .task {
                guard model.needsSetup else { return }
                openWindow(id: Self.windowId)
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

/// The setup in its own window; finishing closes it.
struct SetupWindow: View {
    @ObservedObject var model: PrayerModel
    let l: Localizing
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SetupView(model: model, l: l) { dismiss() }
    }
}

/// Three menu bar samples: normal, first pre-adhan (orange) and second pre-adhan (red),
/// drawn exactly like the real menu bar with the current settings.
struct PreAdhanColorExample: View {
    @ObservedObject var model: PrayerModel
    let l: Localizing

    var body: some View {
        let s = model.settings
        let name = s.showPrayerName ? l.t(Prayer.asr.localizationKey) + " " : ""
        let samples: [(String, String, NSColor?)] = [
            ("setup.color.normal", name + "02:14", nil),
            ("setup.color.pre1", name + Formatters.menuBarCountdown(24 * 60 + 31, showSeconds: s.showSeconds,
                                                                    secondsAlways: s.showSecondsAlways), .systemOrange),
            ("setup.color.pre2", name + Formatters.menuBarCountdown(9 * 60 + 58, showSeconds: s.showSeconds,
                                                                    secondsAlways: s.showSecondsAlways), .systemRed),
        ]
        HStack(alignment: .top, spacing: 8) {
            ForEach(samples, id: \.0) { key, text, color in
                VStack(spacing: 4) {
                    Image(nsImage: MenuBarRenderer.image(symbol: s.showIcon ? "moon.stars.fill" : nil, text: text,
                                                         color: s.colorPreAdhan ? color : nil))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                    Text(l.t(key, key == "setup.color.pre1" ? model.preAdhan.firstMinutes : model.preAdhan.secondMinutes))
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 4)
    }
}

/// Location and sound away from home; used in the setup and in the settings.
struct AwaySettings: View {
    @ObservedObject var model: PrayerModel
    let l: Localizing

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(symbol: "location", tint: .blue, title: l.t("settings.location")) {
                switch model.locationStatus {
                case .authorized:
                    Text(locationText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                case .notDetermined:
                    Button(l.t("action.allow"), action: model.requestLocationPermission).controlSize(.mini).fixedSize()
                case .denied:
                    Button(l.t("network.denied.open"), action: model.openLocationSettings).controlSize(.mini).fixedSize()
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(l.t(model.locationStatus == .denied ? "settings.locationDenied" : "settings.locationHelp",
                         Int(model.config.away.distanceKm)))
                    .font(.caption2)
                    .foregroundStyle(model.locationStatus == .denied ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.bottom, 6)
            SettingsDivider()
            SettingsRow(symbol: "speaker.wave.2", tint: .teal, title: l.t("settings.playback")) {
                Menu {
                    ForEach(PlaybackMode.allCases, id: \.self) { mode in
                        Button(l.t("playback.\(mode.rawValue)")) { model.update { $0.playbackMode = mode } }
                    }
                } label: {
                    Text(l.t("playback.\(model.settings.playbackMode.rawValue)"))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(l.t("settings.soundHelp", model.audio.volumes[.adhan] ?? 0,
                         model.audio.volumes[.fajrAdhan] ?? 0, model.audio.volumes[.preAdhanJingle] ?? 0))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.audio.guestModeActive(at: model.now) {
                    Label(l.t("settings.guestMode"), systemImage: "person.2")
                        .font(.caption2).foregroundStyle(.orange)
                }
                HStack {
                    Spacer()
                    Button(l.t(model.playing == nil ? "action.test" : "action.stop"), action: model.testSound)
                        .controlSize(.mini)
                }
            }
            .padding(.horizontal, 8).padding(.bottom, 6)
        }
    }

    private var locationText: String {
        if let away = model.away {
            return l.t("location.away", away.name ?? "–", Int(away.distanceKm.rounded()))
        }
        return l.t("location.home")
    }
}
