import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'beacon_model.dart';
import 'beacon_scanner_service.dart';

void main() {
  runApp(const HospitalScannerApp());
}

// ─────────────────────────────────────────────────────────────────────────────
//  App root
// ─────────────────────────────────────────────────────────────────────────────

class HospitalScannerApp extends StatelessWidget {
  const HospitalScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Hospital Scanner',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00C853)),
        fontFamily: 'Roboto',
      ),
      home: const EquipmentTrackerScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main screen
// ─────────────────────────────────────────────────────────────────────────────

class EquipmentTrackerScreen extends StatefulWidget {
  const EquipmentTrackerScreen({super.key});

  @override
  State<EquipmentTrackerScreen> createState() => _EquipmentTrackerScreenState();
}

class _EquipmentTrackerScreenState extends State<EquipmentTrackerScreen>
    with SingleTickerProviderStateMixin {
  final _scanner = BeaconScannerService.instance;

  List<BeaconDevice> _beacons = [];
  bool _isScanning = false;
  String _statusMessage = 'Ready to scan';
  DateTime? _lastUpdated;

  // Pulse animation for the scanning indicator
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  StreamSubscription<List<BeaconDevice>>? _beaconSub;
  Timer? _uiUpdateTimer;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Load saved server URL, then start scanning
    _scanner.loadServerUrl().then((_) {
      _requestPermissionsAndScan();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _beaconSub?.cancel();
    _uiUpdateTimer?.cancel();
    _scanner.stopScan();
    super.dispose();
  }

  // ── Permission + scan ──────────────────────────────────────────────────────

  Future<void> _requestPermissionsAndScan() async {
    try {
      setState(() => _statusMessage = 'Requesting permissions…');

      // Request Bluetooth + location permissions
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      // Check if location services are enabled (crucial for some Android devices)
      var locationServiceStatus =
          await Permission.locationWhenInUse.serviceStatus;
      if (locationServiceStatus.isDisabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please enable Location Services (GPS) for Bluetooth scanning',
              ),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }

      final anyDenied = statuses.values.any(
        (s) =>
            s == PermissionStatus.denied ||
            s == PermissionStatus.permanentlyDenied,
      );

      if (anyDenied) {
        setState(() => _statusMessage = 'Permissions denied.');
        if (mounted) {
          _showPermissionDialog();
        }
        return;
      }

      await _startScan();
    } catch (e) {
      setState(() => _statusMessage = 'Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Scan error: $e')));
      }
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permissions Required'),
        content: const Text(
          'This app needs Bluetooth and Location permissions to scan for beacons. Please grant them in settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _startScan() async {
    try {
      setState(() {
        _statusMessage = 'Scanning for beacons…';
        _isScanning = true;
      });
      _pulseController.repeat(reverse: true);

      List<BeaconDevice> latestBeacons = [];
      _beaconSub = _scanner.beaconStream.listen((beacons) {
        latestBeacons = beacons;
      });

      _uiUpdateTimer?.cancel();
      _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (mounted && _isScanning) {
          setState(() {
            _beacons = latestBeacons;
            _lastUpdated = DateTime.now();
          });
        }
      });

      await _scanner.startScan();
    } catch (e) {
      setState(() {
        _statusMessage = e.toString();
        _isScanning = false;
      });
      _pulseController.stop();
      _uiUpdateTimer?.cancel();
    }
  }

  Future<void> _stopScan() async {
    await _beaconSub?.cancel();
    _beaconSub = null;
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = null;
    await _scanner.stopScan();
    setState(() {
      _isScanning = false;
      _statusMessage = 'Scan stopped';
    });
    _pulseController.stop(canceled: false);
  }

  void _toggleScan() {
    if (_isScanning) {
      _stopScan();
    } else {
      _startScan();
    }
  }

  void _showServerUrlDialog() {
    final controller = TextEditingController(text: _scanner.serverUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.dns, color: Color(0xFF00C853), size: 24),
            SizedBox(width: 8),
            Text('Server URL', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the URL of your Hospital Asset Server. This enables the app to sync with the dashboard from any network.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Server URL',
                hintText: 'https://your-app.onrender.com',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.link),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: 8),
            Text(
              'Examples:\n• Local: http://192.168.1.100:3000\n• Cloud: https://hospital-app.onrender.com',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Save'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00C853),
            ),
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isEmpty) return;
              await _scanner.setServerUrl(url);
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ Server URL updated to: $url'),
                    backgroundColor: const Color(0xFF00C853),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _showBeaconDetails(BeaconDevice beacon) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                beacon.name.isEmpty ? 'Unknown Beacon' : beacon.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'ID: ${beacon.id}',
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'monospace',
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),
              _buildDetailRow('RSSI', '${beacon.rssi} dBm'),
              _buildDetailRow('Zone', BeaconDevice.classifyZone(beacon.rssi, nearThreshold: _scanner.nearThreshold, farThreshold: _scanner.farThreshold)),
              if (beacon.txPower != null)
                _buildDetailRow('Tx Power', '${beacon.txPower} dBm'),
              if (beacon.distance != null)
                _buildDetailRow(
                  'Est. Distance',
                  '${beacon.distance!.toStringAsFixed(2)} m',
                ),
              const Divider(height: 32),
              const Text(
                'iBeacon Data',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              if (beacon.uuid != null) ...[
                _buildDetailRow('UUID', beacon.uuid!),
                _buildDetailRow('Major', '${beacon.major}'),
                _buildDetailRow('Minor', '${beacon.minor}'),
              ] else
                const Text(
                  'No iBeacon data detected',
                  style: TextStyle(color: Colors.grey),
                ),
              const Divider(height: 32),
              const Text(
                'Raw Manufacturer Data',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  beacon.rawData,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _filterByEsp32 = false;

  // ── Helpers ────────────────────────────────────────────────────────────────

  String get _lastUpdatedText {
    if (_lastUpdated == null) return '—';
    final diff = DateTime.now().difference(_lastUpdated!);
    if (diff.inSeconds < 5) return 'Just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    return '${diff.inMinutes}m ago';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  List<BeaconDevice> get _filteredBeacons {
    if (!_filterByEsp32) return _beacons;
    return _beacons.where((b) {
      final name = b.name.toLowerCase();
      return name.contains('esp32') || b.major != null;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final displayBeacons = _filteredBeacons;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 0,
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Header ───────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(),
                    Row(
                      children: [
                        // Server Settings button
                        GestureDetector(
                          onTap: _showServerUrlDialog,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey[100],
                            ),
                            child: Icon(Icons.settings, color: Colors.grey[800], size: 20),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey[100],
                          ),
                          child: Icon(Icons.bluetooth, color: Colors.grey[800]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Equipment Tracker',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Hospital BLE Beacon Monitor',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.blueGrey[300],
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Pulsing indicator + stats row ────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 24,
                ),
                child: Column(
                  children: [
                    // Pulse circle
                    Center(
                      child: ScaleTransition(
                        scale: _pulseAnimation,
                        child: Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isScanning
                                ? const Color(0xFF00C853)
                                : Colors.grey[300],
                            boxShadow: _isScanning
                                ? [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF00C853,
                                      ).withValues(alpha: 0.4),
                                      blurRadius: 24,
                                      spreadRadius: 4,
                                    ),
                                  ]
                                : [],
                          ),
                          child: Icon(
                            _isScanning
                                ? Icons.radar
                                : Icons.bluetooth_disabled,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Stats row
                    IntrinsicHeight(
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildStatChip(
                              label: 'Active Beacons',
                              value: '${_beacons.length}',
                              color: const Color(0xFF0288D1),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatChip(
                              label: 'Last Updated',
                              value: _lastUpdatedText,
                              color: const Color(0xFF00897B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Status + Controls ────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _statusMessage,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blueGrey[400],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        // Toggle Filter
                        FilterChip(
                          label: const Text('ESP32 Only'),
                          selected: _filterByEsp32,
                          onSelected: (val) {
                            setState(() => _filterByEsp32 = val);
                          },
                          selectedColor: const Color(
                            0xFF00C853,
                          ).withValues(alpha: 0.2),
                          checkmarkColor: const Color(0xFF00C853),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: _filterByEsp32
                                ? const Color(0xFF00695C)
                                : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Prominent Scan Button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _toggleScan,
                        icon: Icon(
                          _isScanning ? Icons.stop : Icons.search,
                          size: 20,
                        ),
                        label: Text(
                          _isScanning ? 'Stop Scanning' : 'Start Scanning',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: _isScanning
                              ? Colors.redAccent
                              : const Color(0xFF00C853),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // ── Divider ───────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    const Text(
                      'Detected Beacons',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C853).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${displayBeacons.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00695C),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 8)),

            // ── Beacon list ───────────────────────────────────────────────────
            if (displayBeacons.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((_, i) {
                    return Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                      child: _BeaconCard(
                        beacon: displayBeacons[i],
                        nearThreshold: _scanner.nearThreshold,
                        farThreshold: _scanner.farThreshold,
                        onTap: () => _showBeaconDetails(displayBeacons[i]),
                      ),
                    );
                  }, childCount: displayBeacons.length),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isScanning ? Icons.radar : Icons.bluetooth_searching,
            size: 56,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 12),
          Text(
            _isScanning ? 'Searching for beacons…' : 'Tap Scan to start',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.blueGrey[500],
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Single beacon card widget
// ─────────────────────────────────────────────────────────────────────────────

class _BeaconCard extends StatelessWidget {
  final BeaconDevice beacon;
  final int nearThreshold;
  final int farThreshold;
  final VoidCallback? onTap;
  const _BeaconCard({required this.beacon, this.nearThreshold = -65, this.farThreshold = -85, this.onTap});

  Color get _signalColor {
    final q = beacon.signalQuality;
    if (q >= 0.75) return const Color(0xFF00C853);
    if (q >= 0.5) return const Color(0xFFFFA000);
    if (q >= 0.25) return const Color(0xFFFF6D00);
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: const Color(0xFFF8FAFB),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.08)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Top row: name + RSSI badge ──────────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _signalColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.bluetooth,
                        color: _signalColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            beacon.name.isNotEmpty
                                ? beacon.name
                                : 'Unknown Device',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            beacon.id,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blueGrey[400],
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _signalColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${beacon.rssi} dBm',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _signalColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _ZoneBadge(zone: BeaconDevice.classifyZone(beacon.rssi, nearThreshold: nearThreshold, farThreshold: farThreshold)),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right,
                      color: Colors.grey[400],
                      size: 20,
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // ── Signal bar ──────────────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: beacon.signalQuality,
                          minHeight: 6,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _signalColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      beacon.signalLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: _signalColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),

                // ── iBeacon / Raw Data Preview ─────────────────────────────────
                if (beacon.uuid != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sensors, size: 10, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text(
                          'iBeacon: Major ${beacon.major} | Minor ${beacon.minor}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.blue,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (beacon.rawData != '—') ...[
                  const SizedBox(height: 8),
                  Text(
                    beacon.rawData,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.blueGrey[300],
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Zone badge widget
// ─────────────────────────────────────────────────────────────────────────────

class _ZoneBadge extends StatelessWidget {
  final String zone;
  const _ZoneBadge({required this.zone});

  Color get _color {
    switch (zone) {
      case 'Near':
        return const Color(0xFF00C853);
      case 'Mid':
        return const Color(0xFFFFA000);
      case 'Far':
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Text(
        zone,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _color,
        ),
      ),
    );
  }
}

