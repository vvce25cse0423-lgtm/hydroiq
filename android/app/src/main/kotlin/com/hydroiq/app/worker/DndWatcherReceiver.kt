package com.hydroiq.app.worker

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import com.hydroiq.app.SleepPrefs

class DndWatcherReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "HydroIQ_DndWatcher"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != NotificationManager.ACTION_INTERRUPTION_FILTER_CHANGED) return

        val prefs = context.getSharedPreferences(SleepPrefs.FILE, Context.MODE_PRIVATE)
        val isTracking  = prefs.getBoolean(SleepPrefs.KEY_TRACKING, false)
        val dndEnabled  = prefs.getBoolean(SleepPrefs.KEY_DND_ACTIVE, false)

        if (!isTracking || !dndEnabled) return

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val currentlyDND = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            nm.currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_NONE ||
            nm.currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_PRIORITY
        } else false

        Log.d(TAG, "DND filter changed → isDND=$currentlyDND tracking=$isTracking dndActive=$dndEnabled")

        // DND was ON (we enabled it) and is now OFF → user disabled externally → stop sleep
        if (!currentlyDND) {
            Log.d(TAG, "DND disabled externally — stopping sleep tracking")
            SleepPrefs.clearTracking(prefs)
            SleepStopHelper.stopAndNotify(context,
                "☀️ DND turned off — sleep tracking stopped automatically.")
        }
    }
}
