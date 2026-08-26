import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:stagemon/l10n/app_localizations.dart';
import 'screens/connect_screen.dart';
import 'services/screen_awake_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(MaterialApp(
    home: const ConnectScreen(),
    debugShowCheckedModeBanner: false,
    // Global pointer watcher for ScreenAwakeService's inactivity timer — a
    // no-op while it's inactive (i.e. on the connect screen). `Listener`
    // only observes, so it never steals gestures from faders/knobs below it.
    builder: (context, child) => Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => ScreenAwakeService.registerInteraction(),
      onPointerMove: (_) => ScreenAwakeService.registerInteraction(),
      child: child,
    ),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [
      Locale('en'),
      Locale('es'),
    ],
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ).copyWith(
        secondaryContainer: const Color(0xFF1A3F6F),
        onSecondaryContainer: Colors.white,
        outline: const Color(0xFF3A6EA8),
      ),
      scaffoldBackgroundColor: Colors.black,
    ),
  ));
}
