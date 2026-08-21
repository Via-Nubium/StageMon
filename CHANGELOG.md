# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- Long-press a channel, LINE, or FX return chip in Settings to give it a color — the same 16 colors the mixer itself uses for its scribble strips. Arrows let you step through every channel, LINE, and FX return without closing the menu. Leave it set to "Console" and the color automatically matches whatever that channel already has on the mixer. The chosen color shows on the chip in Settings and colors the channel's name on the mixer screen.
- Pinch with two fingers over the faders to resize them, showing more or fewer channels at once.
- Setting to keep the Master fader pinned to the right edge of the mixer screen while the other faders scroll independently (subordinate to "Bus master fader" in Settings).
- Aux bus names configured on the mixer are now shown next to the bus number, in Settings and in the mixer screen title.
- Mixer screen title turns red with a MUTED badge when the bus is muted.
- (Android) New banner that appears immediately when the phone's wifi connection is lost, instead of waiting for the mixer connection to time out.

### Changed
- Bus mute button is now taller, for easier tapping.
- Master fader now has a dark blue background to set it apart from the other faders.
- Aux bus picker in Settings now wraps onto multiple rows instead of a single-line segmented control, so long mixer names stay readable.
- "Aux send" section header in Settings (English) renamed to "Aux bus" for clarity.
- Unified internal naming around "bus" (previously a mix of "bus"/"aux"). As a side effect, the saved "show bus fader" / "always visible" preferences and the bus level/mute stored in existing snapshots reset to their defaults after this update.

### Fixed
- (Android) Fixed StageMon losing connection to the mixer at venues where the wifi network has no internet access. Even though the phone stayed connected to that wifi, Android would sometimes quietly reroute the app's traffic through mobile data instead, which can't reach the mixer since it's only reachable on the local network. StageMon now forces its own connection to stay on wifi whenever wifi is available, regardless of what Android picks as the default network for other apps.
- Fixed fader, pan, mute and name changes made on another app going unnoticed if they happened while StageMon was disconnected (e.g., a wifi drop or a long time in the background). StageMon now re-reads every value from the mixer as soon as the connection comes back.

## [1.0.0] - 2026-08-10

- Initial Play Store release.
