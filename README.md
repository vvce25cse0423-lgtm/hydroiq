# 💧 HydroIQ — Smart Hydration & Wellness Tracker

**Developer:** Nitin Mahadev  
**Platform:** Android (Flutter)  
**Version:** 1.0.0

---

## 🌟 Features

### 💧 Hydration Dashboard
- Animated water-fill circle showing daily progress (live wave animation)
- Quick-add buttons: 100ml, 250ml, 500ml, 1L
- Custom amount entry with voice-to-text ("I drank 2 glasses of water")
- **Water sound** plays on every log entry
- **Daily safety limit** of 5L — prevents over-hydration
- Today's log with swipe-to-delete and visible delete buttons
- Clear All logs with confirmation
- Weather-based hydration tips (adjusts goal for hot days)
- Persistent notification in shade: tap +250ml / +500ml anytime — even with app closed

### 👟 Step Counter
- Hardware pedometer (primary) with automatic activity recognition
- **Smart accelerometer fallback** with anti-vibration filter — ignores phone vibrations, drops, and taps; only counts real walking steps using rhythmic cadence detection
- Step count **persists across app restarts** (SharedPreferences)
- **Weekly steps graph** — bar chart showing last 7 days
- Real-time status: Walking / Stopped / Sensor Mode
- Calories burned and distance calculated
- Hydration tip based on step count

### 😴 Sleep Tracker
- Voice trigger: say **"I am going to sleep"** to start tracking
- Voice stop: say **"Good morning"** or **"Wake up"** to stop
- **Sleep state persists** — reopen app and tracking continues from where it left off
- Background monitoring via WorkManager — auto-stops sleep when phone is actively used for 5+ minutes
- Auto-hydration added on wake: poor sleep (<5h) → +500ml, good sleep (7-9h) → +200ml
- Animated moon/stars UI while tracking
- Sleep score (0-100) based on duration
- Recent sessions history

### 🧠 AI Chat
- **Answers ALL questions** — science, math, history, coding, and general knowledge
- Voice input: tap the **mic button** to speak your question, get instant answer
- Hydration and wellness specialization
- Offline fallback knowledge base (works without internet)
- Typing indicator with animated dots
- Quick suggestion chips
- Clear chat button

### 📊 Stats & Analytics
- Weekly hydration bar chart
- 7-day water intake summary
- Current streak tracking
- **Animated achievement badges**:
  - 💧 First Drop (day 1)
  - 🌱 4-Day Explorer (4 days used)
  - 🔥 7-Day Streak
  - ⭐ 14-Day Hero
  - 🏆 30-Day Champion
- **Data updates instantly** when switching from Hydrate tab

### 🔔 Notifications
- **Hourly hydration reminders** every 2 hours (8am–10pm)
- Persistent progress notification in notification shade
- Quick-add buttons (+250ml / +500ml) directly from notification
- Sleep auto-stop notification on wake detection

### 🌦️ Weather Integration
- Live temperature display in app bar
- Automatically adjusts daily water goal based on temperature
- Hot weather alert with extra intake recommendation

### ⚙️ Settings & Profile
- Dark / Light theme toggle
- Custom daily goal
- Profile setup (name, weight, activity level)
- Notification interval settings

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3.24.5 (Dart) |
| State Management | Riverpod 2.x |
| Backend / Auth | Supabase (PostgreSQL + Auth) |
| Local Storage | SharedPreferences, Hive |
| Charts | fl_chart |
| Notifications | flutter_local_notifications + timezone |
| Background Tasks | WorkManager |
| Step Detection | pedometer + sensors_plus |
| Voice Input | speech_to_text |
| Audio | audioplayers |
| Location | geolocator |
| HTTP | http package |
| UI Animations | flutter_animate, AnimationController |
| Fonts | Google Fonts |
| AI | Google Gemini 1.5 Flash + offline fallback |

---

## 🚀 Getting Started

```bash
# Clone the repository
git clone https://github.com/vvce25cse0423-lgtm/hydroiq.git
cd hydroiq

# Install dependencies
flutter pub get

# Run on Android device/emulator
flutter run

# Build release APK
flutter build apk --release --no-tree-shake-icons
```

### Prerequisites
- Flutter 3.24.5+
- Android SDK 35
- Java 17
- Supabase project (update URL and anon key in `lib/core/constants/app_constants.dart`)

---

## 🗄️ Database Schema

See `supabase_schema.sql` for the full Supabase PostgreSQL schema including:
- `users` — profile data
- `hydration_logs` — water intake logs
- `step_logs` — daily step records
- `sleep_logs` — sleep sessions
- `ai_chats` — conversation history
- `settings` — user preferences

---

## 👨‍💻 Developer

**Nitin Mahadev**  
GitHub: [@vvce25cse0423-lgtm](https://github.com/vvce25cse0423-lgtm)

---

*HydroIQ — Because staying hydrated should be smart, simple, and motivating.*
