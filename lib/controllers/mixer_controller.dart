import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/osc_service.dart';

class MixerController extends ChangeNotifier with WidgetsBindingObserver {
  final OscService service;

  MixerController({required this.service}) {
    WidgetsBinding.instance.addObserver(this);
    _loadChannelNames();
    _loadBusNames();
    _trackBusLink();
    _setupFaderListeners(effectiveBus);
    _trackLineInFader();
    _trackAuxFader();
    service.channelLevels.addListener(_onChannelMeters);
    service.busLevels.addListener(_onBusMeters);
    service.lineInLevels.addListener(_onLineInMeters);
    service.fxReturnLevels.addListener(_onFxReturnMeters);
  }

  bool _disposed = false;

  // ── Exposed state ─────────────────────────────────────────────────────────
  int _bus = 1;
  bool _busPaired = false;
  int _registeredBus = -1;

  int get bus => _bus;
  bool get busPaired => _busPaired;
  int get effectiveBus => (_busPaired && _bus.isEven) ? _bus - 1 : _bus;

  final Map<int, String> channelNames = {};
  final Map<int, String> busNames = {};
  final Map<int, double> faderValues = {};
  final Map<int, double> panValues = {};
  final Map<int, double> fxReturnValues = {};
  final Map<int, double> fxReturnPanValues = {};

  double? lineInFaderValue;
  double? lineInPanValue;
  double? auxFaderValue;
  bool? auxMuted;

  // ── Meter ValueNotifiers ──────────────────────────────────────────────────
  final List<ValueNotifier<double>> meterLevels =
      List.generate(16, (_) => ValueNotifier(0.0));
  final ValueNotifier<double> auxMeterLevel = ValueNotifier(0.0);
  final ValueNotifier<double> auxMeterLevelRight = ValueNotifier(0.0);
  final ValueNotifier<double> lineInMeterL = ValueNotifier(0.0);
  final ValueNotifier<double> lineInMeterR = ValueNotifier(0.0);
  final List<ValueNotifier<double>> fxReturnMeterL =
      List.generate(4, (_) => ValueNotifier(0.0));
  final List<ValueNotifier<double>> fxReturnMeterR =
      List.generate(4, (_) => ValueNotifier(0.0));

  // ── Private listener maps ─────────────────────────────────────────────────
  final Map<int, void Function(dynamic)> _nameListeners = {};
  final Map<int, void Function(dynamic)> _busNameListeners = {};
  final Map<int, void Function(dynamic)> _faderListeners = {};
  final Map<int, void Function(dynamic)> _panListeners = {};
  final Map<int, void Function(dynamic)> _fxReturnListeners = {};
  final Map<int, void Function(dynamic)> _fxReturnPanListeners = {};
  void Function(dynamic)? _lineInFaderListener;
  void Function(dynamic)? _lineInPanListener;
  void Function(dynamic)? _auxFaderListener;
  void Function(dynamic)? _auxMuteListener;
  void Function(dynamic)? _busLinkListener;

