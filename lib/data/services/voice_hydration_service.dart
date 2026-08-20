// voice_hydration_service.dart
// Handles parsing voice input into ml values for water logging.
// Background voice (tile/assistant shortcut) is handled by a Flutter Local
// Notification action + foreground service; the parsing logic lives here so
// it can be reused from the UI and the notification callback.

class VoiceHydrationService {
  /// Converts a voice transcript like "I drank 2 glasses of water" → ml int.
  /// Returns null if parsing fails.
  static int? parseTranscriptToMl(String raw) {
    final text = raw.toLowerCase().trim();

    // Find the first numeric value (int or float)
    final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(text);
    if (numMatch == null) return null;
    final num = double.tryParse(numMatch.group(1)!) ?? 0;
    if (num <= 0) return null;

    // Unit mapping (ordered most-specific first)
    if (_contains(text, ['milliliter', 'millilitre', 'ml'])) return num.round();
    if (_contains(text, ['liter', 'litre', 'liters', 'litres', ' l '])) return (num * 1000).round();
    if (_contains(text, ['glass', 'glasses', 'cup', 'cups'])) return (num * 240).round();
    if (_contains(text, ['bottle', 'bottles'])) return (num * 500).round();
    if (_contains(text, ['sip', 'sips'])) return (num * 50).round();
    if (_contains(text, ['mug', 'mugs'])) return (num * 300).round();
    if (_contains(text, ['can', 'cans'])) return (num * 330).round();
    if (_contains(text, ['jug', 'jugs'])) return (num * 1000).round();

    // Bare number heuristic: ≥ 50 → treat as ml, else as glasses
    return num >= 50 ? num.round() : (num * 240).round();
  }

  static bool _contains(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));

  /// Human-readable description of parsed amount (for confirmation dialogs).
  static String describeAmount(int ml) {
    if (ml >= 1000) return '${(ml / 1000).toStringAsFixed(2)}L';
    return '${ml}ml';
  }
}
