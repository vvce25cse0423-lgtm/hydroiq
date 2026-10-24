package com.hydroiq.app.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import com.hydroiq.app.MainActivity
import com.hydroiq.app.R
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class HydroIQWidgetProvider : HomeWidgetProvider() {

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

                setTextViewText(R.id.widget_current_ml, "$currentMl ml")
                setTextViewText(R.id.widget_goal_ml, "/ $goalMl ml")
                setTextViewText(R.id.widget_percentage, percentage)
                setTextViewText(R.id.widget_status, statusText)
                setProgressBar(R.id.widget_progress_bar, 100, progress, false)

                // Quick add +250ml background tap intent
                val add250Intent = HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    Uri.parse("hydroiq://add?amount=250")
                )
                setOnClickPendingIntent(R.id.btn_add_250, add250Intent)

                // Quick add +500ml background tap intent
                val add500Intent = HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    Uri.parse("hydroiq://add?amount=500")
                )
                setOnClickPendingIntent(R.id.btn_add_500, add500Intent)

                // Tapping header or container launches MainActivity
                val openAppIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("hydroiq://open")
                )
                setOnClickPendingIntent(R.id.widget_container, openAppIntent)
                setOnClickPendingIntent(R.id.btn_open_app, openAppIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
