import SwiftUI

/// Where the prayer times come from: Home Assistant or the app on its own.
struct SourceRow: View {
    @ObservedObject var model: PrayerModel
    let l: Localizing

    var body: some View {
        SettingsRow(symbol: model.isStandalone ? "mappin.and.ellipse" : "house",
                    tint: model.isStandalone ? .green : .blue, title: l.t("settings.source")) {
            Menu {
                ForEach(PrayerSource.allCases, id: \.self) { s in
                    Button(l.t("source.\(s.rawValue)")) { model.setSource(s) }
                }
            } label: {
                Text(l.t("source.\(model.settings.source.rawValue)"))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .controlSize(.small)
        }
    }
}

/// Without Home Assistant: place, calculation method and pre-adhan, set in the app.
struct StandaloneTimesSettings: View {
    @ObservedObject var model: PrayerModel
    let l: Localizing
    /// The settings show the place in their Source row, so they leave it out here.
    var showsPlace = true
    @State private var picking = false
    @State private var query = ""
    @State private var results: [NamedPlace] = []
    @State private var searching = false

    var body: some View {
        VStack(spacing: 0) {
            if showsPlace {
                placeRows
                SettingsDivider()
            }
            SettingsRow(symbol: "function", tint: .purple, title: l.t("settings.method")) {
                Menu {
                    ForEach(CalculationMethods.ids, id: \.self) { id in
                        Button(l.t(CalculationMethods.key(id))) { model.updateStandalone { $0.method = id } }
                    }
                } label: {
                    Text(l.t(CalculationMethods.key(model.standalone.method))).lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .controlSize(.small)
            }
            SettingsDivider()
            SettingsRow(symbol: "bell", tint: .orange, title: l.t("settings.preAdhan1")) {
                MinuteStepper(value: model.standalone.firstMinutes, l: l) { v in
                    model.updateStandalone { $0.firstMinutes = v }
                }
            }
            SettingsDivider()
            SettingsRow(symbol: "bell.badge", tint: .red, title: l.t("settings.preAdhan2")) {
                MinuteStepper(value: model.standalone.secondMinutes, l: l) { v in
                    model.updateStandalone { $0.secondMinutes = v }
                }
                .disabled(!model.standalone.secondEnabled)
                .opacity(model.standalone.secondEnabled ? 1 : 0.4)
                SettingsSwitch(isOn: Binding(get: { model.standalone.secondEnabled },
                                             set: { on in model.updateStandalone { $0.secondEnabled = on } }))
            }
            SettingsDivider()
            SettingsRow(symbol: "checklist", tint: .gray, title: l.t("settings.preAdhanPerPrayer")) {
                HStack(spacing: 3) {
                    ForEach(Prayer.allCases, id: \.self) { prayer in
                        let on = !model.standalone.preAdhanDisabled.contains(prayer)
                        let name = l.t(prayer.localizationKey)
                        Button {
                            model.updateStandalone {
                                if on { $0.preAdhanDisabled.insert(prayer) } else { $0.preAdhanDisabled.remove(prayer) }
                            }
                        } label: {
                            Text(String(name.prefix(1)))
                                .font(.caption2.weight(.semibold))
                                .frame(width: 16, height: 16)
                                .foregroundStyle(on ? Color.white : Color.secondary)
                                .background(RoundedRectangle(cornerRadius: 4)
                                    .fill(on ? Color.accentColor : Color.primary.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .help(name)
                        .accessibilityLabel(name)
                        .accessibilityValue(l.t(on ? "state.on" : "state.off"))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var placeRows: some View {
        SettingsRow(symbol: "location", tint: .blue, title: l.t("settings.location")) {
            Menu {
                Button(l.t("place.automatic")) {
                    picking = false
                    model.updateStandalone { $0.manualPlace = nil }
                    model.requestLocationPermission()
                }
                Button(l.t("place.choose")) { picking = true }
            } label: {
                Text(placeText).lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .controlSize(.small)
        }
        if picking {
            placePicker
        } else if model.standalone.manualPlace == nil && model.locationStatus != .authorized {
            locationNotice
        }
    }

    private var placeText: String {
        if let place = model.standalone.manualPlace { return place.name }
        return l.t("place.automaticNamed", model.timesPlaceName ?? "–")
    }

    private var placePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField(l.t("place.searchPlaceholder"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .onSubmit(search)
                Button(l.t("place.search"), action: search).controlSize(.small).disabled(searching)
            }
            if !searching && results.isEmpty && !query.isEmpty {
                Text(l.t("place.noResults")).font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(results.prefix(5), id: \.name) { place in
                Button {
                    model.updateStandalone { $0.manualPlace = place }
                    picking = false
                    results = []
                    query = ""
                } label: {
                    Label(place.name, systemImage: "mappin").font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8).padding(.bottom, 6)
    }

    private var locationNotice: some View {
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

    private func search() {
        let q = query
        searching = true
        Task {
            results = await model.searchPlaces(q)
            searching = false
        }
    }
}

/// Minutes with − and + buttons, 0 meaning off.
struct MinuteStepper: View {
    let value: Int
    let l: Localizing
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(value > 0 ? l.t("settings.minutes", value) : l.t("state.off"))
                .font(.caption).monospacedDigit().frame(minWidth: 44, alignment: .trailing)
            Stepper("", value: Binding(get: { value }, set: onChange), in: StandaloneSettings.minuteRange)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

/// Without Home Assistant: which sounds from the Nida library the Mac plays, and how loud.
struct StandaloneSoundSettings: View {
    @ObservedObject var model: PrayerModel
    let l: Localizing
    /// The settings show the play switch in their main group, so they leave it out here.
    var showsPlaySwitch = true

    var body: some View {
        VStack(spacing: 0) {
            if showsPlaySwitch {
                SettingsRow(symbol: "speaker.wave.2", tint: .teal, title: l.t("settings.playOnMac")) {
                    SettingsSwitch(isOn: Binding(get: { model.standalone.playSounds },
                                                 set: { on in model.updateStandalone { $0.playSounds = on } }))
                }
            }
            ForEach([NidaAudioSettings.Category.adhan, .fajrAdhan, .preAdhanJingle], id: \.self) { category in
                if showsPlaySwitch || category != .adhan { SettingsDivider() }
                soundRow(category)
            }
            VStack(alignment: .leading, spacing: 4) {
                if model.catalogFailed {
                    HStack {
                        Text(l.t("library.failed")).font(.caption2).foregroundStyle(.orange)
                        Spacer()
                        Button(l.t("action.retry"), action: model.loadCatalog).controlSize(.mini)
                    }
                }
                HStack(alignment: .bottom) {
                    Text(l.t("library.help")).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button(l.t(model.playing == nil ? "action.test" : "action.stop"), action: model.testSound)
                        .controlSize(.mini)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
        }
        .onAppear(perform: model.loadCatalog)
    }

    private func soundRow(_ c: NidaAudioSettings.Category) -> some View {
        let id = model.playingSoundId(c) ?? ""
        return VStack(spacing: 2) {
            SettingsRow(symbol: symbol(c), tint: .teal, title: l.t("sound.\(c.rawValue)")) {
                if model.downloading.contains(id) {
                    ProgressView().controlSize(.mini)
                } else if model.failedDownloads.contains(id) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .help(l.t("library.downloadFailed"))
                        .accessibilityLabel(l.t("library.downloadFailed"))
                }
            }
            HStack(spacing: 6) {
                Menu {
                    if c == .preAdhanJingle {
                        Button(l.t("sound.languageJingle")) {
                            model.updateStandalone { $0.sounds[c.rawValue] = StandaloneSettings.languageJingle }
                        }
                        Divider()
                    }
                    ForEach(model.catalogSounds(for: c)) { sound in
                        Button(sound.label) { model.updateStandalone { $0.sounds[c.rawValue] = sound.id } }
                    }
                } label: {
                    Text(soundLabel(c)).lineLimit(1).truncationMode(.tail)
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(model.catalog.isEmpty)
                Slider(value: Binding(get: { Double(model.standalone.volume(c)) },
                                      set: { v in model.updateStandalone { $0.volumes[c.rawValue] = Int(v.rounded()) } }),
                       in: 0...100, step: 5)
                    .controlSize(.mini)
                    .frame(width: 70)
                    .accessibilityLabel(l.t("sound.volume", l.t("sound.\(c.rawValue)")))
                Text("\(model.standalone.volume(c))%").font(.caption2).monospacedDigit().frame(width: 32, alignment: .trailing)
            }
            .padding(.leading, 36).padding(.trailing, 8).padding(.bottom, 4)
        }
        .opacity(model.standalone.playSounds ? 1 : 0.5)
    }

    private func soundLabel(_ c: NidaAudioSettings.Category) -> String {
        model.standalone.soundId(c) == StandaloneSettings.languageJingle ? l.t("sound.languageJingle") : model.soundLabel(c)
    }

    private func symbol(_ c: NidaAudioSettings.Category) -> String {
        switch c {
        case .adhan: return "speaker.wave.3"
        case .fajrAdhan: return "moon"
        case .preAdhanJingle: return "music.note"
        }
    }
}
