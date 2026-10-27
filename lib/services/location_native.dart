import 'package:flutter/services.dart';

class LocationNativeBridge {
  static const MethodChannel _channel = MethodChannel('rezoplus/location');

  static Future<Map<String, dynamic>?> getCurrentLocation() async {
    try {
      final result = await _channel.invokeMethod('requestLocation');
      if (result is Map) {
        return result.cast<String, dynamic>();
      }
      return null;
    } on PlatformException {
      return null;
    }
  }
}
