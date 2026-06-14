// ═══════════════════════════════════════════════════════════════════════════════
// DEVICE CAPABILITY DETECTION
// ═══════════════════════════════════════════════════════════════════════════════
//
// Phát hiện cấu hình thiết bị để điều chỉnh context window động:
//   - High (≥8GB RAM): 4096 tokens
//   - Medium (6GB RAM): 2048 tokens (default hiện tại)
//   - Low (≤4GB RAM): 1024 tokens (giảm crash risk)
//
// Dùng device_info_plus để lấy thông tin RAM/model thiết bị.

import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:offline_chat/core/utils/logger.dart' as log_util;

/// Phân loại sức mạnh thiết bị dựa trên RAM
enum DeviceTier {
  /// RAM ≥ 8GB: flagship devices
  high,

  /// RAM ~6GB: mid-range devices
  medium,

  /// RAM ≤ 4GB: low-end devices
  low,
}

/// Phát hiện cấu hình thiết bị tại runtime.
class DeviceCapability {
  /// Detect device tier dựa trên RAM (Android) hoặc model (iOS).
  static Future<DeviceTier> detectTier() async {
    try {
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // physicalRamSize trả về MB → convert sang GB
        final ramGB = androidInfo.physicalRamSize / 1024;
        log_util.log.d('📱 [Device] Android RAM: ${ramGB.toStringAsFixed(1)}GB');

        if (ramGB > 7) return DeviceTier.high;
        if (ramGB > 5) return DeviceTier.medium;
        return DeviceTier.low;
      }

      if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        final model = iosInfo.utsname.machine;
        log_util.log.d('📱 [Device] iOS model: $model');
        return _inferIosTier(model);
      }

      return DeviceTier.medium;
    } catch (e) {
      log_util.log.w('⚠️ [Device] Không thể detect device capability: $e');
      return DeviceTier.medium; // fallback an toàn
    }
  }

  /// Lấy context window phù hợp cho device tier.
  static int getContextWindowForTier(DeviceTier tier) {
    switch (tier) {
      case DeviceTier.high:
        return 4096; // 8GB+ RAM
      case DeviceTier.medium:
        return 2048; // 6GB RAM (default hiện tại)
      case DeviceTier.low:
        return 1024; // 4GB RAM, giảm crash risk
    }
  }

  /// Infer iOS device tier từ model name.
  /// iPhone 15 Pro / 16 series: 8GB RAM
  /// iPhone 13-14 Pro: 6GB RAM
  /// iPhone SE / older: 3-4GB RAM
  static DeviceTier _inferIosTier(String model) {
    // iPhone 15 Pro series (A17 Pro) và iPhone 16 series: 8GB
    if (model.contains('iPhone15,') || model.contains('iPhone16,')) {
      return DeviceTier.high;
    }
    // iPhone 14 Pro series: 6GB
    if (model.contains('iPhone14,') || model.contains('iPhone15,')) {
      // iPhone 15,1 - 15,3 là 6GB (không phải Pro)
      // iPhone 14,2+ (Pro) cũng 6GB
      if (model.contains('iPhone15,2') || model.contains('iPhone15,3')) {
        return DeviceTier.high; // iPhone 15 Pro/Pro Max
      }
      return DeviceTier.medium;
    }
    // iPhone 13 series: 4-6GB
    if (model.contains('iPhone13,') || model.contains('iPhone14,')) {
      return DeviceTier.medium;
    }
    // iPad Pro M-series: 8GB+
    if (model.contains('iPad') && model.contains('14,')) {
      return DeviceTier.high;
    }
    // Default: low cho các thiết bị cũ
    return DeviceTier.low;
  }
}