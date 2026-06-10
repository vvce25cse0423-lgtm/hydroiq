import 'dart:convert';
import 'package:http/http.dart' as http;

class AiService {
  static const String _apiUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';
  static const String _apiKey = 'AIzaSyDk0vAga4ylbycpRZTEwzLLt2YD2cRqzHE';

  static const String _systemPrompt = '''
You are HydroIQ AI, a smart and friendly assistant inside the HydroIQ health app.
You can answer ALL questions — general knowledge, science, math, history, coding, and any topic.
You also specialize in:
- Water intake and hydration recommendations
- Dehydration symptoms and prevention
- Exercise and workout hydration
- Sleep and hydration relationships
- Health, nutrition, and wellness tips

Rules:
- Always give a real, helpful, accurate answer to ANY question asked
- Be concise (under 180 words) unless detail is explicitly needed
- Use emojis naturally
- Never say you can only answer hydration questions
- For general questions (math, science, history, etc.) — answer them directly and completely
- Do NOT redirect general questions back to hydration
''';

  Future<String> sendMessage(String userMessage, List<Map<String, String>> history) async {
    try {
      // Build conversation parts
      final contents = <Map<String, dynamic>>[];

      // Add history
      final recent = history.length > 16 ? history.sublist(history.length - 16) : history;
      for (final msg in recent) {
        contents.add({
          'role': msg['role'] == 'user' ? 'user' : 'model',
          'parts': [{'text': msg['content'] ?? ''}],
        });
      }

      // Add current message
      contents.add({
        'role': 'user',
        'parts': [{'text': userMessage}],
      });

      final body = jsonEncode({
        'system_instruction': {'parts': [{'text': _systemPrompt}]},
        'contents': contents,
        'generationConfig': {
          'temperature': 0.7,
          'maxOutputTokens': 400,
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
            return (parts.first as Map<String, dynamic>)['text'] as String? ?? _offlineAnswer(userMessage);
          }
        }
        return _offlineAnswer(userMessage);
      } else {
        return _offlineAnswer(userMessage);
      }
    } catch (_) {
      return _offlineAnswer(userMessage);
    }
  }

  /// Comprehensive offline knowledge base
  String _offlineAnswer(String message) {
    final msg = message.toLowerCase();

    // Science & general knowledge
    if (msg.contains('formula of water') || msg.contains('chemical formula') && msg.contains('water')) {
      return '💧 The chemical formula of water is **H₂O** — two hydrogen atoms bonded to one oxygen atom. Water is a polar molecule with a bent shape, giving it unique properties like high surface tension and the ability to dissolve many substances.';
    }
    if (msg.contains('formula') || msg.contains('chemical')) {
      return '⚗️ I can help with chemical formulas! Common ones: Water = H₂O, Salt = NaCl, Glucose = C₆H₁₂O₆, Carbon dioxide = CO₂, Oxygen = O₂. Which one do you need?';
    }
    if (msg.contains('capital') && (msg.contains('india') || msg.contains('indian'))) {
      return '🇮🇳 The capital of India is New Delhi. It is located in the northern part of India and serves as the seat of all three branches of the Government of India.';
    }
    if (msg.contains('capital')) {
      return '🌍 I can help with world capitals! Ask me about any specific country and I\'ll tell you its capital city.';
    }
    if (msg.contains('prime minister') && msg.contains('india')) {
      return '🇮🇳 The Prime Minister of India is Narendra Modi (as of 2024), leader of the BJP party. He has been PM since May 2014.';
    }
    if (msg.contains('president') && msg.contains('india')) {
      return '🇮🇳 The President of India is Droupadi Murmu, who took office in July 2022. She is the 15th President and the first person from a tribal community to hold this position.';
    }
    if (msg.contains('speed of light')) {
      return '⚡ The speed of light in vacuum is approximately 299,792,458 m/s (about 3×10⁸ m/s). Light travels this fast only in a vacuum; in other mediums it slows down.';
    }
    if (msg.contains('python') || msg.contains('programming') || msg.contains('code')) {
      return '💻 I can help with programming! Python is great for beginners — it\'s readable, versatile, and widely used in AI, data science, and web development. What specific coding question do you have?';
    }
    if (msg.contains('math') || msg.contains('calculate') || msg.contains('equation')) {
      return '🔢 Happy to help with math! Ask me a specific equation, formula, or calculation and I\'ll work through it step by step.';
    }

    // Health & hydration
    if (msg.contains('how much') && msg.contains('water')) {
      return '💧 General recommendation: 8 glasses (~2L/day). More precisely, drink 35ml per kg of body weight. Increase intake during exercise, hot weather, or illness. Your HydroIQ goal is personalized to you!';
    }
    if (msg.contains('dehydrat')) {
      return '⚠️ Dehydration signs: dark yellow urine, dry mouth, headache, fatigue, dizziness. Severe: rapid heartbeat, confusion. Fix: drink water immediately, rest, and if severe — seek medical help.';
    }
    if (msg.contains('sleep')) {
      return '😴 Good sleep (7-9 hrs) optimizes hormone balance and reduces dehydration. Drink a glass of water before bed and immediately upon waking. Poor sleep increases cortisol, worsening fluid retention issues.';
    }
    if (msg.contains('exercise') || msg.contains('workout') || msg.contains('gym')) {
      return '🏋️ Exercise hydration: drink 500ml 2 hours before, 150-250ml every 15-20 min during, and 500ml after. For sessions over 1 hour, consider electrolyte drinks.';
    }
    if (msg.contains('coffee') || msg.contains('caffeine')) {
      return '☕ Coffee is mildly diuretic but 1-3 cups won\'t significantly dehydrate you. Still, pair each coffee with a glass of water. Tea and coffee do count partially toward daily fluid intake.';
    }

    // Default
    return '🤖 I\'m your HydroIQ AI assistant and I can answer any question — science, math, history, health, or anything else! Your question: "${message.length > 50 ? message.substring(0, 50) + "..." : message}". Could you rephrase or add more detail? I\'m here to help!';
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
