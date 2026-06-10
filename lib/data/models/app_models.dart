/// User Profile Model
class UserProfile {
  final String id;
  final String email;
  final String name;
  final String gender; // 'male', 'female', 'other'
  final int age;
  final double weightKg;
  final int dailyGoalMl;
  final String? avatarUrl;
  final DateTime createdAt;

  const UserProfile({
    required this.id,
    required this.email,
    required this.name,
    required this.gender,
    required this.age,
    required this.weightKg,
    required this.dailyGoalMl,
    this.avatarUrl,
    required this.createdAt,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      email: map['email'] as String,
      name: map['name'] as String,
      gender: map['gender'] as String,
      age: map['age'] as int,
      weightKg: (map['weight_kg'] as num).toDouble(),
      dailyGoalMl: map['daily_goal_ml'] as int? ?? 2000,
      avatarUrl: map['avatar_url'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'email': email,
        'name': name,
        'gender': gender,
        'age': age,
        'weight_kg': weightKg,
        'daily_goal_ml': dailyGoalMl,
        'avatar_url': avatarUrl,
        'created_at': createdAt.toIso8601String(),
      };

  UserProfile copyWith({
    String? name,
    String? gender,
    int? age,
    double? weightKg,
    int? dailyGoalMl,
    String? avatarUrl,
  }) {
    return UserProfile(
      id: id,
      email: email,
      name: name ?? this.name,
      gender: gender ?? this.gender,
      age: age ?? this.age,
      weightKg: weightKg ?? this.weightKg,
      dailyGoalMl: dailyGoalMl ?? this.dailyGoalMl,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt,
    );
  }
}

/// Hydration Log Model
class HydrationLog {
  final String id;
  final String userId;
  final int amountMl;
  final DateTime loggedAt;
  final String? note;

  const HydrationLog({
    required this.id,
    required this.userId,
    required this.amountMl,
    required this.loggedAt,
    this.note,
  });

  factory HydrationLog.fromMap(Map<String, dynamic> map) {
    return HydrationLog(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      amountMl: map['amount_ml'] as int,
      loggedAt: DateTime.parse(map['logged_at'] as String),
      note: map['note'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'amount_ml': amountMl,
        'logged_at': loggedAt.toIso8601String(),
        'note': note,
      };
}

/// Step Log Model
class StepLog {
  final String id;
  final String userId;
  final int steps;
  final double distanceKm;
  final double caloriesBurned;
  final DateTime date;

  const StepLog({
    required this.id,
    required this.userId,
    required this.steps,
    required this.distanceKm,
    required this.caloriesBurned,
    required this.date,
  });

  factory StepLog.fromMap(Map<String, dynamic> map) {
    return StepLog(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      steps: map['steps'] as int,
      distanceKm: (map['distance_km'] as num).toDouble(),
      caloriesBurned: (map['calories_burned'] as num).toDouble(),
      date: DateTime.parse(map['date'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'steps': steps,
        'distance_km': distanceKm,
        'calories_burned': caloriesBurned,
        'date': date.toIso8601String(),
      };
}

/// Sleep Log Model
class SleepLog {
  final String id;
  final String userId;
  final DateTime sleepStart;
  final DateTime sleepEnd;
  final double durationHours;
  final int sleepScore; // 0-100

  const SleepLog({
    required this.id,
    required this.userId,
    required this.sleepStart,
    required this.sleepEnd,
    required this.durationHours,
    required this.sleepScore,
  });

  factory SleepLog.fromMap(Map<String, dynamic> map) {
    return SleepLog(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      sleepStart: DateTime.parse(map['sleep_start'] as String),
      sleepEnd: DateTime.parse(map['sleep_end'] as String),
      durationHours: (map['duration_hours'] as num).toDouble(),
      sleepScore: map['sleep_score'] as int,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'sleep_start': sleepStart.toIso8601String(),
        'sleep_end': sleepEnd.toIso8601String(),
        'duration_hours': durationHours,
        'sleep_score': sleepScore,
      };
}

/// Weather Model
class WeatherData {
  final String city;
  final double temperatureC;
  final double humidity;
  final String condition;
  final String iconCode;
  final int recommendedExtraMl;

  const WeatherData({
    required this.city,
    required this.temperatureC,
    required this.humidity,
    required this.condition,
    required this.iconCode,
    required this.recommendedExtraMl,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final temp = (json['main']['temp'] as num).toDouble() - 273.15;
    final humidity = (json['main']['humidity'] as num).toDouble();
    final condition = json['weather'][0]['description'] as String;
    final icon = json['weather'][0]['icon'] as String;
    final city = json['name'] as String;

    // Extra water based on heat
    int extra = 0;
    if (temp > 35) extra = 750;
    else if (temp > 30) extra = 500;
    else if (temp > 25) extra = 250;

    return WeatherData(
      city: city,
      temperatureC: temp,
      humidity: humidity,
      condition: condition,
      iconCode: icon,
      recommendedExtraMl: extra,
    );
  }
}

/// AI Chat Message Model
class ChatMessage {
  final String id;
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime timestamp;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as String,
      role: map['role'] as String,
      content: map['content'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };
}
