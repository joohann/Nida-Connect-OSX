# Changelog

## 1.3.0

### New

- **Setup that asks questions.** Each step asks one thing and picks the settings for you: how you want to see the time, how you want to be alerted, and whether this Mac plays the adhan. A Change button in the settings opens the setup at the right step.
- **Five menu bar styles.** Icon only (Nida's mosque, nothing else), Prayer time (the time of the next prayer, such as `15:42`), Compact (the countdown), With name and Precise (with seconds). Pick one in the setup or from the Style menu in the settings.
- **Nida's voice in your language.** Standalone, the pre-adhan jingle is now the voiced Nida jingle in the app's language (English when there is none). Any other jingle from the library can still be chosen.

### Changed

- **Shorter settings.** About ten rows: source, menu bar style, alerts, notifications, sound and general. Everything else (calculation method, pre-adhan per prayer, each sound and volume, seconds, blinking colon, separate notifications) is under Advanced, folded away.
- **One voice for the adhan.** Standalone, choosing the adhan voice also picks the Fajr adhan by the same reciter when the library has one.

## 1.2.0

### New

- **Works without Home Assistant.** Choose in the setup, or later under Source in the settings, between Nida in Home Assistant and standalone. Standalone, the prayer times come from Aladhan for where you are or for a place you search, with the calculation method you pick (23 methods, Muslim World League by default).
- **Pre-adhan in the app.** Standalone, set the first and second pre-adhan and switch them per prayer. Defaults are Nida's: 25 and 10 minutes.
- **Sounds from the Nida library.** Standalone, choose the adhan, the Fajr adhan and the pre-adhan jingle from the Nida sound library at nida.majikan.nl, each with its own volume. A sound is downloaded when you choose it, checked against the library's SHA-256 and kept on your Mac, so it also plays offline.

## 1.1.0

### New

- **Gold label at prayer time.** At the adhan the countdown in the menu bar becomes a gold label with the prayer's name, for 1, 5, 10 or 15 minutes (5 by default). It pulses with the system clock when the blinking colon is on. Opening the panel ends it. Useful when Focus mutes the notification: the label still shows. On by default; switch it off under Menu bar in the settings.
- **New install window.** The DMG opens in a green window in the style of the app icon, with an arrow from Nida Connect to Applications.

## 1.0.0

### New

- **Upcoming prayer in the menu bar.** Shows the next prayer from [Nida](https://github.com/joohann/Nida) in Home Assistant with a live countdown: `02:14` (hours:minutes) from an hour away, `47:09` (minutes:seconds) in the last hour, always with a leading zero.
- **Pre-adhan colours.** The countdown turns orange at the first pre-adhan and red at the second, using the minutes set in Nida.
- **Panel.** Big countdown, progress since the previous prayer, today's prayer times and the hijri date.
- **Notifications** at the first and second pre-adhan and at the adhan, each with its own switch.
- **Menu bar options.** By default only the countdown shows; turn on the icon and the prayer name if you like. Hide the seconds, or show them all the time (`02:14:05`, off by default).
- **Blinking colon** once per second in step with the system clock, so you can see the app is running. Can be switched off.
- **Finds Home Assistant by itself** on your network over Bonjour, like the Home Assistant iOS app; one click fills in the address. Local addresses without a scheme use http, like a default install.
- **Sign in with Home Assistant's own login page** in your browser (OAuth with PKCE), like the Home Assistant apps. Access tokens renew by themselves; signing out revokes the session in Home Assistant. A long-lived access token still works as an alternative.
- **Setup at first launch** in six steps: welcome, find and sign in to Home Assistant, menu bar (with a live example), notifications, away from home (location and sound), done. Run it again from the settings.
- **Live connection** to Home Assistant over WebSocket; credentials are stored in the Keychain.
- **Home, away and Nabu Casa.** The app learns Home Assistant's internal, external and Nabu Casa addresses and picks the right one by itself: the home address first, and if it does not answer within a few seconds, the external or Nabu Casa address. It starts again with the home address when the network changes. The card shows which one is in use.
- **Prayer times where you are.** More than 15 km from Nida's location, the app uses the prayer times for your current place from Aladhan, with Nida's calculation method. Pre-adhan, sounds and volumes stay Nida's. Location is asked in the setup.
- **Adhan and pre-adhan on your Mac when you are away.** Over Nabu Casa or the external address, the Mac plays Nida's own adhan (Fajr separately) and pre-adhan jingle at Nida's volumes, following Nida's per-prayer switches and guest mode. Files are kept locally. Choose Away from home, Always or Off. Stop from the card, by clicking the menu bar, or with Stop in the notification.
- **Finds the host name** of Home Assistant on the network (for example `ha.local`), with the IP address as fallback.
- **Local network access.** When macOS blocks it, the card says so and opens the right page in System Settings.
- **Updates from within the app** through Sparkle, signed with an EdDSA key.
- **10 languages:** English, Dutch, German, French, Spanish, Japanese, Simplified Chinese, Arabic (right to left), Turkish and Indonesian.
