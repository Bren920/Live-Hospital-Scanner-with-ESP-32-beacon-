# Live Hospital Asset Scanner with ESP32 Beacons

This is a comprehensive hospital asset tracking system that utilizes ESP32 BLE Beacons to accurately track the live locations of mobile medical equipment (like ECG machines, portable X-rays, wheelchairs) across different wards.

## ✨ Advanced Features

### 🛡️ Superadmin System
- **Role-Based Access Control**: Separate views for **Admin** (day-to-day management) and **Superadmin** (technical configuration).
- **Secure Authentication**: Backend-verified credentials for all administrative actions.
- **Password Management**: Superadmin can update system credentials directly from the dashboard.
- **System Maintenance**: "Danger Zone" tools for factory resets and clearing history logs.

### 📐 Precision Signal Calibration
- **Real-Time Tuning**: Adjustable RSSI thresholds (Near/Far zones) via interactive sliders.
- **Environmental Adaptation**: Configurable Path Loss Exponent ($n$) and Tx Power settings to adapt to different hospital ward environments.
- **Live Signal Visualization**: View raw RSSI values from active beacons for immediate calibration feedback.

### 🌐 Cross-Network Synchronization
- **Any-Network Connectivity**: Scanners can operate on mobile data (4G/5G) while the dashboard runs on hospital Wi-Fi.
- **Configurable Server URL**: The Flutter app features a persistent settings menu to point to any public or local server address.
- **Unified Hosting**: The Node.js server is configured to serve the built React dashboard directly, simplifying deployment to platforms like **Railway.app**.

---

## 🏗️ System Architecture

1. **Flutter Mobile App (`/lib`)**
   - **Continuous BLE Scanning**: Rapid detection of ESP32-based iBeacon signals.
   - **Smart Filtering**: Ignores non-hospital Bluetooth noise.
   - **Persistence**: Remembers server configuration across app restarts using `shared_preferences`.

2. **Node.js Express Server (`/server`)**
   - **Unified Backend**: Serves both API endpoints and the static React dashboard.
   - **Location Mapping**: Intelligent mapping of BSSIDs and MAC addresses to physical hospital wards.
   - **Role-Based API**: Protected endpoints for credential verification and system resets.

3. **React Web Dashboard (`/web_dashboard`)**
   - **Real-Time Monitoring**: Dynamic updates without page refreshes.
   - **Calibration Suite**: Advanced interface for technical signal tuning.
   - **Mobile-Responsive**: Clean, premium UI designed for both tablets and desktop monitors.

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install)
- [Node.js](https://nodejs.org/en/) (v18+)

### Unified Local Setup
The easiest way to run the full system locally:

1. **Build the Dashboard**:
   ```bash
   cd server
   npm run build
   ```
2. **Start the Unified Server**:
   ```bash
   npm start
   ```
3. **Launch the Scanner (Flutter)**:
   ```bash
   cd ..
   flutter run
   ```
   *Then, use the ⚙️ icon in the app to set the server address to your computer's IP.*

---
*Created as part of a Final Year Project building robust IoT asset tracking capabilities for modern healthcare settings.*
