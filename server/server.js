const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = 3000;

app.use(cors());
app.use(express.json());

// 1. Hardware Mapping Repository
// In a real app, this would be a database table mapping 
// ESP32 "Major" values to specific medical equipment.
const equipmentMap = {
  // Mapping by Major value (using string keys for easy lookup)
  "100": { id: 'EQ-2024-001', name: 'Portable X-Ray Machine', beaconId: 'BCN-4521', category: 'Imaging Equipment' },
  "101": { id: 'EQ-2024-002', name: 'Ultrasound Scanner', beaconId: 'BCN-4522', category: 'Imaging Equipment' },
  "102": { id: 'EQ-2024-004', name: 'Infusion Pump', beaconId: 'BCN-4524', category: 'Patient Care' },
};

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

// 3. Live Status Tracking
// Keeps track of what equipment we've seen recently.
// Key = Asset ID (e.g. EQ-2024-001)
const activeEquipment = {};

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
  const { major, rssi, mac, location, bssid } = req.body;
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
        ...baseInfo,
        status: status,
        location: liveData.location,
        lastSeen: getTimeAgo(liveData.lastSeenDate)
      });
    } else {
      // It has NEVER been scanned yet
      results.push({
        ...baseInfo,
        status: 'Inactive',
        location: 'Unknown',
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
  console.log(`Available on your network at:`);
  addresses.forEach(addr => console.log(`👉 http://${addr}:${PORT}`));
  console.log(`=================================\n`);
});
