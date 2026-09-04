# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- FX return names configured on the mixer are now shown on the FX faders and on their chips in Settings and group setup, the same way channel names already were.
- Pinch with two fingers over a group's faders to resize them, the same as on the mixer screen. Each screen remembers its own size, so a group of three faders can be spread across the whole screen while the mixer stays packed with sixteen.

### Fixed
- Fixed channel and bus names, scribble-strip colors and fader positions sometimes coming up blank or stale when connecting to the mixer. StageMon now spaces those requests out to avoid overloading the mixer and asks again for anything that doesn't come back, so the mixer state loads completely even on the console's own wifi, or while another app is keeping the connection busy at the same time.

### Changed
- Mixer search now keeps looking for 6 seconds, sending three requests along the way instead of one, so a busy mixer that misses the first one still shows up without having to press Search again. Mixers appear as soon as they answer, and the simulator card is always available while the search runs.
- Every change StageMon sends to the mixer — fader, pan, mute — is now confirmed by the mixer before StageMon considers it done. If no confirmation arrives, the value is read back, so what's on screen always reflects what the mixer actually has.
- Recalling a snapshot now moves the faders over about half a second instead of all at once, so every change reaches the mixer reliably.
- A group's fader screen now scrolls, flings and drags exactly like the mixer screen, and follows the mixer live: names, colors and stereo pairing that change while it is open now show up without leaving the screen.

## [1.1.0] - 2026-08-28

### Added
- Long-press a channel, LINE, FX return, MASTER, or group fader chip in Settings to give it a color — the same 16 colors the mixer itself uses for its scribble strips. Arrows let you step through every fader without closing the menu. Leave it set to "Console" and the color automatically matches whatever that channel already has on the mixer (not available for group faders, which don't exist on the console). The chosen color shows on the chip in Settings and colors the fader's name on the mixer screen.
- Aux bus color, read from the console, shown next to each bus in the picker sheet.
- Pinch with two fingers over the faders to resize them, showing more or fewer channels at once.
- Setting to keep the Master fader pinned to the right edge of the mixer screen while the other faders scroll independently (subordinate to "Bus master fader" in Settings).
- Aux bus names configured on the mixer are now shown next to the bus number, in Settings and in the mixer screen title.
- Mixer screen title turns red with a MUTED badge when the bus is muted.
- (Android) New banner that appears immediately when the phone's wifi connection is lost, instead of waiting for the mixer connection to time out.
- "Try without a mixer" simulator mode on the connect screen: connects to a built-in fake console so the app (faders, groups, snapshots, VU meters) can be tried out without a real mixer nearby.
- New "Layouts" screen in Settings: save the current screen setup (visible channels, groups, colors, and optionally the aux bus) under a name, and reload it later. Loading a layout asks for confirmation, and warns if it will also change the aux bus.
- Layouts can be shared to another device from the Layouts screen, using Android's own share sheet (WhatsApp, email, Drive, Bluetooth...). On the receiving device, a shared layout file can be imported by picking it manually from the Layouts screen, or by simply opening it from wherever it was received (e.g. tapping it in a chat) — StageMon opens straight to the import.
- Screen no longer locks while connected to a mixer, so the faders stay visible during a show. It dims after a period of inactivity (based on your phone's own screen timeout setting) and brightens again on the next touch. Not active on the connect screen.
- Midas MR18, and the V2 hardware revisions of the XR18, X18 and MR18, are now recognized as supported consoles — connecting to one of them no longer shows the "untested model" warning.

### Changed
- Group faders in Settings now use the same visibility chip as channels/LINE/FX/MASTER, with the channel count and the configure button laid out next to it, instead of a separate switch.
- Master mute button is now taller, for easier tapping.
- Master fader now has a dark blue background to set it apart from the other faders.
- Aux bus picker in Settings is now a single row showing the selected bus, which opens a full list of every bus in a bottom sheet; linked bus pairs (1-2, 3-4, 5-6) show as a single entry.
- Unified internal naming around "bus" (previously a mix of "bus"/"aux"). As a side effect, the saved "show bus fader" preference and the bus level/mute stored in existing snapshots reset to their defaults after this update.
- Visible channels, FX Returns, group faders, and the bus master fader are now grouped together in a single card in Settings, to set them apart from the rest of the settings.
- Connect screen: "Search again" now sits below the discovered consoles/simulator list it re-triggers, and manual IP connection has its own full-width "Manual connect" button, instead of the two sitting side by side.
- Snapshots sheet: tapping a snapshot now loads it directly, and a "more options" (⋮) button opens save/rename/delete — matching the tap-to-load-with-menu pattern already used in Layouts, instead of relying on an undiscoverable long-press for those actions.

### Fixed
- (Android) Fixed StageMon losing connection to the mixer at venues where the wifi network has no internet access. Even though the phone stayed connected to that wifi, Android would sometimes quietly reroute the app's traffic through mobile data instead, which can't reach the mixer since it's only reachable on the local network. StageMon now forces its own connection to stay on wifi whenever wifi is available, regardless of what Android picks as the default network for other apps.
- Fixed fader, pan, mute and name changes made on another app going unnoticed if they happened while StageMon was disconnected (e.g., a wifi drop or a long time in the background). StageMon now re-reads every value from the mixer as soon as the connection comes back.

## [1.0.0] - 2026-08-10

- Initial Play Store release.
