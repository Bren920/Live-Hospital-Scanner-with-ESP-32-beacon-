import 'dart:async';

import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';

import 'beacon_model.dart';

/// Service that wraps flutter_blue_plus and exposes a stream of detected beacons.
class BeaconScannerService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  BeaconScannerService._();
  static final BeaconScannerService instance = BeaconScannerService._();

  // ── Internal state ─────────────────────────────────────────────────────────
  final Map<String, BeaconDevice> _beacons = {};
  final StreamController<List<BeaconDevice>> _controller =
      StreamController<List<BeaconDevice>>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _scanningStateSub;
  bool _isScanning = false;
  
  // IP address of the laptop running the Node.js server. 
  final String _serverUrl = 'http://10.41.249.185:3000/api/scan'; 
  final String _logUrl = 'http://10.41.249.185:3000/api/log';

  // Dynamic location set from the UI
  String selectedLocation = 'Dahlia B2 Level 3';

  Timer? _uploadTimer;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Emits the current beacon list every time a new advertisement is received.
  Stream<List<BeaconDevice>> get beaconStream => _controller.stream;

  bool get isScanning => _isScanning;

  /// Start BLE scanning. Safe to call multiple times.
  Future<void> startScan() async {
    if (_isScanning) return;

    // Check adapter state
    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      throw Exception(
        'Bluetooth is off. Please enable Bluetooth and try again.',
      );
    }

    _isScanning = true;

    // Start background timer to upload detected beacons to the web dashboard
    _uploadTimer?.cancel();
    _uploadTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _uploadBeaconsToServer();
    });

    // Subscribe to scan results
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final id = result.device.remoteId.str;
        final name = result.device.platformName.isNotEmpty
            ? result.device.platformName
            : (result.advertisementData.advName.isNotEmpty
                  ? result.advertisementData.advName
                  : 'Unknown Device');

        // Parse iBeacon data if available
        final iBeaconData = _extractIBeaconData(
          result.advertisementData.manufacturerData,
        );
        final isIBeaconPacket = iBeaconData != null;

        // FILTER: Disabled for now to ensure all devices are visible for debugging
        final isEsp32Name = name.toLowerCase().contains('esp32');
        final isIBeaconName = name.toLowerCase().contains('ibeacon');

        // Only keep packets that are formatted strictly like an iBeacon/ESP32
        if (!isEsp32Name && !isIBeaconName && !isIBeaconPacket) {
          continue; // Throw away Bluetooth traffic from random laptops/tvs
        }

        // Build raw data hex string from manufacturer data
        final rawData = _buildRawDataString(result.advertisementData);

        final beacon = BeaconDevice(
          id: id,
          name: name,
          rssi: result.rssi,
          lastSeen: DateTime.now(),
          rawData: rawData,
          uuid: iBeaconData?['uuid'],
          major: iBeaconData?['major'],
          minor: iBeaconData?['minor'],
          txPower: iBeaconData?['txPower'],
          distance: BeaconDevice.calculateDistance(
            result.rssi,
            iBeaconData?['txPower'],
          ),
        );

        _beacons[id] = beacon;
      }

      // Sort by signal strength (strongest first)
      final sorted = _beacons.values.toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi));
      _controller.add(sorted);
    });

    // Start the actual scan
    // Using lowLatency for better results on some devices (like Huawei)
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
      continuousUpdates: true,
      androidScanMode: AndroidScanMode.lowLatency,
    );

    // When the built-in scan times out, restart it so we keep getting updates
    _scanningStateSub = FlutterBluePlus.isScanning.listen((scanning) async {
      if (!scanning && _isScanning) {
        // Small delay to prevent tight loops if something is wrong
        await Future.delayed(const Duration(milliseconds: 500));
        if (_isScanning) {
          try {
            await FlutterBluePlus.startScan(
              timeout: const Duration(seconds: 10),
              continuousUpdates: true,
              androidScanMode: AndroidScanMode.lowLatency,
            );
          } catch (e) {
            // Ignore errors during restart (e.g. if adapter turned off)
            print('Error restarting scan: $e');
          }
        }
      }
    });
  }

  /// Stop BLE scanning and clear the beacon list.
  Future<void> stopScan() async {
    _isScanning = false;
    await _scanSub?.cancel();
    _scanSub = null;
    await _scanningStateSub?.cancel();
    _scanningStateSub = null;
    
    _uploadTimer?.cancel();
    _uploadTimer = null;

    // Check if actually scanning before stopping to avoid errors
    if (await FlutterBluePlus.isScanning.first) {
      await FlutterBluePlus.stopScan();
    }

    // Keep beacons in memory so they remain visible after stop
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<void> _sendLog(String message) async {
    print("🏥 [HOSPITAL SCANNER LOG]: $message"); // Print locally to Cursor IDE console
    try {
      await http.post(
        Uri.parse(_logUrl),
        headers: {
          'Content-Type': 'application/json',
          'Bypass-Tunnel-Reminder': 'true'
        },
        body: jsonEncode({'message': message}),
      ).timeout(const Duration(seconds: 1));
    // ignore: empty_catches
    } catch (e) {}
  }

  Future<void> _uploadBeaconsToServer() async {
    if (_beacons.isEmpty) {
      await _sendLog("Upload timer ran, but 0 beacons detected.");
      return;
    }

    // Fetch Wi-Fi BSSID before uploading
    String? wifiBSSID;
    try {
      wifiBSSID = await NetworkInfo().getWifiBSSID();
    } catch (e) {
      print("Warning: Failed to get BSSID: $e");
    }

    int uploadsAttempted = 0;
    for (final beacon in _beacons.values) {
      if (beacon.name.toLowerCase().contains("esp32") || beacon.name.toLowerCase().contains("ibeacon")) {
        await _sendLog("Found ESP32/iBeacon! MAC: ${beacon.id}, Major: ${beacon.major}, Raw Payload: ${beacon.rawData}");
      }
      
      if (beacon.major != null) {
        uploadsAttempted++;
        try {
          // Send specific ESP32 detected Major and RSSI to the live Dashboard Server
          await http.post(
            Uri.parse(_serverUrl),
            headers: {
              'Content-Type': 'application/json',
              'Bypass-Tunnel-Reminder': 'true'
            },
            body: jsonEncode({
              'major': beacon.major,
              'rssi': beacon.rssi,
              'mac': beacon.id,
              'distance': beacon.distance,
              'location': selectedLocation, // Using standard UI selected location fallback
              'bssid': wifiBSSID,
            }),
          ).timeout(const Duration(seconds: 2));
        } catch (e) {
          await _sendLog("HTTP ERROR sending scan for Major ${beacon.major} to $_serverUrl: $e");
        }
      }
    }
    
    if (uploadsAttempted == 0) {
      await _sendLog("Checked ${_beacons.length} BLE devices, but NONE had a Major value to upload.");
    }
  }

  Map<String, dynamic>? _extractIBeaconData(
    Map<int, List<int>> manufacturerData,
  ) {
    // 0x004C is Apple's ID, commonly used for iBeacons
    // Some ESP32 libraries also use this ID or others.
    // If not found, we can check for other common IDs if needed.
    if (manufacturerData.containsKey(0x004C)) {
      final data = manufacturerData[0x004C]!;
      // Log the payload so we can see what the ESP32 is actually sending
      _sendLog("0x004C payload length: ${data.length}, data: [${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}]");

      // Often ESP32s send 21 bytes (stripped 0x02 0x15 headers) or 23 bytes (full)
      if (data.length >= 21) {
        // Assume if it's 21, the headers are stripped. If 23, they are present.
        int offset = (data[0] == 0x02 && data[1] == 0x15) ? 2 : 0;
        
        final uuidBytes = data.sublist(offset, offset + 16);
        final uuid =
            '${_toHex(uuidBytes.sublist(0, 4))}-'
            '${_toHex(uuidBytes.sublist(4, 6))}-'
            '${_toHex(uuidBytes.sublist(6, 8))}-'
            '${_toHex(uuidBytes.sublist(8, 10))}-'
            '${_toHex(uuidBytes.sublist(10, 16))}';

        final major = (data[offset + 16] << 8) + data[offset + 17];
        final minor = (data[offset + 18] << 8) + data[offset + 19];

        // TxPower is signed 8-bit
        int txPower = data[offset + 20];
        if (txPower > 127) txPower -= 256;

        return {
          'uuid': uuid.toUpperCase(),
          'major': major,
          'minor': minor,
          'txPower': txPower,
        };
      }
    }
    return null;
  }

  String _toHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  String _buildRawDataString(AdvertisementData data) {
    final parts = <String>[];

    // Manufacturer data
    data.manufacturerData.forEach((key, value) {
      final hex = value
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      parts.add('MFR[${key.toRadixString(16)}]: $hex');
    });

    // Service data
    data.serviceData.forEach((uuid, value) {
      final hex = value
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      parts.add('SVC[$uuid]: $hex');
    });

    return parts.isEmpty ? '—' : parts.join(' | ');
  }
}
