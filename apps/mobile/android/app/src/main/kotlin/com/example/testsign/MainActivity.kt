package com.example.testsign

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.provider.ContactsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity: FlutterActivity() {
    private var pending: Pair<MethodCall, MethodChannel.Result>? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "signbridge/hand-camera", HandCameraView.Factory(this, flutterEngine.dartExecutor.binaryMessenger))
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

                    val numbers = linkedSetOf<String>()
                    contentResolver.query(ContactsContract.CommonDataKinds.Phone.CONTENT_URI, arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER),
                        "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} = ?", arrayOf("엄마"), null)?.use { cursor ->
                        while (cursor.moveToNext()) {
                            val number = cursor.getString(0)?.replace(Regex("[\\s()-]"), "") ?: ""
                            if (Regex("^\\+?[0-9]{3,15}$").matches(number)) numbers.add(number)
                        }
                    }
                    require(numbers.isNotEmpty()) { "전화번호부에서 '엄마'의 전화번호를 찾지 못했습니다." }
                    require(numbers.size == 1) { "'엄마'의 번호가 여러 개입니다. 전화번호부에서 사용할 번호 하나만 남겨 주세요." }
                    val number = numbers.single()
                    require(number != "112" && number != "119") { "엄마 연락처의 전화번호를 확인해 주세요." }
                    startActivity(Intent(Intent.ACTION_CALL, Uri.fromParts("tel", number, null)))
                    result.success("전화번호부의 엄마에게 발신을 요청했습니다.")
                }
                "volumeUp", "volumeDown" -> {
                    val audio = getSystemService(AUDIO_SERVICE) as AudioManager
                    check(!audio.isVolumeFixed) { "이 기기는 볼륨 조절을 지원하지 않습니다." }
                    val before = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
                    audio.adjustStreamVolume(AudioManager.STREAM_MUSIC,
                        if (call.method == "volumeUp") AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER,
                        AudioManager.FLAG_SHOW_UI)
                    val after = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
                    result.success(if (before == after) "미디어 볼륨이 이미 한계에 도달했습니다."
                        else "미디어 볼륨을 ${if (call.method == "volumeUp") "올렸습니다" else "내렸습니다"}. ($after/${audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)})")
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
            if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) perform(request.first, request.second)
            else request.second.error("permission_denied", "엄마에게 전화하려면 연락처와 전화 권한을 허용해 주세요.", null)
        }
    }
}
