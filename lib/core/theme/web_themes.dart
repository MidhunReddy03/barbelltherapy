import 'package:material_ui/material_ui.dart';

/// Curated UI theme presets exclusively for the Barbell Therapy web portal.
enum WebThemePreset {
  barbellForge(
    id: 'forge',
    name: 'Barbell Forge',
    subtitle: 'Obsidian & Terracotta',
    bg: Color(0xFF17191C),
    surface: Color(0xFF1F2226),
    surfaceRaised: Color(0xFF282C31),
    border: Color(0xFF32373D),
    accent: Color(0xFFD98A5B),
    accentHighlight: Color(0xFFE0966A),
    onAccent: Color(0xFF17191C),
    textPrimary: Color(0xFFEEEAE3),
    textSecondary: Color(0xFFA5A199),
  ),
  crimsonBull(
    id: 'crimson',
    name: 'Crimson Bull',
    subtitle: 'Iron & Red Steel',
    bg: Color(0xFF110E10),
    surface: Color(0xFF1A1518),
    surfaceRaised: Color(0xFF251E22),
    border: Color(0xFF382B31),
    accent: Color(0xFFE5484D),
    accentHighlight: Color(0xFFFF6B6E),
    onAccent: Color(0xFFFFFFFF),
    textPrimary: Color(0xFFF4EFF2),
    textSecondary: Color(0xFFABA0A6),
  ),
  midnightCobalt(
    id: 'cobalt',
    name: 'Midnight Cobalt',
    subtitle: 'Slate & Electric Blue',
    bg: Color(0xFF0D1117),
    surface: Color(0xFF161B22),
    surfaceRaised: Color(0xFF21262D),
    border: Color(0xFF30363D),
    accent: Color(0xFF3B82F6),
    accentHighlight: Color(0xFF60A5FA),
    onAccent: Color(0xFFFFFFFF),
    textPrimary: Color(0xFFF0F6FC),
    textSecondary: Color(0xFF8B949E),
  ),
  emeraldPulse(
    id: 'emerald',
    name: 'Emerald Pulse',
    subtitle: 'Deep Forest & Mint',
    bg: Color(0xFF0B1412),
    surface: Color(0xFF12201C),
    surfaceRaised: Color(0xFF1A2D28),
    border: Color(0xFF264039),
    accent: Color(0xFF10B981),
    accentHighlight: Color(0xFF34D399),
    onAccent: Color(0xFF062016),
    textPrimary: Color(0xFFECFDF5),
    textSecondary: Color(0xFF94B4A9),
  ),
  champagneGold(
    id: 'gold',
    name: 'Champagne Gold',
    subtitle: 'Matte Onyx & Gold',
    bg: Color(0xFF14120F),
    surface: Color(0xFF1E1B16),
    surfaceRaised: Color(0xFF29251E),
    border: Color(0xFF3B352A),
    accent: Color(0xFFEAB308),
    accentHighlight: Color(0xFFFACC15),
    onAccent: Color(0xFF14120F),
    textPrimary: Color(0xFFFAF6EE),
    textSecondary: Color(0xFFA8A092),
  );

  const WebThemePreset({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.accent,
    required this.accentHighlight,
    required this.onAccent,
    required this.textPrimary,
    required this.textSecondary,
  });

  final String id;
  final String name;
  final String subtitle;
  final Color bg;
  final Color surface;
  final Color surfaceRaised;
  final Color border;
  final Color accent;
  final Color accentHighlight;
  final Color onAccent;
  final Color textPrimary;
  final Color textSecondary;

  static WebThemePreset fromId(String? id) {
    for (final p in WebThemePreset.values) {
      if (p.id == id) return p;
    }
    return WebThemePreset.barbellForge;
  }
}
