import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class FaderSnapshot {
  String name;
  final Map<int, double> values;
  final Map<int, double> panValues;
  final double? busLevel;
  final bool? busMuted;
  final Map<int, double> fxReturnValues;
  final Map<int, double> fxReturnPanValues;
  final double? lineInLevel;
  final double? lineInPan;

  FaderSnapshot({
    required this.name,
    required this.values,
    Map<int, double>? panValues,
    this.busLevel,
    this.busMuted,
    Map<int, double>? fxReturnValues,
    Map<int, double>? fxReturnPanValues,
    this.lineInLevel,
    this.lineInPan,
  })  : panValues = panValues ?? {},
        fxReturnValues = fxReturnValues ?? {},
        fxReturnPanValues = fxReturnPanValues ?? {};

  Map<String, dynamic> toJson() => {
        'name': name,
        'values': values.map((k, v) => MapEntry(k.toString(), v)),
        'panValues': panValues.map((k, v) => MapEntry(k.toString(), v)),
        if (busLevel != null) 'busLevel': busLevel,
        if (busMuted != null) 'busMuted': busMuted! ? 1 : 0,
        if (fxReturnValues.isNotEmpty)
          'fxReturnValues': fxReturnValues.map((k, v) => MapEntry(k.toString(), v)),
        if (fxReturnPanValues.isNotEmpty)
          'fxReturnPanValues': fxReturnPanValues.map((k, v) => MapEntry(k.toString(), v)),
        if (lineInLevel != null) 'lineInLevel': lineInLevel,
        if (lineInPan != null) 'lineInPan': lineInPan,
      };

  factory FaderSnapshot.fromJson(Map<String, dynamic> json) => FaderSnapshot(
        name: json['name'] as String,
        values: (json['values'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(int.parse(k), (v as num).toDouble())),
        panValues: json['panValues'] != null
            ? (json['panValues'] as Map<String, dynamic>)
                .map((k, v) => MapEntry(int.parse(k), (v as num).toDouble()))
            : null,
        busLevel: json['busLevel'] != null ? (json['busLevel'] as num).toDouble() : null,
        busMuted: json['busMuted'] != null ? (json['busMuted'] as num) != 0 : null,
        fxReturnValues: json['fxReturnValues'] != null
            ? (json['fxReturnValues'] as Map<String, dynamic>)
                .map((k, v) => MapEntry(int.parse(k), (v as num).toDouble()))
            : null,
        fxReturnPanValues: json['fxReturnPanValues'] != null
            ? (json['fxReturnPanValues'] as Map<String, dynamic>)
                .map((k, v) => MapEntry(int.parse(k), (v as num).toDouble()))
            : null,
        lineInLevel: json['lineInLevel'] != null ? (json['lineInLevel'] as num).toDouble() : null,
        lineInPan: json['lineInPan'] != null ? (json['lineInPan'] as num).toDouble() : null,
      );
}

class SnapshotManager {
  static const _key = 'fader_snapshots_v1';
  final List<FaderSnapshot> snapshots = [];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      snapshots.clear();
      snapshots.addAll(
        list.map((e) => FaderSnapshot.fromJson(e as Map<String, dynamic>)),
      );
    } catch (_) {}
  }

  Future<void> add(FaderSnapshot snapshot) async {
    snapshots.add(snapshot);
    await _persist();
  }

  Future<void> remove(int index) async {
    snapshots.removeAt(index);
    await _persist();
  }

  Future<void> rename(int index, String newName) async {
    snapshots[index].name = newName;
    await _persist();
  }

  /// Replaces the snapshot at [index] but keeps its name: overwriting is
  /// "re-take this snapshot", not "rename it to whatever the caller passed".
  Future<void> overwrite(int index, FaderSnapshot snapshot) async {
    snapshot.name = snapshots[index].name;
    snapshots[index] = snapshot;
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(snapshots.map((s) => s.toJson()).toList()),
    );
  }
}
