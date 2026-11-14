import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'ui/login_screen.dart';
import 'ui/shell.dart';
import 'ui/widgets.dart';

class UberMaidsApp extends StatelessWidget {
  const UberMaidsApp({super.key, this.state});

  final AppState? state;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>(
      create: (_) => (state ?? AppState())..init(),
      child: MaterialApp(
        title: 'UBER MAIDS WATCH',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const _Gate(),
      ),
    );
  }
}

class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, app, _) {
        if (app.restoring) return const SplashScreen();
        if (!app.signedIn) return const LoginScreen();
        return const ShellScreen();
      },
    );
  }
}

const _brandTeal = Color(0xFF079DA5);
const _brandDeep = Color(0xFF075B63);
const _brandDeepInk = Color(0xFF053F45);
const _brandLightTeal = Color(0xFFE8F6F5);
const _brandCanvas = Color(0xFFF4F6F6);
const _brandGold = Color(0xFFE9A93B);
const _brandCharcoal = Color(0xFF22302F);
const _brandLine = Color(0xFFE1E9E8);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: _brandTeal,
    brightness: Brightness.light,
  ).copyWith(
    primary: _brandTeal,
    onPrimary: Colors.white,
    primaryContainer: _brandLightTeal,
    onPrimaryContainer: _brandDeep,
    secondary: _brandGold,
    onSecondary: _brandCharcoal,
    secondaryContainer: const Color(0xFFFDF1D8),
    onSecondaryContainer: const Color(0xFF6B4A08),
    surface: Colors.white,
    onSurface: _brandCharcoal,
    surfaceTint: Colors.transparent,
    outline: const Color(0xFFCFDCDA),
    error: const Color(0xFFB5342A),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: _brandCanvas,
    fontFamily: 'Segoe UI',
    appBarTheme: const AppBarTheme(
      backgroundColor: _brandCanvas,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: _brandCharcoal,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: _brandCharcoal,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFFBFDFD),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _brandTeal, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 46),
        backgroundColor: _brandTeal,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        foregroundColor: _brandDeep,
        side: BorderSide(color: Colors.black.withValues(alpha: 0.14)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: _brandDeep,
      indicatorColor: _brandLightTeal,
      selectedIconTheme: IconThemeData(color: _brandDeep),
      unselectedIconTheme: IconThemeData(color: Colors.white70),
      selectedLabelTextStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: TextStyle(color: Colors.white70),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: BorderSide.none,
    ),
    dividerTheme: const DividerThemeData(
      color: _brandLine,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: _brandDeepInk,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
  );
}
