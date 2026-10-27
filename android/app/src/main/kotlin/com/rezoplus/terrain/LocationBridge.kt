package com.rezoplus.terrain

import android.Manifest
import android.content.pm.PackageManager
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.*
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class LocationBridge : FlutterActivity() {
    private val channelName = "rezoplus/location"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestLocation" -> {
                        val granted =
                            ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) ==
                                PackageManager.PERMISSION_GRANTED &&
                            ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) ==
                                PackageManager.PERMISSION_GRANTED

                        if (!granted) {
                            result.error("PERMISSION_DENIED", "Permission GPS non accordée", null)
                            return@setMethodCallHandler
                        }

                        requestNativeLocation(result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestNativeLocation(result: MethodChannel.Result) {
        val fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)

        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 5000L)
            .setMinUpdateDistanceMeters(5f)
            .setWaitForAccurateLocation(true)
            .build()

        val callback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                val loc = locationResult.lastLocation ?: return
                result.success(mapOf(
                    "latitude" to loc.latitude,
                    "longitude" to loc.longitude,
                    "accuracy" to loc.accuracy,
                    "speed" to loc.speed,
                    "time" to loc.time
                ))
                fusedLocationClient.removeLocationUpdates(this)
            }
        }

        val permissionCheck = ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
        if (permissionCheck == PackageManager.PERMISSION_GRANTED) {
            fusedLocationClient.requestLocationUpdates(request, callback, Looper.getMainLooper())
        } else {
            result.error("PERMISSION_DENIED", "Permission GPS non accordée", null)
        }
    }
}
