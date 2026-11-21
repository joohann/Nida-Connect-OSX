import AppKit
import Combine

/// Combines Nida's data from Home Assistant, the clock and the settings for the UI.
@MainActor
final class PrayerModel: ObservableObject {
    @Published private(set) var now: Date
    /// The prayer time whose gold label was ended by opening the panel.
    @Published private var dismissedSignal: Date?
    /// Until when the gold label shows as a preview.
    @Published private var signalPreviewUntil: Date?
    /// The prayer curtain while it is closed.
    @Published private(set) var curtain: CurtainMoment?
    /// The prayer time the curtain last closed for, so it closes once per prayer.
    private var curtainHandled: Date?
    /// The prayer day in use: Nida's at home, Aladhan's for the current place when away.
    @Published private(set) var day: PrayerDay
    /// Set while the Mac is more than `away.distanceKm` from Nida's location.
    @Published private(set) var away: AwayPlace?
    @Published private(set) var locationStatus: LocationStatus = .notDetermined
    @Published private(set) var preAdhan: PreAdhanSettings
    @Published private(set) var connection: ConnectionState = .notConfigured
    @Published private(set) var settings: AppSettings
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var notificationsDenied = false
    @Published private(set) var isRefreshing = false
    /// The address chosen at sign-in.
    @Published private(set) var server: ServerAddress?
    /// The address the live connection uses: home, external or Nabu Casa.
    @Published private(set) var activeRoute: ServerAddress?
    @Published private(set) var endpoints: HAEndpoints
    /// Nida's sound settings: which adhan and jingle, volumes, per-prayer switches, guest mode.
    @Published private(set) var audio: NidaAudioSettings
    /// The sound playing right now, shown with a Stop button.
    @Published private(set) var playing: PlannedSound?
    /// How the app is signed in, or nil when it is not.
    @Published private(set) var signIn: SignInMethod?
    @Published private(set) var isLoggingIn = false
    @Published private(set) var loginError: AuthError?
    /// macOS blocks local network access for this app (System Settings, Privacy, Local Network).
    @Published private(set) var localNetworkDenied = false
    /// Version found by a background update check, shown on the card until the user acts on it.
    @Published private(set) var availableUpdate: String?
    /// Home Assistant instances found on the local network while the connection form is open.
    @Published private(set) var discovered: [DiscoveredServer] = []
    /// Settings for running without Home Assistant.
    @Published private(set) var standalone: StandaloneSettings
    /// The setup step to open at, set by a Change button in the settings; the setup takes it once.
    @Published var setupEntry: Int?
    /// The Nida sound library, loaded when running without Home Assistant.
    @Published private(set) var catalog: [CatalogSound] = []
    @Published private(set) var catalogFailed = false
    /// Library sounds being downloaded right now, by catalog id.
    @Published private(set) var downloading: Set<String> = []
    /// Library sounds that could not be fetched or did not match their checksum, by catalog id.
    @Published private(set) var failedDownloads: Set<String> = []

    let config: AppConfig
    private let source: NidaSource
    private let credentials: CredentialStoring
    /// Read once from the Keychain and kept in memory, so macOS does not ask on every reconnect.
    private var credential: HACredential?
    private let makeLogin: () -> LoopbackLogin
    private let openURL: (URL) -> Void
    private var loginTask: Task<Void, Never>?
    private var discoveryWanted = false
    private let loginItem: LoginItemManaging
    private let preferences: PreferencesStoring
    private let notifier: NotificationPosting
    private let planner: NotificationPlanner
    private let updater: UpdateManaging
    private let discovery: ServerDiscovering?
    private let sounds: SoundCaching?
    private let player: SoundPlaying?
    private let soundPlanner = SoundPlanner()
    private let soundCatalog: SoundCatalogLoading?
    private var catalogTask: Task<Void, Never>?
    private let location: LocationProviding?
    private let aladhan: AladhanClient?
    private var nidaDay: PrayerDay
    private var awayDay: (day: PrayerDay, place: Coordinate, date: String)?
    private var awayFetch: Task<Void, Never>?
    private var method: Int
    private var nidaHome: Coordinate?
    private var haHome: Coordinate?
    private var lastAwayCheck = Date.distantPast
    private let clock: () -> Date
    private let prayerClock = PrayerClock()
    private var scheduledPlan: [PlannedNotification]?
    private var ticker: Timer?
    private var wake: AnyCancellable?
    private var settingsTask: Task<Void, Never>?
    /// The app's language code, for the voiced Nida jingle.
    private let language: String
    private let media: MediaPausing?
    /// True while other media is paused for our sound, so only our own pause gets resumed.
    private var pausedMedia = false

