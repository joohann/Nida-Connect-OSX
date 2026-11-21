import AppKit
import Combine
import SwiftUI

/// A closed prayer curtain: for which prayer, and when it opens by itself. Value object.
struct CurtainMoment: Equatable {
    let prayer: Prayer
    let time: Date
    let opensAt: Date
}

/// What the curtain views show; shared by the curtains on every screen.
@MainActor
final class CurtainState: ObservableObject {
    @Published var moment: CurtainMoment?
    @Published var closed = false
    /// How far ⌘ + Esc has been held, from 0 to 1.
    @Published var holdProgress: Double = 0
}

/// Shows the prayer curtain over every screen while the model has one closed, below the menu bar.
/// It takes the keyboard and the mouse, so the Mac pauses for the prayer; holding ⌘ + Esc for two
/// seconds opens it.
@MainActor
final class CurtainPresenter {
    /// How long ⌘ + Esc must be held.
    static let holdTime: TimeInterval = 2
    /// How long the curtains take to close or open.
    static let slideTime: TimeInterval = 2.4
    private static let escapeKey: UInt16 = 53

    private let model: PrayerModel
    private let l: Localizing
    private let state = CurtainState()
    private var panels: [NSPanel] = []
    private var subscription: AnyCancellable?
    private var keyMonitor: Any?
    private var holdTimer: Timer?
    private var holdStart: Date?

    init(model: PrayerModel, l: Localizing) {
        self.model = model
        self.l = l
        subscription = model.$curtain.removeDuplicates().sink { [weak self] moment in
            MainActor.assumeIsolated { self?.show(moment) }
        }
    }

    private func show(_ moment: CurtainMoment?) {
        if let moment {
            state.moment = moment
            if panels.isEmpty { open() }
            DispatchQueue.main.async { self.state.closed = true }
        } else if !panels.isEmpty {
            cancelHold()
            state.closed = false
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.slideTime) { [weak self] in
                guard let self, self.model.curtain == nil else { return }
                self.close()
            }
        }
    }

    private func open() {
        for (index, screen) in NSScreen.screens.enumerated() {
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            var frame = screen.frame
            frame.size.height -= menuBar
            let panel = CurtainPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: CurtainView(state: state, l: l, showsText: index == 0))
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        panels.first?.makeKey()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self, self.panels.contains(where: { $0 === event.window }) else { return event }
            if event.type == .keyDown, event.keyCode == Self.escapeKey,
               event.modifierFlags.contains(.command), !event.isARepeat {
                self.startHold()
            }
            return nil
        }
    }

    private func close() {
        cancelHold()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panels.forEach { $0.orderOut(nil) }
        panels = []
        state.moment = nil
    }

    /// Follows the keys themselves while held, because macOS does not always send the key-up of a
    /// combination with ⌘.
    private func startHold() {
        guard holdTimer == nil else { return }
        holdStart = Date()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followHold() }
        }
    }

    private func followHold() {
        guard let holdStart else { return }
        let held = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(Self.escapeKey))
            && NSEvent.modifierFlags.contains(.command)
        guard held else { cancelHold(); return }
        let progress = Date().timeIntervalSince(holdStart) / Self.holdTime
        state.holdProgress = min(1, progress)
        if progress >= 1 {
            cancelHold()
            model.openCurtain(reason: "command-escape held")
        }
    }

    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        holdStart = nil
        state.holdProgress = 0
    }
}

/// A borderless panel that can take the keyboard without making the app active.
private final class CurtainPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Two dark curtains that slide in from the sides, with the prayer in the middle.
struct CurtainView: View {
    @ObservedObject var state: CurtainState
    let l: Localizing
    let showsText: Bool

    var body: some View {
        GeometryReader { geometry in
            let half = geometry.size.width / 2
            ZStack {
                HStack(spacing: 0) {
                    CurtainCloth(edge: .trailing).offset(x: state.closed ? 0 : -half)
                    CurtainCloth(edge: .leading).offset(x: state.closed ? 0 : half)
                }
                .animation(.easeInOut(duration: CurtainPresenter.slideTime), value: state.closed)
                if showsText, let moment = state.moment {
                    message(moment)
                        .opacity(state.closed ? 1 : 0)
                        .animation(state.closed ? .easeIn(duration: 0.8).delay(CurtainPresenter.slideTime - 0.6)
                                                : .easeOut(duration: 0.3), value: state.closed)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func message(_ moment: CurtainMoment) -> some View {
        VStack(spacing: 12) {
            Text(l.t(moment.prayer.localizationKey))
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(MenuBarRenderer.goldColor)
            Text(Formatters.time.string(from: moment.time))
                .font(.system(size: 20, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
            Text(l.t("curtain.title"))
                .font(.title3)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 8)
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 3)
                    Circle().trim(from: 0, to: state.holdProgress)
                        .stroke(MenuBarRenderer.goldColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 20, height: 20)
                Text(l.t("curtain.hint"))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.top, 24)
            Text(l.t("curtain.opensAt", Formatters.time.string(from: moment.opensAt)))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .multilineTextAlignment(.center)
    }
}

/// One half of the curtain: dark cloth with soft folds, a little lighter towards the middle.
private struct CurtainCloth: View {
    let edge: HorizontalEdge

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.06, blue: 0.07).opacity(0.93)
            HStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in
                    LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.035), .white.opacity(0.0)],
                                   startPoint: .leading, endPoint: .trailing)
                }
            }
            LinearGradient(colors: [.black.opacity(0.25), .clear],
                           startPoint: edge == .leading ? .trailing : .leading,
                           endPoint: edge == .leading ? .leading : .trailing)
        }
    }
}
