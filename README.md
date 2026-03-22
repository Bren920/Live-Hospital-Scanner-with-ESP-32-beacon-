# Live Hospital Asset Scanner with ESP32 Beacons

This is a comprehensive hospital asset tracking system that utilizes ESP32 BLE Beacons to accurately track the live locations of mobile medical equipment (like ECG machines, portable X-rays, wheelchairs) across different wards. 

## 📦 Download the App
You can download the compiled Android app directly here:
**[⬇️ Download `hospital-scanner.apk`](./releases/hospital-scanner.apk)**

*(Note: Ensure your Android device has "Install from Unknown Sources" enabled to successfully install the app.)*

---

## 🏗️ System Architecture

This full-stack system consists of three main components:

1. **Flutter Mobile App (`/lib`)** 
   - Acts as a moving scanner to continuously detect nearby ESP32 Beacons via Bluetooth Low Energy (BLE).
   - Calculates the approximate distances based on Received Signal Strength Indicator (RSSI) values.
   - Synchronizes live MAC addresses, beacon data, and current location tracking back to the central server.
   
2. **Node.js Express Server (`/server`)**
   - The central nervous system acting as a bridge between the mobile scanners and the front-end dashboard.
   - Maintains a live memory of recently seen equipment, filtering out inactive/stale devices.
   - Maps raw beacon MAC addresses and router BSSIDs to human-readable hospital locations (e.g. "Dahlia, Level 3", "ICU Ward").

3. **React Web Dashboard (`/web_dashboard`)**
   - A beautiful, real-time frontend dashboard for hospital staff.
   - Visually displays all active equipment and their exact current locations within the hospital.
   - Refreshes automatically to always maintain a "Live" view of the hospital floor.

## 🚀 Getting Started for Developers

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install)
- [Node.js](https://nodejs.org/en/) (v16+)
- [Git](https://git-scm.com/)

### Running the Server
```bash
cd server
npm i
node server.js
```

### Running the Web Dashboard (React)
```bash
cd web_dashboard
npm i
npm run dev
```

### Running the Mobile App (Flutter)
```bash
flutter pub get
flutter run
```

---
*Created as part of a Final Year Project building robust IoT asset tracking capabilities for modern healthcare settings.*
