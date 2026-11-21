import SwiftUI

/// First-launch setup: welcome, where the times come from, Home Assistant (or place and method
/// without it), menu bar, notifications, away or sound, done. Display only; every change goes
/// through PrayerModel.
struct SetupView: View {
    enum Step: Int, CaseIterable {
        case welcome, source, connect, menuBar, alerts, sound, done
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
                case .source: sourceStep
                case .connect: connect
                case .menuBar: menuBar
                case .alerts: alerts
                case .sound: sound
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
        .onAppear(perform: takeEntry)
        .onChange(of: model.setupEntry) { _ in takeEntry() }
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

    /// Home Assistant with Nida, or the app on its own.
    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            title("setup.source.title", "setup.source.body")
            ForEach(PrayerSource.allCases, id: \.self) { s in
                let on = model.settings.source == s
                Button { model.setSource(s) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: s == .homeAssistant ? "house.fill" : "mappin.and.ellipse")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 7).fill(s == .homeAssistant ? Color.blue : Color.green))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(l.t("source.\(s.rawValue)")).font(.headline)
                            Text(l.t("source.\(s.rawValue).body")).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(on ? MenuBarRenderer.goldColor : Color.primary.opacity(0.12), lineWidth: on ? 2 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private var connect: some View {
        Group {
            if model.isStandalone { placeStep } else { haStep }
        }
    }

    /// Without Home Assistant: place and calculation method.
    private var placeStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            title("setup.place.title", "setup.place.body")
            StandaloneTimesSettings(model: model, l: l)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        }
        .onAppear { model.requestLocationPermission() }
    }

    private var haStep: some View {
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

    /// One of three styles instead of separate switches; each card shows the real menu bar.
    private var menuBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            title("setup.menuBar.title", "setup.menuBar.body")
            ForEach(MenuBarStyle.allCases, id: \.self) { style in
                ChoiceCard(symbol: "menubar.rectangle", tint: .indigo, title: l.t("style.\(style.rawValue)"),
                           detail: l.t("style.\(style.rawValue).body"),
                           selected: model.settings.menuBarStyle == style) {
                    model.update { $0.menuBarStyle = style }
                } trailing: {
                    MenuBarSample(model: model, l: l, style: style)
                }
            }
        }
    }

    /// Notification, colour and gold label as three cards you switch on or off.
    private var alerts: some View {
        VStack(alignment: .leading, spacing: 10) {
            title("setup.alerts.title", "setup.alerts.body")
            ToggleCard(symbol: "bell.fill", tint: .orange, title: l.t("alert.notifications"),
                       detail: l.t("alert.notifications.body"),
                       isOn: Binding(get: { model.settings.notifiesPrayers },
                                     set: { on in
                                         model.update { $0.notifiesPrayers = on }
                                         if on { model.requestNotificationPermission() }
                                     })) {
                if model.isStandalone {
                    HStack(spacing: 10) {
                        MinuteStepper(value: model.standalone.firstMinutes, l: l) { v in
                            model.updateStandalone { $0.firstMinutes = v }
                        }
                        MinuteStepper(value: model.standalone.secondMinutes, l: l) { v in
                            model.updateStandalone { $0.secondMinutes = v; $0.secondEnabled = v > 0 }
                        }
                    }
                }
            }
            ToggleCard(symbol: "paintpalette.fill", tint: .orange, title: l.t("alert.color"),
                       detail: l.t("alert.color.body"), isOn: flag(\.colorPreAdhan)) {
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 8, height: 8)
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                }
            }
            ToggleCard(symbol: "sparkles", tint: .yellow, title: l.t("alert.signal"),
                       detail: l.t("alert.signal.body"), isOn: flag(\.prayerSignal)) {
                Image(nsImage: MenuBarRenderer.badge(symbol: nil, text: l.t(Prayer.asr.localizationKey), dimmed: false))
            }
            if model.notificationsDenied && model.settings.notifiesPrayers {
                Text(l.t("settings.notificationsDenied")).font(.caption).foregroundStyle(.orange)
            }
        }
        .onAppear {
            if model.settings.wantsNotifications { model.requestNotificationPermission() }
        }
    }

    /// Whether this Mac plays the adhan. Standalone: yes or no, and the voice.
    /// With Home Assistant: always, only away from home, or never.
    private var sound: some View {
        VStack(alignment: .leading, spacing: 10) {
            title("setup.sound.title", model.isStandalone ? "setup.sound.body" : "setup.sound.bodyHA")
            if model.isStandalone {
                standaloneSound
            } else {
                ForEach([PlaybackMode.away, .always, .home, .off], id: \.self) { mode in
                    ChoiceCard(symbol: mode == .off ? "speaker.slash.fill" : "speaker.wave.2.fill",
                               tint: mode == .off ? .gray : .teal, title: l.t("playback.\(mode.rawValue).title"),
                               detail: l.t("playback.\(mode.rawValue).body"),
                               selected: model.settings.playbackMode == mode) {
                        model.update { $0.playbackMode = mode }
                        if mode == .away { model.requestLocationPermission() }
                    } trailing: { EmptyView() }
                }
            }
        }
        .onAppear { if model.isStandalone { model.loadCatalog() } }
    }

    @ViewBuilder
    private var standaloneSound: some View {
        ChoiceCard(symbol: "speaker.wave.2.fill", tint: .teal, title: l.t("sound.yes"), detail: l.t("sound.yes.body"),
                   selected: model.standalone.playSounds) {
            model.updateStandalone { $0.playSounds = true }
        } trailing: { EmptyView() }
        if model.standalone.playSounds {
            VoiceRow(model: model, l: l)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        }
        ChoiceCard(symbol: "speaker.slash.fill", tint: .gray, title: l.t("sound.no"), detail: l.t("sound.no.body"),
                   selected: !model.standalone.playSounds) {
            model.updateStandalone { $0.playSounds = false }
        } trailing: { EmptyView() }
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
                if step == .connect && model.signIn == nil && !model.isStandalone {
                    Button(l.t("setup.later")) { go(1) }.buttonStyle(.link)
                }
                Button(primaryTitle, action: primaryAction)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .disabled(step == .connect && model.signIn == nil && !model.isStandalone)
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

    private func flag(_ path: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { model.settings[keyPath: path] }, set: { value in model.update { $0[keyPath: path] = value } })
    }

    /// Opens at the step a Change button in the settings asked for.
    private func takeEntry() {
        guard let entry = model.setupEntry else { return }
        model.setupEntry = nil
        step = Step(rawValue: entry) ?? .welcome
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

/// Which volumes Nida uses, and whether guest mode is on; under the playback choice.
struct NidaSoundInfo: View {
    @ObservedObject var model: PrayerModel
    let l: Localizing
    var showsTest = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            JustifiedText(l.t("settings.soundHelp", model.audio.volumes[.adhan] ?? 0,
                              model.audio.volumes[.fajrAdhan] ?? 0, model.audio.volumes[.preAdhanJingle] ?? 0))
            if model.audio.guestModeActive(at: model.now) {
                Label(l.t("settings.guestMode"), systemImage: "person.2")
                    .font(.caption2).foregroundStyle(.orange)
            }
            if showsTest {
                HStack {
                    Spacer()
                    Button(l.t(model.playing == nil ? "action.test" : "action.stop"), action: model.testSound)
                        .controlSize(.mini)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.bottom, 6)
    }
}

/// Location and sound away from home; used in the setup and in the settings.
struct AwaySettings: View {
    @ObservedObject var model: PrayerModel
    let l: Localizing
    /// The settings show playback in their main group, so they leave it out here.
    var showsPlayback = true

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
                JustifiedText(l.t(model.locationStatus == .denied ? "settings.locationDenied" : "settings.locationHelp",
                                  Int(model.config.away.distanceKm)),
                              color: model.locationStatus == .denied ? .systemOrange : .secondaryLabelColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.bottom, 6)
            if showsPlayback {
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
                NidaSoundInfo(model: model, l: l, showsTest: true)
            }
        }
    }

    private var locationText: String {
        if let away = model.away {
            return l.t("location.away", away.name ?? "–", Int(away.distanceKm.rounded()))
        }
        return l.t("location.home")
    }
}
