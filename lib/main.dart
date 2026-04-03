import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';

import 'beacon_model.dart';
import 'beacon_scanner_service.dart';
import 'equipment_map.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(const HospitalScannerApp());
}

// ─────────────────────────────────────────────────────────────────────────────
//  Background Service Setup
// ─────────────────────────────────────────────────────────────────────────────

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'hospital_scanner_channel',
      initialNotificationTitle: 'Hospital Scanner',
      initialNotificationContent: 'Running in background',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Start the beacon scanner in the background isolate
  final scanner = BeaconScannerService.instance;
  await scanner.loadServerUrl();
  await scanner.startScan();
  
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: "Hospital Scanner Active",
      content: "Scanning for medical equipment...",
    );
  }
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
      title: 'Hospital Equipment Tracker',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00C853),
          surface: const Color(0xFFF5F7FA),
        ),
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
  final _equipmentMap = EquipmentMapService.instance;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<BeaconDevice> _beacons = [];
  bool _isScanning = false;
  String _statusMessage = 'Ready to scan';

  // Equipment filter (null = show all)
  int? _selectedMajorFilter;
  String? _selectedEquipmentName;

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

      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
        Permission.locationAlways,
      ].request();

      var locationServiceStatus =
          await Permission.locationWhenInUse.serviceStatus;
      if (locationServiceStatus.isDisabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please enable Location Services for equipment scanning',
              ),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }

      final criticalDenied = statuses[Permission.bluetoothScan] == PermissionStatus.denied ||
                             statuses[Permission.bluetoothConnect] == PermissionStatus.denied ||
                             statuses[Permission.locationWhenInUse] == PermissionStatus.denied;

      if (criticalDenied) {
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
          'This app needs Bluetooth and Location permissions to find hospital equipment. Please grant them in settings.',
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
        _statusMessage = 'Scanning for equipment…';
        _isScanning = true;
      });
      _pulseController.repeat(reverse: true);

      List<BeaconDevice> latestBeacons = [];
      _beaconSub = _scanner.beaconStream.listen((beacons) {
        latestBeacons = beacons;
      });

      _uiUpdateTimer?.cancel();
      _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
        if (mounted && _isScanning) {
          final isCurrentlyScanning = await FlutterBluePlus.isScanning.first;
          
          setState(() {
            _beacons = latestBeacons;
            
            if (isCurrentlyScanning) {
              _statusMessage = 'Scanning for equipment…';
              if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
            } else {
              _statusMessage = 'Saving battery…';
              _pulseController.stop();
            }
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
            Text('Server Settings', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the server address to sync with the web dashboard.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Server Address',
                hintText: 'https://your-app.onrender.com',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: const Icon(Icons.link),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
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
                    content: Text('✅ Server updated to: $url'),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.55,
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Equipment Icon + Name
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: _getCategoryColor(beacon.equipmentCategory).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    _getCategoryIcon(beacon.equipmentCategory),
                    color: _getCategoryColor(beacon.equipmentCategory),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        beacon.displayName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        beacon.equipmentCategory ?? 'Medical Equipment',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blueGrey[400],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Distance Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _getDistanceColor(beacon.distance).withValues(alpha: 0.08),
                    _getDistanceColor(beacon.distance).withValues(alpha: 0.03),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _getDistanceColor(beacon.distance).withValues(alpha: 0.15),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    _getDistanceIcon(beacon.distance),
                    size: 40,
                    color: _getDistanceColor(beacon.distance),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    beacon.distanceText,
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: _getDistanceColor(beacon.distance),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    beacon.proximityGuide,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.blueGrey[500],
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Signal strength indicator
            Row(
              children: [
                Text(
                  'Signal Strength',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blueGrey[400],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  beacon.signalLabel,
                  style: TextStyle(
                    fontSize: 13,
                    color: _getSignalColor(beacon.signalQuality),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: beacon.signalQuality,
                minHeight: 8,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(
                  _getSignalColor(beacon.signalQuality),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Filter helpers ─────────────────────────────────────────────────────────

  List<BeaconDevice> get _filteredBeacons {
    if (_selectedMajorFilter == null) return _beacons;
    return _beacons.where((b) => b.major == _selectedMajorFilter).toList();
  }

  void _clearFilter() {
    setState(() {
      _selectedMajorFilter = null;
      _selectedEquipmentName = null;
    });
  }

  void _selectEquipment(EquipmentInfo equipment) {
    setState(() {
      _selectedMajorFilter = equipment.major;
      _selectedEquipmentName = equipment.name;
    });
    Navigator.pop(context); // close drawer
  }

  // ── Color/icon helpers ─────────────────────────────────────────────────────

  Color _getSignalColor(double quality) {
    if (quality >= 0.75) return const Color(0xFF00C853);
    if (quality >= 0.5) return const Color(0xFFFFA000);
    if (quality >= 0.25) return const Color(0xFFFF6D00);
    return Colors.redAccent;
  }

  Color _getDistanceColor(double? distance) {
    if (distance == null || distance < 0) return Colors.grey;
    if (distance < 1.0) return const Color(0xFF00C853);
    if (distance < 5.0) return const Color(0xFF0288D1);
    if (distance < 15.0) return const Color(0xFFFFA000);
    return Colors.redAccent;
  }

  IconData _getDistanceIcon(double? distance) {
    if (distance == null || distance < 0) return Icons.help_outline;
    if (distance < 1.0) return Icons.near_me;
    if (distance < 5.0) return Icons.directions_walk;
    if (distance < 15.0) return Icons.explore;
    return Icons.map;
  }

  IconData _getCategoryIcon(String? category) {
    switch (category) {
      case 'Imaging Equipment':
        return Icons.camera_alt_outlined;
      case 'Patient Care':
        return Icons.medical_services_outlined;
      case 'Emergency Equipment':
        return Icons.emergency_outlined;
      case 'Monitoring Equipment':
        return Icons.monitor_heart_outlined;
      case 'Respiratory Equipment':
        return Icons.air_outlined;
      default:
        return Icons.local_hospital_outlined;
    }
  }

  Color _getCategoryColor(String? category) {
    switch (category) {
      case 'Imaging Equipment':
        return const Color(0xFF5C6BC0);
      case 'Patient Care':
        return const Color(0xFF00897B);
      case 'Emergency Equipment':
        return Colors.redAccent;
      case 'Monitoring Equipment':
        return const Color(0xFF0288D1);
      case 'Respiratory Equipment':
        return const Color(0xFF7B1FA2);
      default:
        return const Color(0xFF00C853);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final displayBeacons = _filteredBeacons;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF5F7FA),
      
      // ── Sidebar / Drawer ─────────────────────────────────────────────────
      drawer: _buildDrawer(),
      
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── App Bar ─────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    // Hamburger menu
                    GestureDetector(
                      onTap: () => _scaffoldKey.currentState?.openDrawer(),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.menu_rounded, color: Colors.black87, size: 22),
                      ),
                    ),
                    const Spacer(),
                    // Title
                    const Text(
                      'Hospital Equipment\nTracker',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                        height: 1.2,
                      ),
                    ),
                    const Spacer(),
                    // Scan toggle
                    GestureDetector(
                      onTap: _toggleScan,
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _isScanning ? const Color(0xFF00C853) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: _isScanning
                                  ? const Color(0xFF00C853).withValues(alpha: 0.3)
                                  : Colors.black.withValues(alpha: 0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          _isScanning ? Icons.stop_rounded : Icons.search_rounded,
                          color: _isScanning ? Colors.white : Colors.black87,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Scanning indicator ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Center(
                      child: ScaleTransition(
                        scale: _pulseAnimation,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isScanning
                                ? const Color(0xFF00C853)
                                : Colors.grey[300],
                            boxShadow: _isScanning
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF00C853).withValues(alpha: 0.35),
                                      blurRadius: 20,
                                      spreadRadius: 3,
                                    ),
                                  ]
                                : [],
                          ),
                          child: Icon(
                            _isScanning ? Icons.radar : Icons.bluetooth_disabled,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isScanning ? 'Scanning for equipment…' : 'Tap search to start',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blueGrey[400],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Filter banner (when equipment selected) ─────────────────────
            if (_selectedEquipmentName != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0288D1).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF0288D1).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.filter_alt_rounded, size: 18, color: Color(0xFF0288D1)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Finding: $_selectedEquipmentName',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0288D1),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _clearFilter,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0288D1).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Clear',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0288D1),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Section header ──────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    const Text(
                      'Nearby Equipment',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C853).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
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

            const SliverToBoxAdapter(child: SizedBox(height: 4)),

            // ── Equipment list ──────────────────────────────────────────────
            if (displayBeacons.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((_, i) {
                    return Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                      child: _EquipmentCard(
                        beacon: displayBeacons[i],
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

  // ── Drawer / Sidebar ───────────────────────────────────────────────────────

  Widget _buildDrawer() {
    final allEquipment = _equipmentMap.getAllEquipment();

    return Drawer(
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF00C853), Color(0xFF00E676)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.local_hospital, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Hospital Equipment\nTracker',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // All Equipment option
            _DrawerTile(
              icon: Icons.dashboard_rounded,
              label: 'All Equipment',
              isSelected: _selectedMajorFilter == null,
              onTap: () {
                _clearFilter();
                Navigator.pop(context);
              },
            ),

            // Divider with section title
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(
                'FIND EQUIPMENT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.blueGrey[300],
                  letterSpacing: 1.2,
                ),
              ),
            ),

            // Equipment list
            Expanded(
              child: allEquipment.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 40, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text(
                              'No equipment registered.\nAdd equipment from the web dashboard.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: allEquipment.length,
                      itemBuilder: (_, i) {
                        final eq = allEquipment[i];
                        final isSelected = _selectedMajorFilter == eq.major;
                        return _DrawerTile(
                          icon: _getCategoryIcon(eq.category),
                          label: eq.name,
                          subtitle: eq.category,
                          isSelected: isSelected,
                          onTap: () => _selectEquipment(eq),
                        );
                      },
                    ),
            ),

            const Divider(height: 1),

            // Server Settings
            _DrawerTile(
              icon: Icons.settings_rounded,
              label: 'Server Settings',
              onTap: () {
                Navigator.pop(context);
                _showServerUrlDialog();
              },
            ),

            const SizedBox(height: 8),
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
            _isScanning ? Icons.radar : Icons.search_off_rounded,
            size: 56,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 12),
          Text(
            _isScanning
                ? 'Searching for nearby equipment…'
                : 'Tap search button to start',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
          if (_selectedEquipmentName != null) ...[
            const SizedBox(height: 8),
            Text(
              'No "$_selectedEquipmentName" found nearby',
              style: TextStyle(color: Colors.blueGrey[300], fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Drawer tile widget
// ─────────────────────────────────────────────────────────────────────────────

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool isSelected;
  final VoidCallback? onTap;

  const _DrawerTile({
    required this.icon,
    required this.label,
    this.subtitle,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: isSelected
            ? const Color(0xFF00C853).withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: isSelected ? const Color(0xFF00C853) : Colors.blueGrey[400],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? const Color(0xFF00695C) : Colors.black87,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blueGrey[300],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF00C853),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Equipment card widget (simplified, no technical jargon)
// ─────────────────────────────────────────────────────────────────────────────

class _EquipmentCard extends StatelessWidget {
  final BeaconDevice beacon;
  final VoidCallback? onTap;

  const _EquipmentCard({required this.beacon, this.onTap});

  Color get _signalColor {
    final q = beacon.signalQuality;
    if (q >= 0.75) return const Color(0xFF00C853);
    if (q >= 0.5) return const Color(0xFFFFA000);
    if (q >= 0.25) return const Color(0xFFFF6D00);
    return Colors.redAccent;
  }

  IconData get _categoryIcon {
    switch (beacon.equipmentCategory) {
      case 'Imaging Equipment':
        return Icons.camera_alt_outlined;
      case 'Patient Care':
        return Icons.medical_services_outlined;
      case 'Emergency Equipment':
        return Icons.emergency_outlined;
      case 'Monitoring Equipment':
        return Icons.monitor_heart_outlined;
      case 'Respiratory Equipment':
        return Icons.air_outlined;
      default:
        return Icons.local_hospital_outlined;
    }
  }

  Color get _categoryColor {
    switch (beacon.equipmentCategory) {
      case 'Imaging Equipment':
        return const Color(0xFF5C6BC0);
      case 'Patient Care':
        return const Color(0xFF00897B);
      case 'Emergency Equipment':
        return Colors.redAccent;
      case 'Monitoring Equipment':
        return const Color(0xFF0288D1);
      case 'Respiratory Equipment':
        return const Color(0xFF7B1FA2);
      default:
        return const Color(0xFF00C853);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Category icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _categoryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _categoryIcon,
                    color: _categoryColor,
                    size: 24,
                  ),
                ),

                const SizedBox(width: 14),

                // Name + proximity guide
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        beacon.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        beacon.proximityGuide,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey[400],
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Distance display
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      beacon.distanceText,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _signalColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Small signal dot
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _signalColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          beacon.signalLabel,
                          style: TextStyle(
                            fontSize: 10,
                            color: _signalColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: Colors.grey[300], size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
