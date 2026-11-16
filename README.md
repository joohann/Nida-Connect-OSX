# Nida Connect

![Nida Connect: the upcoming prayer in your Mac menu bar, connected to the Nida integration for Home Assistant](docs/showcase.png)

The upcoming prayer from [Nida](https://github.com/joohann/Nida) (Home Assistant) in your macOS menu bar, with a live countdown.

- Menu bar: `02:14`, under an hour `47:09`; orange at the first pre-adhan, red at the second, a gold label with the prayer's name at prayer time. Icon and prayer name are optional.
- Panel: countdown, today's prayer times, hijri date. Settings on the back of the card.
- Notifications at pre-adhan 1, pre-adhan 2 and the adhan.
- 10 languages, follows your macOS language.

## Requirements

- macOS 13 or later
- Home Assistant with the Nida integration

## Setup

At first launch a short setup opens. The app finds Home Assistant on your network by itself; otherwise enter the address (for example `http://homeassistant.local`). Then sign in with Home Assistant's own login page, or use a long-lived access token. Credentials are stored in the Keychain. Use https outside your home network.

The app reads Nida's sensors through the entity registry, so renamed entities keep working, and reads the pre-adhan minutes from Nida's settings.

## Build from source

Everything (name, bundle id, version, update feed) lives in `config.json`; `.env` is generated from it.

```bash
scripts/build.sh           # build/Nida Connect.app
scripts/build.sh install   # also install to /Applications and start
scripts/i18n.sh            # report missing translations
scripts/i18n.sh new xx     # new language file with empty keys
scripts/i18n.sh fill xx    # add only the missing keys, empty
```

### Icon

`Icon/IconDrawing.swift` draws the app icon on the macOS icon grid (824 px body, radius 185 on a 1024 canvas), with the mosque from Nida's own icon (`Icon/AppIcon-source.png`). That shape keeps macOS from putting the icon on a grey plate.

### Install window

`Icon/DMGBackground/main.swift` draws the DMG window background (660 × 400, 1x and 2x) with the app name from `config.json`, and holds the icon positions. `scripts/package.sh` uses it and lets Finder store the layout; the first time, macOS asks to allow controlling Finder.

### Previewing the gold label

Start the app with `open -a "Nida Connect" --args -previewPrayerSignal 90` to see the gold prayer label for 90 seconds, without waiting for a prayer time.

### Signing

`signing.identity` in `config.json` is a local, self-signed code signing certificate. It gives the app a stable signature, so the Keychain recognises it after every build and update and does not ask for your password again. Create it once with `scripts/signing-identity.sh`. With an Apple Developer ID, put its name there instead; the build then also enables the hardened runtime and notarisation.

### Updates

1. Set `version` in `config.json` and add a `## <version>` section to `CHANGELOG.md`.
2. `scripts/package.sh` builds the DMG and signs `appcast.xml` with the EdDSA key from the Keychain (`update.keyAccount`).
3. Publish a GitHub release `v<version>` with the DMG, then commit and push `appcast.xml`.

The updater is off until `update.publicKey` is set in `config.json`.

## License

MIT
