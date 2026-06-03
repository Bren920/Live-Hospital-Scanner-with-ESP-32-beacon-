import 'dart:math';

/// Represents a single detected Bluetooth beacon/device.
class BeaconDevice {
  final String id; // MAC address or platform-specific device ID
  final String name; // Advertised name (may be empty)
  final int rssi; // Signal strength in dBm (more negative = farther away)
  final DateTime lastSeen;
  final String rawData; // Hex string of manufacturer/service data (if any)

  // iBeacon specific fields (nullable as not all devices are iBeacons)
  final String? uuid;
  final int? major;
  final int? minor;
  final int? txPower;
  final double? distance; // Estimated distance in meters

  // User-friendly fields
  final String? equipmentName; // e.g. "Portable X-Ray Machine"
  final String? equipmentCategory; // e.g. "Imaging Equipment"

  const BeaconDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.lastSeen,
    required this.rawData,
    this.uuid,
    this.major,
    this.minor,
    this.txPower,
    this.distance,
    this.equipmentName,
    this.equipmentCategory,
  });

  /// Signal quality as a 0.0–1.0 value based on typical RSSI range [-100, -30].
  double get signalQuality {
    const minRssi = -100;
    const maxRssi = -30;
    final clamped = rssi.clamp(minRssi, maxRssi);
    return (clamped - minRssi) / (maxRssi - minRssi);
  }

  /// Human-readable zone label based on estimated distance.
  /// Near: 0-1m, Mid: 1-3m, Far: > 3m
  String get signalLabel {
    if (distance == null || distance! < 0) return 'Far';
    if (distance! <= 1.0) return 'Near';
    if (distance! <= 3.0) return 'Mid';
    return 'Far';
  }

  /// User-friendly proximity guide based on estimated distance.
  String get proximityGuide {
    if (distance == null || distance! < 0) return 'Calculating...';
    final d = distance!;
    if (d < 0.5) return 'Right next to you!';
    if (d < 1.0) return 'Very close — look around you';
    if (d < 3.0) return 'Getting closer, keep moving';
    if (d < 8.0) return 'Nearby — walk towards the signal';
    if (d < 15.0) return 'In the area — keep searching';
    return 'Far away — try another area';
  }

  /// Friendly display name — equipment name if available, else fallback
  String get displayName {
    if (equipmentName != null && equipmentName!.isNotEmpty) {
      return equipmentName!;
    }
    if (name.isNotEmpty && name != 'Unknown Device') {
      return name;
    }
    return 'Unknown Equipment';
  }

  /// Formatted distance string for display
  String get distanceText {
    if (distance == null || distance! < 0) return '—';
    if (distance! < 1.0) {
      return '${(distance! * 100).toStringAsFixed(0)} cm';
    }
    return '${distance!.toStringAsFixed(1)} m';
  }

  BeaconDevice copyWith({
    int? rssi,
    DateTime? lastSeen,
    double? distance,
    String? equipmentName,
    String? equipmentCategory,
  }) {
    return BeaconDevice(
      id: id,
      name: name,
      rssi: rssi ?? this.rssi,
      lastSeen: lastSeen ?? this.lastSeen,
      rawData: rawData,
      uuid: uuid,
      major: major,
      minor: minor,
      txPower: txPower,
      distance: distance ?? this.distance,
      equipmentName: equipmentName ?? this.equipmentName,
      equipmentCategory: equipmentCategory ?? this.equipmentCategory,
    );
  }

  @override
  bool operator ==(Object other) => other is BeaconDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;

  /// Helper to calculate distance based on RSSI and TxPower using the
  /// Log-Distance Path Loss Model:
  ///   Distance = 10 ^ ((TxPower - RSSI) / (10 * n))
  ///
  /// where:
  ///   - TxPower = RSSI measured at exactly 1 meter (calibration reference)
  ///   - RSSI = current signal strength reading (smoothed via SMA)
  ///   - n = path loss exponent (2.0 = open space, 2.5-4.0 = indoors)
  ///
  /// txPowerCalibration overrides the beacon-reported txPower if provided.
  /// Result is clamped to [0.1m, 100m] to avoid physically impossible values.
  static double calculateDistance(int rssi, int? txPower, {double pathLossExponent = 2.5, int? txPowerCalibration}) {
    final effectiveTxPower = txPowerCalibration ?? txPower;
    if (effectiveTxPower == null) return -1.0;
    if (rssi == 0) return -1.0;
    if (pathLossExponent <= 0) return -1.0;

    // If RSSI is stronger than txPower, the device is less than 1m away.
    // The formula still handles this correctly (result < 1.0).

    // Log-distance path loss model formula
    final distance = pow(10, (effectiveTxPower - rssi) / (10.0 * pathLossExponent)).toDouble();

    // Clamp to physically reasonable BLE range:
    // - Minimum 0.1m (10cm) — closer readings are noise
    // - Maximum 100m — beyond practical BLE range
    return distance.clamp(0.1, 100.0);
  }

  /// Classify the zone based on RSSI thresholds
  static String classifyZone(int rssi, {int nearThreshold = -65, int farThreshold = -89}) {
    if (rssi >= nearThreshold) return 'Near';
    if (rssi >= farThreshold) return 'Mid';
    return 'Far';
  }
}
