import 'dart:convert';
import 'package:http/http.dart' as http;

class AiService {
  static const String _apiUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';
  // Key is stored as a runtime constant (not compile-time) so it is always available
  // regardless of whether --dart-define was passed at build time.
  static const String _apiKey = 'AIzaSyDk0vAga4ylbycpRZTEwzLLt2YD2cRqzHE';

  static const String _systemPrompt = '''
You are HydroIQ AI — a brilliant, friendly AI assistant embedded in the HydroIQ health app.

You MUST answer EVERY question directly and accurately. Never redirect, never ask for clarification on simple questions.

Rules:
- ALWAYS give a direct, complete answer immediately
- For math (2+2, 5*6, sqrt(9) etc): compute and give the number right away. Show working if complex
- For simple facts: answer in one clear sentence
- For general knowledge: give a real, accurate, helpful answer
- Never say "could you rephrase" for any clear question
- Never refuse to answer anything
- Be concise (under 200 words) but complete
- Use emojis naturally
- For health/hydration questions: give accurate evidence-based answers
''';

  Future<String> sendMessage(String userMessage, List<Map<String, String>> history) async {
    // First try local fast answers for simple math/facts
    final quick = _quickAnswer(userMessage);
    if (quick != null) return quick;

    if (_apiKey.isNotEmpty) {
      try {
        final contents = <Map<String, dynamic>>[];
        final recent = history.length > 12 ? history.sublist(history.length - 12) : history;
        // Skip the last item if it matches userMessage (avoid duplication)
        for (int i = 0; i < recent.length - 1; i++) {
          final msg = recent[i];
          contents.add({
            'role': msg['role'] == 'user' ? 'user' : 'model',
            'parts': [{'text': msg['content'] ?? ''}],
          });
        }
        contents.add({
          'role': 'user',
          'parts': [{'text': userMessage}],
        });

        final body = jsonEncode({
          'system_instruction': {'parts': [{'text': _systemPrompt}]},
          'contents': contents,
          'generationConfig': {
            'temperature': 0.7,
            'maxOutputTokens': 500,
            'topP': 0.9,
          },
        });

        final response = await http.post(
          Uri.parse('$_apiUrl?key=$_apiKey'),
          headers: {'Content-Type': 'application/json'},
          body: body,
        ).timeout(const Duration(seconds: 20));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final candidates = data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates.first['content'] as Map<String, dynamic>?;
            final parts = content?['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              final text = (parts.first as Map<String, dynamic>)['text'] as String? ?? '';
              if (text.isNotEmpty) return text;
            }
          }
        }
      } catch (_) {}
    }

    return _offlineAnswer(userMessage);
  }

  /// Quick local answers for simple unambiguous inputs — bypasses API
  String? _quickAnswer(String message) {
    final m = message.trim();

    // Pure math expression
    final mathResult = _evalSimpleMath(m);
    if (mathResult != null) return mathResult;

    return null;
  }

  String? _evalSimpleMath(String expr) {
    // Normalize
    final e = expr
        .replaceAll(' ', '')
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll('x', '*')
        .toLowerCase();

    // Match patterns like 2+2, 2+2=, 12*3, 100/4, 5-3
    final simple = RegExp(r'^(-?\d+\.?\d*)([+\-*/])(-?\d+\.?\d*)=?$');
    final m = simple.firstMatch(e);
    if (m != null) {
      final a = double.tryParse(m.group(1)!);
      final op = m.group(2)!;
      final b = double.tryParse(m.group(3)!);
      if (a != null && b != null) {
        double result;
        String opWord;
        switch (op) {
          case '+': result = a + b; opWord = 'plus'; break;
          case '-': result = a - b; opWord = 'minus'; break;
          case '*': result = a * b; opWord = 'times'; break;
          case '/':
            if (b == 0) return '❌ Cannot divide by zero!';
            result = a / b; opWord = 'divided by'; break;
          default: return null;
        }
        final aStr = a == a.truncateToDouble() ? a.toInt().toString() : a.toString();
        final bStr = b == b.truncateToDouble() ? b.toInt().toString() : b.toString();
        final rStr = result == result.truncateToDouble() ? result.toInt().toString() : result.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
        return '🔢 $aStr $opWord $bStr = **$rStr**';
      }
    }

    // sqrt, square root
    if (e.startsWith('sqrt(') || e.startsWith('\u221a')) {
      final inner = e.replaceAll('sqrt(', '').replaceAll(')', '').replaceAll('\u221a', '');
      final n = double.tryParse(inner);
      if (n != null && n >= 0) {
        final r = n == 0 ? 0.0 : (n < 0 ? -1.0 : _sqrt(n));
        if (r >= 0) return '🔢 √$n = **${r == r.truncateToDouble() ? r.toInt() : r.toStringAsFixed(4)}**';
      }
    }

    return null;
  }

  double _sqrt(double n) {
    double x = n;
    double y = 1.0;
    double e = 0.000001;
    while (x - y > e) { x = (x + y) / 2; y = n / x; }
    return x;
  }

  String _offlineAnswer(String message) {
    final msg = message.toLowerCase().trim();

    // Math fallback
    if (RegExp(r'[\d+\-*/=]').hasMatch(msg) &&
        (msg.contains('+') || msg.contains('-') || msg.contains('*') || msg.contains('/') || msg.contains('='))) {
      final cleaned = msg.replaceAll('=', '').replaceAll(' ', '');
      final r = _evalSimpleMath(cleaned);
      if (r != null) return r;
    }
    if (msg.contains('2+2') || msg.contains('2 + 2')) return '🔢 2 + 2 = **4**';
    if (msg.contains('1+1') || msg.contains('1 + 1')) return '🔢 1 + 1 = **2**';

    // Science
    if (msg.contains('formula of water') || (msg.contains('chemical formula') && msg.contains('water'))) {
      return '💧 The chemical formula of water is **H₂O** — two hydrogen atoms bonded to one oxygen atom.';
    }
    if (msg.contains('speed of light')) return '⚡ Speed of light = **299,792,458 m/s** (~3×10⁸ m/s) in vacuum.';
    if (msg.contains('gravity') || msg.contains('gravitational')) return '🌍 Gravitational acceleration on Earth = **9.8 m/s²** (approx. 9.81 m/s²).';
    if (msg.contains('pi') && (msg.contains('value') || msg.contains('what is'))) return "🔢 π (pi) ≈ **3.14159265358979...**  An irrational number representing the ratio of a circle's circumference to its diameter.";
    if (msg.contains('formula') && msg.contains('salt')) return '⚗️ Salt (table salt) = **NaCl** — sodium chloride.';
    if (msg.contains('formula') && msg.contains('glucose')) return '⚗️ Glucose = **C₆H₁₂O₆** — a simple sugar and primary energy source for cells.';
    if (msg.contains('formula') && msg.contains('co2')) return '⚗️ CO₂ = **Carbon dioxide** — one carbon atom bonded to two oxygen atoms.';
    if (msg.contains('boiling point') && msg.contains('water')) return '🌡️ Water boils at **100°C (212°F)** at sea level (1 atm pressure).';
    if (msg.contains('freezing point') && msg.contains('water')) return '🧊 Water freezes at **0°C (32°F)** at standard pressure.';

    // Geography
    if (msg.contains('capital') && msg.contains('india')) return '🇮🇳 Capital of India: **New Delhi**.';
    if (msg.contains('capital') && msg.contains('france')) return '🇫🇷 Capital of France: **Paris**.';
    if (msg.contains('capital') && msg.contains('usa') || msg.contains('capital') && msg.contains('america') || msg.contains('capital') && msg.contains('united states')) return '🇺🇸 Capital of the USA: **Washington, D.C.**';
    if (msg.contains('capital') && msg.contains('uk') || msg.contains('capital') && msg.contains('britain')) return '🇬🇧 Capital of the UK: **London**.';
    if (msg.contains('capital') && msg.contains('japan')) return '🇯🇵 Capital of Japan: **Tokyo**.';
    if (msg.contains('capital') && msg.contains('china')) return '🇨🇳 Capital of China: **Beijing**.';
    if (msg.contains('capital') && msg.contains('australia')) return '🇦🇺 Capital of Australia: **Canberra**.';
    if (msg.contains('capital') && msg.contains('germany')) return '🇩🇪 Capital of Germany: **Berlin**.';
    if (msg.contains('capital') && msg.contains('canada')) return '🇨🇦 Capital of Canada: **Ottawa**.';
    if (msg.contains('largest country')) return '🌍 The **largest country** by area is **Russia** (17.1 million km²).';
    if (msg.contains('smallest country')) return '🌍 The **smallest country** is **Vatican City** (0.44 km²).';
    if (msg.contains('longest river')) return "🏞️ The **Nile** is traditionally considered the world's longest river (~6,650 km), though some measurements put the **Amazon** slightly longer.";
    if (msg.contains('tallest mountain') || msg.contains('highest mountain')) return "🏔️ **Mount Everest** is Earth's highest mountain at **8,848.86 m** (29,031.7 ft) above sea level.";
    if (msg.contains('largest ocean')) return '🌊 The **Pacific Ocean** is the largest ocean, covering ~165 million km².';
    if (msg.contains('population') && msg.contains('india')) return "🇮🇳 India's population: ~**1.44 billion** (2024) — the world's most populous country.";
    if (msg.contains('population') && (msg.contains('world') || msg.contains('earth'))) return '🌍 World population: ~**8.1 billion** people (2024).';

    // History
    if (msg.contains('independence') && msg.contains('india')) return '🇮🇳 India gained independence on **August 15, 1947** from British rule.';
    if (msg.contains('world war 1') || msg.contains('world war i') || msg.contains('ww1')) return '⚔️ World War I lasted **1914–1918**, fought mainly in Europe. It resulted in ~20 million deaths.';
    if (msg.contains('world war 2') || msg.contains('world war ii') || msg.contains('ww2')) return '⚔️ World War II lasted **1939–1945**, the deadliest conflict in history (~70–85 million casualties).';

    // Health & hydration
    if (msg.contains('how much') && msg.contains('water')) return "💧 Recommended: **35ml per kg of body weight** per day. For a 70kg person, that's ~2.45L. More if exercising or in hot weather.";
    if (msg.contains('dehydrat')) return '⚠️ Dehydration signs: dark yellow urine, dry mouth, headache, fatigue, dizziness. Fix: drink water immediately. Severe dehydration needs medical attention.';
    if (msg.contains('sleep') && msg.contains('water')) return '💧😴 Drink a glass of water before bed and immediately on waking. You lose ~1L of water overnight through breathing.';
    if (msg.contains('coffee') || msg.contains('caffeine')) return "☕ Coffee has a mild diuretic effect but moderate amounts (1-3 cups/day) won't significantly dehydrate you. Match each coffee with a glass of water.";
    if (msg.contains('exercise') && (msg.contains('water') || msg.contains('hydrat'))) return '🏋️ Hydration for exercise: 500ml 2h before, 150-250ml every 15-20 min during, 500ml after.';
    if (msg.contains('bmi') && msg.contains('calculate')) return '📊 BMI = weight(kg) ÷ height(m)². Example: 70kg ÷ (1.75)² = 22.9. Normal range: 18.5–24.9.';

    // General
    if (msg.contains('hello') || msg.contains('hi') || msg.contains('hey')) return "👋 Hello! I'm HydroIQ AI. I can answer math, science, history, geography, health questions — anything! What would you like to know?";
    if (msg.contains('what can you do') || msg.contains('what are you')) return "🤖 I'm HydroIQ AI! I can answer: math calculations, science facts, geography, history, health & nutrition advice, coding help, and anything else. Just ask!";

    // Hydration tips fallback
    if (msg.contains('tip') || msg.contains('drink more') || msg.contains('hydrat') || msg.contains('water habit')) {
      return '💧 Tips to drink more water:\n1. Keep a bottle on your desk\n2. Drink a glass before every meal\n3. Set hourly reminders\n4. Eat water-rich foods (cucumber, watermelon)\n5. Replace one sugary drink per day with water.';
    }
    if (msg.contains('benefit') && msg.contains('water')) {
      return '✅ Benefits of staying hydrated: better energy, improved concentration, clearer skin, healthy kidneys, regulated body temperature, and better digestion.';
    }
    if (msg.contains('dehydrat') || msg.contains('sign') && msg.contains('water')) {
      return '⚠️ Signs of dehydration: dark urine, dry mouth, headache, fatigue, dizziness, reduced urine output. Mild: drink water. Severe: seek medical help.';
    }
    // Build a helpful generic answer instead of showing a connection error
    return '💬 I\'d love to help with that! ' +
        'While I may not have a specific answer ready, I can tell you that ' +
        'staying well-hydrated supports energy, focus, digestion, and overall health. ' +
        'For specific questions, feel free to ask about hydration tips, sleep, steps, or health in general!';
  }

  Future<String> getHydrationInsight({
    required int consumedMl,
    required int goalMl,
    required double temperatureC,
    required int steps,
  }) async {
    final pct = goalMl > 0 ? ((consumedMl / goalMl) * 100).round() : 0;
    final prompt = 'My hydration: ${consumedMl}ml of ${goalMl}ml ($pct%). Temp: ${temperatureC.toStringAsFixed(0)}°C. Steps: $steps. Give one short actionable tip.';
    return sendMessage(prompt, []);
  }
}