    init(config: AppConfig, source: NidaSource, credentials: CredentialStoring,
         makeLogin: @escaping () -> LoopbackLogin, openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
         loginItem: LoginItemManaging,
         preferences: PreferencesStoring, notifier: NotificationPosting, planner: NotificationPlanner,
         updater: UpdateManaging? = nil, discovery: ServerDiscovering? = nil,
         sounds: SoundCaching? = nil, player: SoundPlaying? = nil,
         location: LocationProviding? = nil, aladhan: AladhanClient? = nil,
         soundCatalog: SoundCatalogLoading? = nil, language: String = "en", media: MediaPausing? = nil,
         clock: @escaping () -> Date = Date.init) {
        self.config = config
        self.source = source
        self.credentials = credentials
        self.makeLogin = makeLogin
        self.openURL = openURL
        self.loginItem = loginItem
        self.preferences = preferences
        self.notifier = notifier
        self.planner = planner
        self.updater = updater ?? NoUpdates()
        self.discovery = discovery
        self.sounds = sounds
        self.player = player
        self.location = location
        self.aladhan = aladhan
        self.soundCatalog = soundCatalog
        self.language = language
        self.media = media
        self.standalone = preferences.standalone ?? StandaloneSettings()
        let calc = preferences.lastCalculation ?? .nidaDefault
        self.method = calc.method
        self.nidaHome = calc.home
        self.audio = preferences.lastAudio ?? .nidaDefault
        self.clock = clock
        self.now = clock()
        self.nidaDay = preferences.lastDay ?? PrayerDay()
        self.day = preferences.lastDay ?? PrayerDay()
        self.preAdhan = preferences.lastPreAdhan ?? .nidaDefault
        self.settings = preferences.load()
        self.launchAtLogin = loginItem.isEnabled
        self.server = preferences.serverAddress.flatMap(ServerAddress.init)
        self.endpoints = preferences.endpoints ?? HAEndpoints()
        let stored = credentials.load()
        self.credential = stored
        self.signIn = stored.map(SignInMethod.init)
        if settings.source == .standalone {
            day = preferences.lastStandaloneDay ?? PrayerDay()
            preAdhan = standalone.preAdhan
            audio = standalone.audio(language: language)
        }
        start()
    }

    /// The colon toggles on every whole second of the system clock, like the menu bar clock's
    /// flashing separators: visible on even seconds, hidden on odd ones.
    var colonVisible: Bool {
        guard settings.blinkColon else { return true }
        let second = Int(now.timeIntervalSince1970.rounded(.down))
        return second % 2 == 0
    }

    var upcoming: UpcomingPrayer? { prayerClock.upcoming(day: day, preAdhan: preAdhan, now: now) }

    /// The prayer the menu bar shows as a gold label: its time began less than the chosen minutes
    /// ago and the panel has not been opened since.
    var prayerSignal: Prayer? {
        if let until = signalPreviewUntil, now < until {
            return upcoming?.prayer ?? .dhuhr
        }
        guard settings.prayerSignal,
              let started = prayerClock.justStarted(day: day, now: now,
                                                    duration: TimeInterval(settings.prayerSignalMinutes * 60)),
              started.date != dismissedSignal else { return nil }
        return started.prayer
    }

