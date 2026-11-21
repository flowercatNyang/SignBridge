package com.example.testsign

import android.Manifest
import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.provider.ContactsContract
import android.provider.AlarmClock
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.Calendar

import android.app.AlarmManager
import android.app.NotificationManager
import android.provider.Settings

class MainActivity: FlutterActivity() {
    private var pipChannel: MethodChannel? = null
    private var backgroundChannel: MethodChannel? = null
    private var resumed = false

    fun backgroundStateChanged() {
        backgroundChannel?.invokeMethod("changed", RecognitionService.state(this))
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        RecognitionService.attach(this, true)
        backgroundStateChanged()
        consumeBackgroundCommand(intent)
    }

    override fun onPause() {
        resumed = false
        RecognitionService.attach(this, false)
        RecognitionService.prepareNotifications(this)
        super.onPause()
    }

    override fun onDestroy() {
        RecognitionService.detached(this)
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (resumed) consumeBackgroundCommand(intent)
    }

    private fun consumeBackgroundCommand(intent: Intent?) {
        val token = intent?.getStringExtra("backgroundCommandToken") ?: return
        intent.removeExtra("backgroundCommandToken")
        RecognitionService.consumeCommand(token) ?: return
        Toast.makeText(this, "앱에서 백그라운드 입력 가져오기를 눌러 확인해 주세요.", Toast.LENGTH_LONG).show()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (RecognitionService.isEnabled() && !enteringPip &&
            getSharedPreferences("signbridge", MODE_PRIVATE).getBoolean("backgroundPip", true) &&
            Build.VERSION.SDK_INT >= 26 && !isInPictureInPictureMode && HandCameraView.isCameraReady()) {
            try {
                enteringPip = true
                HandCameraView.setCompact(true)
                if (!enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(Rational(3, 4)).build())) {
                    enteringPip = false
                    HandCameraView.setCompact(false)
                }
            } catch (error: Exception) {
                enteringPip = false
                HandCameraView.setCompact(false)
            }
        }
    }
    private var enteringPip = false
    fun keepCameraInPip(): Boolean = enteringPip ||
        (Build.VERSION.SDK_INT >= 26 && isInPictureInPictureMode)

    override fun onPictureInPictureModeChanged(inPip: Boolean, config: Configuration) {
        super.onPictureInPictureModeChanged(inPip, config)
        enteringPip = false
        HandCameraView.setCompact(inPip)
        pipChannel?.invokeMethod("changed", inPip)
    }

    override fun onStop() {
        enteringPip = false
        pipChannel?.invokeMethod("changed", false)
        super.onStop()
    }

    override fun onStart() {
        super.onStart()
        val inPip = Build.VERSION.SDK_INT >= 26 && isInPictureInPictureMode
        HandCameraView.setCompact(inPip)
        pipChannel?.invokeMethod("changed", inPip)
    }

    private var pending: Pair<MethodCall, MethodChannel.Result>? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        RecognitionService.attach(this, false)
        backgroundChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "signbridge/background")
        backgroundChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "state" -> result.success(RecognitionService.state(this))
                "takeInput" -> {
                    RecognitionService.disable(this)
                    result.success(RecognitionService.takeInput())
                }
                "notificationSettings" -> {
                    try {
                        val settings = if (Build.VERSION.SDK_INT >= 26)
                            Intent("android.settings.APP_NOTIFICATION_SETTINGS")
                                .putExtra("android.provider.extra.APP_PACKAGE", packageName)
                        else Intent("android.settings.APPLICATION_DETAILS_SETTINGS", Uri.parse("package:$packageName"))
                        startActivity(settings)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("settings_failed", "앱 알림 설정을 열 수 없습니다.", null)
                    }
                }
                "setPip" -> {
                    getSharedPreferences("signbridge", MODE_PRIVATE).edit()
                        .putBoolean("backgroundPip", call.arguments == true).apply()
                    result.success(RecognitionService.state(this))
                }
                "setEnabled" -> {
                    if (call.arguments != true) {
                        RecognitionService.disable(this)
                        result.success(RecognitionService.state(this))
                    } else if (!resumed || !HandCameraView.isCameraReady()) {
                        result.error("camera_unavailable", "앱에서 카메라 영상이 나온 뒤 백그라운드 인식을 켜 주세요.", null)
                    } else if (!getSystemService(android.app.NotificationManager::class.java).areNotificationsEnabled()) {
                        result.error("notifications_disabled", "알림 설정에서 SignBridge 알림을 허용해 주세요. 인식 중지와 입력 확인에 필요합니다.", null)
                    } else {
                        RecognitionService.enable(this, RecognitionService.Ready { error ->
                            if (error == null) result.success(RecognitionService.state(this))
                            else result.error("background_failed", error, null)
                        })
                    }
                }
                "hide" -> {
                    if (!RecognitionService.isEnabled()) result.error("disabled", "백그라운드 인식을 먼저 켜 주세요.", null)
                    else result.success(moveTaskToBack(true))
                }
                "resetGate" -> { RecognitionService.resetGate(); result.success(null) }
                else -> result.notImplemented()
            }
        }
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "signbridge/pip")
        pipChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "enter" -> {
                    if (Build.VERSION.SDK_INT < 26 ||
                        !packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) {
                        result.error("unsupported", "이 기기는 PiP 백그라운드 실행을 지원하지 않습니다.", null)
                    } else if (!HandCameraView.isCameraReady()) {
                        result.error("camera_unavailable", "카메라 권한을 허용하고 영상이 나온 뒤 다시 눌러 주세요.", null)
                    } else {
                        try {
                            enteringPip = true
                            HandCameraView.setCompact(true)
                            val entered = enterPictureInPictureMode(PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(3, 4)).build())
                            if (!entered) {
                                enteringPip = false
                                HandCameraView.setCompact(false)
                            }
                            result.success(entered)
                        } catch (error: Exception) {
                            enteringPip = false
                            HandCameraView.setCompact(false)
                            result.error("pip_failed", "PiP 실행에 실패했습니다. 앱 설정에서 화면 속 화면 권한을 확인해 주세요.", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "signbridge/hand-camera", HandCameraView.Factory(this, flutterEngine.dartExecutor.binaryMessenger))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "signbridge/assistant-settings")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "loadAssistantConnection" -> result.success(AssistantConnectionStore(this).load())
                        "saveAssistantConnection" -> {
                            AssistantConnectionStore(this).save(call.argument<String>("baseUrl") ?: "",
                                call.argument<String>("accessToken") ?: "")
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("assistant_connection", "서버 연결 설정을 처리하지 못했습니다. 다시 저장해 주세요.", null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "signbridge/actions")
            .setMethodCallHandler { call, result -> perform(call, result) }
    }

    private fun companyData(value: String): JSONObject {
        val data = JSONObject(value)
        require(data.getString("name").isNotBlank()) { "회사 이름을 입력해 주세요." }
        require(data.getDouble("lat") in 31.43..44.35 && data.getDouble("lng") in 122.37..132.0) {
            "유효한 국내 회사 위치 좌표를 입력해 주세요."
        }
        return data
    }

    private fun perform(call: MethodCall, result: MethodChannel.Result) {
        try {
            val prefs = getSharedPreferences("signbridge", MODE_PRIVATE)
            when (call.method) {
                "loadCompany" -> result.success(prefs.getString("company", ""))
                "saveCompany" -> {
                    val value = call.argument<String>("value") ?: ""
                    companyData(value)
                    check(prefs.edit().putString("company", value).commit()) { "회사 위치 저장 실패" }
                    result.success(null)
                }
                "set_alarm" -> {
                    val data = JSONObject(call.argument<String>("value") ?: "")
                    val hour = data.get("hour")
                    val minute = data.get("minute")
                    require(hour is Int && hour in 0..23 && minute is Int && minute in 0..59) {
                        "알람 시각을 확인해 주세요."
                    }
                    val label = data.getString("label")
                    require(label.length <= 120) { "알람 이름이 너무 깁니다." }
                    val rawDays = data.getJSONArray("days")
                    require(rawDays.length() <= 7) { "반복 요일을 확인해 주세요." }
                    val days = arrayListOf<Int>()
                    for (index in 0 until rawDays.length()) {
                        val day = rawDays.get(index)
                        require(day is Int && day in 1..7) { "반복 요일을 확인해 주세요." }
                        // API uses Calendar.SUNDAY=1; assistant uses ISO Monday=1.
                        val calendarDay = (day % 7) + Calendar.SUNDAY
                        require(!days.contains(calendarDay)) { "반복 요일이 중복되었습니다." }
                        days.add(calendarDay)
                    }
                    if (data.has("date")) {
                        require(days.isEmpty()) { "날짜 알람에는 반복 요일을 지정할 수 없습니다." }
                        val time = DatedAlarmReceiver.timestamp(data)
                        require(time > System.currentTimeMillis()) { "이미 지난 시각입니다. 다시 입력해 주세요." }
                        DatedAlarmReceiver.ensureChannel(this)
                        val notifications = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED) {
                            requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), 4105)
                            result.error("notification_permission", "알림 권한을 허용한 뒤 다시 승인해 주세요.", null)
                            return
                        }
                        require(notifications.areNotificationsEnabled()) { "앱 설정에서 알림을 허용해 주세요." }
                        if (Build.VERSION.SDK_INT >= 26) {
                            require(notifications.getNotificationChannel(DatedAlarmReceiver.CHANNEL).importance != NotificationManager.IMPORTANCE_NONE) {
                                "앱 설정에서 날짜 지정 알람 채널을 허용해 주세요."
                            }
                        }
                        val alarms = getSystemService(ALARM_SERVICE) as AlarmManager
                        if (Build.VERSION.SDK_INT >= 31 && !alarms.canScheduleExactAlarms()) {
                            startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName")))
                            result.error("alarm_permission", "정확한 알람 권한을 허용한 뒤 다시 승인해 주세요.", null)
                            return
                        }
                        val saved = getSharedPreferences("dated_alarms", MODE_PRIVATE)
                        val id = saved.getInt("next_id", 1)
                        check(saved.edit().putString(id.toString(), data.toString()).putInt("next_id", id + 1).commit())
                        try { DatedAlarmReceiver.schedule(this, id, time) }
                        catch (error: Exception) { saved.edit().remove(id.toString()).commit(); throw error }
                        result.success("${data.getString("date")} ${hour}:${minute.toString().padStart(2, '0')} 날짜 알림을 예약했습니다. 소리·진동은 기기 알림 설정을 따릅니다.")
                        return
                    }
                    val intent = Intent(AlarmClock.ACTION_SET_ALARM)
                        .putExtra(AlarmClock.EXTRA_HOUR, hour as Int)
                        .putExtra(AlarmClock.EXTRA_MINUTES, minute as Int)
                        .putExtra(AlarmClock.EXTRA_MESSAGE, label)
                        .putExtra(AlarmClock.EXTRA_VIBRATE, true)
                        .putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                    if (days.isNotEmpty()) intent.putIntegerArrayListExtra(AlarmClock.EXTRA_DAYS, days)
                    require(intent.resolveActivity(packageManager) != null) { "알람을 지원하는 시계 앱이 없습니다." }
                    startActivity(intent)
                    result.success("알람 설정을 시계 앱에 전달했습니다. 시계 앱에서 실제 설정을 확인해 주세요.")
                }
                "compose_message" -> {
                    val data = JSONObject(call.argument<String>("value") ?: "")
                    val recipient = data.getString("recipient").trim()
                    val body = data.getString("body").trim()
                    require(recipient.isNotEmpty() && recipient.length <= 80 && body.isNotEmpty() && body.length <= 1000) {
                        "문자 수신자와 내용을 확인해 주세요."
                    }
                    if (checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
                        if (pending != null) { result.error("busy", "다른 권한 요청을 처리 중입니다.", null); return }
                        pending = Pair(call, result)
                        requestPermissions(arrayOf(Manifest.permission.READ_CONTACTS), 4104)
                        return
                    }
                    val number = contactNumber(recipient)
                    val intent = Intent(Intent.ACTION_SENDTO, Uri.fromParts("smsto", number, null))
                        .putExtra("sms_body", body)
                    require(intent.resolveActivity(packageManager) != null) { "문자 작성을 지원하는 앱이 없습니다." }
                    startActivity(intent)
                    result.success("문자 작성 화면을 열었습니다. 수신자와 내용을 확인하고 문자 앱에서 전송해 주세요.")
                }
                "emergency" -> {
                    startActivity(Intent(Intent.ACTION_DIAL, Uri.fromParts("tel", "119", null)))
                    result.success("119 발신 화면을 열었습니다. 전화 앱에서 통화 버튼을 눌러 주세요.")
                }
                "company" -> {
                    val saved = prefs.getString("company", "") ?: ""
                    require(saved.isNotEmpty()) { "먼저 회사 위치를 등록해 주세요." }
                    val data = companyData(saved)
                    val uri = Uri.parse("nmap://route/public").buildUpon()
                        .appendQueryParameter("dlat", data.getDouble("lat").toString())
                        .appendQueryParameter("dlng", data.getDouble("lng").toString())
                        .appendQueryParameter("dname", data.getString("name"))
                        .appendQueryParameter("appname", packageName).build()
                    val intent = Intent(Intent.ACTION_VIEW, uri).setPackage("com.nhn.android.nmap")
                    if (intent.resolveActivity(packageManager) == null) {
                        result.error("missing_app", "네이버맵 앱을 설치한 뒤 다시 인식해 주세요.", null)
                    } else {
                        startActivity(intent)
                        result.success("등록한 회사로 네이버맵 길찾기를 시작했습니다.")
                    }
                }
                "mother" -> {
                    val missing = arrayOf(Manifest.permission.READ_CONTACTS, Manifest.permission.CALL_PHONE)
                        .filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
                    if (missing.isNotEmpty()) {
                        if (pending != null) { result.error("busy", "다른 권한 요청을 처리 중입니다.", null); return }
                        pending = Pair(call, result)
                        requestPermissions(missing.toTypedArray(), 4103)
                        return
                    }

                    val number = contactNumber("엄마")
                    startActivity(Intent(Intent.ACTION_CALL, Uri.fromParts("tel", number, null)))
                    result.success("전화번호부의 엄마에게 발신을 요청했습니다.")
                }
                "volumeUp", "volumeDown", "adjust_volume" -> {
                    val raise = if (call.method == "adjust_volume") {
                        val data = JSONObject(call.argument<String>("value") ?: "")
                        val direction = data.getString("direction")
                        require(data.length() == 1 && direction in listOf("up", "down")) { "볼륨 방향을 확인해 주세요." }
                        direction == "up"
                    } else call.method == "volumeUp"
                    val audio = getSystemService(AUDIO_SERVICE) as AudioManager
                    check(!audio.isVolumeFixed) { "이 기기는 볼륨 조절을 지원하지 않습니다." }
                    val before = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
                    audio.adjustStreamVolume(AudioManager.STREAM_MUSIC,
                        if (raise) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER,
                        AudioManager.FLAG_SHOW_UI)
                    val after = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
                    result.success(if (before == after) "미디어 볼륨이 이미 한계에 도달했습니다."
                        else "미디어 볼륨을 ${if (raise) "올렸습니다" else "내렸습니다"}. ($after/${audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)})")
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("action_failed", error.localizedMessage ?: "기능을 실행하지 못했습니다.", null)
        }
    }

    private fun contactNumber(name: String): String {
        val numbers = linkedSetOf<String>()
        contentResolver.query(ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER),
            "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} = ?", arrayOf(name), null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val number = cursor.getString(0)?.replace(Regex("[\\s()-]"), "") ?: ""
                if (Regex("^\\+?[0-9]{3,15}$").matches(number)) numbers.add(number)
            }
        }
        require(numbers.isNotEmpty()) { "전화번호부에서 '$name'의 번호를 찾지 못했습니다. 저장된 이름을 확인해 주세요." }
        require(numbers.size == 1) { "'$name'의 번호가 여러 개입니다. 사용할 연락처를 구분해 주세요." }
        val number = numbers.single()
        require(number.removePrefix("+") != "112" && number.removePrefix("+") != "119") {
            "연락처의 전화번호를 확인해 주세요."
        }
        return number
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4102) HandCameraView.permissionChanged()
        if (requestCode == 4103 || requestCode == 4104) {
            val request = pending ?: return
            pending = null
            if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) perform(request.first, request.second)
            else request.second.error("permission_denied",
                if (requestCode == 4104) "문자 수신자를 찾으려면 연락처 권한을 허용해 주세요."
                else "엄마에게 전화하려면 연락처와 전화 권한을 허용해 주세요.", null)
        }
    }
}
