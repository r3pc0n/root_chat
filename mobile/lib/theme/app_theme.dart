import 'package:flutter/material.dart';

class AppThemeData {
  final String key;
  final String label;
  final bool isLight;

  final Color bg, surface, border, dim, dimmer, muted, body;
  final Color amber, green, red, own, subtle, saved, sys;

  const AppThemeData({
    required this.key,
    required this.label,
    required this.isLight,
    required this.bg,
    required this.surface,
    required this.border,
    required this.dim,
    required this.dimmer,
    required this.muted,
    required this.body,
    required this.amber,
    required this.green,
    required this.red,
    required this.own,
    required this.subtle,
    required this.saved,
    required this.sys,
  });

  static const dark = AppThemeData(
    key: 'dark', label: 'dark', isLight: false,
    bg:      Color(0xFF0D0D0D),
    surface: Color(0xFF141414),
    border:  Color(0xFF1A1A1A),
    dim:     Color(0xFF2E2E2E),
    dimmer:  Color(0xFF1E1E1E),
    muted:   Color(0xFF444444),
    body:    Color(0xFF888888),
    amber:   Color(0xFFFFAA00),
    green:   Color(0xFF4A7C59),
    red:     Color(0xFF6B2020),
    own:     Color(0xFF555555),
    subtle:  Color(0xFF252525),
    saved:   Color(0xFF2A2A2A),
    sys:     Color(0xFF3A3A3A),
  );

  static const highContrast = AppThemeData(
    key: 'contrast', label: 'contrast', isLight: false,
    bg:      Color(0xFF0D0D0D),
    surface: Color(0xFF161616),
    border:  Color(0xFF303030),
    dim:     Color(0xFF5A5A5A),
    dimmer:  Color(0xFF333333),
    muted:   Color(0xFF888888),
    body:    Color(0xFFCCCCCC),
    amber:   Color(0xFFFFCC44),
    green:   Color(0xFF55BB66),
    red:     Color(0xFFDD4444),
    own:     Color(0xFF999999),
    subtle:  Color(0xFF444444),
    saved:   Color(0xFF555555),
    sys:     Color(0xFF666666),
  );

  static const light = AppThemeData(
    key: 'light', label: 'light', isLight: true,
    bg:      Color(0xFFF0EFE8),
    surface: Color(0xFFE3E2DB),
    border:  Color(0xFFC8C7C0),
    dim:     Color(0xFF9E9D96),
    dimmer:  Color(0xFFB8B7B0),
    muted:   Color(0xFF6E6D66),
    body:    Color(0xFF252420),
    amber:   Color(0xFF8B5E00),
    green:   Color(0xFF1A5C30),
    red:     Color(0xFF8B1A1A),
    own:     Color(0xFF555550),
    subtle:  Color(0xFFB8B7B0),
    saved:   Color(0xFFA0A09A),
    sys:     Color(0xFF7A7A74),
  );

  static const all = [dark, highContrast, light];

  static AppThemeData fromKey(String key) =>
      all.firstWhere((t) => t.key == key, orElse: () => dark);
}

class AppTheme extends InheritedWidget {
  final AppThemeData data;
  final ValueNotifier<AppThemeData> notifier;

  const AppTheme({
    super.key,
    required this.data,
    required this.notifier,
    required super.child,
  });

  static AppThemeData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppTheme>()!.data;

  static ValueNotifier<AppThemeData> notifierOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppTheme>()!.notifier;

  @override
  bool updateShouldNotify(AppTheme old) => data != old.data;
}
