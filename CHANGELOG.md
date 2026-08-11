# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- Setting to keep the Master fader pinned to the right edge of the mixer screen while the other faders scroll independently (subordinate to "Bus fader" in Settings).
- Aux bus names configured on the console are now shown next to the bus number, in Settings and in the mixer screen title.
- Mixer screen title turns red with a MUTED badge when the bus is muted.

### Changed
- Master fader now has a dark blue background to set it apart from the other faders.
- Aux bus picker in Settings now wraps onto multiple rows instead of a single-line segmented control, so long console names stay readable.
- "Aux send" section header in Settings (English) renamed to "Aux bus" for clarity.
- Unified internal naming around "bus" (previously a mix of "bus"/"aux"). As a side effect, the saved "show bus fader" / "always visible" preferences and the bus level/mute stored in existing snapshots reset to their defaults after this update.

## [1.0.0] - 2026-08-10

- Initial Play Store release.
