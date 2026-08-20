package com.hydroiq.app

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import com.hydroiq.app.worker.BootReceiver
import com.hydroiq.app.worker.DndWatcherReceiver
import com.hydroiq.app.worker.HealthSyncWorker
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG            = "HydroIQ_Main"
        private const val VOLUME_CHANNEL = "com.hydroiq.app/volume"
        private const val HC_CHANNEL     = "com.hydroiq.app/healthconnect"
        private const val SLEEP_CHANNEL  = "com.hydroiq.app/sleep_controls"
    }

    private val scope = CoroutineScope(Dispatchers.Main)
    private val dndReceiver = DndWatcherReceiver()
    private var dndReceiverRegistered = false

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        HealthSyncWorker.schedule(this)
        HealthSyncWorker.scheduleImmediateSync(this)
        Log.d(TAG, "WorkManager sync scheduled")
    }

    override fun onResume() {
        super.onResume()
        // Register dynamic DND receiver when app is in foreground
        // (The static manifest receiver handles background)
        if (!dndReceiverRegistered) {
            val filter = IntentFilter(NotificationManager.ACTION_INTERRUPTION_FILTER_CHANGED)
            registerReceiver(dndReceiver, filter)
            dndReceiverRegistered = true
        }
    }

    override fun onPause() {
        super.onPause()
        // Unregister dynamic receiver — static manifest receiver takes over in background
        if (dndReceiverRegistered) {
            unregisterReceiver(dndReceiver)
            dndReceiverRegistered = false
        }
    }

    // ── Flutter Engine ────────────────────────────────────────────────────────

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Volume channel ────────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOLUME_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "isMuted") {
                    val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val muted = audio.ringerMode == AudioManager.RINGER_MODE_SILENT ||
                                audio.ringerMode == AudioManager.RINGER_MODE_VIBRATE
                    result.success(muted)
                } else result.notImplemented()
            }

        // ── Health Connect channel ────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HC_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "syncNow" -> {
                        HealthSyncWorker.scheduleImmediateSync(this)
                        result.success("syncing")
                    }
                    "getSteps" -> {
                        scope.launch {
                            try {
                                val repo  = com.hydroiq.app.health.HealthConnectRepository(applicationContext)
                                val steps = repo.getTodaySteps()
                                result.success(steps)
                            } catch (e: Exception) {
                                result.error("HC_ERROR", e.message, null)
                            }
                        }
                    }
                    "getWeeklySteps" -> {
                        scope.launch {
                            try {
                                val repo  = com.hydroiq.app.health.HealthConnectRepository(applicationContext)
                                val weekly = repo.getWeeklySteps()
                                val mapped = weekly.entries.associate {
                                    "${it.key.year}_${it.key.monthValue}_${it.key.dayOfMonth}" to it.value
                                }
                                result.success(mapped)
                            } catch (e: Exception) {
                                result.error("HC_ERROR", e.message, null)
                            }
                        }
                    }
                    "getHourlySteps" -> {
                        scope.launch {
                            try {
                                val repo   = com.hydroiq.app.health.HealthConnectRepository(applicationContext)
                                val hourly = repo.getTodayHourlySteps()
                                result.success(hourly)
                            } catch (e: Exception) {
                                result.error("HC_ERROR", e.message, null)
                            }
                        }
                    }
                    "getSleep" -> {
                        scope.launch {
                            try {
                                val repo            = com.hydroiq.app.health.HealthConnectRepository(applicationContext)
                                val (hours, minutes)= repo.getLastNightSleep()
                                result.success(mapOf("hours" to hours, "minutes" to minutes))
                            } catch (e: Exception) {
                                result.error("HC_ERROR", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Sleep controls channel ────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SLEEP_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "enableDND" -> {
                        try {
                            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                if (nm.isNotificationPolicyAccessGranted) {
                                    nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_NONE)
                                    // ── Persist flag so background receiver knows DND was our doing ──
                                    applicationContext
                                        .getSharedPreferences(SleepPrefs.FILE, Context.MODE_PRIVATE)
                                        .edit()
                                        .putBoolean(SleepPrefs.KEY_DND_ACTIVE, true)
                                        .apply()
                                    result.success(true)
                                } else {
                                    result.success(false)
                                }
                            } else {
                                result.success(false)
                            }
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }

                    "disableDND" -> {
                        try {
                            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                if (nm.isNotificationPolicyAccessGranted) {
                                    nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)
                                }
                            }
                            // Clear the flag — we disabled it ourselves (not external trigger)
                            applicationContext
                                .getSharedPreferences(SleepPrefs.FILE, Context.MODE_PRIVATE)
                                .edit()
                                .remove(SleepPrefs.KEY_DND_ACTIVE)
                                .apply()
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }

                    "muteAudio" -> {
                        try {
                            val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            audio.ringerMode = AudioManager.RINGER_MODE_SILENT
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }

                    "unmuteAudio" -> {
                        try {
                            val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            audio.ringerMode = AudioManager.RINGER_MODE_NORMAL
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }

                    "openDNDSettings" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }

                    "isDNDEnabled" -> {
                        try {
                            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            val enabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                nm.currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_NONE ||
                                nm.currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_PRIORITY
                            } else false
                            result.success(enabled)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }

                    "hasDNDPermission" -> {
                        try {
                            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            result.success(
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                                    nm.isNotificationPolicyAccessGranted
                                else true
                            )
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
