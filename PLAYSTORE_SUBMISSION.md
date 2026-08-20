# HydroIQ — Play Store Submission Guide

## Before You Submit

### 1. Set Up API Keys (Required)
Copy `.env.example` to `.env` and fill in all values:
```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your_supabase_anon_key
WEATHER_API_KEY=your_openweather_key
GEMINI_API_KEY=your_gemini_key
```
Never commit `.env` to git.

### 2. Build Release AAB
```bash
./scripts/build_release.sh
```
Output: `build/app/outputs/bundle/release/app-release.aab`

---

## Health Connect Declaration (MANDATORY — Do First)

1. Go to [Google Play Console](https://play.google.com/console)
2. Select your app → Policy → App Content → Health Connect
3. Fill in the declaration:
   - **Data types read:** Steps, Sleep Session, Sleep Stages
   - **Data types written:** None
   - **Purpose:** Personalised hydration goals based on activity and sleep quality
   - **Privacy policy URL:** https://hydroiq.app/privacy-policy
4. Submit and **wait 2–4 weeks** for approval before publishing

> ⚠️ App will be rejected if you publish before Health Connect approval.

---

## Data Safety Form (Play Console → Policy → Data Safety)

Fill in exactly:

| Data Type | Collected | Shared | Purpose |
|---|---|---|---|
| Email address | Yes | No | Account management |
| Name | Yes | No | Personalisation |
| Health info (steps, sleep, water) | Yes | No | Core app functionality |
| Approximate location | Yes | No | Weather-based hydration advice |
| App activity | Yes | No | Analytics / crash reporting |

- **Is data encrypted in transit?** Yes
- **Can users request deletion?** Yes (Settings → Delete My Account)

---

## Permissions Justification (for review notes)

| Permission | Justification |
|---|---|
| `ACTIVITY_RECOGNITION` | Count steps for hydration goal adjustment |
| `ACCESS_FINE_LOCATION` | Fetch local weather to adjust hydration advice |
| `RECORD_AUDIO` | Voice commands for hands-free water logging |
| `POST_NOTIFICATIONS` | Hydration reminders (user opt-in) |
| `ACCESS_NOTIFICATION_POLICY` | Enable Do Not Disturb during sleep tracking |
| `MODIFY_AUDIO_SETTINGS` | Mute phone during sleep tracking (user opt-in) |
| `FOREGROUND_SERVICE_HEALTH` | Background Health Connect sync |
| `SCHEDULE_EXACT_ALARM` | Timed hydration reminders |

---

## Store Listing Checklist

- [ ] App title: **HydroIQ – Smart Hydration Tracker**
- [ ] Short description (80 chars): *AI-powered water, steps & sleep tracker with Health Connect sync*
- [ ] Full description written
- [ ] Privacy policy URL added: `https://hydroiq.app/privacy-policy`
- [ ] Screenshots: phone (min 2), tablet optional
- [ ] Feature graphic: 1024 × 500px
- [ ] App icon: 512 × 512px (already in assets)
- [ ] Content rating questionnaire completed
- [ ] Target audience: 13+

---

## Supabase — Required Before Launch

Add this SQL function to handle auth account deletion via DB trigger
(since client SDK cannot delete auth users):

```sql
-- In Supabase SQL Editor
CREATE OR REPLACE FUNCTION delete_user()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  DELETE FROM auth.users WHERE id = auth.uid();
END;
$$;

GRANT EXECUTE ON FUNCTION delete_user() TO authenticated;
```

Then update `deleteAccount()` in `supabase_service.dart` to also call:
```dart
await _client.rpc('delete_user');
```

---

## Pre-Launch Report

Before public release, upload to **Internal Testing** track first.
Go to: Play Console → Testing → Internal Testing → Run pre-launch report.
Fix any crashes shown before moving to production.
