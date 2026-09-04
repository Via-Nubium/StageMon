import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stagemon/models/saved_layout.dart';

import 'saved_layout_test.dart' show buildLayout, buildLayoutState;

// LayoutManager is what a tester actually exercises: save a layout, rename
// it, overwrite it, reopen the app. Each mutation has to reach disk, since
// there is no other copy of the list.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  SavedLayout named(String name) {
    final l = buildLayout();
    l.name = name;
    return l;
  }

  test('starts empty and stays empty when nothing was ever saved', () async {
    final m = LayoutManager();
    await m.load();
    expect(m.layouts, isEmpty);
  });

  test('an added layout survives a reload', () async {
    final m = LayoutManager();
    await m.add(named('Guitarra'));

    final reopened = LayoutManager();
    await reopened.load();
    expect(reopened.layouts.length, 1);
    expect(reopened.layouts.single.name, 'Guitarra');
    final state = reopened.layouts.single.resolvedLayout(1);
    expect(state.channels, {1, 2, 3, 9});
    expect(state.groups.single.channels, {5, 6});
  });

  test('keeps insertion order across a reload', () async {
    final m = LayoutManager();
    await m.add(named('A'));
    await m.add(named('B'));
    await m.add(named('C'));

    final reopened = LayoutManager();
    await reopened.load();
    expect(reopened.layouts.map((l) => l.name), ['A', 'B', 'C']);
  });

  test('rename persists', () async {
    final m = LayoutManager();
    await m.add(named('Viejo'));
    await m.rename(0, 'Nuevo');

    final reopened = LayoutManager();
    await reopened.load();
    expect(reopened.layouts.single.name, 'Nuevo');
  });

  test('remove persists and shifts the rest down', () async {
    final m = LayoutManager();
    await m.add(named('A'));
    await m.add(named('B'));
    await m.remove(0);

    final reopened = LayoutManager();
    await reopened.load();
    expect(reopened.layouts.map((l) => l.name), ['B']);
  });

  test('overwrite replaces the contents but keeps the existing name', () async {
    final m = LayoutManager();
    await m.add(named('Monitor Batería'));

    final replacement = SavedLayout(
      name: 'nombre que se descarta',
      console: 'XR18',
      bus: 3,
      layout: buildLayoutState().copyWith(channels: {7, 8}),
    );
    await m.overwrite(0, replacement);

    final reopened = LayoutManager();
    await reopened.load();
    expect(reopened.layouts.single.name, 'Monitor Batería');
    expect(reopened.layouts.single.resolvedLayout(1).channels, {7, 8});
  });

  test('a corrupt store loads as empty instead of throwing', () async {
    SharedPreferences.setMockInitialValues({
      'saved_layouts_v2': 'not json at all',
    });
    final m = LayoutManager();
    await expectLater(m.load(), completes);
    expect(m.layouts, isEmpty);
  });

  test('one unreadable entry does not cost the user the others', () async {
    // SavedLayout.fromJson throws on anything that isn't a layout, so a
    // single bad entry must not abort the whole load — nor leave the list
    // half-filled from a clear() that already ran.
    final good = named('Buena').toJson();
    SharedPreferences.setMockInitialValues({
      'saved_layouts_v2': jsonEncode([
        good,
        {'not': 'a layout'},
        {...good, 'name': 'Otra buena'},
      ]),
    });
    final m = LayoutManager();
    await m.load();
    expect(m.layouts.map((l) => l.name), ['Buena', 'Otra buena']);
  });

  test('load() twice does not duplicate the list', () async {
    final m = LayoutManager();
    await m.add(named('A'));
    await m.load();
    await m.load();
    expect(m.layouts.length, 1);
  });
}