    /// Shows the gold label for the upcoming prayer for a while, to see what it looks like.
    func previewPrayerSignal(seconds: TimeInterval) {
        signalPreviewUntil = clock().addingTimeInterval(seconds)
    }

    /// Opening the panel ends the gold label, like it stops a playing sound.
    func dismissPrayerSignal() {
        signalPreviewUntil = nil
        guard settings.prayerSignal,
              let started = prayerClock.justStarted(day: day, now: now,
                                                    duration: TimeInterval(settings.prayerSignalMinutes * 60))
        else { return }
        dismissedSignal = started.date
    }

    // MARK: Curtain

    /// How long after the adhan the curtain opens by itself, so the Mac never stays locked.
    static let curtainOpensAfter: TimeInterval = 20 * 60
    /// The curtain only closes in the first minute of a prayer, not when the app starts later.
    private static let curtainCloseWindow: TimeInterval = 60

    private func updateCurtain() {
        if let curtain, now >= curtain.opensAt { openCurtain(reason: "time is up") }
        guard settings.prayerCurtain, curtain == nil,
              let started = prayerClock.justStarted(day: day, now: now, duration: Self.curtainCloseWindow),
              started.date != curtainHandled else { return }
        curtainHandled = started.date
        curtain = CurtainMoment(prayer: started.prayer, time: started.date,
                                opensAt: started.date.addingTimeInterval(Self.curtainOpensAfter))
        Log.curtain.notice("closed for \(started.prayer.rawValue, privacy: .public)")
    }

    /// Opens the curtain, for instance when ⌘ + Esc was held.
    func openCurtain(reason: String) {
        guard curtain != nil else { return }
        curtain = nil
        Log.curtain.notice("opened: \(reason, privacy: .public)")
    }

    /// Closes the curtain at once for the upcoming prayer, to see what it looks like.
    func previewCurtain(seconds: TimeInterval) {
        curtain = CurtainMoment(prayer: upcoming?.prayer ?? .dhuhr, time: now,
                                opensAt: now.addingTimeInterval(seconds))
    }

    /// The phase the menu bar shows in colour; `.normal` when colours are switched off.
    var menuBarPhase: CountdownPhase {
        guard settings.colorPreAdhan else { return .normal }
        return upcoming?.phase ?? .normal
    }

