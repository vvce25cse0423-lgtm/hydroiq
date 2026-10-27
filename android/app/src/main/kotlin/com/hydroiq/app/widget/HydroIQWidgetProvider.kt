package com.hydroiq.app.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews
import com.hydroiq.app.MainActivity
import com.hydroiq.app.R
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class HydroIQWidgetProvider : HomeWidgetProvider() {

    companion object {
        const val ACTION_ADD_WATER = "com.hydroiq.app.widget.ACTION_ADD_WATER"
        const val EXTRA_AMOUNT = "extra_amount"
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        if (intent.action == ACTION_ADD_WATER) {
            val amount = intent.getIntExtra(EXTRA_AMOUNT, 250)
            handleQuickAdd(context, amount)
        }
    }

    private fun handleQuickAdd(context: Context, amount: Int) {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)

        // Read current ml
        val currentStr = prefs.getString("current_ml", "0")?.replace(",", "") ?: "0"
        val currentMl = currentStr.toIntOrNull() ?: 0

        val goalStr = prefs.getString("goal_ml", "5,000")?.replace(",", "") ?: "5000"
        val goalMl = goalStr.toIntOrNull() ?: 5000

        val newTotal = currentMl + amount
        val pct = if (goalMl > 0) ((newTotal.toFloat() / goalMl.toFloat()) * 100).toInt().coerceIn(0, 100) else 0

        val formattedCurrent = String.format("%,d", newTotal)
        val formattedGoal = String.format("%,d", goalMl)
        val statusText = if (newTotal >= goalMl) {
            "🎉 Daily goal achieved!"
        } else {
            "Keep Going! ${String.format("%,d", goalMl - newTotal)} ml left ✨"
        }

        // Update preferences
        prefs.edit()
            .putString("current_ml", formattedCurrent)
            .putString("goal_ml", formattedGoal)
            .putInt("progress", pct)
            .putString("percentage", "$pct%")
            .putString("status_text", statusText)
            .apply()

        // Also track pending addition for Flutter app synchronization
        val appPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val pendingKey = "flutter.pending_widget_added_ml"
        val currentPending = appPrefs.getLong(pendingKey, 0L)
        appPrefs.edit().putLong(pendingKey, currentPending + amount).apply()

        // Immediately update all widget instances on home screen
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val widgetIds = appWidgetManager.getAppWidgetIds(ComponentName(context, HydroIQWidgetProvider::class.java))
        onUpdate(context, appWidgetManager, widgetIds, prefs)

        // Forward to HomeWidgetBackgroundReceiver to notify Dart background engine
        try {
            val bgIntent = Intent(context, HomeWidgetBackgroundReceiver::class.java).apply {
                action = "es.antonborri.home_widget.action.BACKGROUND"
                data = Uri.parse("hydroiq://add?amount=$amount")
            }
            context.sendBroadcast(bgIntent)
        } catch (_: Exception) {}
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val flags = if (Build.VERSION.SDK_INT >= 23) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        appWidgetIds.forEach { widgetId ->
            try {
                val views = RemoteViews(context.packageName, R.layout.hydroiq_widget).apply {
                    val currentMl = widgetData.getString("current_ml", "0") ?: "0"
                    val goalMl = widgetData.getString("goal_ml", "5,000") ?: "5,000"
                    val progress = widgetData.getInt("progress", 0)
                    val percentage = widgetData.getString("percentage", "0%") ?: "0%"
                    val statusText = widgetData.getString("status_text", "Keep Going! You're doing great ✨") ?: "Keep Going! You're doing great ✨"
                    val stepsText = widgetData.getString("steps_text", "0 steps") ?: "0 steps"
                    val stepsSubText = widgetData.getString("steps_sub_text", "0 kcal • 0 km") ?: "0 kcal • 0 km"
                    val sleepText = widgetData.getString("sleep_text", "Sleep: -- hrs") ?: "Sleep: -- hrs"
                    val sleepQuality = widgetData.getString("sleep_quality", "Good Rest") ?: "Good Rest"
                    val weatherTemp = widgetData.getString("weather_temp", "28°C") ?: "28°C"
                    val weatherCond = widgetData.getString("weather_cond", "Partly Cloudy") ?: "Partly Cloudy"

                    setTextViewText(R.id.widget_percentage, percentage)
                    setTextViewText(R.id.widget_current_ml, "$currentMl ml")
                    setTextViewText(R.id.widget_goal_ml, "of $goalMl ml")
                    setTextViewText(R.id.widget_status, statusText)
                    setTextViewText(R.id.widget_limit_val, "$goalMl ml")
                    setTextViewText(R.id.widget_weather_temp, weatherTemp)
                    setTextViewText(R.id.widget_weather_cond, weatherCond)
                    setTextViewText(R.id.widget_steps_val, stepsText)
                    setTextViewText(R.id.widget_steps_sub, stepsSubText)
                    setTextViewText(R.id.widget_sleep_val, sleepText)
                    setTextViewText(R.id.widget_sleep_quality, sleepQuality)

                    // Helper to create add-water PendingIntent
                    fun createAddIntent(amount: Int): PendingIntent {
                        val intent = Intent(context, HydroIQWidgetProvider::class.java).apply {
                            action = ACTION_ADD_WATER
                            putExtra(EXTRA_AMOUNT, amount)
                        }
                        return PendingIntent.getBroadcast(context, amount, intent, flags)
                    }

                    // Wire Quick-Add Buttons (100ml, 250ml, 500ml, 1000ml)
                    setOnClickPendingIntent(R.id.btn_add_100, createAddIntent(100))
                    setOnClickPendingIntent(R.id.btn_add_250, createAddIntent(250))
                    setOnClickPendingIntent(R.id.btn_add_500, createAddIntent(500))
                    setOnClickPendingIntent(R.id.btn_add_1000, createAddIntent(1000))

                    // Wire Bottom Quick Action Pills (+250ml, +500ml)
                    setOnClickPendingIntent(R.id.btn_quick_add_250, createAddIntent(250))
                    setOnClickPendingIntent(R.id.btn_quick_add_500, createAddIntent(500))

                    // Helper to create Deep Link Launch Intent into Flutter App
                    fun createLaunchIntent(uriStr: String): PendingIntent {
                        return HomeWidgetLaunchIntent.getActivity(
                            context,
                            MainActivity::class.java,
                            Uri.parse(uriStr)
                        )
                    }

                    // Header & Gauge launch Hydration Dashboard
                    val openDashboard = createLaunchIntent("hydroiq://open")
                    setOnClickPendingIntent(R.id.widget_header_area, openDashboard)
                    setOnClickPendingIntent(R.id.widget_gauge_area, openDashboard)
                    setOnClickPendingIntent(R.id.nav_hydration, openDashboard)

                    // Weather card launches Weather screen
                    setOnClickPendingIntent(R.id.widget_weather_card, createLaunchIntent("hydroiq://weather"))

                    // Voice trigger launches Voice Input
                    setOnClickPendingIntent(R.id.btn_voice_input, createLaunchIntent("hydroiq://voice"))

                    // Steps card & nav launch Steps tab
                    val openSteps = createLaunchIntent("hydroiq://steps")
                    setOnClickPendingIntent(R.id.card_steps, openSteps)
                    setOnClickPendingIntent(R.id.nav_steps, openSteps)

                    // Sleep card & nav launch Sleep tab
                    val openSleep = createLaunchIntent("hydroiq://sleep")
                    setOnClickPendingIntent(R.id.card_sleep, openSleep)
                    setOnClickPendingIntent(R.id.nav_sleep, openSleep)

                    // AI Assistant card launches AI chat tab
                    setOnClickPendingIntent(R.id.card_ai, createLaunchIntent("hydroiq://ai"))

                    // Stats nav launches Analytics tab
                    setOnClickPendingIntent(R.id.nav_stats, createLaunchIntent("hydroiq://stats"))

                    // Badges nav launches Challenges/Badges
                    setOnClickPendingIntent(R.id.nav_badges, createLaunchIntent("hydroiq://badges"))

                    // Settings nav launches Settings screen
                    setOnClickPendingIntent(R.id.nav_settings, createLaunchIntent("hydroiq://settings"))
                }
                appWidgetManager.updateAppWidget(widgetId, views)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
}
