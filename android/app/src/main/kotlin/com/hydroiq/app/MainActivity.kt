package com.hydroiq.app

import android.content.Context
import android.media.AudioManager
import android.os.Bundle
import android.util.Log
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
    }

    private val scope = CoroutineScope(Dispatchers.Main)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Schedule background sync on every app open
        HealthSyncWorker.schedule(this)
        // Trigger immediate sync
        HealthSyncWorker.scheduleImmediateSync(this)
        Log.d(TAG, "WorkManager sync scheduled")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Volume channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOLUME_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "isMuted") {
                    val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val muted = audio.ringerMode == AudioManager.RINGER_MODE_SILENT ||
                                audio.ringerMode == AudioManager.RINGER_MODE_VIBRATE
                    result.success(muted)
                } else result.notImplemented()
            }

        // Health Connect channel — Flutter can trigger sync and read results
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
    }
}
