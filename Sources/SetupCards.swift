import SwiftUI

/// A selectable card with an icon, a title, a line of explanation and an optional sample on the right.
/// The chosen card gets a gold border.
struct ChoiceCard<Trailing: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let trailing: Trailing

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CardIcon(symbol: symbol, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                trailing
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? MenuBarRenderer.goldColor : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A card with a switch; extra content (such as minutes or a sample) goes under the explanation.
struct ToggleCard<Extra: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    @Binding var isOn: Bool
    @ViewBuilder let extra: Extra

    var body: some View {
        HStack(spacing: 12) {
            CardIcon(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                extra.opacity(isOn ? 1 : 0.4)
            }
            Spacer(minLength: 6)
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .accessibilityLabel(title)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}

struct CardIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(tint))
    }
}

/// The menu bar as it looks in one style, drawn exactly like the real one.
struct MenuBarSample: View {
    @ObservedObject var model: PrayerModel
    let l: Localizing
    let style: MenuBarStyle

    var body: some View {
        var s = model.settings
        s.menuBarStyle = style
        let remaining: TimeInterval = 84 * 60 + 7
        let time = Formatters.menuBarCountdown(remaining, showSeconds: s.showSeconds, secondsAlways: s.showSecondsAlways)
        let text = style == .time ? Formatters.time.string(from: model.now.addingTimeInterval(remaining))
            : (s.showPrayerName ? l.t(Prayer.asr.localizationKey) + " " : "") + time
        return Image(nsImage: style == .icon
                        ? MenuBarRenderer.image(symbol: "moon.stars.fill", text: "", color: nil, useLogo: true)
                        : MenuBarRenderer.image(symbol: s.showsMoon ? "moon.stars.fill" : nil, text: text, color: nil))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
    }
}

/// Without Home Assistant: the adhan voice and how loud it plays. The Fajr adhan follows the voice.
struct VoiceRow: View {
    @ObservedObject var model: PrayerModel
    let l: Localizing

    var body: some View {
        let id = model.playingSoundId(.adhan) ?? ""
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(l.t("sound.voice")).font(.callout).foregroundStyle(.secondary)
                Menu {
                    ForEach(model.catalogSounds(for: .adhan)) { sound in
                        Button(sound.label) { model.chooseVoice(sound) }
                    }
                } label: {
                    Text(model.soundLabel(.adhan)).lineLimit(1).truncationMode(.tail)
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(model.catalog.isEmpty)
                if model.downloading.contains(id) {
                    ProgressView().controlSize(.mini)
                } else if model.failedDownloads.contains(id) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .help(l.t("library.downloadFailed"))
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.1").foregroundStyle(.secondary)
                Slider(value: Binding(get: { Double(model.standalone.volume(.adhan)) },
                                      set: { v in model.updateStandalone { $0.volumes[NidaAudioSettings.Category.adhan.rawValue] = Int(v.rounded()) } }),
                       in: 0...100, step: 5)
                    .controlSize(.small)
                    .accessibilityLabel(l.t("sound.volume", l.t("sound.adhan")))
                Text("\(model.standalone.volume(.adhan))%").font(.caption).monospacedDigit().frame(width: 34, alignment: .trailing)
                Button(l.t(model.playing == nil ? "action.test" : "action.stop"), action: model.testSound).controlSize(.small)
            }
            Text(l.t("sound.voiceHelp")).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.catalogFailed {
                HStack {
                    Text(l.t("library.failed")).font(.caption2).foregroundStyle(.orange)
                    Spacer()
                    Button(l.t("action.retry"), action: model.loadCatalog).controlSize(.mini)
                }
            }
        }
        .padding(.horizontal, 12)
    }
}
