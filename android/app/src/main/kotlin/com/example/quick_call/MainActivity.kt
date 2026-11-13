package com.example.quick_call

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import androidx.lifecycle.Lifecycle

class MainActivity : FlutterActivity() {
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"quick_call/device_vibration",
		).setMethodCallHandler { call, result ->
			if (call.method != "vibrate") {
				result.notImplemented()
				return@setMethodCallHandler
			}

			@Suppress("DEPRECATION")
			val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
			if (vibrator == null || !vibrator.hasVibrator()) {
				Log.w("QuickCall", "Vibration requested, but no vibrator is available.")
				result.error("VIBRATOR_UNAVAILABLE", "This device has no vibrator.", null)
				return@setMethodCallHandler
			}

			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
				vibrator.vibrate(
					VibrationEffect.createOneShot(350, VibrationEffect.DEFAULT_AMPLITUDE),
				)
			} else {
				@Suppress("DEPRECATION")
				vibrator.vibrate(350)
			}
			Log.i("QuickCall", "Hand-raise vibration started.")
			result.success(null)
		}

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"quick_call/call_foreground_service",
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"start" -> {
					if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
						result.error("MICROPHONE_PERMISSION_REQUIRED", "Microphone permission is required to start the call service.", null)
						return@setMethodCallHandler
					}
					if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
						!lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
					) {
						result.error("APP_NOT_VISIBLE", "The call service must start while QuickCall is visible.", null)
						return@setMethodCallHandler
					}
					val intent = Intent(this, CallForegroundService::class.java)
					try {
						if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
							startForegroundService(intent)
						} else {
							startService(intent)
						}
						result.success(null)
					} catch (error: SecurityException) {
						result.error("FOREGROUND_SERVICE_DENIED", error.message, null)
					}
				}
				"stop" -> {
					stopService(Intent(this, CallForegroundService::class.java))
					result.success(null)
				}
				else -> result.notImplemented()
			}
		}
	}
}
