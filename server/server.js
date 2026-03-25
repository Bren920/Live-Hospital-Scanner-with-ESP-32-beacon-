const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// Serve the built React dashboard from the public folder
app.use(express.static(path.join(__dirname, 'public')));

// 1. Hardware Mapping Repository
const EQUIPMENT_FILE = path.join(__dirname, 'equipmentMap.json');
let equipmentMap = {};

try {
  if (fs.existsSync(EQUIPMENT_FILE)) {
    equipmentMap = JSON.parse(fs.readFileSync(EQUIPMENT_FILE, 'utf8'));
  } else {
    equipmentMap = {
      "100": { id: 'EQ-2024-001', name: 'Portable X-Ray Machine', beaconId: 'BCN-4521', category: 'Imaging Equipment' },
      "101": { id: 'EQ-2024-002', name: 'Ultrasound Scanner', beaconId: 'BCN-4522', category: 'Imaging Equipment' },
      "102": { id: 'EQ-2024-004', name: 'Infusion Pump', beaconId: 'BCN-4524', category: 'Patient Care' },
    };
    fs.writeFileSync(EQUIPMENT_FILE, JSON.stringify(equipmentMap, null, 2));
  }
} catch (error) {
  console.error("Error loading equipment map:", error);
}

// 2. Location Mapping Repository (BSSID -> Physical Location)
const LOCATION_FILE = path.join(__dirname, 'locationMap.json');
let locationMap = {};

try {
  if (fs.existsSync(LOCATION_FILE)) {
    locationMap = JSON.parse(fs.readFileSync(LOCATION_FILE, 'utf8'));
  } else {
    locationMap = {
      // Replace these with your actual router MAC addresses
      "00:00:00:00:00:00": "Dahlia, Level 3",
      "02:00:00:00:00:00": "Allamanda Cafe Merah",
      "22:22:22:22:22:22": "ICU Ward",
    };
    fs.writeFileSync(LOCATION_FILE, JSON.stringify(locationMap, null, 2));
  }
} catch (error) {
  console.error("Error loading location map:", error);
}

// 3. Calibration Settings
const CALIBRATION_FILE = path.join(__dirname, 'calibration.json');
let calibrationSettings = {};

try {
  if (fs.existsSync(CALIBRATION_FILE)) {
    calibrationSettings = JSON.parse(fs.readFileSync(CALIBRATION_FILE, 'utf8'));
  } else {
    calibrationSettings = {
      nearThreshold: -65,
      farThreshold: -85,
      pathLossExponent: 2.5,
      txPowerCalibration: -59
    };
    fs.writeFileSync(CALIBRATION_FILE, JSON.stringify(calibrationSettings, null, 2));
  }
} catch (error) {
  console.error("Error loading calibration settings:", error);
}

// 4. Credentials
const CREDENTIALS_FILE = path.join(__dirname, 'credentials.json');
let credentials = {};

try {
  if (fs.existsSync(CREDENTIALS_FILE)) {
    credentials = JSON.parse(fs.readFileSync(CREDENTIALS_FILE, 'utf8'));
  } else {
    credentials = {
      admin: { username: 'admin123', password: '123' },
      superadmin: { username: 'superadmin', password: 'super123' }
    };
    fs.writeFileSync(CREDENTIALS_FILE, JSON.stringify(credentials, null, 2));
  }
} catch (error) {
  console.error("Error loading credentials:", error);
}

// 5. Live Status Tracking
// Keeps track of what equipment we've seen recently.
// Key = Asset ID (e.g. EQ-2024-001)
const activeEquipment = {};

// Helper to classify zone based on RSSI and calibration thresholds
function classifyZone(rssi) {
  if (rssi == null) return 'Unknown';
  if (rssi >= calibrationSettings.nearThreshold) return 'Near';
  if (rssi >= calibrationSettings.farThreshold) return 'Mid';
  return 'Far';
}

