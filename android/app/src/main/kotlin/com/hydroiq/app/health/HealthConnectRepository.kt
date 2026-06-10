package com.hydroiq.app.health

import android.content.Context
import android.util.Log
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class HealthData(
    val steps: Long = 0L,
    val sleepHours: Double = 0.0,
    val sleepMinutes: Int = 0,
    val lastSyncTime: Long = System.currentTimeMillis(),
    val error: String? = null
)

class HealthConnectRepository(private val context: Context) {

    companion object {
        private const val TAG = "HydroIQ_HC"
        val PERMISSIONS = setOf(
            HealthPermission.getReadPermission(StepsRecord::class),
            HealthPermission.getReadPermission(SleepSessionRecord::class),
        )
    }

    private val client: HealthConnectClient? by lazy {
        try {
            val status = HealthConnectClient.getSdkStatus(context, "com.google.android.apps.healthdata")
            if (status == HealthConnectClient.SDK_AVAILABLE) {
                HealthConnectClient.getOrCreate(context)
            } else {
                Log.w(TAG, "HC SDK not available: $status")
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "HC init failed", e)
            null
        }
    }

    suspend fun isAvailable(): Boolean = withContext(Dispatchers.IO) {
        try {
            HealthConnectClient.getSdkStatus(context, "com.google.android.apps.healthdata") ==
                HealthConnectClient.SDK_AVAILABLE
        } catch (_: Exception) { false }
    }

    suspend fun hasPermissions(): Boolean = withContext(Dispatchers.IO) {
        try {
            val granted = client?.permissionController?.getGrantedPermissions() ?: return@withContext false
            granted.containsAll(PERMISSIONS)
        } catch (_: Exception) { false }
    }

    suspend fun getTodaySteps(): Long = withContext(Dispatchers.IO) {
        try {
            val c    = client ?: return@withContext 0L
            val zone = ZoneId.systemDefault()
            val now  = Instant.now()
            val startOfDay = LocalDate.now(zone).atStartOfDay(zone).toInstant()

            val response = c.aggregate(
                AggregateRequest(
                    metrics = setOf(StepsRecord.COUNT_TOTAL),
                    timeRangeFilter = TimeRangeFilter.between(startOfDay, now)
                )
            )
            val steps = response[StepsRecord.COUNT_TOTAL] ?: 0L
            Log.d(TAG, "Today steps: $steps (${startOfDay} -> $now)")
            steps
        } catch (e: Exception) {
            Log.e(TAG, "getTodaySteps failed", e)
            0L
        }
    }

    suspend fun getStepsForDate(date: LocalDate): Long = withContext(Dispatchers.IO) {
        try {
            val c    = client ?: return@withContext 0L
            val zone = ZoneId.systemDefault()
            val s    = date.atStartOfDay(zone).toInstant()
            val e    = date.plusDays(1).atStartOfDay(zone).toInstant()
            val resp = c.aggregate(AggregateRequest(
                metrics = setOf(StepsRecord.COUNT_TOTAL),
                timeRangeFilter = TimeRangeFilter.between(s, e)
            ))
            resp[StepsRecord.COUNT_TOTAL] ?: 0L
        } catch (_: Exception) { 0L }
    }

    suspend fun getLastNightSleep(): Pair<Double, Int> = withContext(Dispatchers.IO) {
        try {
            val c   = client ?: return@withContext Pair(0.0, 0)
            val now = Instant.now()
            val s   = now.minusSeconds(86400)
            val resp = c.readRecords(ReadRecordsRequest(
                recordType = SleepSessionRecord::class,
                timeRangeFilter = TimeRangeFilter.between(s, now),
                pageSize = 10,
            ))
            if (resp.records.isEmpty()) return@withContext Pair(0.0, 0)
            val longest = resp.records.maxByOrNull {
                it.endTime.epochSecond - it.startTime.epochSecond
            } ?: return@withContext Pair(0.0, 0)
            val mins = (longest.endTime.epochSecond - longest.startTime.epochSecond) / 60
            Pair((mins / 60).toDouble(), (mins % 60).toInt())
        } catch (e: Exception) {
            Log.e(TAG, "getSleep failed", e)
            Pair(0.0, 0)
        }
    }

    suspend fun fetchHealthData(): HealthData = withContext(Dispatchers.IO) {
        if (!isAvailable()) return@withContext HealthData(error = "HC unavailable")
        if (!hasPermissions()) return@withContext HealthData(error = "No permissions")
        val steps = getTodaySteps()
        val (h, m) = getLastNightSleep()
        HealthData(steps = steps, sleepHours = h, sleepMinutes = m,
            lastSyncTime = System.currentTimeMillis())
    }

    suspend fun getWeeklySteps(): Map<LocalDate, Long> = withContext(Dispatchers.IO) {
        val result = mutableMapOf<LocalDate, Long>()
        val today  = LocalDate.now()
        for (i in 6 downTo 0) {
            val date = today.minusDays(i.toLong())
            result[date] = getStepsForDate(date)
        }
        result
    }
}
