package com.example.testsign

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import org.json.JSONObject

/** Dated alarms are SignBridge notifications, not undated clock-app alarms. */
class DatedAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val prefs = context.getSharedPreferences("dated_alarms", Context.MODE_PRIVATE)
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_TIME_CHANGED ||
            intent.action == Intent.ACTION_TIMEZONE_CHANGED) {
            for ((key, value) in prefs.all) {
                if (key == "next_id") continue
                try {
                    val time = timestamp(JSONObject(value as String))
                    if (time > System.currentTimeMillis()) schedule(context, key.toInt(), time)
                    else prefs.edit().remove(key).apply()
                } catch (_: Exception) { /* Keep entries if alarm access was revoked. */ }
            }
            return
        }
        val id = intent.getIntExtra("id", -1)
        val saved = prefs.getString(id.toString(), null) ?: return
        val alarm = JSONObject(saved)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannel(context)
        val open = PendingIntent.getActivity(context, id, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL)
            else Notification.Builder(context).setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM))
                .setVibrate(longArrayOf(0, 500, 300, 500)).setPriority(Notification.PRIORITY_HIGH)
        val notification = builder.setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("SignBridge 알람")
            .setContentText(alarm.optString("label", "").ifBlank { "설정한 알람 시각입니다." })
            .setCategory(Notification.CATEGORY_ALARM).setContentIntent(open).setAutoCancel(true).build()
        try { manager.notify(id, notification) }
        catch (_: SecurityException) { /* Access may be revoked after scheduling. */ }
        prefs.edit().remove(id.toString()).apply()
    }

    companion object {
        const val CHANNEL = "signbridge_dated_alarms"

        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= 26) {
                val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val channel = NotificationChannel(CHANNEL, "날짜 지정 알람", NotificationManager.IMPORTANCE_HIGH)
                channel.description = "날짜와 시각을 지정한 SignBridge 알람"
                channel.enableVibration(true)
                channel.vibrationPattern = longArrayOf(0, 500, 300, 500)
                channel.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
                    AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build())
                manager.createNotificationChannel(channel)
            }
        }

        fun timestamp(data: JSONObject): Long {
            val value = data.getString("date")
            require(Regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$").matches(value)) { "날짜 형식을 확인해 주세요." }
            val parts = value.split("-").map { it.toInt() }
            val hour = data.get("hour")
            val minute = data.get("minute")
            require(hour is Int && hour in 0..23 && minute is Int && minute in 0..59)
            val calendar = java.util.Calendar.getInstance()
            calendar.isLenient = false
            calendar.clear()
            calendar.set(parts[0], parts[1] - 1, parts[2], hour as Int, minute as Int, 0)
            return calendar.timeInMillis
        }

        fun schedule(context: Context, id: Int, time: Long) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val fire = PendingIntent.getBroadcast(context, id,
                Intent(context, DatedAlarmReceiver::class.java).putExtra("id", id),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val show = PendingIntent.getActivity(context, id, Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            alarmManager.setAlarmClock(AlarmManager.AlarmClockInfo(time, show), fire)
        }
    }
}
