import 'package:flutter/material.dart';
import '../services/osc_service.dart';
import '../utils/osc_addresses.dart' as osc;
import '../services/xr18_simulator.dart';

class MixerController extends ChangeNotifier with WidgetsBindingObserver {
  final OscService service;
  final XR18Simulator? simulator;

  MixerController({required this.service, this.simulator}) {
    WidgetsBinding.instance.addObserver(this);
    _loadChannelNames();
    _loadBusNames();
    _loadFxReturnNames();
    _loadChannelColors();
    _loadLineInColor();
    _loadFxReturnColors();
    _loadBusColors();
    _trackBusLinks();
    _setupFaderListeners(effectiveBus);
    _trackLineInFader();
    _trackBusFader();
    service.channelLevels.addListener(_onChannelMeters);
    service.busLevels.addListener(_onBusMeters);
    service.lineInLevels.addListener(_onLineInMeters);
    service.fxReturnLevels.addListener(_onFxReturnMeters);
    service.isReceiving.addListener(_onReceivingChanged);
  }

  bool _disposed = false;

  // Optimistic like AndroidNetworkBinder.wifiAvailable — avoids treating the
  // very first connection (false→true) as a reconnection needing a refresh.
  bool _wasReceiving = true;

  // ── Exposed state ─────────────────────────────────────────────────────────
  int _bus = 1;
  int _registeredBus = -1;

  int get bus => _bus;
  int _pairBaseOf(int busNum) => busNum.isOdd ? busNum : busNum - 1;
  bool get busPaired => busLinked[_pairBaseOf(_bus)] ?? false;
  int get effectiveBus => (busPaired && _bus.isEven) ? _bus - 1 : _bus;

  final Map<int, String> channelNames = {};
  final Map<int, String> busNames = {};
  final Map<int, String> fxReturnNames = {};
  // Colors the console itself reports for /config/color — separate from any
  // local override the user picked in Settings.
  final Map<int, int> consoleChannelColors = {};
  final Map<int, int> consoleFxReturnColors = {};
  int? consoleLineInColor;
  // All 6 buses, like busNames — the bus picker needs every color up
  // front, not just the currently active bus.
  final Map<int, int> consoleBusColors = {};
  final Map<int, bool> busLinked = {1: false, 3: false, 5: false};
  final Map<int, double> faderValues = {};
  final Map<int, double> panValues = {};
  final Map<int, double> fxReturnValues = {};
  final Map<int, double> fxReturnPanValues = {};

  double? lineInFaderValue;
  double? lineInPanValue;
  double? busFaderValue;
  bool? busMuted;

  // ── Meter ValueNotifiers ──────────────────────────────────────────────────
  final List<ValueNotifier<double>> meterLevels =
      List.generate(16, (_) => ValueNotifier(0.0));
  final ValueNotifier<double> busMeterLevel = ValueNotifier(0.0);
  final ValueNotifier<double> busMeterLevelRight = ValueNotifier(0.0);
  final ValueNotifier<double> lineInMeterL = ValueNotifier(0.0);
  final ValueNotifier<double> lineInMeterR = ValueNotifier(0.0);
  final List<ValueNotifier<double>> fxReturnMeterL =
      List.generate(4, (_) => ValueNotifier(0.0));
  final List<ValueNotifier<double>> fxReturnMeterR =
      List.generate(4, (_) => ValueNotifier(0.0));

  // ── Private listener maps ─────────────────────────────────────────────────
  final Map<int, void Function(dynamic)> _nameListeners = {};
  final Map<int, void Function(dynamic)> _busNameListeners = {};
  final Map<int, void Function(dynamic)> _fxReturnNameListeners = {};
  final Map<int, void Function(dynamic)> _colorListeners = {};
  final Map<int, void Function(dynamic)> _fxReturnColorListeners = {};
  void Function(dynamic)? _lineInColorListener;
  final Map<int, void Function(dynamic)> _busColorListeners = {};
  final Map<int, void Function(dynamic)> _faderListeners = {};
  final Map<int, void Function(dynamic)> _panListeners = {};
  final Map<int, void Function(dynamic)> _fxReturnListeners = {};
  final Map<int, void Function(dynamic)> _fxReturnPanListeners = {};
  void Function(dynamic)? _lineInFaderListener;
  void Function(dynamic)? _lineInPanListener;
  void Function(dynamic)? _busFaderListener;
  void Function(dynamic)? _busMuteListener;
  final Map<int, void Function(dynamic)> _busLinkListeners = {};

