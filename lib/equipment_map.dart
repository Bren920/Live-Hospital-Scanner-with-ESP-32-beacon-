import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service that maps iBeacon Major values to friendly equipment names.
/// Fetches from the server and falls back to hardcoded defaults if offline.
class EquipmentMapService {
  EquipmentMapService._();
  static final EquipmentMapService instance = EquipmentMapService._();

  // Major → { name, category, id }
  Map<String, Map<String, String>> _equipmentMap = {
    '100': {'name': 'Portable X-Ray Machine', 'category': 'Imaging Equipment', 'id': 'EQ-2024-001'},
    '101': {'name': 'Ultrasound Scanner', 'category': 'Imaging Equipment', 'id': 'EQ-2024-002'},
    '102': {'name': 'Infusion Pump', 'category': 'Patient Care', 'id': 'EQ-2024-004'},
  };

  bool _loaded = false;

  /// Fetch equipment map from the server
  Future<void> fetchFromServer(String serverBase) async {
    try {
      final response = await http
          .get(
            Uri.parse('$serverBase/api/equipment/map'),
            headers: {'Bypass-Tunnel-Reminder': 'true'},
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        _equipmentMap = {};
        data.forEach((major, info) {
          if (info is Map) {
            _equipmentMap[major] = {
              'name': info['name']?.toString() ?? 'Unknown Equipment',
              'category': info['category']?.toString() ?? 'General',
              'id': info['id']?.toString() ?? '',
            };
          }
        });
        _loaded = true;
      }
    } catch (e) {
      // Use defaults if server unreachable
      print('Equipment map fetch failed, using defaults: $e');
    }
  }

  /// Get the friendly name for a Major value
  String getEquipmentName(int? major) {
    if (major == null) return 'Unknown Equipment';
    final entry = _equipmentMap[major.toString()];
    return entry?['name'] ?? 'Equipment #$major';
  }

  /// Get the category for a Major value
  String getCategory(int? major) {
    if (major == null) return 'General';
    final entry = _equipmentMap[major.toString()];
    return entry?['category'] ?? 'General';
  }

  /// Get all registered equipment (for the sidebar equipment list)
  List<EquipmentInfo> getAllEquipment() {
    return _equipmentMap.entries.map((e) {
      return EquipmentInfo(
        major: int.tryParse(e.key) ?? 0,
        name: e.value['name'] ?? 'Unknown',
        category: e.value['category'] ?? 'General',
        id: e.value['id'] ?? '',
      );
    }).toList();
  }

  bool get isLoaded => _loaded;
}

/// Simple data class for equipment info
class EquipmentInfo {
  final int major;
  final String name;
  final String category;
  final String id;

  const EquipmentInfo({
    required this.major,
    required this.name,
    required this.category,
    required this.id,
  });
}
