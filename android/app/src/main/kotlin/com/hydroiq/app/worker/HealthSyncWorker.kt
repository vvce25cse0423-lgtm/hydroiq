package com.hydroiq.app.worker

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.work.*
import com.hydroiq.app.health.HealthConnectRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.util.concurrent.TimeUnit

class HealthSyncWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    companion object {
        private const val TAG            = "HydroIQ_SyncWorker"
        private const val WORK_NAME      = "hydroiq_health_sync"
        private const val PREFS_NAME     = "FlutterSharedPreferences"

        fun schedule(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.NOT_REQUIRED)
                .build()

            val periodic = PeriodicWorkRequestBuilder<HealthSyncWorker>(
                15, TimeUnit.MINUTES,
                5, TimeUnit.MINUTES
            )
                .setConstraints(constraints)
                .setBackoffCriteria(BackoffPolicy.LINEAR, 5, TimeUnit.MINUTES)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                periodic
            )

            Log.d(TAG, "Periodic sync scheduled")
        }

        fun scheduleImmediateSync(context: Context) {
            val request = OneTimeWorkRequestBuilder<HealthSyncWorker>()
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .build()
            WorkManager.getInstance(context).enqueue(request)
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        }
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        Log.d(TAG, "HealthSyncWorker started")
        try {
            val repo  = HealthConnectRepository(applicationContext)
            val prefs: SharedPreferences = applicationContext
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            // Check for day change and reset if needed
            val today    = LocalDate.now().toString()
            val lastDate = prefs.getString("flutter.last_sync_date", "") ?: ""
            if (lastDate != today) {
                Log.d(TAG, "New day detected: $today — resetting step counter")
                prefs.edit()
                    .putString("flutter.last_sync_date", today)
                    .putInt("flutter.widget_steps", 0)
                    .apply()
            }

            // Fetch Health Connect data
            val health = repo.fetchHealthData()
            if (health.error != null) {
                Log.w(TAG, "HC error: ${health.error}")
                return@withContext Result.retry()
            }

            Log.d(TAG, "Synced: steps=${health.steps}, sleep=${health.sleepHours}h${health.sleepMinutes}m")

            val editor = prefs.edit()

            // Save today's steps + meta
            editor.putFloat("flutter.widget_water_ml",
                    prefs.getFloat("flutter.widget_water_ml", 0f))
                .putFloat("flutter.widget_goal_ml",
                    prefs.getFloat("flutter.widget_goal_ml", 2500f))
                .putInt("flutter.widget_steps", health.steps.toInt())
                .putLong("flutter.last_sync_ms", System.currentTimeMillis())

            // Persist weekly step history for streak + chart continuity
            try {
                val weekly = repo.getWeeklySteps()
                for ((date, count) in weekly) {
                    val key = "flutter.steps_${date.year}_${date.monthValue}_${date.dayOfMonth}"
                    val existing = prefs.getInt(key, 0)
                    // Only overwrite if HC reports a higher (more authoritative) value
                    if (count.toInt() > existing) {
                        editor.putInt(key, count.toInt())
                    }
                }
                Log.d(TAG, "Weekly step history saved (${weekly.size} days)")
            } catch (e: Exception) {
                Log.w(TAG, "Weekly steps sync skipped: ${e.message}")
            }

            editor.apply()
            Log.d(TAG, "Sync complete")
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Sync failed", e)
            Result.retry()
        }
    }
}
