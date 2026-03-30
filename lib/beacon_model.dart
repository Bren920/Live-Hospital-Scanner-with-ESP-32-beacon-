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
  });

  /// Signal quality as a 0.0–1.0 value based on typical RSSI range [-100, -30].
  double get signalQuality {
    const minRssi = -100;
    const maxRssi = -30;
    final clamped = rssi.clamp(minRssi, maxRssi);
    return (clamped - minRssi) / (maxRssi - minRssi);
  }

  /// Human-readable signal label.
  String get signalLabel {
    final q = signalQuality;
    if (q >= 0.75) return 'Excellent';
    if (q >= 0.5) return 'Good';
    if (q >= 0.25) return 'Fair';
    return 'Weak';
  }

  BeaconDevice copyWith({
    int? rssi,
    DateTime? lastSeen,
    double? distance,
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
    );
  }

  @override
  bool operator ==(Object other) => other is BeaconDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;

  /// Helper to calculate distance based on RSSI and TxPower
  /// Distance = 10 ^ ((TxPower - RSSI) / (10 * n))
  /// n is the path loss exponent (typically 2.0 to 4.0)
  /// txPowerCalibration overrides the beacon-reported txPower if provided
  static double calculateDistance(int rssi, int? txPower, {double pathLossExponent = 2.5, int? txPowerCalibration}) {
    final effectiveTxPower = txPowerCalibration ?? txPower;
    if (effectiveTxPower == null) return -1.0;
    if (rssi == 0) return -1.0;

    // Log-distance path loss model formula: Distance = 10 ^ ((TxPower - RSSI) / (10 * PathLossExponent))
    return pow(10, (effectiveTxPower - rssi) / (10.0 * pathLossExponent)).toDouble();
  }

  /// Classify the zone based on RSSI thresholds
  static String classifyZone(int rssi, {int nearThreshold = -65, int farThreshold = -85}) {
    if (rssi >= nearThreshold) return 'Near';
    if (rssi >= farThreshold) return 'Mid';
    return 'Far';
  }
}
