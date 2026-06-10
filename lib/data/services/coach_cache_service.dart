import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class CoachCacheService {
  static const _keyDailySummary  = 'coach_daily_summary';
  static const _keyDailyDate     = 'coach_daily_date';
  static const _keyWeeklySummary = 'coach_weekly_summary';
  static const _keyWeeklyDate    = 'coach_weekly_date';

  Future<String?> getCachedDailySummary() async {
    final prefs = await SharedPreferences.getInstance();
    final date  = prefs.getString(_keyDailyDate) ?? '';
    final today = _todayStr();
    if (date == today) return prefs.getString(_keyDailySummary);
    return null;
  }

  Future<void> cacheDailySummary(String summary) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDailySummary, summary);
    await prefs.setString(_keyDailyDate, _todayStr());
  }

  Future<String?> getCachedWeeklySummary() async {
    final prefs  = await SharedPreferences.getInstance();
    final week   = prefs.getString(_keyWeeklyDate) ?? '';
    final thisWk = _weekStr();
    if (week == thisWk) return prefs.getString(_keyWeeklySummary);
    return null;
  }

  Future<void> cacheWeeklySummary(String summary) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyWeeklySummary, summary);
    await prefs.setString(_keyWeeklyDate, _weekStr());
  }

  String _todayStr() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  String _weekStr() {
    final n = DateTime.now();
    final monday = n.subtract(Duration(days: n.weekday - 1));
    return '${monday.year}-${monday.month}-${monday.day}';
  }

  // Health score history
  Future<List<Map<String, dynamic>>> getScoreHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('health_score_history') ?? '[]';
    return List<Map<String, dynamic>>.from(jsonDecode(raw));
  }

  Future<void> saveScoreEntry(int score, String date) async {
    final prefs   = await SharedPreferences.getInstance();
    final history = await getScoreHistory();
    history.removeWhere((e) => e['date'] == date);
    history.add({'date': date, 'score': score});
    if (history.length > 90) history.removeAt(0);
    await prefs.setString('health_score_history', jsonEncode(history));
  }

  // Challenge progress
  Future<Map<String, dynamic>> getChallengeState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString('challenge_state') ?? '{}';
    return Map<String, dynamic>.from(jsonDecode(raw));
  }

  Future<void> saveChallengeState(Map<String, dynamic> state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('challenge_state', jsonEncode(state));
  }
}
