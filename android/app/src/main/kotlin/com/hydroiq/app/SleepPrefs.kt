package com.hydroiq.app

import android.content.SharedPreferences

/**
 * Single source of truth for sleep SharedPreferences keys.
 * Mirrors the Dart constants in sleep_detection_engine.dart.
 */
object SleepPrefs {
    const val FILE = "FlutterSharedPreferences"   // flutter_shared_prefs default file

    // Keys — must match Dart constants exactly (flutter prefixes them with "flutter.")
    // WorkManager/Dart use raw keys via shared_preferences plugin which stores as:
    // "flutter.<key>" in MODE_PRIVATE file "FlutterSharedPreferences"
    const val KEY_TRACKING    = "flutter.sleep_is_tracking"
    const val KEY_START_MS    = "flutter.sleep_start_ms"
    const val KEY_CONFIDENCE  = "flutter.sleep_confidence"
    const val KEY_INTERRUPTS  = "flutter.sleep_interruptions"
    const val KEY_LAST_MOTION = "flutter.sleep_last_motion_ms"

    // Extra keys written by MainActivity when sleep starts with DND
    const val KEY_DND_ACTIVE  = "flutter.sleep_dnd_was_active"

    fun clearTracking(prefs: SharedPreferences) {
        prefs.edit()
            .remove(KEY_TRACKING)
            .remove(KEY_START_MS)
            .remove(KEY_CONFIDENCE)
            .remove(KEY_INTERRUPTS)
            .remove(KEY_LAST_MOTION)
            .remove(KEY_DND_ACTIVE)
            .apply()
    }
}
