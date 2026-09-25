package com.parthi.play

import android.content.Context
import android.content.pm.ActivityInfo
import android.media.AudioManager
import android.provider.Settings
import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val SYSTEM_CHANNEL = "next_player/system_controls"
    private val ORIENTATION_CHANNEL = "parthi_play/orientation"
    private val audioFocusChangeListener =
        AudioManager.OnAudioFocusChangeListener { }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ORIENTATION_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSensorLandscape" -> {
                    requestedOrientation =
                        ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                    result.success(true)
                }
                "setSensorPortrait" -> {
                    requestedOrientation =
                        ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
                    result.success(true)
                }
                "setSensorAuto" -> {
                    requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR
                    result.success(true)
                }
                "setFullSensor" -> {
                    requestedOrientation =
                        ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR
                    result.success(true)
                }
                "clear" -> {
                    requestedOrientation =
                        ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // System Controls Channel
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SYSTEM_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getBrightness" -> result.success(getBrightness())
                "setBrightness" -> {
                    val brightness = call.argument<Double>("brightness")
                    if (brightness != null) {
                        setBrightness(brightness.toFloat())
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Brightness is null", null)
                    }
                }
                "getVolume" -> result.success(getVolume())
                "setVolume" -> {
                    val volume = call.argument<Double>("volume")
                    if (volume != null) {
                        setVolume(volume.toFloat())
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Volume is null", null)
                    }
                }
                "requestAudioFocus" -> result.success(requestAudioFocus())
                "abandonAudioFocus" -> result.success(abandonAudioFocus())
                "isSupported" -> result.success(true)
                "setSecure" -> {
                    // Blocks screenshots, screen recording and the recent-apps
                    // preview while vault content is on screen.
                    val secure = call.argument<Boolean>("secure") ?: false
                    runOnUiThread {
                        if (secure) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    private fun getBrightness(): Float {
        return try {
            val layoutParams = window.attributes
            if (layoutParams.screenBrightness < 0) {
                Settings.System.getInt(
                    contentResolver,
                    Settings.System.SCREEN_BRIGHTNESS
                ).toFloat() / 255f
            } else {
                layoutParams.screenBrightness
            }
        } catch (e: Exception) {
            0.5f
        }
    }

    private fun setBrightness(brightness: Float) {
        runOnUiThread {
            val layoutParams = window.attributes
            layoutParams.screenBrightness = brightness
            window.attributes = layoutParams
        }
    }

    private fun getVolume(): Float {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val currentVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        return currentVolume.toFloat() / maxVolume.toFloat()
    }

    private fun setVolume(volume: Float) {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val targetVolume = (volume * maxVolume).toInt()
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, targetVolume, 0)
    }

    @Suppress("DEPRECATION")
    private fun requestAudioFocus(): Boolean {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val result = audioManager.requestAudioFocus(
            audioFocusChangeListener,
            AudioManager.STREAM_MUSIC,
            AudioManager.AUDIOFOCUS_GAIN
        )
        return result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    @Suppress("DEPRECATION")
    private fun abandonAudioFocus(): Boolean {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val result = audioManager.abandonAudioFocus(audioFocusChangeListener)
        return result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }
}
