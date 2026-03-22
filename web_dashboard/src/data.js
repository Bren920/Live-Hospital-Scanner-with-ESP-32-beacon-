export const mockEquipment = [
  { id: 'EQ-2024-001', name: 'Portable X-Ray Machine', beaconId: 'BCN-4521', category: 'Imaging Equipment', status: 'Active', location: 'Emergency Ward', lastSeen: '2 minutes ago' },
  { id: 'EQ-2024-002', name: 'Ultrasound Scanner', beaconId: 'BCN-4522', category: 'Imaging Equipment', status: 'Active', location: 'Radiology', lastSeen: '15 minutes ago' },
  { id: 'EQ-2024-003', name: 'Defibrillator', beaconId: 'BCN-4523', category: 'Emergency Equipment', status: 'Active', location: 'ICU - Room 204', lastSeen: '1 hour ago' },
  { id: 'EQ-2024-004', name: 'Infusion Pump', beaconId: 'BCN-4524', category: 'Patient Care', status: 'Active', location: 'Pediatric Ward', lastSeen: '3 hours ago' },
  { id: 'EQ-2024-005', name: 'Wheelchair', beaconId: 'BCN-4525', category: 'Respiratory Equipment', status: 'Active', location: 'Corridor 3A', lastSeen: '5 hours ago' },
  { id: 'EQ-2024-006', name: 'ECG Monitor', beaconId: 'BCN-4526', category: 'Monitoring Equipment', status: 'Active', location: 'Cardiology', lastSeen: '12 minutes ago' },
  { id: 'EQ-2024-007', name: 'Patient Monitor', beaconId: 'BCN-4527', category: 'Monitoring Equipment', status: 'Active', location: 'Surgery - OR 2', lastSeen: '30 minutes ago' },
  { id: 'EQ-2024-008', name: 'Syringe Pump', beaconId: 'BCN-4528', category: 'Patient Care', status: 'Inactive', location: 'ICU - Room 201', lastSeen: '8 minutes ago' },
  { id: 'EQ-2024-009', name: 'Blood Pressure Monitor', beaconId: 'BCN-4529', category: 'Monitoring Equipment', status: 'Active', location: 'General Ward', lastSeen: '45 minutes ago' },
  { id: 'EQ-2024-010', name: 'IV Stand', beaconId: 'BCN-4530', category: 'Patient Care', status: 'Active', location: 'Maternity', lastSeen: '10 minutes ago' },
];

export const mockMetrics = {
  totalEquipment: 1247,
  activeBeacons: 1185,
  missingItems: 3
};
