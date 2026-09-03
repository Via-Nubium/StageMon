/// Every OSC address the app speaks, in one place.
///
/// Two ends use these: MixerController, which asks a real console, and the
/// embedded simulator, which answers as one. The simulator exists so the app
/// runs with no console nearby, not to double-check the app's spelling — the
/// tests and the standalone Python simulator in tools/ are the independent
/// check on that.
///
/// Note the padding: channel and bus numbers are zero-padded to two digits
/// inside a /mix path, FX return numbers are not, and a bus is *not* padded
/// in its own /bus path. That asymmetry is the console's, not a typo.
library;

String _pad2(int n) => n.toString().padLeft(2, '0');

// ── Where a source sits in a bus mix ────────────────────────────────────────

String channelLevelAddress(int channel, int bus) =>
    '/ch/${_pad2(channel)}/mix/${_pad2(bus)}/level';

String channelPanAddress(int channel, int bus) =>
    '/ch/${_pad2(channel)}/mix/${_pad2(bus)}/pan';

String fxReturnLevelAddress(int rtn, int bus) =>
    '/rtn/$rtn/mix/${_pad2(bus)}/level';

String fxReturnPanAddress(int rtn, int bus) =>
    '/rtn/$rtn/mix/${_pad2(bus)}/pan';

String lineInLevelAddress(int bus) => '/rtn/aux/mix/${_pad2(bus)}/level';

String lineInPanAddress(int bus) => '/rtn/aux/mix/${_pad2(bus)}/pan';

// ── The bus itself ──────────────────────────────────────────────────────────

String busFaderAddress(int bus) => '/bus/$bus/mix/fader';

String busMuteAddress(int bus) => '/bus/$bus/mix/on';

/// A stereo pair is addressed by its odd (base) bus: 1-2, 3-4, 5-6.
String busLinkAddress(int oddBus) => '/config/buslink/$oddBus-${oddBus + 1}';

// ── Scribble strips: names and colors ───────────────────────────────────────

String channelNameAddress(int channel) =>
    '/ch/${_pad2(channel)}/config/name';

String channelColorAddress(int channel) =>
    '/ch/${_pad2(channel)}/config/color';

String fxReturnNameAddress(int rtn) => '/rtn/$rtn/config/name';

String fxReturnColorAddress(int rtn) => '/rtn/$rtn/config/color';

const String kLineInColorAddress = '/rtn/aux/config/color';

String busNameAddress(int bus) => '/bus/$bus/config/name';

String busColorAddress(int bus) => '/bus/$bus/config/color';

// ── The session itself ──────────────────────────────────────────────────────

/// Discovery: the console answers with its model, firmware and name.
const String kInfoAddress = '/xinfo';

/// Renews the console's push subscription, which it drops after ~10 seconds.
const String kRemoteAddress = '/xremote';

/// Asks for a meter bank, named by the address its blobs arrive at.
const String kMetersAddress = '/meters';
const String kMeterBank1Address = '/meters/1';