  // ── App lifecycle ─────────────────────────────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      await service.init();
      service.request(_busLinkAddress());
      for (int ch = 1; ch <= 16; ch++) {
        service.request(busAddress(ch));
        if (_busPaired) service.request(panAddress(ch));
      }
      for (int rtn = 1; rtn <= 4; rtn++) {
        service.request(fxReturnAddress(rtn));
        if (_busPaired) service.request(fxReturnPanAddress(rtn));
      }
      service.request(lineInAddress());
      service.request(lineInPanAddress());
      service.request(auxAddress());
      service.request(auxMuteAddress());
    }
  }

  // ── Bus link ──────────────────────────────────────────────────────────────

  String _busLinkAddress() {
    final odd = _bus.isOdd ? _bus : _bus - 1;
    return '/config/buslink/$odd-${odd + 1}';
  }

  void _trackBusLink() {
    final address = _busLinkAddress();
    void listener(dynamic value) {
      final paired = value == 1 || value == true;
      _onBusPairingChanged(paired);
    }
    _busLinkListener = listener;
    service.addListener(address, listener);
    service.request(address);
  }

  void _onBusPairingChanged(bool newPaired) {
    if (_busPaired == newPaired) return;
    final oldEb = effectiveBus;
    _busPaired = newPaired;
    final newEb = effectiveBus;
    if (oldEb != newEb) {
      _setupFaderListeners(newEb, oldBus: oldEb);
      _reRegisterLineInFader(oldBus: oldEb, newBus: newEb);
      _reRegisterAuxFader(oldBus: oldEb, newBus: newEb);
    }
    if (!_disposed) notifyListeners();
  }

  // ── Fader value tracking (for snapshots) ─────────────────────────────────

  void _setupFaderListeners(int busNum, {int? oldBus}) {
    if (_registeredBus == busNum) return;

    if (oldBus != null && oldBus != -1) {
      for (int ch = 1; ch <= 16; ch++) {
        final fl = _faderListeners[ch];
        if (fl != null) service.removeListener(_buildBusAddress(ch, oldBus), fl);
        final pl = _panListeners[ch];
        if (pl != null) service.removeListener(_buildPanAddress(ch, oldBus), pl);
      }
      for (int rtn = 1; rtn <= 4; rtn++) {
        final fl = _fxReturnListeners[rtn];
        if (fl != null) service.removeListener(_buildFxReturnAddress(rtn, oldBus), fl);
        final pl = _fxReturnPanListeners[rtn];
        if (pl != null) service.removeListener(_buildFxReturnPanAddress(rtn, oldBus), pl);
      }
    }

    _registeredBus = busNum;
    for (int ch = 1; ch <= 16; ch++) {
      void faderListener(dynamic value) {
        if (value is double) faderValues[ch] = value;
      }
      _faderListeners[ch] = faderListener;
      service.addListener(_buildBusAddress(ch, busNum), faderListener);
      service.request(_buildBusAddress(ch, busNum));

      void panListener(dynamic value) {
        if (value is double) panValues[ch] = value;
      }
      _panListeners[ch] = panListener;
      service.addListener(_buildPanAddress(ch, busNum), panListener);
      service.request(_buildPanAddress(ch, busNum));
    }
    for (int rtn = 1; rtn <= 4; rtn++) {
      void fxListener(dynamic value) {
        if (value is double) fxReturnValues[rtn] = value;
      }
      _fxReturnListeners[rtn] = fxListener;
      service.addListener(_buildFxReturnAddress(rtn, busNum), fxListener);
      service.request(_buildFxReturnAddress(rtn, busNum));

      void fxPanListener(dynamic value) {
        if (value is double) fxReturnPanValues[rtn] = value;
      }
      _fxReturnPanListeners[rtn] = fxPanListener;
      service.addListener(_buildFxReturnPanAddress(rtn, busNum), fxPanListener);
      service.request(_buildFxReturnPanAddress(rtn, busNum));
    }
  }

  void _reRegisterAuxFader({required int oldBus, required int newBus}) {
    if (_auxFaderListener != null) {
      service.removeListener(_buildAuxAddress(oldBus), _auxFaderListener!);
      service.addListener(_buildAuxAddress(newBus), _auxFaderListener!);
      service.request(_buildAuxAddress(newBus));
    }
    if (_auxMuteListener != null) {
      service.removeListener(_buildAuxMuteAddress(oldBus), _auxMuteListener!);
      service.addListener(_buildAuxMuteAddress(newBus), _auxMuteListener!);
      service.request(_buildAuxMuteAddress(newBus));
    }
  }

  void changeBus(int newBus) {
    if (_bus == newBus) return;

    if (_busLinkListener != null) {
      service.removeListener(_busLinkAddress(), _busLinkListener!);
      _busLinkListener = null;
    }
    final oldEb = effectiveBus;
    for (int ch = 1; ch <= 16; ch++) {
      final fl = _faderListeners[ch];
      if (fl != null) service.removeListener(_buildBusAddress(ch, oldEb), fl);
      final pl = _panListeners[ch];
      if (pl != null) service.removeListener(_buildPanAddress(ch, oldEb), pl);
    }
    for (int rtn = 1; rtn <= 4; rtn++) {
      final fl = _fxReturnListeners[rtn];
      if (fl != null) service.removeListener(_buildFxReturnAddress(rtn, oldEb), fl);
      final pl = _fxReturnPanListeners[rtn];
      if (pl != null) service.removeListener(_buildFxReturnPanAddress(rtn, oldEb), pl);
    }
    _faderListeners.clear();
    _panListeners.clear();
    _fxReturnListeners.clear();
    _fxReturnPanListeners.clear();
    if (_lineInFaderListener != null) {
      service.removeListener(_buildLineInAddress(oldEb), _lineInFaderListener!);
      _lineInFaderListener = null;
    }
    if (_lineInPanListener != null) {
      service.removeListener(_buildLineInPanAddress(oldEb), _lineInPanListener!);
      _lineInPanListener = null;
    }
    if (_auxFaderListener != null) {
      service.removeListener(_buildAuxAddress(oldEb), _auxFaderListener!);
      _auxFaderListener = null;
    }
    if (_auxMuteListener != null) {
      service.removeListener(_buildAuxMuteAddress(oldEb), _auxMuteListener!);
      _auxMuteListener = null;
    }

    _bus = newBus;
    _busPaired = false;
    _registeredBus = -1;
    faderValues.clear();
    panValues.clear();
    fxReturnValues.clear();
    fxReturnPanValues.clear();
    lineInFaderValue = null;
    lineInPanValue = null;
    auxFaderValue = null;
    auxMuted = null;

    _trackBusLink();
    _setupFaderListeners(effectiveBus);
    _trackLineInFader();
    _trackAuxFader();
    SharedPreferences.getInstance().then((p) => p.setInt('selected_bus', _bus));
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
      service.removeListener(_buildLineInAddress(oldBus), _lineInFaderListener!);
      service.addListener(_buildLineInAddress(newBus), _lineInFaderListener!);
      service.request(_buildLineInAddress(newBus));
    }
    if (_lineInPanListener != null) {
      service.removeListener(_buildLineInPanAddress(oldBus), _lineInPanListener!);
      service.addListener(_buildLineInPanAddress(newBus), _lineInPanListener!);
      service.request(_buildLineInPanAddress(newBus));
    }
  }

  void _trackAuxFader() {
    void faderListener(dynamic value) {
      if (value is double) auxFaderValue = value;
    }
    void muteListener(dynamic value) {
      final enabled = value == 1 || value == 1.0;
      auxMuted = !enabled;
      if (!_disposed) notifyListeners();
    }
    _auxFaderListener = faderListener;
    _auxMuteListener = muteListener;
    service.addListener(auxAddress(), faderListener);
    service.request(auxAddress());
    service.addListener(auxMuteAddress(), muteListener);
    service.request(auxMuteAddress());
  }

  void setAuxMuted(bool muted) {
    service.send(auxMuteAddress(), muted ? 0 : 1);
    auxMuted = muted;
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
    final currentL = auxMeterLevel.value;
    final alphaL = targetL > currentL ? 0.7 : 0.12;
    auxMeterLevel.value = currentL + (targetL - currentL) * alphaL;

    if (_busPaired) {
      final idxR = idxL + 1;
      final targetR = idxR < levels.length ? levels[idxR] : 0.0;
      final currentR = auxMeterLevelRight.value;
      final alphaR = targetR > currentR ? 0.7 : 0.12;
      auxMeterLevelRight.value = currentR + (targetR - currentR) * alphaR;
    } else {
      auxMeterLevelRight.value = 0.0;
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
      final address = '/ch/${ch.toString().padLeft(2, '0')}/config/name';
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
      final address = _buildBusNameAddress(busNum);
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

  // ── OSC address helpers ───────────────────────────────────────────────────

  String _buildBusAddress(int channel, int busNum) {
    final ch = channel.toString().padLeft(2, '0');
    final bus = busNum.toString().padLeft(2, '0');
    return '/ch/$ch/mix/$bus/level';
  }

  String _buildAuxAddress(int busNum) => '/bus/$busNum/mix/fader';

  String _buildBusNameAddress(int busNum) => '/bus/$busNum/config/name';

  String _buildPanAddress(int channel, int busNum) {
    final ch = channel.toString().padLeft(2, '0');
    final bus = busNum.toString().padLeft(2, '0');
    return '/ch/$ch/mix/$bus/pan';
  }

  String _buildFxReturnAddress(int rtn, int busNum) {
    final bus = busNum.toString().padLeft(2, '0');
    return '/rtn/$rtn/mix/$bus/level';
  }

  String _buildFxReturnPanAddress(int rtn, int busNum) {
    final bus = busNum.toString().padLeft(2, '0');
    return '/rtn/$rtn/mix/$bus/pan';
  }

  String _buildAuxMuteAddress(int busNum) => '/bus/$busNum/mix/on';

  String _buildLineInAddress(int busNum) {
    final bus = busNum.toString().padLeft(2, '0');
    return '/rtn/aux/mix/$bus/level';
  }

  String _buildLineInPanAddress(int busNum) {
    final bus = busNum.toString().padLeft(2, '0');
    return '/rtn/aux/mix/$bus/pan';
  }

  String busAddress(int channel) => _buildBusAddress(channel, effectiveBus);
  String auxAddress() => _buildAuxAddress(effectiveBus);
  String panAddress(int channel) => _buildPanAddress(channel, effectiveBus);
  String fxReturnAddress(int rtn) => _buildFxReturnAddress(rtn, effectiveBus);
  String fxReturnPanAddress(int rtn) => _buildFxReturnPanAddress(rtn, effectiveBus);
  String lineInAddress() => _buildLineInAddress(effectiveBus);
  String lineInPanAddress() => _buildLineInPanAddress(effectiveBus);
  String auxMuteAddress() => _buildAuxMuteAddress(effectiveBus);

  String channelLabel(int ch) =>
      channelNames[ch] ?? 'Ch ${ch.toString().padLeft(2, '0')}';

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
      final address = '/ch/${entry.key.toString().padLeft(2, '0')}/config/name';
      service.removeListener(address, entry.value);
    }
    for (final entry in _busNameListeners.entries) {
      service.removeListener(_buildBusNameAddress(entry.key), entry.value);
    }
    for (int ch = 1; ch <= 16; ch++) {
      final fl = _faderListeners[ch];
      if (fl != null) service.removeListener(_buildBusAddress(ch, _registeredBus), fl);
      final pl = _panListeners[ch];
      if (pl != null) service.removeListener(_buildPanAddress(ch, _registeredBus), pl);
    }
    for (int rtn = 1; rtn <= 4; rtn++) {
      final fl = _fxReturnListeners[rtn];
      if (fl != null) service.removeListener(_buildFxReturnAddress(rtn, _registeredBus), fl);
      final pl = _fxReturnPanListeners[rtn];
      if (pl != null) service.removeListener(_buildFxReturnPanAddress(rtn, _registeredBus), pl);
    }
    if (_lineInFaderListener != null) {
      service.removeListener(lineInAddress(), _lineInFaderListener!);
    }
    if (_lineInPanListener != null) {
      service.removeListener(lineInPanAddress(), _lineInPanListener!);
    }
    if (_auxFaderListener != null) {
      service.removeListener(auxAddress(), _auxFaderListener!);
    }
    if (_auxMuteListener != null) {
      service.removeListener(auxMuteAddress(), _auxMuteListener!);
    }
    if (_busLinkListener != null) {
      service.removeListener(_busLinkAddress(), _busLinkListener!);
    }
    service.channelLevels.removeListener(_onChannelMeters);
    service.busLevels.removeListener(_onBusMeters);
    service.lineInLevels.removeListener(_onLineInMeters);
    service.fxReturnLevels.removeListener(_onFxReturnMeters);
    for (final n in meterLevels) {
      n.dispose();
    }
    auxMeterLevel.dispose();
    auxMeterLevelRight.dispose();
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