    // MARK: Actions

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        if isStandalone {
            awayDay = nil
            refreshAway()
            loadCatalog()
        } else if connection == .connected { source.refreshSettings() } else { connectIfConfigured() }
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            isRefreshing = false
        }
    }

    /// Saves the address and a long-lived token and connects. Returns false when something is invalid.
    @discardableResult
    func saveConnection(address: String, token: String) -> Bool {
        guard let server = ServerAddress(address) else { return false }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            let next = HACredential.longLived(token: token)
            do { try credentials.save(next) } catch { return false }
            credential = next
        } else if credential == nil {
            return false
        }
        use(server: server, credential: credential)
        return true
    }

    /// Opens Home Assistant's login page in the browser and waits for the redirect.
    func login(address: String) {
        guard let server = ServerAddress(address), !isLoggingIn else { return }
        isLoggingIn = true
        loginError = nil
        let login = makeLogin()
        loginTask = Task { [weak self] in
            do {
                let result = try await login.run(server: server) { url in self?.openURL(url) }
                guard let self else { return }
                try? self.credentials.save(result.credential)
                self.credential = result.credential
                self.use(server: server, credential: result.credential,
                         seed: (result.accessToken, result.expires))
            } catch let error as AuthError {
                if error != .cancelled { self?.loginError = error }
            } catch {
                self?.loginError = .unreachable
            }
            self?.isLoggingIn = false
            self?.loginTask = nil
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func cancelLogin() {
        loginTask?.cancel()
    }

    /// Signs out: revokes an OAuth refresh token in Home Assistant and removes everything stored.
    func forgetConnection() {
        if let server, case .oauth(let refresh, _)? = credential {
            Task { await HomeAssistantTokenAPI().revoke(server: server, refreshToken: refresh) }
        }
        credentials.delete()
        credential = nil
        preferences.endpoints = nil
        endpoints = HAEndpoints()
        activeRoute = nil
        preferences.serverAddress = nil
        server = nil
        signIn = nil
        source.disconnect()
    }

    /// Bonjour browsing while the connection form is open; it also tells whether macOS blocks the local network.
    func startDiscovery() {
        discoveryWanted = true
        runDiscovery(true)
    }

    func stopDiscovery() {
        discoveryWanted = false
        runDiscovery(discoveryNeeded)
    }

    func openLocalNetworkSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
            openURL(url)
        }
    }

    private func runDiscovery(_ on: Bool) {
        guard let discovery else { return }
        if on {
            discovery.onChange = { [weak self, weak discovery] in
                guard let self, let discovery else { return }
                self.discovered = discovery.servers
                self.localNetworkDenied = discovery.isDenied
            }
            discovery.start()
        } else {
            discovery.stop()
        }
    }

    private func use(server: ServerAddress, credential: HACredential?,
                     seed: (token: String, expires: Date)? = nil) {
        if server != self.server, !endpoints.routes(primary: server).contains(where: { $0 == self.server }) {
            // Another Home Assistant: its old addresses no longer apply.
            endpoints = HAEndpoints()
            preferences.endpoints = nil
        }
        preferences.serverAddress = server.baseURL.absoluteString
        self.server = server
        signIn = credential.map(SignInMethod.init)
        loginError = nil
        connectIfConfigured(seed: seed)
    }

    // MARK: Setup

    /// The first-launch setup shows until it is finished. Someone already signed in (an update
    /// from a version without setup) does not need it; it stays available from the settings.
    var needsSetup: Bool {
        if !preferences.setupDone && signIn != nil { preferences.setupDone = true }
        return !preferences.setupDone
    }

    func finishSetup() {
        preferences.setupDone = true
    }

    func setLaunchAtLogin(_ on: Bool) {
        guard on != loginItem.isEnabled else { return }
        toggleLaunchAtLogin()
    }

    /// Asks macOS for permission now, so the question comes during setup and not at the first prayer.
    func requestNotificationPermission() {
        Task { await authorizeNotifications() }
    }

    func toggleLaunchAtLogin() {
        try? loginItem.setEnabled(!loginItem.isEnabled)
        launchAtLogin = loginItem.isEnabled
    }

    func checkForUpdates() {
        updater.checkNow()
    }

    func update(_ change: (inout AppSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        let turnedOn = next.wantsNotifications && !settings.wantsNotifications
        settings = next
        preferences.save(next)
        updater.automaticallyChecks = next.checkForUpdates
        if !next.prayerCurtain && curtain != nil { openCurtain(reason: "switched off") }
        runDiscovery(discoveryNeeded)
        if !next.checkForUpdates { availableUpdate = nil }
        scheduleNotifications(force: true)
        if turnedOn { Task { await authorizeNotifications() } }
    }

    // MARK: Without Home Assistant

    var isStandalone: Bool { settings.source == .standalone }

    /// True when the app still needs a Home Assistant connection before it can show anything.
    var needsConnection: Bool { !isStandalone && connection == .notConfigured }

    /// Name of the place the times are for: the picked place, the Mac's place, or the away place.
    var timesPlaceName: String? {
        if isStandalone { return standalone.manualPlace?.name ?? location?.placeName }
        return away?.name
    }

    /// Switches between Nida in Home Assistant and running on its own.
    func setSource(_ source: PrayerSource) {
        guard source != settings.source else { return }
        update { $0.source = source }
        awayDay = nil
        if source == .standalone {
            self.source.disconnect()
            connection = .notConfigured
            preAdhan = standalone.preAdhan
            audio = standalone.audio(language: language)
            loadCatalog()
            location?.requestPermission()
        } else {
            preAdhan = preferences.lastPreAdhan ?? .nidaDefault
            audio = preferences.lastAudio ?? .nidaDefault
            connectIfConfigured()
        }
        setAway(nil)
        refreshAway()
        scheduleNotifications(force: true)
    }

    /// Changes the settings for running without Home Assistant and applies them at once.
    func updateStandalone(_ change: (inout StandaloneSettings) -> Void) {
        var next = standalone
        change(&next)
        guard next != standalone else { return }
        let placeChanged = next.method != standalone.method || next.manualPlace != standalone.manualPlace
        standalone = next
        preferences.standalone = next
        guard isStandalone else { return }
        preAdhan = next.preAdhan
        audio = next.audio(language: language)
        if placeChanged { awayDay = nil; refreshAway() }
        fetchStandaloneSounds()
        scheduleNotifications(force: true)
    }

    /// Picks the adhan voice; the Fajr adhan follows with the same reciter when the library has one.
    func chooseVoice(_ sound: CatalogSound) {
        let fajr = sound.id.replacingOccurrences(of: "adhan_day_", with: "adhan_fajr_")
        let hasFajr = catalog.contains { $0.id == fajr && $0.kind == .fajr }
        updateStandalone {
            $0.sounds[NidaAudioSettings.Category.adhan.rawValue] = sound.id
            if hasFajr { $0.sounds[NidaAudioSettings.Category.fajrAdhan.rawValue] = fajr }
        }
    }

    func searchPlaces(_ query: String) async -> [NamedPlace] {
        await location?.search(query) ?? []
    }

    /// Loads the Nida sound library once, then makes sure the chosen sounds are on this Mac.
    func loadCatalog() {
        guard let soundCatalog, catalogTask == nil else { return }
        if !catalog.isEmpty { fetchStandaloneSounds(); return }
        catalogFailed = false
        catalogTask = Task { [weak self] in
            let result = try? await soundCatalog.load()
            guard let self else { return }
            self.catalogTask = nil
            if let result {
                self.catalog = result
                self.fetchStandaloneSounds()
            } else {
                self.catalogFailed = true
            }
        }
    }

    func catalogSounds(for category: NidaAudioSettings.Category) -> [CatalogSound] {
        let kind = CatalogSound.kind(for: category)
        return catalog.filter { $0.kind == kind }
    }

    /// The label of the chosen sound, from the library or, before it loaded, from its id.
    func soundLabel(_ category: NidaAudioSettings.Category) -> String {
        guard let id = standalone.soundId(category) else { return "–" }
        return catalog.first { $0.id == id }?.label ?? id
    }

    /// The library sound that plays for a category, with the language jingle resolved.
    func playingSoundId(_ category: NidaAudioSettings.Category) -> String? {
        standalone.soundId(category, language: language)
    }

    private func fetchStandaloneSounds() {
        guard let sounds, isStandalone else { return }
        let wanted = NidaAudioSettings.Category.allCases.compactMap { c in
            playingSoundId(c).flatMap { id in catalog.first { $0.id == id } }
        }
        for sound in wanted where !downloading.contains(sound.id) {
            guard sounds.localURL(for: SoundLibrary.catalogFile(sound.id)) == nil else { continue }
            downloading.insert(sound.id)
            failedDownloads.remove(sound.id)
            Task { [weak self] in
                let ok = await sounds.fetch(sound)
                self?.downloading.remove(sound.id)
                if !ok { self?.failedDownloads.insert(sound.id) }
            }
        }
    }

    // MARK: Lifecycle

    private func start() {
        updater.automaticallyChecks = settings.checkForUpdates
        updater.onUpdateFound = { [weak self] version in self?.updateFound(version) }
        updater.onUpdateHandled = { [weak self] in self?.availableUpdate = nil }
        notifier.onStop = { [weak self] in self?.stopSound(reason: .notification) }
        player?.onFinish = { [weak self] in
            guard let self else { return }
            Log.sound.notice("finished after \(self.secondsPlayed, privacy: .public) s")
            self.playing = nil
            self.resumeMedia()
        }
        notifier.onOpen = { [weak self] id in
            if id == NotificationPlanner.updateId { self?.checkForUpdates() }
        }
        source.onEvent = { [weak self] event in self?.handle(event) }
        location?.onChange = { [weak self] in self?.refreshAway() }
        location?.start()

        scheduleTick()
        wake = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.now = self.clock()
                self.connectIfConfigured()
            }
        // Nida's settings change without a state event; re-read them every 10 minutes.
        settingsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 600_000_000_000)
                self?.source.refreshSettings()
            }
        }
        if settings.wantsNotifications {
            Task { await authorizeNotifications() }
        }
        scheduleNotifications(force: true)
        connectIfConfigured()
        if isStandalone { loadCatalog() }
    }

    /// Ticks on every whole second of the system clock. Each tick schedules the next one from the
    /// clock itself, so it never drifts; seconds and colon change together with the system clock.
    private func scheduleTick() {
        let reference = clock().timeIntervalSince1970
        let next = Date(timeIntervalSince1970: reference.rounded(.down) + 1)
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let previous = self.now
                self.now = self.clock()
                self.scheduleNotifications()
                self.playDueSound(since: previous)
                self.updateCurtain()
                if self.now.timeIntervalSince(self.lastAwayCheck) >= 60 { self.refreshAway() }
                self.scheduleTick()
            }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    // MARK: Away from home

    /// Home is Nida's own location, or Home Assistant's home when Nida follows it.
    var home: Coordinate? { nidaHome ?? haHome }

    func requestLocationPermission() {
        location?.requestPermission()
    }

    func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            openURL(url)
        }
    }

    private func saveCalculation() {
        preferences.lastCalculation = NidaCalculation(method: method, home: home)
        awayDay = nil   // method or home changed: fetch again
        refreshAway()
    }

    /// Decides between Nida's times and own times for the current place, and fetches those once
    /// per day and place (again after moving 5 km). Pre-adhan, sounds and notifications stay Nida's.
    private func refreshAway() {
        lastAwayCheck = now
        locationStatus = location?.status ?? .denied
        if isStandalone {
            refreshStandalone()
            return
        }
        guard let here = location?.current, let home else {
            setAway(nil)
            return
        }
        let distance = here.distanceKm(to: home)
        guard distance > config.away.distanceKm else {
            setAway(nil)
            return
        }
        setAway(AwayPlace(name: location?.placeName, distanceKm: distance))
        let today = Self.dayKey(now)
        if let cached = awayDay, cached.date == today, cached.place.distanceKm(to: here) < 5 { return }
        guard awayFetch == nil, let aladhan else { return }
        let method = self.method
        awayFetch = Task { [weak self] in
            let result = try? await aladhan.day(for: Date(), at: here, method: method)
            guard let self else { return }
            self.awayFetch = nil
            guard let result else { return }
            self.awayDay = (result, here, today)
            self.useDay()
        }
    }

    /// Without Home Assistant: Aladhan's times for the picked place or the Mac's place, fetched once
    /// per day and place (again after moving 5 km).
    private func refreshStandalone() {
        if away != nil { away = nil }
        guard let here = standalone.manualPlace?.coordinate ?? location?.current else { return }
        let today = Self.dayKey(now)
        if let cached = awayDay, cached.date == today, cached.place.distanceKm(to: here) < 5 { return }
        guard awayFetch == nil, let aladhan else { return }
        let method = standalone.method
        awayFetch = Task { [weak self] in
            let result = try? await aladhan.day(for: Date(), at: here, method: method)
            guard let self else { return }
            self.awayFetch = nil
            guard let result, self.isStandalone else { return }
            self.awayDay = (result, here, today)
            self.preferences.lastStandaloneDay = result
            self.useDay()
        }
    }

    private func setAway(_ next: AwayPlace?) {
        if next == nil { awayDay = nil }
        if next != away { away = next }
        useDay()
    }

    /// Switches to the right day and replans notifications when it changed.
    private func useDay() {
        let next: PrayerDay
        if isStandalone {
            next = awayDay?.day ?? preferences.lastStandaloneDay ?? PrayerDay()
        } else {
            next = (away != nil ? awayDay?.day : nil) ?? nidaDay
        }
        guard next != day else { return }
        day = next
        scheduleNotifications(force: true)
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    // MARK: Sound

    /// Whether the Mac plays the sounds itself right now. In "away" mode only away from home, where
    /// Home Assistant's own speakers cannot be heard; in "home" mode only at home.
    var playsSoundsHere: Bool {
        if isStandalone { return standalone.playSounds }
        switch settings.playbackMode {
        case .off: return false
        case .always: return true
        case .away: return awayFromHome
        case .home: return !awayFromHome
        }
    }

    /// Away from home: connected over Nabu Casa or the external address, and Home Assistant is not
    /// on the Mac's network.
    private var awayFromHome: Bool {
        (routeKind == .nabuCasa || routeKind == .external) && !onHomeNetwork
    }

    /// The modes that depend on where the Mac is.
    private var playbackFollowsLocation: Bool {
        !isStandalone && (settings.playbackMode == .away || settings.playbackMode == .home)
    }

    /// True when this Home Assistant announces itself on the network the Mac is on, so the Mac is at
    /// home even when it connects through the external address or Nabu Casa.
    var onHomeNetwork: Bool {
        guard let name = endpoints.locationName else { return false }
        return discovered.contains { $0.name == name }
    }

    /// Home detection needs Bonjour while playback depends on being home or away.
    private var discoveryNeeded: Bool {
        discoveryWanted || (connection != .connected && connection != .notConfigured)
            || playbackFollowsLocation
    }

    /// Why a sound was stopped early, for the log.
    enum StopReason: String {
        case panel, notification, test, stopButton
    }

    func stopSound(reason: StopReason) {
        guard playing != nil else { return }
        Log.sound.notice("stopped by \(reason.rawValue, privacy: .public) after \(self.secondsPlayed, privacy: .public) s")
        player?.stop()
        playing = nil
        resumeMedia()
    }

    private var soundStarted: Date?
    private var secondsPlayed: Int { Int((soundStarted.map { clock().timeIntervalSince($0) } ?? 0).rounded()) }

    /// Plays Nida's own file at Nida's own volume, from the local copy.
    func play(_ sound: PlannedSound) {
        guard let player, let url = sounds?.localURL(for: sound.file) else {
            Log.sound.notice("not available locally: \(sound.file, privacy: .public)")
            return
        }
        if playing != nil { Log.sound.notice("replaced after \(self.secondsPlayed, privacy: .public) s") }
        if settings.pauseMedia && !pausedMedia, let media {
            pausedMedia = media.pauseIfPlaying()
            Log.sound.notice("other media \(self.pausedMedia ? "paused" : "not playing", privacy: .public)")
        }
        if player.play(url, volume: sound.volume) {
            playing = sound
            soundStarted = clock()
            Log.sound.notice("""
                started \(String(describing: sound.kind), privacy: .public) for \(sound.prayer.rawValue, privacy: .public): \
                \(sound.file, privacy: .public) at \(sound.volume, privacy: .public)%
                """)
        } else {
            Log.sound.notice("could not play \(sound.file, privacy: .public)")
            resumeMedia()
        }
    }

    private func resumeMedia() {
        guard pausedMedia else { return }
        pausedMedia = false
        media?.resume()
        Log.sound.notice("other media resumed")
    }

    /// Plays the pre-adhan jingle once, to check the volume.
    func testSound() {
        if playing != nil { stopSound(reason: .test); return }
        guard let prayer = upcoming?.prayer ?? Prayer.allCases.first else { return }
        play(PlannedSound(prayer: prayer, kind: .preAdhan, file: audio.sounds[.preAdhanJingle] ?? "",
                          volume: audio.volumes[.preAdhanJingle] ?? 20))
    }

    private func playDueSound(since previous: Date) {
        guard let sound = soundPlanner.due(from: previous, to: now, day: day,
                                           preAdhan: preAdhan, audio: audio) else { return }
        guard playsSoundsHere else {
            if playbackFollowsLocation {
                Log.sound.notice("""
                    not played: \(self.awayFromHome ? "away from home" : "at home", privacy: .public) \
                    (\(self.settings.playbackMode.rawValue, privacy: .public) mode)
                    """)
            }
            return
        }
        play(sound)
    }

    /// Keeps local copies of the chosen files, fetched over whichever address is in use.
    private func fetchSounds() {
        guard let sounds, let route = activeRoute else { return }
        let files = Array(Set(audio.sounds.values))
        Task { await sounds.fetch(files, from: route) }
    }

    private func connectIfConfigured(seed: (token: String, expires: Date)? = nil) {
        guard !isStandalone else {
            connection = .notConfigured
            return
        }
        guard let server, let credential else {
            connection = .notConfigured
            return
        }
        source.connect(routes: endpoints.routes(primary: server),
                       auth: HomeAssistantAuth(credential: credential, seed: seed))
    }

    private func handle(_ event: NidaEvent) {
        // Without Home Assistant nothing from Nida applies; a late event is ignored.
        if isStandalone { return }
        switch event {
        case .state(let state):
            connection = state
            // While Home Assistant is out of reach, check whether macOS blocks the local network.
            if state == .connected { localNetworkDenied = false }
            runDiscovery(discoveryNeeded)
        case .day(let next):
            guard next != nidaDay else { return }
            nidaDay = next
            if next.isComplete { preferences.lastDay = next }
            useDay()
        case .calculation(let m, let home):
            method = m
            nidaHome = home
            saveCalculation()
        case .haHome(let home):
            haHome = home
            saveCalculation()
        case .route(let address):
            activeRoute = address
            fetchSounds()
        case .audio(let next):
            guard next != audio else { return }
            audio = next
            preferences.lastAudio = next
            fetchSounds()
        case .endpoints(let next):
            guard next != endpoints else { return }
            endpoints = next
            preferences.endpoints = next
            if let server { source.update(routes: next.routes(primary: server)) }
        case .preAdhan(let next):
            guard next != preAdhan else { return }
            preAdhan = next
            preferences.lastPreAdhan = next
            scheduleNotifications(force: true)
        }
    }

    private func updateFound(_ version: String) {
        Log.update.info("update found: \(version, privacy: .public)")
        availableUpdate = version
        if let note = planner.updateNote(version: version, settings: settings,
                                         notified: preferences.notifiedUpdateVersion) {
            preferences.notifiedUpdateVersion = version
            notifier.post(note)
        }
    }

    private func authorizeNotifications() async {
        _ = await notifier.requestAuthorization()
        notificationsDenied = await notifier.isDenied()
    }

    /// Reschedules only when the plan changed, e.g. after a prayer passed or settings changed.
    private func scheduleNotifications(force: Bool = false) {
        let plan = planner.prayerPlan(day: day, preAdhan: preAdhan, now: now, settings: settings)
        guard force || plan.map(\.id) != scheduledPlan?.map(\.id) else { return }
        scheduledPlan = plan
        notifier.replaceScheduled(plan, ids: NotificationPlanner.prayerIds)
    }
}

/// How the app is signed in to Home Assistant, for display.
enum SignInMethod: Equatable {
    case loginPage
    case token

    init(_ credential: HACredential) {
        switch credential {
        case .oauth: self = .loginPage
        case .longLived: self = .token
        }
    }
}

/// Which kind of address the connection uses, for display.
enum RouteKind: Equatable {
    case home, external, nabuCasa
}

extension PrayerModel {
    var routeKind: RouteKind? {
        guard let route = activeRoute, connection == .connected else { return nil }
        if endpoints.isCloud(route) { return .nabuCasa }
        return route.isLocal ? .home : .external
    }
}

/// Where the Mac is when it is away from Nida's location. Value object.
struct AwayPlace: Equatable {
    let name: String?
    let distanceKm: Double
}
