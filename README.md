# 💧 HydroIQ — Smart Hydration & Wellness Tracker

**Developer:** Nitin Mahadev  
**Platform:** Android (Flutter)  
**Version:** 1.0.0  
**Repository:** [github.com/vvce25cse0423-lgtm/hydroiq](https://github.com/vvce25cse0423-lgtm/hydroiq)

---

## 🌟 Key Features

### 💧 Hydration Dashboard
- Animated water-fill circle with live wave motion and percentage indicator.
- Quick-add buttons: 100ml, 250ml, 500ml, 1L.
- Custom amount entry with voice-to-text ("I drank 2 glasses of water").
- **Water sound effects** on every log entry.
- **Daily safety limit** (5L) preventing over-hydration.
- Real-time logging with swipe-to-delete and Clear All confirmation.
- Weather-based intake adjustments (auto-increases on hotter days).
- Persistent notification shade with one-tap quick-add buttons (+250ml / +500ml) even when the app is closed.

### 📱 Android Home Screen Widget
- Quick-add **+250ml** widget directly from your Android home screen without opening the app.
- Real-time hydration level and daily goal progress synchronized seamlessly with the app database.
- Modern visual styling with glassmorphism, clean typography, and interactive button feedback.

### 🔐 Authentication & Google Sign-In
- Email & password sign-up and sign-in with auto-confirmation.
- **One-tap Google Sign-In** integrated into both Login and Signup screens using official Google branding.
- Secure Supabase OAuth with deep-link redirection (`io.supabase.hydroiq://login-callback/`).
- Seamless guest / offline fallback when backend credentials are not supplied.

### 👟 Step & Activity Tracking
- Dual tracking: Hardware pedometer (primary) with automatic activity recognition + **smart accelerometer fallback** with rhythmic cadence filtering to eliminate false positives from phone vibrations or bumps.
- Step count persistence across app restarts.
- Weekly interactive step charts (fl_chart) showing last 7 days.
- Real-time sensor status (Walking / Stopped / Sensor Mode) with estimated calories burned and distance.
- Health Connect integration for reading step counts.

### 😴 Sleep Tracker
- Voice triggers: "I am going to sleep" to start, "Good morning" or "Wake up" to stop.
- Sleep session state persistence across app lifecycle.
- Automated background monitoring via WorkManager.
- Auto-hydration bonus on wake-up: Poor sleep (<5h) → +500ml, Good sleep (7–9h) → +200ml.
- Night-sky animated interface with sleep quality scoring (0–100).

### 🤖 World-Class AI Chatbot (Powered by Groq)
- **Universal General Knowledge**: Answers ANY question in the world on ANY topic — mathematics, science, world history, coding, health, fitness, or daily advice.
- **Ultra-Fast Groq Inference**: High-speed, high-accuracy conversational AI with automatic fallback model recovery.
- Voice input: Tap the microphone to dictate questions directly.
- Offline knowledge base: Embedded instant responses for core facts and math even when offline.
- Conversation history persistence in Supabase.

### 📊 Stats, Streaks & Badges
- Weekly hydration bar charts and historical analytics.
- Daily streaks and milestone badges (First Drop, 4-Day Explorer, 7-Day Streak, 14-Day Hero, 30-Day Champion).
- Instant metric refresh between views.

### 🌦️ Weather Integration
- Pre-fetched weather data during splash initialization for instant display on the dashboard.
- Temperature and condition badge that adjusts your recommended hydration intake dynamically.

---

## 🛠️ Tech Stack

| Component | Technology |
|---|---|
| Framework | Flutter 3.24.5 (Dart 3.x) |
| Architecture / State | Riverpod 2.x (StateNotifier / Providers) |
| Backend & Auth | Supabase (PostgreSQL, Row-Level Security, OAuth) |
| AI Engine | Groq API (High-performance inference + offline fallback) |
| Weather | OpenWeatherMap API |
| Home Screen Widget | `home_widget` package (Android RemoteViews & AppWidgetProvider) |
| Step Detection | `pedometer`, `sensors_plus`, `health` (Health Connect) |
| Voice & Audio | `speech_to_text`, `audioplayers` |
| Notifications & Tasks | `flutter_local_notifications`, `timezone`, `workmanager` |
| Local Storage | `shared_preferences`, `hive_flutter` |
| Charts & UI | `fl_chart`, `flutter_animate`, Google Fonts |

---

## 🔒 Security & Environment Configuration

All API keys and secrets are injected at compile time. **No sensitive API keys are ever stored in the tracked source code.**

### Setting Up Environment Variables

1. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```

2. Fill in your keys in `.env`:
   ```env
   SUPABASE_URL=https://your-project.supabase.co
   SUPABASE_ANON_KEY=your_supabase_anon_key
   WEATHER_API_KEY=your_openweather_key
   GROQ_API_KEY=your_groq_api_key
   ```
   *(Note: `.env` is ignored by `.gitignore` and must never be committed)*.

---

## 🚀 Building & Running

### Prerequisites
- Flutter 3.24.5
- Android SDK 35 / NDK 27.0.12077973
- Java 17

### Development Run
```bash
# Run with environment variables loaded from .env
flutter run --dart-define-from-file=.env
```

### Release APK Build
```bash
# Build release APK
flutter build apk --release --no-tree-shake-icons --dart-define-from-file=.env
```

---

## 🗄️ Database Schema

The database runs on Supabase PostgreSQL. Core tables:
- `users`: User profiles, goals, and metric preferences.
- `hydration_logs`: Individual intake timestamps, volumes, and beverage types.
- `step_logs`: Daily step counts, distance, and calories.
- `sleep_logs`: Sleep sessions, start/end times, and quality ratings.
- `ai_chats`: AI chatbot conversation histories.
- `settings`: Application and notification configurations.

---

## 👨‍💻 Author

**Nitin Mahadev**  
GitHub: [@vvce25cse0423-lgtm](https://github.com/vvce25cse0423-lgtm)

---

*HydroIQ — Because staying hydrated should be smart, simple, and motivating.*