  // ── App lifecycle ─────────────────────────────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      await simulator?.restart();
      await service.init();
    }
  }

  // Fires on every false→true transition of the heartbeat, which covers all
  // reconnection paths with one hook: app resume (service.init() always
  // forces isReceiving false first), Android wifi loss/recovery (same, via
  // OscService._onWifiAvailabilityChanged), and plain network blips where
  // nothing else in the app noticed a disconnection happened.
  void _onReceivingChanged() {
    final now = service.isReceiving.value;
    if (!_wasReceiving && now) {
      _refreshAll();
    }
    _wasReceiving = now;
  }

  // Re-requests every tracked parameter so nothing changed by another
  // controller while we were disconnected is missed.
  void _refreshAll() {
    for (final odd in [1, 3, 5]) {
      service.request(osc.busLinkAddress(odd));
    }
    for (int ch = 1; ch <= 16; ch++) {
      service.request(busAddress(ch));
      if (busPaired) service.request(panAddress(ch));
      service.request(osc.channelNameAddress(ch));
      service.request(osc.channelColorAddress(ch));
    }
    for (int rtn = 1; rtn <= 4; rtn++) {
      service.request(fxReturnAddress(rtn));
      if (busPaired) service.request(fxReturnPanAddress(rtn));
      service.request(osc.fxReturnColorAddress(rtn));
      service.request(osc.fxReturnNameAddress(rtn));
    }
    for (int busNum = 1; busNum <= 6; busNum++) {
      service.request(osc.busNameAddress(busNum));
      service.request(osc.busColorAddress(busNum));
    }
    service.request(lineInAddress());
    service.request(lineInPanAddress());
    service.request(busFaderAddress());
    service.request(busMuteAddress());
    service.request(osc.kLineInColorAddress);
  }

  // ── Bus link ──────────────────────────────────────────────────────────────
  // Buses pair up as fixed stereo pairs (1-2, 3-4, 5-6); link state is
  // tracked for all three pairs at once so both the mixer (current bus) and
  // the bus selector (all buses) can reflect it.


  void _trackBusLinks() {
    for (final odd in [1, 3, 5]) {
      final address = osc.busLinkAddress(odd);
      void listener(dynamic value) {
        final paired = value == 1 || value == true;
        _onBusLinkChanged(odd, paired);
      }
      _busLinkListeners[odd] = listener;
      service.addListener(address, listener);
      service.request(address);
    }
  }

  void _onBusLinkChanged(int odd, bool newPaired) {
    if (busLinked[odd] == newPaired) return;
    final isCurrentPair = odd == _pairBaseOf(_bus);
    final oldEb = isCurrentPair ? effectiveBus : null;
    busLinked[odd] = newPaired;
    if (isCurrentPair) {
      final newEb = effectiveBus;
      if (oldEb != newEb) {
        _setupFaderListeners(newEb, oldBus: oldEb);
        _reRegisterLineInFader(oldBus: oldEb!, newBus: newEb);
        _reRegisterBusFader(oldBus: oldEb, newBus: newEb);
      }
    }
    if (!_disposed) notifyListeners();
  }

  // ── Fader value tracking (for snapshots) ─────────────────────────────────

  void _setupFaderListeners(int busNum, {int? oldBus}) {
    if (_registeredBus == busNum) return;

    if (oldBus != null && oldBus != -1) {
      for (int ch = 1; ch <= 16; ch++) {
        final fl = _faderListeners[ch];
        if (fl != null) service.removeListener(osc.channelLevelAddress(ch, oldBus), fl);
        final pl = _panListeners[ch];
        if (pl != null) service.removeListener(osc.channelPanAddress(ch, oldBus), pl);
      }
      for (int rtn = 1; rtn <= 4; rtn++) {
        final fl = _fxReturnListeners[rtn];
        if (fl != null) service.removeListener(osc.fxReturnLevelAddress(rtn, oldBus), fl);
        final pl = _fxReturnPanListeners[rtn];
        if (pl != null) service.removeListener(osc.fxReturnPanAddress(rtn, oldBus), pl);
      }
    }

    _registeredBus = busNum;
    for (int ch = 1; ch <= 16; ch++) {
      void faderListener(dynamic value) {
        if (value is double) faderValues[ch] = value;
      }
      _faderListeners[ch] = faderListener;
      service.addListener(osc.channelLevelAddress(ch, busNum), faderListener);
      service.request(osc.channelLevelAddress(ch, busNum));

      void panListener(dynamic value) {
        if (value is double) panValues[ch] = value;
      }
      _panListeners[ch] = panListener;
      service.addListener(osc.channelPanAddress(ch, busNum), panListener);
      service.request(osc.channelPanAddress(ch, busNum));
    }
    for (int rtn = 1; rtn <= 4; rtn++) {
      void fxListener(dynamic value) {
        if (value is double) fxReturnValues[rtn] = value;
      }
      _fxReturnListeners[rtn] = fxListener;
      service.addListener(osc.fxReturnLevelAddress(rtn, busNum), fxListener);
      service.request(osc.fxReturnLevelAddress(rtn, busNum));

      void fxPanListener(dynamic value) {
        if (value is double) fxReturnPanValues[rtn] = value;
      }
      _fxReturnPanListeners[rtn] = fxPanListener;
      service.addListener(osc.fxReturnPanAddress(rtn, busNum), fxPanListener);
      service.request(osc.fxReturnPanAddress(rtn, busNum));
    }
  }

  void _reRegisterBusFader({required int oldBus, required int newBus}) {
    if (_busFaderListener != null) {
      service.removeListener(osc.busFaderAddress(oldBus), _busFaderListener!);
      service.addListener(osc.busFaderAddress(newBus), _busFaderListener!);
      service.request(osc.busFaderAddress(newBus));
    }
    if (_busMuteListener != null) {
      service.removeListener(osc.busMuteAddress(oldBus), _busMuteListener!);
      service.addListener(osc.busMuteAddress(newBus), _busMuteListener!);
      service.request(osc.busMuteAddress(newBus));
    }
  }

  void changeBus(int newBus) {
    if (_bus == newBus) return;

    final oldEb = effectiveBus;
    for (int ch = 1; ch <= 16; ch++) {
      final fl = _faderListeners[ch];
      if (fl != null) service.removeListener(osc.channelLevelAddress(ch, oldEb), fl);
      final pl = _panListeners[ch];
      if (pl != null) service.removeListener(osc.channelPanAddress(ch, oldEb), pl);
    }
    for (int rtn = 1; rtn <= 4; rtn++) {
      final fl = _fxReturnListeners[rtn];
      if (fl != null) service.removeListener(osc.fxReturnLevelAddress(rtn, oldEb), fl);
      final pl = _fxReturnPanListeners[rtn];
      if (pl != null) service.removeListener(osc.fxReturnPanAddress(rtn, oldEb), pl);
    }
    _faderListeners.clear();
    _panListeners.clear();
    _fxReturnListeners.clear();
    _fxReturnPanListeners.clear();
    if (_lineInFaderListener != null) {
      service.removeListener(osc.lineInLevelAddress(oldEb), _lineInFaderListener!);
      _lineInFaderListener = null;
    }
    if (_lineInPanListener != null) {
      service.removeListener(osc.lineInPanAddress(oldEb), _lineInPanListener!);
      _lineInPanListener = null;
    }
    if (_busFaderListener != null) {
      service.removeListener(osc.busFaderAddress(oldEb), _busFaderListener!);
      _busFaderListener = null;
    }
    if (_busMuteListener != null) {
      service.removeListener(osc.busMuteAddress(oldEb), _busMuteListener!);
      _busMuteListener = null;
    }

    _bus = newBus;
    _registeredBus = -1;
    faderValues.clear();
    panValues.clear();
    fxReturnValues.clear();
    fxReturnPanValues.clear();
    lineInFaderValue = null;
    lineInPanValue = null;
    busFaderValue = null;
    busMuted = null;

    _setupFaderListeners(effectiveBus);
    _trackLineInFader();
    _trackBusFader();
    if (!_disposed) notifyListeners();
  }

  void _trackLineInFader() {
    void levelListener(dynamic value) {
      if (value is double) lineInFaderValue = value;
    }
    void panListener(dynamic value) {
      if (value is double) lineInPanValue = value;
    }
    _lineInFaderListener = levelListener;
    _lineInPanListener = panListener;
    service.addListener(lineInAddress(), levelListener);
    service.request(lineInAddress());
    service.addListener(lineInPanAddress(), panListener);
    service.request(lineInPanAddress());
  }

  void _reRegisterLineInFader({required int oldBus, required int newBus}) {
    if (_lineInFaderListener != null) {
      service.removeListener(osc.lineInLevelAddress(oldBus), _lineInFaderListener!);
      service.addListener(osc.lineInLevelAddress(newBus), _lineInFaderListener!);
      service.request(osc.lineInLevelAddress(newBus));
    }
    if (_lineInPanListener != null) {
      service.removeListener(osc.lineInPanAddress(oldBus), _lineInPanListener!);
      service.addListener(osc.lineInPanAddress(newBus), _lineInPanListener!);
      service.request(osc.lineInPanAddress(newBus));
    }
  }

  void _trackBusFader() {
    void faderListener(dynamic value) {
      if (value is double) busFaderValue = value;
    }
    void muteListener(dynamic value) {
      final enabled = value == 1 || value == 1.0;
      busMuted = !enabled;
      if (!_disposed) notifyListeners();
    }
    _busFaderListener = faderListener;
    _busMuteListener = muteListener;
    service.addListener(busFaderAddress(), faderListener);
    service.request(busFaderAddress());
    service.addListener(busMuteAddress(), muteListener);
    service.request(busMuteAddress());
  }

  void setBusMuted(bool muted) {
    service.send(busMuteAddress(), muted ? 0 : 1);
    busMuted = muted;
    if (!_disposed) notifyListeners();
  }

  // ── Meter smoothing ───────────────────────────────────────────────────────

  void _onChannelMeters() {
    final levels = service.channelLevels.value;
    for (int i = 0; i < 16; i++) {
      final target = i < levels.length ? levels[i] : 0.0;
      final current = meterLevels[i].value;
      final alpha = target > current ? 0.7 : 0.12;
      meterLevels[i].value = current + (target - current) * alpha;
    }
  }

  void _onBusMeters() {
    final levels = service.busLevels.value;
    final idxL = effectiveBus - 1;
    final targetL = idxL < levels.length ? levels[idxL] : 0.0;
    final currentL = busMeterLevel.value;
    final alphaL = targetL > currentL ? 0.7 : 0.12;
    busMeterLevel.value = currentL + (targetL - currentL) * alphaL;

    if (busPaired) {
      final idxR = idxL + 1;
      final targetR = idxR < levels.length ? levels[idxR] : 0.0;
      final currentR = busMeterLevelRight.value;
      final alphaR = targetR > currentR ? 0.7 : 0.12;
      busMeterLevelRight.value = currentR + (targetR - currentR) * alphaR;
    } else {
      busMeterLevelRight.value = 0.0;
    }
  }

  void _onLineInMeters() {
    final levels = service.lineInLevels.value;
    final targetL = levels.isNotEmpty ? levels[0] : 0.0;
    final targetR = levels.length > 1 ? levels[1] : 0.0;
    final alphaL = targetL > lineInMeterL.value ? 0.7 : 0.12;
    lineInMeterL.value = lineInMeterL.value + (targetL - lineInMeterL.value) * alphaL;
    final alphaR = targetR > lineInMeterR.value ? 0.7 : 0.12;
    lineInMeterR.value = lineInMeterR.value + (targetR - lineInMeterR.value) * alphaR;
  }

  void _onFxReturnMeters() {
    final levels = service.fxReturnLevels.value;
    for (int i = 0; i < 4; i++) {
      final targetL = i * 2 < levels.length ? levels[i * 2] : 0.0;
      final targetR = i * 2 + 1 < levels.length ? levels[i * 2 + 1] : 0.0;
      final alphaL = targetL > fxReturnMeterL[i].value ? 0.7 : 0.12;
      fxReturnMeterL[i].value =
          fxReturnMeterL[i].value + (targetL - fxReturnMeterL[i].value) * alphaL;
      final alphaR = targetR > fxReturnMeterR[i].value ? 0.7 : 0.12;
      fxReturnMeterR[i].value =
          fxReturnMeterR[i].value + (targetR - fxReturnMeterR[i].value) * alphaR;
    }
  }

  // ── Channel names ─────────────────────────────────────────────────────────

  void _loadChannelNames() {
    for (int ch = 1; ch <= 16; ch++) {
      final address = osc.channelNameAddress(ch);
      void listener(dynamic value) {
        if (value is! String || _disposed) return;
        final name = value.trim().replaceAll('\x00', '');
        channelNames[ch] =
            name.isEmpty ? 'Ch ${ch.toString().padLeft(2, '0')}' : name;
        notifyListeners();
      }
      _nameListeners[ch] = listener;
      service.addListener(address, listener);
      service.request(address);
    }
  }

  void _loadBusNames() {
    for (int busNum = 1; busNum <= 6; busNum++) {
      final address = osc.busNameAddress(busNum);
      void listener(dynamic value) {
        if (value is! String || _disposed) return;
        final name = value.trim().replaceAll('\x00', '');
        busNames[busNum] = name;
        notifyListeners();
      }
      _busNameListeners[busNum] = listener;
      service.addListener(address, listener);
      service.request(address);
    }
  }

  void _loadFxReturnNames() {
    for (int rtn = 1; rtn <= 4; rtn++) {
      final address = osc.fxReturnNameAddress(rtn);
      void listener(dynamic value) {
        if (value is! String || _disposed) return;
        final name = value.trim().replaceAll('\x00', '');
        fxReturnNames[rtn] = name.isEmpty ? 'FX $rtn' : name;
        notifyListeners();
      }
      _fxReturnNameListeners[rtn] = listener;
      service.addListener(address, listener);
      service.request(address);
    }
  }

  void _loadChannelColors() {
    for (int ch = 1; ch <= 16; ch++) {
      final address = osc.channelColorAddress(ch);
      void listener(dynamic value) {
        if (value is! int || _disposed) return;
        consoleChannelColors[ch] = value.clamp(0, 15);
        notifyListeners();
      }
      _colorListeners[ch] = listener;
      service.addListener(address, listener);
      service.request(address);
    }
  }

  void _loadLineInColor() {
    void listener(dynamic value) {
      if (value is! int || _disposed) return;
      consoleLineInColor = value.clamp(0, 15);
      notifyListeners();
    }
    _lineInColorListener = listener;
    service.addListener(osc.kLineInColorAddress, listener);
    service.request(osc.kLineInColorAddress);
  }

  void _loadFxReturnColors() {
    for (int rtn = 1; rtn <= 4; rtn++) {
      final address = osc.fxReturnColorAddress(rtn);
      void listener(dynamic value) {
        if (value is! int || _disposed) return;
        consoleFxReturnColors[rtn] = value.clamp(0, 15);
        notifyListeners();
      }
      _fxReturnColorListeners[rtn] = listener;
      service.addListener(address, listener);
      service.request(address);
    }
  }

  void _loadBusColors() {
    for (int busNum = 1; busNum <= 6; busNum++) {
      final address = osc.busColorAddress(busNum);
      void listener(dynamic value) {
        if (value is! int || _disposed) return;
        consoleBusColors[busNum] = value.clamp(0, 15);
        notifyListeners();
      }
      _busColorListeners[busNum] = listener;
      service.addListener(address, listener);
      service.request(address);
    }
  }

  // ── OSC address helpers ───────────────────────────────────────────────────


  String busAddress(int channel) => osc.channelLevelAddress(channel, effectiveBus);
  String busFaderAddress() => osc.busFaderAddress(effectiveBus);
  String panAddress(int channel) => osc.channelPanAddress(channel, effectiveBus);
  String fxReturnAddress(int rtn) => osc.fxReturnLevelAddress(rtn, effectiveBus);
  String fxReturnPanAddress(int rtn) => osc.fxReturnPanAddress(rtn, effectiveBus);
  String lineInAddress() => osc.lineInLevelAddress(effectiveBus);
  String lineInPanAddress() => osc.lineInPanAddress(effectiveBus);
  String busMuteAddress() => osc.busMuteAddress(effectiveBus);

  String channelLabel(int ch) =>
      channelNames[ch] ?? 'Ch ${ch.toString().padLeft(2, '0')}';

  String fxReturnLabel(int rtn) => fxReturnNames[rtn] ?? 'FX $rtn';

  String busLabel(int busNum) {
    final name = busNames[busNum];
    return (name == null || name.isEmpty) ? '$busNum' : '$busNum · $name';
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    for (final entry in _nameListeners.entries) {
      final address = osc.channelNameAddress(entry.key);
      service.removeListener(address, entry.value);
    }
    for (final entry in _busNameListeners.entries) {
      service.removeListener(osc.busNameAddress(entry.key), entry.value);
    }
    for (final entry in _fxReturnNameListeners.entries) {
      service.removeListener(osc.fxReturnNameAddress(entry.key), entry.value);
    }
    for (final entry in _busColorListeners.entries) {
      service.removeListener(osc.busColorAddress(entry.key), entry.value);
    }
    for (final entry in _colorListeners.entries) {
      service.removeListener(osc.channelColorAddress(entry.key), entry.value);
    }
    for (final entry in _fxReturnColorListeners.entries) {
      service.removeListener(osc.fxReturnColorAddress(entry.key), entry.value);
    }
    if (_lineInColorListener != null) {
      service.removeListener(osc.kLineInColorAddress, _lineInColorListener!);
    }
    for (int ch = 1; ch <= 16; ch++) {
      final fl = _faderListeners[ch];
      if (fl != null) service.removeListener(osc.channelLevelAddress(ch, _registeredBus), fl);
      final pl = _panListeners[ch];
      if (pl != null) service.removeListener(osc.channelPanAddress(ch, _registeredBus), pl);
    }
    for (int rtn = 1; rtn <= 4; rtn++) {
      final fl = _fxReturnListeners[rtn];
      if (fl != null) service.removeListener(osc.fxReturnLevelAddress(rtn, _registeredBus), fl);
      final pl = _fxReturnPanListeners[rtn];
      if (pl != null) service.removeListener(osc.fxReturnPanAddress(rtn, _registeredBus), pl);
    }
    if (_lineInFaderListener != null) {
      service.removeListener(lineInAddress(), _lineInFaderListener!);
    }
    if (_lineInPanListener != null) {
      service.removeListener(lineInPanAddress(), _lineInPanListener!);
    }
    if (_busFaderListener != null) {
      service.removeListener(busFaderAddress(), _busFaderListener!);
    }
    if (_busMuteListener != null) {
      service.removeListener(busMuteAddress(), _busMuteListener!);
    }
    for (final entry in _busLinkListeners.entries) {
      service.removeListener(osc.busLinkAddress(entry.key), entry.value);
    }
    service.channelLevels.removeListener(_onChannelMeters);
    service.busLevels.removeListener(_onBusMeters);
    service.lineInLevels.removeListener(_onLineInMeters);
    service.fxReturnLevels.removeListener(_onFxReturnMeters);
    service.isReceiving.removeListener(_onReceivingChanged);
    for (final n in meterLevels) {
      n.dispose();
    }
    busMeterLevel.dispose();
    busMeterLevelRight.dispose();
    lineInMeterL.dispose();
    lineInMeterR.dispose();
    for (final n in fxReturnMeterL) {
      n.dispose();
    }
    for (final n in fxReturnMeterR) {
      n.dispose();
    }
    service.dispose();
    super.dispose();
  }
}
