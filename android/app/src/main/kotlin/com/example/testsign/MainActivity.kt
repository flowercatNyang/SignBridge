package com.example.testsign

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.AlarmClock
import org.json.JSONObject
import android.telecom.TelecomManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private var pending: Pair<MethodCall, MethodChannel.Result>? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "signbridge/hand-camera", HandCameraView.Factory(this, flutterEngine.dartExecutor.binaryMessenger))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "signbridge/actions")
            .setMethodCallHandler { call, result -> perform(call, result) }
    }

    @Suppress("DEPRECATION")
    private fun perform(call: MethodCall, result: MethodChannel.Result) {
        try {
            val value = call.argument<String>("value") ?: ""
            val prefs = getSharedPreferences("signbridge", MODE_PRIVATE)
            when (call.method) {
                "loadPhone" -> result.success(prefs.getString("emergencyPhone", ""))
                "savePhone" -> {
                    require(Regex("^\\+?[0-9]{3,15}$").matches(value)) { "올바른 전화번호를 입력해 주세요." }
                    if (!prefs.edit().putString("emergencyPhone", value).commit()) throw IllegalStateException("전화번호 저장 실패")
                    result.success(null)
                }
                "endCall", "call" -> {
                    if (call.method == "endCall" && Build.VERSION.SDK_INT < 28) {
                        result.error("unsupported", "통화 종료는 Android 9 이상에서 지원합니다.", null); return
                    }
                    val permission = if (call.method == "endCall") Manifest.permission.ANSWER_PHONE_CALLS else Manifest.permission.CALL_PHONE
                    if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
                        if (pending != null) { result.error("busy", "다른 권한 요청을 처리 중입니다.", null); return }
                        pending = Pair(call, result)
                        requestPermissions(arrayOf(permission), 4103)
                        return
                    }
                    if (call.method == "endCall") {
                        val telecom = getSystemService(TELECOM_SERVICE) as TelecomManager
                        if (telecom.endCall()) result.success("통화를 종료했습니다.")
                        else result.error("not_ended", "종료할 통화가 없거나 시스템에서 통화 종료를 허용하지 않습니다.", null)
                    } else {
                        require(Regex("^\\+?[0-9]{3,15}$").matches(value)) { "전화번호가 올바르지 않습니다." }
                        val intent = if (value == "112" || value == "119") Intent.ACTION_DIAL else Intent.ACTION_CALL
                        startActivity(Intent(intent, Uri.fromParts("tel", value, null)))
                        result.success(if (intent == Intent.ACTION_DIAL) "전화 앱 발신 화면을 열었습니다." else "등록된 번호로 발신을 요청했습니다.")
                    }
                }
                "dial" -> {
                    require(value == "112" || value == "119")
                    startActivity(Intent(Intent.ACTION_DIAL, Uri.fromParts("tel", value, null)))
                    result.success("$value 발신 화면을 열었습니다. 전화 앱에서 통화 버튼을 눌러 주세요.")
                }
                "message" -> {
                    val message = JSONObject(value)
                    val phone = message.getString("phone")
                    val body = message.getString("body")
                    require(Regex("^\\+?[0-9]{3,15}$").matches(phone) && body.isNotBlank())
                    startActivity(Intent(Intent.ACTION_SENDTO, Uri.fromParts("smsto", phone, null))
                        .putExtra("sms_body", body))
                    result.success("메시지 작성 화면을 열었습니다. 메시지 앱에서 전송을 눌러 주세요.")
                }
                "timer" -> {
                    val seconds = value.toInt()
                    require(seconds in 1..5999) { "1초부터 99분 59초까지 설정할 수 있습니다." }
                    startActivity(Intent(AlarmClock.ACTION_SET_TIMER)
                        .putExtra(AlarmClock.EXTRA_LENGTH, seconds)
                        .putExtra(AlarmClock.EXTRA_MESSAGE, "SignBridge 타이머")
                        .putExtra(AlarmClock.EXTRA_SKIP_UI, false))
                    result.success("${seconds / 60}분 ${seconds % 60}초 타이머 시작을 요청했습니다. 시계 앱에서 확인해 주세요.")
                }
                "baemin" -> {
                    val intent = packageManager.getLaunchIntentForPackage("com.sampleapp")
                    if (intent == null) result.error("missing_app", "배달의민족 앱이 설치되어 있지 않습니다.", null)
                    else { startActivity(intent); result.success("배달의민족 앱을 열었습니다.") }
                }
                "translate" -> {
                    require(value.isNotBlank())
                    val uri = Uri.parse("https://translate.google.com/").buildUpon()
                        .appendQueryParameter("sl", "ko").appendQueryParameter("tl", "en")
                        .appendQueryParameter("text", value).appendQueryParameter("op", "translate").build()
                    startActivity(Intent(Intent.ACTION_VIEW, uri))
                    result.success("영어 번역 페이지를 열었습니다.")
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("action_failed", error.localizedMessage ?: "기능을 실행하지 못했습니다.", null)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4102) HandCameraView.permissionChanged()
        if (requestCode == 4103) {
            val request = pending ?: return
            pending = null
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) perform(request.first, request.second)
            else request.second.error("permission_denied", "전화 권한이 거부되었습니다. 설정에서 권한을 허용한 뒤 다시 인식해 주세요.", null)
        }
    }
}
