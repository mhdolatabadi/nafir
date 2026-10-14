import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

abstract interface class DeviceSettings {
  bool get supportsNative;
  Future<Map<String, bool>> permissions();
  Future<bool> openSettings();
  Future<String?> appVersion();
}

class PlatformDeviceSettings implements DeviceSettings {
  const PlatformDeviceSettings();
  static const _channel = MethodChannel('ir.mhdolatabadi.nafir/local_audio');
  @override
  bool get supportsNative =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  Future<Map<String, bool>> permissions() async {
    if (!supportsNative) {
      return {};
    }
    final values =
        await _channel.invokeMapMethod<String, bool>('permissionStatus');
    return values ?? {};
  }

  @override
  Future<bool> openSettings() async =>
      supportsNative &&
      await _channel.invokeMethod<bool>('openAppSettings') == true;
  @override
  Future<String?> appVersion() async {
    try {
      Map<dynamic, dynamic>? info;
      if (supportsNative) {
        info = await _channel.invokeMapMethod('appVersion');
      } else if (kIsWeb) {
        final response = await http
            .get(Uri.base.resolve('version.json'))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          if (decoded is Map) {
            info = decoded;
          }
        }
      }
      final version = info?['version'];
      final build = info?['build_number'];
      if (version is! String || version.isEmpty) {
        return null;
      }
      return build == null || '$build'.isEmpty ? version : '$version+$build';
    } catch (_) {
      return null;
    }
  }
}
