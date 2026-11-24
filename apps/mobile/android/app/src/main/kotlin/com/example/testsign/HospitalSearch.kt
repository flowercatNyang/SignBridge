package com.example.testsign

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/** Resolve the district on Android and pass only a search phrase to the map. */
class HospitalSearch(private val activity: Activity) {
    private val handler = Handler(Looper.getMainLooper())
    private val manager = activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private var listener: LocationListener? = null
    private var job = 0

    fun close() {
        job++
        handler.removeCallbacksAndMessages(null)
        listener?.let { runCatching { manager.removeUpdates(it) } }
        listener = null
    }

    @SuppressLint("MissingPermission")
    fun open(department: String, permitted: Boolean, result: MethodChannel.Result) {
        close()
        val token = job
        fun launch(area: String) {
            if (token != job || activity.isFinishing || activity.isDestroyed) return
            close()
            val query = listOf(area, department).filter { it.isNotBlank() }.joinToString(" ")
            val uri = Uri.parse("nmap://search").buildUpon().appendQueryParameter("query", query)
                .appendQueryParameter("appname", activity.packageName).build()
            try {
                activity.startActivity(Intent(Intent.ACTION_VIEW, uri).setPackage("com.nhn.android.nmap"))
                result.success("네이버 지도에서 ${query} 검색을 열었습니다.")
            } catch (error: android.content.ActivityNotFoundException) {
                result.error("missing_app", "네이버 지도 앱을 설치해 주세요.", null)
            }
        }
        if (!permitted) { launch(""); return }
        // Bound both acquisition and geocoding. A late callback cannot launch twice.
        handler.postDelayed({ launch("") }, 8000)
        fun resolve(location: Location) {
            Thread {
                val area = runCatching {
                    val address = Geocoder(activity, Locale.KOREA)
                        .getFromLocation(location.latitude, location.longitude, 1)?.firstOrNull()
                    listOf(address?.adminArea, address?.locality, address?.subLocality,
                        address?.thoroughfare).filterNotNull().distinct().joinToString(" ")
                }.getOrDefault("")
                handler.post { launch(area) }
            }.start()
        }
        try {
            val provider = LocationManager.NETWORK_PROVIDER
            val last = manager.getLastKnownLocation(provider)
            if (last != null && SystemClock.elapsedRealtimeNanos() - last.elapsedRealtimeNanos in 0L..120_000_000_000L) {
                resolve(last)
            } else if (manager.isProviderEnabled(provider)) {
                val callback = object : LocationListener {
                    override fun onLocationChanged(location: Location) = resolve(location)
                    override fun onProviderEnabled(name: String) {}
                    override fun onProviderDisabled(name: String) { launch("") }
                    override fun onStatusChanged(name: String?, status: Int, extras: Bundle?) {}
                }
                listener = callback
                manager.requestSingleUpdate(provider, callback, Looper.getMainLooper())
            } else launch("")
        } catch (error: RuntimeException) { launch("") }
    }
}
