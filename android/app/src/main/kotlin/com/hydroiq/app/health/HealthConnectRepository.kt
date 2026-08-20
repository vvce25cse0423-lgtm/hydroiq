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

data class SleepSessionData(
    val startMs: Long,
    val endMs: Long,
    val durationMinutes: Long,
    val stages: List<String> = emptyList()
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
            val status = HealthConnectClient.getSdkStatus(
                context, "com.google.android.apps.healthdata")
            if (status == HealthConnectClient.SDK_AVAILABLE) {
                HealthConnectClient.getOrCreate(context)
            } else {
                Log.w(TAG, "HC SDK not available: $status"); null
            }
        } catch (e: Exception) {
            Log.e(TAG, "HC init failed", e); null
        }
    }

    suspend fun isAvailable(): Boolean = withContext(Dispatchers.IO) {
        try {
            HealthConnectClient.getSdkStatus(
                context, "com.google.android.apps.healthdata"
            ) == HealthConnectClient.SDK_AVAILABLE
        } catch (_: Exception) { false }
    }

    suspend fun hasPermissions(): Boolean = withContext(Dispatchers.IO) {
        try {
            val granted = client?.permissionController?.getGrantedPermissions()
                ?: return@withContext false
            granted.containsAll(PERMISSIONS)
        } catch (_: Exception) { false }
    }

    suspend fun getTodaySteps(): Long = withContext(Dispatchers.IO) {
        try {
            val c    = client ?: return@withContext 0L
            val zone = ZoneId.systemDefault()
            val now  = Instant.now()
            val startOfDay = LocalDate.now(zone).atStartOfDay(zone).toInstant()
            val resp = c.aggregate(AggregateRequest(
                metrics = setOf(StepsRecord.COUNT_TOTAL),
                timeRangeFilter = TimeRangeFilter.between(startOfDay, now)
            ))
            resp[StepsRecord.COUNT_TOTAL] ?: 0L
        } catch (e: Exception) {
            Log.e(TAG, "getTodaySteps failed", e); 0L
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

    /**
     * Returns last-night sleep — longest session in past 24h.
     * Used by the WorkManager widget sync.
     */
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
            Log.e(TAG, "getSleep failed", e); Pair(0.0, 0)
        }
    }

    /**
     * Returns full sessions for last N days — used for history + dedup.
     */
    suspend fun getRecentSleepSessions(days: Int = 14): List<SleepSessionData> =
        withContext(Dispatchers.IO) {
            try {
                val c   = client ?: return@withContext emptyList()
                val now = Instant.now()
                val s   = now.minusSeconds(days * 86400L)
                val resp = c.readRecords(ReadRecordsRequest(
                    recordType = SleepSessionRecord::class,
                    timeRangeFilter = TimeRangeFilter.between(s, now),
                    pageSize = 50,
                ))
                resp.records
                    .filter { it.endTime.epochSecond - it.startTime.epochSecond > 1800 }
                    .sortedByDescending { it.startTime }
                    .map { rec ->
                        SleepSessionData(
                            startMs = rec.startTime.toEpochMilli(),
                            endMs   = rec.endTime.toEpochMilli(),
                            durationMinutes =
                                (rec.endTime.epochSecond - rec.startTime.epochSecond) / 60,
                            stages  = rec.stages.map { it.stage.toString() }
                        )
                    }
            } catch (e: Exception) {
                Log.e(TAG, "getRecentSleep failed", e); emptyList()
            }
        }

    suspend fun fetchHealthData(): HealthData = withContext(Dispatchers.IO) {
        if (!isAvailable()) return@withContext HealthData(error = "HC unavailable")
        if (!hasPermissions()) return@withContext HealthData(error = "No permissions")
        val steps  = getTodaySteps()
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

    /**
     * Returns today's steps bucketed by hour (0–23).
     * Queries Health Connect for each completed hour bucket for accuracy.
     */
    suspend fun getTodayHourlySteps(): Map<Int, Long> = withContext(Dispatchers.IO) {
        val c      = client ?: return@withContext emptyMap()
        val zone   = ZoneId.systemDefault()
        val today  = LocalDate.now(zone)
        val result = mutableMapOf<Int, Long>()
        val currentHour = java.time.LocalTime.now(zone).hour

        for (h in 0..currentHour) {
            try {
                val start = today.atTime(h, 0).atZone(zone).toInstant()
                val end   = today.atTime(h, 59, 59).atZone(zone).toInstant()
                val resp  = c.aggregate(AggregateRequest(
                    metrics         = setOf(StepsRecord.COUNT_TOTAL),
                    timeRangeFilter = TimeRangeFilter.between(start, end)
                ))
                result[h] = resp[StepsRecord.COUNT_TOTAL] ?: 0L
            } catch (_: Exception) {
                result[h] = 0L
            }
        }
        result
    }
}
