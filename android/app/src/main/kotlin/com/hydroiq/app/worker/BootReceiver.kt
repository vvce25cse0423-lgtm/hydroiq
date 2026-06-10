package com.hydroiq.app.worker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "HydroIQ_Boot"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            action == "android.intent.action.QUICKBOOT_POWERON") {
            Log.d(TAG, "Boot/restart detected — rescheduling sync")
            HealthSyncWorker.schedule(context)
            // Immediate sync after boot
            HealthSyncWorker.scheduleImmediateSync(context)
        }
    }
}
