package com.gymcrm.gym_crm

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.telephony.SmsManager
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

class SmsReminderWorker(
    private val appContext: Context,
    workerParams: WorkerParameters
) : Worker(appContext, workerParams) {

    companion object {
        const val TASK_NAME = "gym-crm-native-sms-24h"
        const val TAG = "SmsReminderWorker"
        // Our own prefs file — written by SmsPlugin.storeCredentials from foreground Dart
        const val NATIVE_PREFS = "gym_crm_native"
        // Flutter shared_preferences file — written by Dart SharedPreferences package
        const val FLUTTER_PREFS = "FlutterSharedPreferences"
    }

    override fun doWork(): Result {
        // Use Log.e so logs survive ColorOS/OEM debug-log filtering on release builds.
        Log.e(TAG, "Worker started at ${Date()}")

        // Worker only runs when scheduled — scheduling is controlled by enabled toggle.
        // Read days/template from Flutter SharedPreferences (key prefix "flutter.").
        // Try both with and without prefix to handle shared_preferences version differences.
        val flutterPrefs = appContext.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        // Flutter stores Dart int as Long on Android — use getLong(), not getInt().
        val daysBefore = (flutterPrefs.getLong("flutter.${SmsConst.KEY_DAYS_BEFORE}", 0L)
            .takeIf { it > 0L } ?: flutterPrefs.getLong(SmsConst.KEY_DAYS_BEFORE, 3L)).toInt()
        val template = (flutterPrefs.getString("flutter.${SmsConst.KEY_TEMPLATE}", null)
            ?: flutterPrefs.getString(SmsConst.KEY_TEMPLATE, null)
            ?: SmsConst.DEFAULT_TEMPLATE)

        // url and anonKey are compiled into the binary via BuildConfig (--dart-define).
        // Tokens and gymId are written at runtime by SmsPlugin.storeCredentials.
        val supabaseUrl = BuildConfig.SUPABASE_URL.takeIf { it.isNotBlank() } ?: run {
            Log.e(TAG, "SUPABASE_URL not compiled in — rebuild with --dart-define=SUPABASE_URL=...")
            return Result.retry()
        }
        val anonKey = BuildConfig.SUPABASE_ANON_KEY.takeIf { it.isNotBlank() } ?: run {
            Log.e(TAG, "SUPABASE_ANON_KEY not compiled in — rebuild with --dart-define=SUPABASE_ANON_KEY=...")
            return Result.retry()
        }

        val nativePrefs = appContext.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
        val gymId = nativePrefs.getString("supabase_gym_id", null) ?: run {
            Log.e(TAG, "No gym_id stored — open the app once to sync")
            return Result.retry()
        }

        val accessToken = getValidAccessToken(nativePrefs, supabaseUrl, anonKey) ?: run {
            Log.e(TAG, "Could not obtain valid access token")
            return Result.retry()
        }

        val members = fetchExpiringMembers(supabaseUrl, anonKey, accessToken, gymId, daysBefore)
        Log.e(TAG, "Fetched ${members.size} expiring member(s) for daysBefore=$daysBefore")

        var sent = 0
        for (member in members) {
            val phone = member.optString("phone", "").trim()
            val name = member.optString("first_name", "Member")
            if (phone.isEmpty()) continue
            val msg = template.replace("{name}", name).replace("{days}", daysBefore.toString())
            if (sendSms(phone, msg)) sent++
        }

        Log.e(TAG, "Sent $sent reminder SMS(es)")
        return Result.success()
    }

    private fun getValidAccessToken(prefs: SharedPreferences, supabaseUrl: String, anonKey: String): String? {
        val stored = prefs.getString("supabase_access_token", null)
        if (!stored.isNullOrBlank()) {
            Log.e(TAG, "Using stored access token")
            return stored
        }

        val refreshToken = prefs.getString("supabase_refresh_token", null)
        if (refreshToken.isNullOrBlank()) {
            Log.e(TAG, "No refresh token available")
            return null
        }

        Log.e(TAG, "Refreshing access token...")
        return try {
            val url = URL("$supabaseUrl/auth/v1/token?grant_type=refresh_token")
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("apikey", anonKey)
            conn.doOutput = true
            conn.outputStream.write("""{"refresh_token":"$refreshToken"}""".toByteArray())
            conn.connectTimeout = 15_000
            conn.readTimeout = 15_000

            if (conn.responseCode == 200) {
                val json = JSONObject(conn.inputStream.bufferedReader().readText())
                val newAccess = json.getString("access_token")
                val newRefresh = json.optString("refresh_token", refreshToken)
                prefs.edit()
                    .putString("supabase_access_token", newAccess)
                    .putString("supabase_refresh_token", newRefresh)
                    .apply()
                Log.e(TAG, "Token refreshed successfully")
                newAccess
            } else {
                val err = conn.errorStream?.bufferedReader()?.readText() ?: ""
                Log.e(TAG, "Token refresh failed ${conn.responseCode}: $err")
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Token refresh exception: ${e.message}")
            null
        }
    }

    private fun fetchExpiringMembers(
        supabaseUrl: String,
        anonKey: String,
        accessToken: String,
        gymId: String,
        daysBefore: Int
    ): List<JSONObject> {
        return try {
            val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
            val cal = Calendar.getInstance()
            cal.add(Calendar.DAY_OF_YEAR, daysBefore)
            val start = sdf.format(cal.time)
            cal.add(Calendar.DAY_OF_YEAR, 1)
            val end = sdf.format(cal.time)

            val endpoint = ("$supabaseUrl/rest/v1/members" +
                "?select=id,first_name,last_name,phone" +
                "&gym_id=eq.$gymId" +
                "&status=eq.active" +
                "&next_payment_date=gte.$start" +
                "&next_payment_date=lt.$end" +
                "&phone=not.is.null")

            Log.e(TAG, "Fetching members: expiry between $start and $end")
            val conn = URL(endpoint).openConnection() as HttpURLConnection
            conn.setRequestProperty("Authorization", "Bearer $accessToken")
            conn.setRequestProperty("apikey", anonKey)
            conn.setRequestProperty("Accept", "application/json")
            conn.connectTimeout = 15_000
            conn.readTimeout = 15_000

            if (conn.responseCode == 200) {
                val arr = JSONArray(conn.inputStream.bufferedReader().readText())
                (0 until arr.length()).map { arr.getJSONObject(it) }
            } else {
                val err = conn.errorStream?.bufferedReader()?.readText() ?: ""
                Log.e(TAG, "Fetch members failed ${conn.responseCode}: $err")
                emptyList()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Fetch members exception: ${e.message}")
            emptyList()
        }
    }

    private fun sendSms(phone: String, message: String): Boolean {
        return try {
            val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                appContext.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
            val parts = smsManager.divideMessage(message)
            if (parts.size > 1) {
                smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
            } else {
                smsManager.sendTextMessage(phone, null, message, null, null)
            }
            Log.e(TAG, "SMS sent to $phone")
            true
        } catch (e: Exception) {
            Log.e(TAG, "SMS failed for $phone: ${e.message}")
            false
        }
    }
}

// Shared constants between SmsPlugin and SmsReminderWorker
object SmsConst {
    const val KEY_ENABLED = "sms_reminders_enabled"
    const val KEY_DAYS_BEFORE = "sms_reminders_days_before"
    const val KEY_TEMPLATE = "sms_reminders_template"
    const val DEFAULT_TEMPLATE = "Hi {name}, your gym membership expires in {days} days. Please renew to continue."
}
