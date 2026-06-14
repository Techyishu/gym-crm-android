package com.gymcrm.gym_crm

import android.content.Context
import android.os.Build
import android.telephony.SmsManager
import android.util.Log
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit

object SmsPlugin {
    private const val CHANNEL = "com.gymcrm/sms"

    fun register(activity: FlutterActivity, flutterEngine: FlutterEngine) {
        val appContext = activity.applicationContext
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sendSms" -> {
                        val to = call.argument<String>("to")
                            ?: return@setMethodCallHandler result.error("INVALID", "Missing 'to'", null)
                        val message = call.argument<String>("message")
                            ?: return@setMethodCallHandler result.error("INVALID", "Missing 'message'", null)
                        try {
                            val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                appContext.getSystemService(SmsManager::class.java)
                            } else {
                                @Suppress("DEPRECATION")
                                SmsManager.getDefault()
                            }
                            val parts = smsManager.divideMessage(message)
                            if (parts.size == 1) {
                                smsManager.sendTextMessage(to, null, message, null, null)
                            } else {
                                smsManager.sendMultipartTextMessage(to, null, parts, null, null)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SMS_FAILED", e.message, null)
                        }
                    }

                    "storeCredentials" -> {
                        // url and anonKey are no longer sent over IPC — they are
                        // compiled into BuildConfig via --dart-define at build time.
                        val accessToken = call.argument<String>("accessToken")
                        val refreshToken = call.argument<String>("refreshToken")
                        val gymId = call.argument<String>("gymId")

                        if (gymId == null) {
                            result.error("INVALID", "gymId is required", null)
                            return@setMethodCallHandler
                        }

                        appContext.getSharedPreferences(SmsReminderWorker.NATIVE_PREFS, Context.MODE_PRIVATE)
                            .edit()
                            .apply {
                                if (accessToken != null) putString("supabase_access_token", accessToken)
                                if (refreshToken != null) putString("supabase_refresh_token", refreshToken)
                            }
                            .putString("supabase_gym_id", gymId)
                            .apply()

                        Log.d(SmsReminderWorker.TAG, "Credentials stored (gymId=$gymId)")
                        result.success(true)
                    }

                    "startNativeReminders" -> {
                        scheduleNativeWorker(appContext)
                        Log.d(SmsReminderWorker.TAG, "Native SMS reminder worker scheduled (24h)")
                        result.success(true)
                    }

                    "stopNativeReminders" -> {
                        WorkManager.getInstance(appContext)
                            .cancelUniqueWork(SmsReminderWorker.TASK_NAME)
                        Log.e(SmsReminderWorker.TAG, "Native SMS reminder worker cancelled")
                        result.success(true)
                    }

                    "runNowForTest" -> {
                        val request = androidx.work.OneTimeWorkRequestBuilder<SmsReminderWorker>()
                            .build()
                        WorkManager.getInstance(appContext).enqueue(request)
                        Log.e(SmsReminderWorker.TAG, "Test one-shot worker enqueued")
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    fun scheduleNativeWorker(context: Context) {
        val request = PeriodicWorkRequestBuilder<SmsReminderWorker>(24, TimeUnit.HOURS)
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            SmsReminderWorker.TASK_NAME,
            ExistingPeriodicWorkPolicy.KEEP,
            request
        )
    }
}