// Helper to calculate "time ago" string
function getTimeAgo(date) {
  const seconds = Math.floor((new Date() - date) / 1000);
  if (seconds < 60) return `${seconds} seconds ago`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} minute${minutes !== 1 ? 's' : ''} ago`;
  const hours = Math.floor(minutes / 60);
  return `${hours} hour${hours !== 1 ? 's' : ''} ago`;
}

// ==========================================
// ROUTES
// ==========================================

// Endpoint: Flutter App POSTs here when it scans an ESP32
app.post('/api/scan', (req, res) => {
  const { major, rssi, mac, location, bssid, distance } = req.body;
  const clientIp = req.ip || req.connection.remoteAddress;

  // Determine location based on BSSID
  let finalLocation = 'Unknown';
  if (bssid && locationMap[bssid]) {
    finalLocation = locationMap[bssid];
    console.log(`[Location Mapped] BSSID ${bssid} -> ${finalLocation}`);
  } else if (location) {
    // Fallback to whatever the app sends
    finalLocation = location;
    if (bssid) console.log(`[Unknown BSSID] ${bssid} - using fallback location: ${location}`);
  }

  console.log(`[${new Date().toLocaleTimeString()}] Incoming scan from ${clientIp} - Major: ${major}, Location: ${finalLocation}`);

  if (!major) {
    return res.status(400).json({ error: "Missing major value in scan payload" });
  }

  // Look up if we know what piece of equipment this 'Major' string belongs to
  const mappedEquipment = equipmentMap[major.toString()];

  if (mappedEquipment) {
    // We found it! Register it as "Active" right now.
    activeEquipment[mappedEquipment.id] = {
      ...mappedEquipment,
      rssi: rssi,
      distance: distance,
      lastSeenDate: new Date(),
      status: 'Active',
      location: finalLocation
    };
    console.log(`📡 Scan logged: ${mappedEquipment.name} (RSSI: ${rssi})`);
  } else {
    console.log(`⚠️ Unknown device scanned with Major: ${major}`);
  }

  res.json({ success: true });
});

// Endpoint: React Dashboard GETs this every 2 seconds to update the UI
app.get('/api/equipment', (req, res) => {
  const now = new Date();
  const results = [];

  // Loop through all our mapped hardware dictionary
  for (const majorKey in equipmentMap) {
    const baseInfo = equipmentMap[majorKey];
    const liveData = activeEquipment[baseInfo.id];

    if (liveData) {
      // It was scanned at some point! Check if it was recent.
      const secondsSinceSeen = (now - liveData.lastSeenDate) / 1000;

      // If it hasn't been seen in 60 seconds, mark it as Inactive
      const status = secondsSinceSeen > 60 ? 'Inactive' : 'Active';

      results.push({
        major: majorKey,
        ...baseInfo,
        status: status,
        location: liveData.location,
        distance: liveData.distance,
        rssi: liveData.rssi,
        zone: classifyZone(liveData.rssi),
        lastSeen: getTimeAgo(liveData.lastSeenDate)
      });
    } else {
      // It has NEVER been scanned yet
      results.push({
        major: majorKey,
        ...baseInfo,
        status: 'Inactive',
        location: 'Unknown',
        distance: null,
        rssi: null,
        zone: 'Unknown',
        lastSeen: 'Never'
      });
    }
  }

  res.json(results);
});

// Endpoint: Getting the BSSID Location Map
app.get('/api/locations', (req, res) => {
  res.json(locationMap);
});

// Endpoint: Adding or Updating a BSSID Location Map
app.post('/api/locations', (req, res) => {
  const { bssid, location } = req.body;
  if (!bssid || !location) {
    return res.status(400).json({ error: "Missing bssid or location in payload" });
  }
  locationMap[bssid] = location;
  try {
    fs.writeFileSync(LOCATION_FILE, JSON.stringify(locationMap, null, 2));
  } catch (error) {
    console.error("Error saving location map:", error);
  }
  res.json({ success: true, locationMap });
});

// Endpoint: Deleting a BSSID Location Map
app.delete('/api/locations/:bssid', (req, res) => {
  const bssid = req.params.bssid;
  if (locationMap[bssid]) {
    delete locationMap[bssid];
    try {
      fs.writeFileSync(LOCATION_FILE, JSON.stringify(locationMap, null, 2));
    } catch (error) {
      console.error("Error saving location map:", error);
    }
  }
  res.json({ success: true, locationMap });
});

// Endpoint: Get Raw Equipment Map (for Beacon Management UI)
app.get('/api/equipment/map', (req, res) => {
  res.json(equipmentMap);
});

// Endpoint: Adding or Updating Equipment Map
app.post('/api/equipment', (req, res) => {
  const { major, id, name, beaconId, category } = req.body;
  
  if (!major || !id) {
    return res.status(400).json({ error: "Missing major or id in payload" });
  }
  
  equipmentMap[major] = { id, name: name || 'Unknown', beaconId: beaconId || '', category: category || 'General' };
  
  try {
    fs.writeFileSync(EQUIPMENT_FILE, JSON.stringify(equipmentMap, null, 2));
  } catch (error) {
    console.error("Error saving equipment map:", error);
  }
  res.json({ success: true, equipmentMap });
});

// Endpoint: Deleting Equipment Map
app.delete('/api/equipment/:major', (req, res) => {
  const major = req.params.major;
  if (equipmentMap[major]) {
    const eqId = equipmentMap[major].id;
    if (activeEquipment[eqId]) {
      delete activeEquipment[eqId];
    }
    delete equipmentMap[major];
    
    try {
      fs.writeFileSync(EQUIPMENT_FILE, JSON.stringify(equipmentMap, null, 2));
    } catch (error) {
      console.error("Error saving equipment map:", error);
    }
  }
  res.json({ success: true, equipmentMap });
});

// Endpoint: Get Calibration Settings
app.get('/api/calibration', (req, res) => {
  res.json(calibrationSettings);
});

// Endpoint: Update Calibration Settings
app.post('/api/calibration', (req, res) => {
  const { nearThreshold, farThreshold, pathLossExponent, txPowerCalibration } = req.body;

  if (nearThreshold != null) calibrationSettings.nearThreshold = Number(nearThreshold);
  if (farThreshold != null) calibrationSettings.farThreshold = Number(farThreshold);
  if (pathLossExponent != null) calibrationSettings.pathLossExponent = Number(pathLossExponent);
  if (txPowerCalibration != null) calibrationSettings.txPowerCalibration = Number(txPowerCalibration);

  try {
    fs.writeFileSync(CALIBRATION_FILE, JSON.stringify(calibrationSettings, null, 2));
    console.log(`[Calibration] Updated: Near=${calibrationSettings.nearThreshold}, Far=${calibrationSettings.farThreshold}, N=${calibrationSettings.pathLossExponent}, TxCal=${calibrationSettings.txPowerCalibration}`);
  } catch (error) {
    console.error("Error saving calibration settings:", error);
  }
  res.json({ success: true, calibration: calibrationSettings });
});

// Endpoint: Verify Credentials (role-based login)
app.post('/api/credentials/verify', (req, res) => {
  const { username, password, role } = req.body;

  if (!role || !credentials[role]) {
    return res.status(400).json({ success: false, error: 'Invalid role' });
  }

  const cred = credentials[role];
  if (username === cred.username && password === cred.password) {
    res.json({ success: true, role });
  } else {
    res.status(401).json({ success: false, error: 'Invalid credentials' });
  }
});

// Endpoint: Update Credentials (superadmin only)
app.post('/api/credentials/update', (req, res) => {
  const { currentPassword, role, newUsername, newPassword } = req.body;

  // Verify caller is superadmin
  if (currentPassword !== credentials.superadmin.password) {
    return res.status(403).json({ success: false, error: 'Superadmin password required' });
  }

  if (!role || !credentials[role]) {
    return res.status(400).json({ success: false, error: 'Invalid role' });
  }

  if (newUsername) credentials[role].username = newUsername;
  if (newPassword) credentials[role].password = newPassword;

  try {
    fs.writeFileSync(CREDENTIALS_FILE, JSON.stringify(credentials, null, 2));
    console.log(`[Credentials] Updated ${role} credentials`);
  } catch (error) {
    console.error("Error saving credentials:", error);
  }
  res.json({ success: true });
});

// Endpoint: Factory Reset (clear equipment, locations, calibration)
app.post('/api/system/reset', (req, res) => {
  const { password } = req.body;

  if (password !== credentials.superadmin.password) {
    return res.status(403).json({ success: false, error: 'Superadmin password required' });
  }

  // Reset equipment map to empty
  for (const key in equipmentMap) delete equipmentMap[key];
  fs.writeFileSync(EQUIPMENT_FILE, JSON.stringify(equipmentMap, null, 2));

  // Reset location map to empty
  for (const key in locationMap) delete locationMap[key];
  fs.writeFileSync(LOCATION_FILE, JSON.stringify(locationMap, null, 2));

  // Reset calibration to defaults
  calibrationSettings.nearThreshold = -65;
  calibrationSettings.farThreshold = -85;
  calibrationSettings.pathLossExponent = 2.5;
  calibrationSettings.txPowerCalibration = -59;
  fs.writeFileSync(CALIBRATION_FILE, JSON.stringify(calibrationSettings, null, 2));

  // Clear active tracking
  for (const key in activeEquipment) delete activeEquipment[key];

  console.log('[System] Factory reset performed');
  res.json({ success: true, message: 'Factory reset complete' });
});

// Endpoint: Clear History Logs (only clears active tracking data)
app.post('/api/system/clear-logs', (req, res) => {
  const { password } = req.body;

  if (password !== credentials.superadmin.password) {
    return res.status(403).json({ success: false, error: 'Superadmin password required' });
  }

  for (const key in activeEquipment) delete activeEquipment[key];

  console.log('[System] History logs cleared');
  res.json({ success: true, message: 'History logs cleared' });
});

// Catch-all: serve the React app for any non-API route (SPA client-side routing)
app.get(/.*/, (req, res) => {
  const indexPath = path.join(__dirname, 'public', 'index.html');
  if (fs.existsSync(indexPath)) {
    res.sendFile(indexPath);
  } else {
    res.status(200).send('Hospital Asset Server is running. Dashboard not built yet — run: npm run build');
  }
});

// ── Server Initialize ────────────────────────────────────────────────────────

const os = require('os');
const interfaces = os.networkInterfaces();
const addresses = [];
for (const k in interfaces) {
  for (const k2 in interfaces[k]) {
    const address = interfaces[k][k2];
    if (address.family === 'IPv4' && !address.internal) {
      addresses.push(address.address);
    }
  }
}

app.listen(PORT, '0.0.0.0', () => {
  console.log(`\n=================================`);
  console.log(`🏥 Hospital Asset Server Running!`);
  console.log(`---------------------------------`);
  console.log(`   Port: ${PORT}`);
  console.log(`   Local: http://localhost:${PORT}`);
  addresses.forEach(addr => console.log(`   Network: http://${addr}:${PORT}`));
  console.log(`=================================\n`);
});
