# StageMon

A Flutter app for controlling monitor mixes on a **Behringer XR18 / X AIR** mixer via OSC/UDP.

Designed for live sound: each musician on stage can use StageMon to adjust their own monitor mix in real time, without touching the main console.

---

## Features

- **Auto-discovery** — finds XR18 consoles on the local network automatically
- **Per-bus fader control** — sends individual channel levels to any of the 6 aux buses
- **Stereo bus support** — detects paired buses (1/2, 3/4, 5/6) and shows pan knobs automatically
- **VCA-style group faders** — move multiple channels together while preserving relative levels
- **Snapshots** — save and restore complete mix states (levels, pans, aux master)
- **VU meters** — real-time channel and bus level indicators
- **Channel visibility** — show only the channels that matter for each monitor mix
- **Dark theme** optimized for stage use

## Screenshots

_Coming soon_

## Requirements

- Flutter 3.38 or later
- A Behringer XR18 or X AIR mixer on the same Wi-Fi network
- Android or iOS device

## Getting started

```bash
git clone https://github.com/Via-Nubium/StageMon.git
cd stagemon
flutter pub get
flutter run
```

## Development tools

The `tools/` folder contains two Python utilities:

- **`xr18_simulator.py`** — simulates an XR18 mixer for testing without hardware. No external dependencies.
  ```bash
  python tools/xr18_simulator.py
  ```
- **`osc_listener.py`** — listens on UDP port 10024 and prints incoming OSC messages.
  Requires `pip install python-osc`.

## License

MIT License — Copyright (c) 2026 Via Nubium. See [LICENSE](LICENSE) for details.

This software is provided "as is", without warranty of any kind. Use at your own risk.
