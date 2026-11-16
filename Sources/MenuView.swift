import SwiftUI

/// The panel: a card with the upcoming prayer on the front and settings on the back.
struct MenuView: View {
    @ObservedObject var model: PrayerModel
    let l: Localizing
    @State var showsSettings = false
    @State private var angle: Double = 0

    var body: some View {
        Group {
            if showsSettings || model.connection == .notConfigured {
                SettingsView(model: model, l: l, onDone: flip)
            } else {
                PrayerFront(model: model, l: l, onSettings: flip)
            }
        }
        .padding(14)
        .frame(width: 300)
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        .environment(\.layoutDirection, l.isRightToLeft ? .rightToLeft : .leftToRight)
        // A click on the menu bar while a sound plays stops it: opening the panel is that click.
        // The same click ends the gold prayer label.
        .onAppear {
            model.stopSound()
            model.dismissPrayerSignal()
        }
        // Closing the panel turns the card back to the front, so it always opens on the prayer.
        .background(PanelCloseObserver {
            showsSettings = false
            angle = 0
        })
    }

    /// Turns the card over: rotate to the edge, swap faces, rotate back in.
    private func flip() {
        withAnimation(.easeIn(duration: 0.12)) { angle = 90 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            showsSettings.toggle()
            angle = -90
            withAnimation(.easeOut(duration: 0.12)) { angle = 0 }
        }
    }
}

/// Front of the card. Display only; all logic lives in PrayerModel.
struct PrayerFront: View {
    @ObservedObject var model: PrayerModel
    let l: Localizing
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let sound = model.playing {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(Color.accentColor)
                    Text(l.t(sound.kind == .adhan ? "playing.adhan" : "playing.preAdhan",
                             l.t(sound.prayer.localizationKey)))
                        .font(.callout)
                    Spacer()
                    Button(l.t("action.stop"), action: model.stopSound).controlSize(.small)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.1)))
            }
            header
            if let next = model.upcoming {
                countdown(next)
                Divider()
                dayList(next)
            } else {
                Text(l.t("prayer.waiting")).font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            connectionRow
            if let version = model.availableUpdate {
                Divider()
                HStack {
                    Label(l.t("update.available", version), systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    Button(l.t("action.update"), action: model.checkForUpdates).controlSize(.small)
                }
            }
        }
    }

    private var phaseColor: Color {
        switch model.upcoming?.phase ?? .normal {
        case .normal: return .accentColor
        case .preAdhan1: return .orange
        case .preAdhan2: return .red
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 18))
                .foregroundStyle(phaseColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                if let next = model.upcoming {
                    Text(l.t("prayer.at", l.t(next.prayer.localizationKey), Formatters.time.string(from: next.date)))
                        .font(.headline)
                } else {
                    Text(model.config.appName).font(.headline)
                }
                if let away = model.away {
                    Label(l.t("location.timesFor", away.name ?? l.t("location.here")), systemImage: "location.fill")
                        .font(.caption).foregroundStyle(.blue)
                }
                if let hijri = model.day.hijri, let text = Formatters.hijri(hijri, locale: l.locale) {
                    Text(text).font(.callout).foregroundStyle(.secondary)
                }
                if let holiday = model.day.hijri?.holiday {
                    Text(holiday).font(.caption).foregroundStyle(.green)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                IconButton(symbol: "arrow.clockwise", help: l.t("action.refresh"),
                           spinning: model.isRefreshing, action: model.refresh)
                IconButton(symbol: "gearshape", help: l.t("action.settings"), action: onSettings)
            }
        }
    }

    private func countdown(_ next: UpcomingPrayer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Formatters.fullCountdown(next.remaining(at: model.now)))
                .font(.system(size: 34, weight: .medium).monospacedDigit())
                .foregroundStyle(next.phase == .normal ? Color.primary : phaseColor)
                .environment(\.layoutDirection, .leftToRight)
            if next.phase != .normal {
                Text(l.t(next.phase == .preAdhan2 ? "phase.preAdhan2" : "phase.preAdhan1"))
                    .font(.caption).foregroundStyle(phaseColor)
            }
            if next.isEstimate {
                Text(l.t("prayer.estimate")).font(.caption).foregroundStyle(.secondary)
            }
            if let progress = next.progress(at: model.now) {
                ProgressView(value: progress).tint(phaseColor)
            }
        }
    }

    private func dayList(_ next: UpcomingPrayer) -> some View {
        VStack(spacing: 2) {
            ForEach(Prayer.allCases, id: \.self) { prayer in
                let isNext = prayer == next.prayer && !next.isEstimate
                let passed = (model.day.times[prayer] ?? .distantFuture) <= model.now
                HStack {
                    Text(l.t(prayer.localizationKey))
                    Spacer()
                    Text(model.day.times[prayer].map(Formatters.time.string(from:)) ?? "–").monospacedDigit()
                }
                .font(.body.weight(isNext ? .semibold : .regular))
                .foregroundStyle(isNext ? phaseColor : (passed ? Color.secondary : Color.primary))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(isNext ? phaseColor.opacity(0.12) : .clear))
            }
        }
    }

    private var connectionRow: some View {
        let (symbol, color, key): (String, Color, String) = {
            switch model.connection {
            case .connected: return ("checkmark.circle.fill", .green, "connection.connected")
            case .connecting: return ("arrow.triangle.2.circlepath", .secondary, "connection.connecting")
            case .authFailed: return ("key.slash", .red, "connection.authFailed")
            case .nidaNotFound: return ("questionmark.circle", .orange, "connection.nidaNotFound")
            case .unreachable: return ("wifi.exclamationmark", .orange, "connection.unreachable")
            case .notConfigured: return ("gearshape", .secondary, "connection.notConfigured")
            }
        }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(color)
                Text(l.t(key)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let kind = model.routeKind {
                    Label(l.t(Self.routeKey(kind)), systemImage: Self.routeSymbol(kind))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        .help(model.activeRoute?.display ?? "")
                } else if let server = model.server {
                    Text(server.display).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            if model.localNetworkDenied {
                HStack(spacing: 6) {
                    Image(systemName: "network.slash").foregroundStyle(.orange)
                    Text(l.t("network.denied.title")).font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button(l.t("network.denied.open"), action: model.openLocalNetworkSettings).controlSize(.mini)
                }
            }
        }
    }
}

extension PrayerFront {
    static func routeKey(_ kind: RouteKind) -> String {
        switch kind {
        case .home: return "route.home"
        case .external: return "route.external"
        case .nabuCasa: return "route.nabuCasa"
        }
    }

    static func routeSymbol(_ kind: RouteKind) -> String {
        switch kind {
        case .home: return "house.fill"
        case .external: return "globe"
        case .nabuCasa: return "cloud.fill"
        }
    }
}

/// Small borderless icon button with a tooltip; optionally spins while busy.
struct IconButton: View {
    let symbol: String
    let help: String
    var spinning = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                           value: spinning)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }
}
