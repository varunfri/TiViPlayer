package com.app.tvplayer.tv_player_app

import android.app.AppOpsManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Rational
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.app.tvplayer/pip"
    private var pipChannel: MethodChannel? = null
    private var autoEnterPip: Boolean = false
    private var currentNumerator: Int = 16
    private var currentDenominator: Int = 9
    private var currentIsPlaying: Boolean = true

    companion object {
        const val ACTION_PIP_PLAY_PAUSE = "com.app.tvplayer.ACTION_PIP_PLAY_PAUSE"
        const val ACTION_PIP_NEXT_CHANNEL = "com.app.tvplayer.ACTION_PIP_NEXT_CHANNEL"
    }

    private var playPausePendingIntent: PendingIntent? = null
    private var nextPendingIntent: PendingIntent? = null

    private val pipActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                ACTION_PIP_PLAY_PAUSE -> {
                    currentIsPlaying = !currentIsPlaying
                    updatePipParamsAndActions(currentIsPlaying)
                    pipChannel?.invokeMethod("togglePlayPause", null)
                }
                ACTION_PIP_NEXT_CHANNEL -> {
                    pipChannel?.invokeMethod("nextChannel", null)
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)

        setupPendingIntents()
        registerPipReceiver()

        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isPipSupported" -> {
                    val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                    result.success(supported)
                }
                "isPipAllowed" -> {
                    result.success(isPipAllowed())
                }
                "openPipSettings" -> {
                    result.success(openPipSettings())
                }
                "isInPipMode" -> {
                    val inPip = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        isInPictureInPictureMode
                    } else {
                        false
                    }
                    result.success(inPip)
                }
                "enterPip" -> {
                    val num = call.argument<Int>("numerator") ?: 16
                    val den = call.argument<Int>("denominator") ?: 9
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                    currentNumerator = num
                    currentDenominator = den
                    currentIsPlaying = isPlaying
                    val entered = enterPipMode(num, den, isPlaying)
                    result.success(entered)
                }
                "setAutoEnterPip" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val num = call.argument<Int>("numerator") ?: 16
                    val den = call.argument<Int>("denominator") ?: 9
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                    autoEnterPip = enabled
                    currentNumerator = num
                    currentDenominator = den
                    currentIsPlaying = isPlaying
                    updatePipParamsAndActions(isPlaying)
                    result.success(true)
                }
                "updatePlaybackState" -> {
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                    currentIsPlaying = isPlaying
                    updatePipParamsAndActions(isPlaying)
                    updateKeepScreenOn(isPlaying)
                    result.success(true)
                }
                "setKeepScreenOn" -> {
                    val keepOn = call.argument<Boolean>("keepOn") ?: false
                    updateKeepScreenOn(keepOn)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun updateKeepScreenOn(keepOn: Boolean) {
        runOnUiThread {
            try {
                if (keepOn) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun setupPendingIntents() {
        val playPauseIntent = Intent(ACTION_PIP_PLAY_PAUSE).setPackage(packageName)
        playPausePendingIntent = PendingIntent.getBroadcast(
            this,
            101,
            playPauseIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val nextIntent = Intent(ACTION_PIP_NEXT_CHANNEL).setPackage(packageName)
        nextPendingIntent = PendingIntent.getBroadcast(
            this,
            102,
            nextIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun registerPipReceiver() {
        val filter = IntentFilter().apply {
            addAction(ACTION_PIP_PLAY_PAUSE)
            addAction(ACTION_PIP_NEXT_CHANNEL)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(pipActionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(pipActionReceiver, filter)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun isPipAllowed(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps?.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_PICTURE_IN_PICTURE,
                    android.os.Process.myUid(),
                    packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps?.checkOpNoThrow(
                    AppOpsManager.OPSTR_PICTURE_IN_PICTURE,
                    android.os.Process.myUid(),
                    packageName
                )
            }
            return mode == AppOpsManager.MODE_ALLOWED || mode == AppOpsManager.MODE_DEFAULT
        }
        return false
    }

    private fun openPipSettings(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return try {
                val intent = Intent(
                    "android.settings.PICTURE_IN_PICTURE_SETTINGS",
                    Uri.parse("package:$packageName")
                ).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                true
            } catch (_: Exception) {
                try {
                    val intent = Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$packageName")
                    ).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    true
                } catch (_: Exception) {
                    false
                }
            }
        }
        return false
    }

    private fun getSafeRational(numerator: Int, denominator: Int): Rational {
        val num = if (numerator <= 0) 16 else numerator
        val den = if (denominator <= 0) 9 else denominator
        val ratio = num.toFloat() / den.toFloat()
        // Android enforces aspect ratio between 1:2.39 (0.4184) and 2.39:1 (2.3900)
        return when {
            ratio < 0.42f -> Rational(42, 100)
            ratio > 2.38f -> Rational(238, 100)
            else -> Rational(num, den)
        }
    }

    private fun getPipActions(isPlaying: Boolean): List<RemoteAction> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return emptyList()

        val actions = mutableListOf<RemoteAction>()
        try {
            if (playPausePendingIntent != null) {
                val playPauseIcon = Icon.createWithResource(
                    this,
                    if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
                )
                val playPauseAction = RemoteAction(
                    playPauseIcon,
                    if (isPlaying) "Pause" else "Play",
                    if (isPlaying) "Pause" else "Play",
                    playPausePendingIntent!!
                )
                actions.add(playPauseAction)
            }

            if (nextPendingIntent != null) {
                val nextIcon = Icon.createWithResource(this, android.R.drawable.ic_media_next)
                val nextAction = RemoteAction(
                    nextIcon,
                    "Next Channel",
                    "Next Channel",
                    nextPendingIntent!!
                )
                actions.add(nextAction)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return actions
    }

    private fun enterPipMode(numerator: Int, denominator: Int, isPlaying: Boolean = currentIsPlaying): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
        ) {
            return try {
                if (isInPictureInPictureMode) {
                    return true
                }
                val rational = getSafeRational(numerator, denominator)
                val builder = PictureInPictureParams.Builder()
                    .setAspectRatio(rational)
                    .setActions(getPipActions(isPlaying))
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    builder.setAutoEnterEnabled(autoEnterPip)
                }
                enterPictureInPictureMode(builder.build())
            } catch (e: Exception) {
                e.printStackTrace()
                false
            }
        }
        return false
    }

    private fun updatePipParamsAndActions(isPlaying: Boolean = currentIsPlaying) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
        ) {
            try {
                val rational = getSafeRational(currentNumerator, currentDenominator)
                val builder = PictureInPictureParams.Builder()
                    .setAspectRatio(rational)
                    .setActions(getPipActions(isPlaying))
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    builder.setAutoEnterEnabled(autoEnterPip)
                }
                setPictureInPictureParams(builder.build())
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (currentIsPlaying) {
            updateKeepScreenOn(true)
        }
        if (autoEnterPip && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            updatePipParamsAndActions(currentIsPlaying)
        }
    }

    override fun onStop() {
        super.onStop()
        val inPip = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) isInPictureInPictureMode else false
        if (!inPip) {
            updateKeepScreenOn(false)
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Called when user leaves the activity (presses Home, opens another app, recents, etc.)
        // This guarantees PiP triggers across ALL Android versions (8.0 through 15+)
        if (autoEnterPip && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
        ) {
            val inPip = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) isInPictureInPictureMode else false
            if (!inPip) {
                enterPipMode(currentNumerator, currentDenominator, currentIsPlaying)
            }
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (!isInPictureInPictureMode) {
            if (currentIsPlaying) {
                updateKeepScreenOn(true)
            }
            if (autoEnterPip) {
                // Android resets autoEnterEnabled when leaving PiP, re-enable it immediately
                updatePipParamsAndActions(currentIsPlaying)
            }
        }
        pipChannel?.invokeMethod("onPipModeChanged", isInPictureInPictureMode)
    }

    override fun onDestroy() {
        updateKeepScreenOn(false)
        try {
            unregisterReceiver(pipActionReceiver)
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
