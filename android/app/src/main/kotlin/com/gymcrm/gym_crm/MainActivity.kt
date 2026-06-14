package com.gymcrm.gym_crm

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        SmsPlugin.register(this, flutterEngine)
        // Re-schedule native worker on every launch so it survives app updates.
        val prefs = applicationContext.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        if (prefs.getBoolean("flutter.sms_reminders_enabled", false)) {
            SmsPlugin.scheduleNativeWorker(applicationContext)
        }
    }
}
