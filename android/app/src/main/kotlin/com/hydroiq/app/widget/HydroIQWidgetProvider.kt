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

        // Read current ml (stored either as string or int)
        val currentStr = prefs.getString("current_ml", "0")?.replace(",", "") ?: "0"
        val currentMl = currentStr.toIntOrNull() ?: 0

        val goalStr = prefs.getString("goal_ml", "2,000")?.replace(",", "") ?: "2000"
        val goalMl = goalStr.toIntOrNull() ?: 2000

        val newTotal = currentMl + amount
        val pct = if (goalMl > 0) ((newTotal.toFloat() / goalMl.toFloat()) * 100).toInt().coerceIn(0, 100) else 0

        val formattedCurrent = String.format("%,d", newTotal)
        val formattedGoal = String.format("%,d", goalMl)
        val statusText = if (newTotal >= goalMl) "🎉 Daily goal achieved!" else "💧 ${String.format("%,d", goalMl - newTotal)} ml left today"

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
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.hydroiq_widget).apply {
                val currentMl = widgetData.getString("current_ml", "0") ?: "0"
                val goalMl = widgetData.getString("goal_ml", "2,000") ?: "2,000"
                val progress = widgetData.getInt("progress", 0)
                val percentage = widgetData.getString("percentage", "0%") ?: "0%"
                val statusText = widgetData.getString("status_text", "Daily Hydration Goal") ?: "Daily Hydration Goal"
                val stepsText = widgetData.getString("steps_text", "0 steps") ?: "0 steps"
                val sleepText = widgetData.getString("sleep_text", "-- hrs") ?: "-- hrs"

                setTextViewText(R.id.widget_current_ml, "$currentMl ml")
                setTextViewText(R.id.widget_goal_ml, "/ $goalMl ml")
                setTextViewText(R.id.widget_percentage, percentage)
                setTextViewText(R.id.widget_status, statusText)
                setProgressBar(R.id.widget_progress_bar, 100, progress, false)
                setTextViewText(R.id.widget_steps_val, stepsText)
                setTextViewText(R.id.widget_sleep_val, sleepText)

                // Quick add +250ml explicit PendingIntent
                val flags = if (Build.VERSION.SDK_INT >= 23) {
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }

                val intent250 = Intent(context, HydroIQWidgetProvider::class.java).apply {
                    action = ACTION_ADD_WATER
                    putExtra(EXTRA_AMOUNT, 250)
                }
                val pIntent250 = PendingIntent.getBroadcast(context, 250, intent250, flags)
                setOnClickPendingIntent(R.id.btn_add_250, pIntent250)

                // Quick add +500ml explicit PendingIntent
                val intent500 = Intent(context, HydroIQWidgetProvider::class.java).apply {
                    action = ACTION_ADD_WATER
                    putExtra(EXTRA_AMOUNT, 500)
                }
                val pIntent500 = PendingIntent.getBroadcast(context, 500, intent500, flags)
                setOnClickPendingIntent(R.id.btn_add_500, pIntent500)

                // Tapping header area or open button launches MainActivity
                val openAppIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("hydroiq://open")
                )
                setOnClickPendingIntent(R.id.widget_header_area, openAppIntent)
                setOnClickPendingIntent(R.id.btn_open_app, openAppIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
