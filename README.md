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

## License

MIT
