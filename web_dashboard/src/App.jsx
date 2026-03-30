import React, { useState, useEffect } from 'react';
import { LayoutDashboard, Package, Settings, Search, Box, Radio, AlertTriangle, Lock, Unlock, Edit2, Wifi, Plus, Trash2, Shield, KeyRound, Eye, EyeOff } from 'lucide-react';
import './index.css';

// In production (served from Node.js on same domain/cloud host), use relative paths (empty string).
// In local Vite development (port 5173/5174), point to the local Node.js server.
const isViteDev = window.location.port === '5173' || window.location.port === '5174';
const API = isViteDev ? `http://${window.location.hostname}:3000` : '';

// Components
const Sidebar = ({ activeTab, setActiveTab }) => (
  <div className="sidebar">
    <div className="sidebar-header">
      Hospital Asset<br />Tracker
    </div>
    <div className="sidebar-nav">
      <div className={`nav-item ${activeTab === 'dashboard' ? 'active' : ''}`} onClick={() => setActiveTab('dashboard')}>
        <LayoutDashboard size={20} /> Dashboard
      </div>
      <div className={`nav-item ${activeTab === 'equipment' ? 'active' : ''}`} onClick={() => setActiveTab('equipment')}>
        <Package size={20} /> Equipment
      </div>
      <div className={`nav-item ${activeTab === 'settings' ? 'active' : ''}`} onClick={() => setActiveTab('settings')}>
        <Settings size={20} /> Settings
      </div>
      <div className={`nav-item superadmin-nav ${activeTab === 'superadmin' ? 'active' : ''}`} onClick={() => setActiveTab('superadmin')}>
        <Shield size={20} /> Superadmin
      </div>
    </div>
  </div>
);

const DashboardView = ({ liveData }) => (
  <div className="content-area">
    <div className="metrics-row">
      <div className="metric-card">
        <div className="metric-info">
          <h3>Total Equipment</h3>
          <div className="value">{liveData.length}</div>
        </div>
        <div className="metric-icon blue"><Box /></div>
      </div>
      <div className="metric-card">
        <div className="metric-info">
          <h3>Active Beacons</h3>
          <div className="value">{liveData.filter(e => e.status === 'Active').length}</div>
        </div>
        <div className="metric-icon green"><Radio /></div>
      </div>
      <div className="metric-card">
        <div className="metric-info">
          <h3>Missing Items</h3>
          <div className="value">{liveData.filter(e => e.status === 'Inactive').length}</div>
        </div>
        <div className="metric-icon red"><AlertTriangle /></div>
      </div>
    </div>

    <div className="section-wrapper">
      <h2>Medical Equipment</h2>
      <p>Real-time location and status of all tracked assets</p>
    </div>

    <div className="table-container">
      <table>
        <thead>
          <tr>
            <th>Asset ID</th>
            <th>Name</th>
            <th>Current Location (Ward)</th>
            <th>Est. Distance</th>
            <th>Zone</th>
            <th>Last Seen</th>
          </tr>
        </thead>
        <tbody>
          {liveData.length === 0 ? (
            <tr><td colSpan="6" style={{textAlign:'center', padding: '32px'}}>Scanning for assets...</td></tr>
          ) : (
             liveData.map((eq) => (
              <tr key={eq.id}>
                <td>{eq.id}</td>
                <td style={{ fontWeight: 500, color: '#1e293b' }}>{eq.name}</td>
                <td>{eq.location || 'Unknown'}</td>
                <td>{eq.distance != null ? `${Number(eq.distance).toFixed(2)}m` : 'N/A'}</td>
                <td>
                  <span className={`zone-pill zone-${(eq.zone || 'unknown').toLowerCase()}`}>
                    {eq.zone || 'Unknown'}
                  </span>
                </td>
                <td>{eq.lastSeen || 'Never'}</td>
              </tr>
            ))
          )}
        </tbody>
      </table>
    </div>
  </div>
);

const EquipmentView = ({ liveData }) => (
  <div className="content-area">
    <div className="section-wrapper">
      <h2>All Equipment</h2>
      <p>Complete list of medical equipment with beacon assignments and status</p>
    </div>

    <div className="table-container">
      <table>
        <thead>
          <tr>
            <th>Asset ID</th>
            <th>Equipment Name</th>
            <th>Major Value</th>
            <th>Assigned Beacon ID</th>
            <th>Category</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          {liveData.length === 0 ? (
             <tr><td colSpan="5" style={{textAlign:'center'}}>No equipment data loaded</td></tr>
          ) : (
             liveData.map((eq) => (
              <tr key={eq.id}>
                <td>{eq.id}</td>
                <td style={{ fontWeight: 500, color: '#1e293b' }}>{eq.name}</td>
                <td>{eq.major}</td>
                <td>{eq.beaconId}</td>
                <td>{eq.category}</td>
                <td>
                  <span className={`status-pill status-${(eq.status||'inactive').toLowerCase()}`}>
                    {eq.status || 'Inactive'}
                  </span>
                </td>
              </tr>
            ))
          )}
        </tbody>
      </table>
    </div>
  </div>
);

// ────────────────────────────────────────────────────────────
// SETTINGS VIEW (Admin) — Beacon Management + BSSID Locations
// ────────────────────────────────────────────────────────────
const SettingsView = ({ isUnlocked, setIsUnlocked, liveData }) => {
  const [adminId, setAdminId] = useState('');
  const [password, setPassword] = useState('');
  const [loginError, setLoginError] = useState('');

  const [locations, setLocations] = useState({});
  const [newBssid, setNewBssid] = useState('');
  const [newLocationName, setNewLocationName] = useState('');

  const [showAddBeacon, setShowAddBeacon] = useState(false);
  const [newBeacon, setNewBeacon] = useState({ major: '', id: '', name: '', beaconId: '', category: '' });
  const [beaconMap, setBeaconMap] = useState({});

  useEffect(() => {
    if (isUnlocked) {
      fetchLocations();
      fetchBeaconMap();
    }
  }, [isUnlocked]);

  useEffect(() => {
    if (!isUnlocked) return;
    const interval = setInterval(fetchBeaconMap, 3000);
    return () => clearInterval(interval);
  }, [isUnlocked]);

  const fetchLocations = async () => {
    try {
      const response = await fetch(`${API}/api/locations`);
      const data = await response.json();
      setLocations(data);
    } catch (err) {
      console.error("Failed to fetch locations", err);
    }
  };

  const fetchBeaconMap = async () => {
    try {
      const response = await fetch(`${API}/api/equipment/map`);
      const data = await response.json();
      setBeaconMap(data);
    } catch (err) {
      console.error("Failed to fetch beacon map", err);
    }
  };

  const addLocation = async (e) => {
    e.preventDefault();
    if (!newBssid || !newLocationName) return;
    try {
      await fetch(`${API}/api/locations`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ bssid: newBssid, location: newLocationName })
      });
      setNewBssid('');
      setNewLocationName('');
      fetchLocations();
    } catch (err) {
      console.error("Failed to add location", err);
    }
  };

  const deleteLocation = async (bssid) => {
    if (!window.confirm(`Delete mapping for ${bssid}?`)) return;
    try {
      await fetch(`${API}/api/locations/${encodeURIComponent(bssid)}`, { method: 'DELETE' });
      fetchLocations();
    } catch (err) {
      console.error("Failed to delete location", err);
    }
  };

  const handleAddBeacon = async (e) => {
    e.preventDefault();
    if (!newBeacon.major || !newBeacon.id) return;
    try {
      await fetch(`${API}/api/equipment`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(newBeacon)
      });
      setNewBeacon({ major: '', id: '', name: '', beaconId: '', category: '' });
      setShowAddBeacon(false);
      fetchBeaconMap();
    } catch (err) {
      console.error("Failed to add beacon", err);
    }
  };

  const deleteBeacon = async (major) => {
    if (!major) return alert('Cannot delete: missing Major value.');
    if (!window.confirm(`Delete beacon with Major ${major}?`)) return;
    try {
      await fetch(`${API}/api/equipment/${encodeURIComponent(major)}`, { method: 'DELETE' });
      fetchBeaconMap();
    } catch (err) {
      console.error("Failed to delete beacon", err);
    }
  };

  const handleUnlock = async (e) => {
    e.preventDefault();
    setLoginError('');
    try {
      const res = await fetch(`${API}/api/credentials/verify`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username: adminId, password, role: 'admin' })
      });
      const data = await res.json();
      if (data.success) {
        setIsUnlocked(true);
      } else {
        setLoginError('Invalid Admin ID or Password');
      }
    } catch {
      setLoginError('Cannot reach server');
    }
  };

  return (
    <div style={{ position: 'relative', height: '100%' }}>
      {!isUnlocked && (
        <div className="auth-overlay">
          <div className="auth-modal">
            <div className="auth-icon"><Lock size={32} /></div>
            <h2>Admin Access Required</h2>
            <p>Please authenticate to access admin settings</p>
            <form onSubmit={handleUnlock} style={{ width: '100%' }}>
              <div className="input-group">
                <label>Admin ID</label>
                <input type="text" placeholder="Enter your admin ID" value={adminId} onChange={e => setAdminId(e.target.value)} required />
              </div>
              <div className="input-group">
                <label>Password</label>
                <input type="password" placeholder="Enter your password" value={password} onChange={e => setPassword(e.target.value)} required />
              </div>
              {loginError && <div style={{ color: '#ef4444', fontSize: '0.85rem', marginBottom: '8px' }}>{loginError}</div>}
              <button type="submit" className="auth-btn">
                <Unlock size={18} /> Unlock Settings
              </button>
            </form>
          </div>
        </div>
      )}

      <div className="content-area" style={{ filter: !isUnlocked ? 'blur(4px)' : 'none', pointerEvents: !isUnlocked ? 'none' : 'auto' }}>
        <div className="settings-grid">
          
          {/* BSSID & Location Config */}
          <div className="settings-card">
            <div className="settings-card-header" style={{ marginBottom: '16px' }}>
              <Wifi size={20} className="blue" /> BSSID & Physical Location Config
            </div>
            
            <form onSubmit={addLocation} style={{ display: 'flex', gap: '8px', marginBottom: '24px' }}>
              <div className="input-group" style={{ flex: 1, marginBottom: 0 }}>
                <input type="text" placeholder="WiFi BSSID (e.g., 00:11:22...)" value={newBssid} onChange={e => setNewBssid(e.target.value)} required />
              </div>
              <div className="input-group" style={{ flex: 1, marginBottom: 0 }}>
                <input type="text" placeholder="Physical Location" value={newLocationName} onChange={e => setNewLocationName(e.target.value)} required />
              </div>
              <button type="submit" className="btn btn-primary" style={{ padding: '0 16px' }}>
                <Plus size={18} /> Add
              </button>
            </form>

            <div style={{ maxHeight: '250px', overflowY: 'auto' }}>
              {Object.keys(locations).length === 0 ? (
                <div style={{ textAlign: 'center', color: '#64748b', padding: '16px' }}>No location mappings found.</div>
              ) : (
                Object.entries(locations).map(([bssid, locName]) => (
                  <div key={bssid} style={{ display: 'flex', justifyContent: 'space-between', padding: '12px 0', borderBottom: '1px solid #e2e8f0' }}>
                    <div>
                      <div style={{ fontWeight: 500, fontSize: '0.9rem' }}>{locName}</div>
                      <div style={{ fontSize: '0.8rem', color: '#64748b', fontFamily: 'monospace' }}>BSSID: {bssid}</div>
                    </div>
                    <button onClick={() => deleteLocation(bssid)} style={{ background: 'none', border: 'none', cursor: 'pointer', color: '#ef4444' }}>
                      <Trash2 size={16} />
                    </button>
                  </div>
                ))
              )}
            </div>
          </div>

          {/* Beacon Management */}
          <div className="settings-card">
            <div className="settings-card-header" style={{ justifyContent: 'space-between', marginBottom: '16px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <Radio size={20} className="blue" /> Beacon Management
              </div>
              <button 
                className={`btn ${showAddBeacon ? 'btn-danger-outline' : 'btn-primary'}`} 
                onClick={() => setShowAddBeacon(!showAddBeacon)}
                style={{ padding: '6px 12px', width: 'auto' }}
              >
                {showAddBeacon ? 'Cancel' : '+ Add Beacon'}
              </button>
            </div>

            {showAddBeacon && (
              <form onSubmit={handleAddBeacon} style={{ display: 'flex', flexDirection: 'column', gap: '12px', marginBottom: '24px', padding: '16px', backgroundColor: '#f8fafc', borderRadius: '8px', border: '1px solid #e2e8f0' }}>
                <div style={{ display: 'flex', gap: '8px' }}>
                  <input type="text" placeholder="Major Value (e.g. 200)" value={newBeacon.major} onChange={e => setNewBeacon({...newBeacon, major: e.target.value})} required style={{ flex: 1, padding: '8px', border: '1px solid #cbd5e1', borderRadius: '4px' }}/>
                  <input type="text" placeholder="Designated Asset ID (e.g. EQ-105)" value={newBeacon.id} onChange={e => setNewBeacon({...newBeacon, id: e.target.value})} required style={{ flex: 1, padding: '8px', border: '1px solid #cbd5e1', borderRadius: '4px' }}/>
                </div>
                <div style={{ display: 'flex', gap: '8px' }}>
                  <input type="text" placeholder="Asset Name" value={newBeacon.name} onChange={e => setNewBeacon({...newBeacon, name: e.target.value})} style={{ flex: 1, padding: '8px', border: '1px solid #cbd5e1', borderRadius: '4px' }}/>
                  <input type="text" placeholder="Category" value={newBeacon.category} onChange={e => setNewBeacon({...newBeacon, category: e.target.value})} style={{ flex: 1, padding: '8px', border: '1px solid #cbd5e1', borderRadius: '4px' }}/>
                  <input type="text" placeholder="Beacon Label" value={newBeacon.beaconId} onChange={e => setNewBeacon({...newBeacon, beaconId: e.target.value})} style={{ flex: 1, padding: '8px', border: '1px solid #cbd5e1', borderRadius: '4px' }}/>
                </div>
                <button type="submit" className="btn btn-primary" style={{ alignSelf: 'flex-start' }}>Save Beacon Database</button>
              </form>
            )}

            <div style={{ maxHeight: '300px', overflowY: 'auto' }}>
              {Object.keys(beaconMap).length === 0 && <div style={{ color: '#64748b', padding: '16px', textAlign: 'center' }}>No beacons registered yet.</div>}
              {Object.entries(beaconMap).map(([majorKey, info]) => {
                const live = liveData.find(d => d.id === info.id);
                const status = live ? live.status : 'Inactive';
                const location = live ? live.location : 'Not scanned';
                return (
                  <div key={majorKey} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '14px 0', borderBottom: '1px solid #e2e8f0' }}>
                    <div style={{ flex: 1 }}>
                      <div style={{ fontWeight: 600, fontSize: '0.95rem', color: '#1e293b' }}>
                        {info.name || 'Unnamed'} <span style={{ color: '#64748b', fontSize: '0.8rem', fontWeight: 400 }}>({info.id})</span>
                      </div>
                      <div style={{ fontSize: '0.8rem', color: '#64748b', display: 'flex', alignItems: 'center', gap: '10px', marginTop: '5px', flexWrap: 'wrap' }}>
                        <span style={{ fontWeight: 700, color: '#2563eb', backgroundColor: '#eff6ff', padding: '2px 8px', borderRadius: '4px', fontSize: '0.78rem' }}>Major: {majorKey}</span>
                        <span style={{ color: '#94a3b8' }}>|</span>
                        <span>Label: {info.beaconId || 'N/A'}</span>
                        <span style={{ color: '#94a3b8' }}>|</span>
                        <span>{info.category || 'General'}</span>
                        <span style={{ color: '#94a3b8' }}>|</span>
                        <span style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                          <span style={{ width: 7, height: 7, borderRadius: '50%', backgroundColor: status === 'Active' ? '#22c55e' : '#cbd5e1', display: 'inline-block' }}></span> 
                          {status} — {location}
                        </span>
                      </div>
                    </div>
                    <button 
                      onClick={() => deleteBeacon(majorKey)} 
                      style={{ background: 'none', border: 'none', cursor: 'pointer', color: '#ef4444', padding: '8px', marginLeft: '12px' }}
                      title={`Delete beacon Major ${majorKey}`}
                    >
                      <Trash2 size={18} />
                    </button>
                  </div>
                );
              })}
            </div>
          </div>

        </div>
      </div>
    </div>
  );
};

// ────────────────────────────────────────────────────────────
// SUPERADMIN VIEW — Signal Calibration + Danger Zone + Passwords
// ────────────────────────────────────────────────────────────
const SuperadminView = ({ isUnlocked, setIsUnlocked, liveData }) => {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [loginError, setLoginError] = useState('');
  const [superadminPassword, setSuperadminPassword] = useState('');

  // Calibration state
  const [nearThreshold, setNearThreshold] = useState(-65);
  const [farThreshold, setFarThreshold] = useState(-85);
  const [pathLossExponent, setPathLossExponent] = useState(2.5);
  const [txPowerCalibration, setTxPowerCalibration] = useState(-59);
  const [calibrationDirty, setCalibrationDirty] = useState(false);

  // Password management state
  const [pwRole, setPwRole] = useState('admin');
  const [pwNewUsername, setPwNewUsername] = useState('');
  const [pwNewPassword, setPwNewPassword] = useState('');
  const [pwConfirmPassword, setPwConfirmPassword] = useState('');
  const [pwMessage, setPwMessage] = useState('');
  const [showNewPassword, setShowNewPassword] = useState(false);

  const fetchCalibration = async () => {
    try {
      const response = await fetch(`${API}/api/calibration`);
      const data = await response.json();
      setNearThreshold(data.nearThreshold ?? -65);
      setFarThreshold(data.farThreshold ?? -85);
      setPathLossExponent(data.pathLossExponent ?? 2.5);
      setTxPowerCalibration(data.txPowerCalibration ?? -59);
    } catch (err) {
      console.error('Failed to fetch calibration', err);
    }
  };

  const saveCalibration = async (overrides = {}) => {
    const payload = {
      nearThreshold: overrides.nearThreshold ?? nearThreshold,
      farThreshold: overrides.farThreshold ?? farThreshold,
      pathLossExponent: overrides.pathLossExponent ?? pathLossExponent,
      txPowerCalibration: overrides.txPowerCalibration ?? txPowerCalibration
    };
    try {
      await fetch(`${API}/api/calibration`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
      setCalibrationDirty(false);
    } catch (err) {
      console.error('Failed to save calibration', err);
    }
  };

  useEffect(() => {
    if (isUnlocked) {
      fetchCalibration();
    }
  }, [isUnlocked]);

  const handleUnlock = async (e) => {
    e.preventDefault();
    setLoginError('');
    try {
      const res = await fetch(`${API}/api/credentials/verify`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password, role: 'superadmin' })
      });
      const data = await res.json();
      if (data.success) {
        setIsUnlocked(true);
        setSuperadminPassword(password);
      } else {
        setLoginError('Invalid Superadmin credentials');
      }
    } catch {
      setLoginError('Cannot reach server');
    }
  };

  const handleFactoryReset = async () => {
    if (!window.confirm('⚠️ WARNING: This will delete ALL equipment, location, and calibration data. This action CANNOT be undone. Continue?')) return;
    try {
      const res = await fetch(`${API}/api/system/reset`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password: superadminPassword })
      });
      const data = await res.json();
      if (data.success) {
        alert('✅ Factory reset complete. All data has been cleared.');
        fetchCalibration();
      } else {
        alert('❌ Factory reset failed: ' + (data.error || 'Unknown error'));
      }
    } catch {
      alert('❌ Cannot reach server');
    }
  };

  const handleClearLogs = async () => {
    if (!window.confirm('This will clear all active tracking history. Equipment and location definitions will remain. Continue?')) return;
    try {
      const res = await fetch(`${API}/api/system/clear-logs`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password: superadminPassword })
      });
      const data = await res.json();
      if (data.success) {
        alert('✅ History logs cleared.');
      } else {
        alert('❌ Failed: ' + (data.error || 'Unknown error'));
      }
    } catch {
      alert('❌ Cannot reach server');
    }
  };

  const handlePasswordUpdate = async (e) => {
    e.preventDefault();
    setPwMessage('');
    if (pwNewPassword !== pwConfirmPassword) {
      setPwMessage('❌ Passwords do not match');
      return;
    }
    if (!pwNewPassword && !pwNewUsername) {
      setPwMessage('❌ Provide a new username or password');
      return;
    }
    try {
      const res = await fetch(`${API}/api/credentials/update`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          currentPassword: superadminPassword,
          role: pwRole,
          newUsername: pwNewUsername || undefined,
          newPassword: pwNewPassword || undefined
        })
      });
      const data = await res.json();
      if (data.success) {
        setPwMessage(`✅ ${pwRole} credentials updated successfully`);
        setPwNewUsername('');
        setPwNewPassword('');
        setPwConfirmPassword('');
        // If superadmin changed their own password, update local reference
        if (pwRole === 'superadmin' && pwNewPassword) {
          setSuperadminPassword(pwNewPassword);
        }
      } else {
        setPwMessage('❌ ' + (data.error || 'Update failed'));
      }
    } catch {
      setPwMessage('❌ Cannot reach server');
    }
  };

  return (
    <div style={{ position: 'relative', height: '100%' }}>
      {!isUnlocked && (
        <div className="auth-overlay">
          <div className="auth-modal superadmin-modal">
            <div className="auth-icon superadmin-auth-icon"><Shield size={32} /></div>
            <h2>Superadmin Access Required</h2>
            <p>Only authorized system administrators can access this section</p>
            <form onSubmit={handleUnlock} style={{ width: '100%' }}>
              <div className="input-group">
                <label>Superadmin ID</label>
                <input type="text" placeholder="Enter superadmin ID" value={username} onChange={e => setUsername(e.target.value)} required />
              </div>
              <div className="input-group">
                <label>Password</label>
                <input type="password" placeholder="Enter superadmin password" value={password} onChange={e => setPassword(e.target.value)} required />
              </div>
              {loginError && <div style={{ color: '#ef4444', fontSize: '0.85rem', marginBottom: '8px' }}>{loginError}</div>}
              <button type="submit" className="auth-btn superadmin-auth-btn">
                <Shield size={18} /> Unlock Superadmin
              </button>
            </form>
          </div>
        </div>
      )}

      <div className="content-area" style={{ filter: !isUnlocked ? 'blur(4px)' : 'none', pointerEvents: !isUnlocked ? 'none' : 'auto' }}>
        <div className="settings-grid">

          {/* Signal Calibration */}
          <div className="settings-card">
            <div className="settings-card-header">
              <Settings size={20} className="blue" /> Signal Calibration
            </div>
            
            <div className="slider-group">
              <div className="slider-group-header">
                <span>Near Zone Threshold</span>
                <span className="slider-val">{nearThreshold} dBm</span>
              </div>
              <input type="range" min="-100" max="-30" value={nearThreshold} onChange={e => { setNearThreshold(Number(e.target.value)); setCalibrationDirty(true); }} onMouseUp={e => saveCalibration({ nearThreshold: Number(e.target.value) })} onTouchEnd={e => saveCalibration({ nearThreshold: Number(e.target.value) })} />
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.7rem', color: '#94a3b8', marginTop: '2px' }}>
                <span>-100 (far)</span><span>-30 (close)</span>
              </div>
            </div>

            <div className="slider-group">
              <div className="slider-group-header">
                <span>Far Zone Threshold</span>
                <span className="slider-val">{farThreshold} dBm</span>
              </div>
              <input type="range" min="-100" max="-30" value={farThreshold} onChange={e => { setFarThreshold(Number(e.target.value)); setCalibrationDirty(true); }} onMouseUp={e => saveCalibration({ farThreshold: Number(e.target.value) })} onTouchEnd={e => saveCalibration({ farThreshold: Number(e.target.value) })} />
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.7rem', color: '#94a3b8', marginTop: '2px' }}>
                <span>-100 (far)</span><span>-30 (close)</span>
              </div>
            </div>

            <div style={{ display: 'flex', gap: '12px', marginTop: '16px' }}>
              <div className="input-group" style={{ flex: 1, marginBottom: 0 }}>
                <label style={{ fontSize: '0.8rem', fontWeight: 500 }}>Path Loss Exponent (n)</label>
                <input type="number" step="0.1" min="1" max="6" value={pathLossExponent} onChange={e => { setPathLossExponent(Number(e.target.value)); setCalibrationDirty(true); }} onBlur={() => saveCalibration()} />
                <div style={{ fontSize: '0.7rem', color: '#94a3b8', marginTop: '2px' }}>2.0 = open space, 3-4 = indoors</div>
              </div>
              <div className="input-group" style={{ flex: 1, marginBottom: 0 }}>
                <label style={{ fontSize: '0.8rem', fontWeight: 500 }}>Tx Power at 1m (dBm)</label>
                <input type="number" step="1" min="-100" max="0" value={txPowerCalibration} onChange={e => { setTxPowerCalibration(Number(e.target.value)); setCalibrationDirty(true); }} onBlur={() => saveCalibration()} />
                <div style={{ fontSize: '0.7rem', color: '#94a3b8', marginTop: '2px' }}>Measured RSSI at 1 meter</div>
              </div>
            </div>

            {calibrationDirty && (
              <button className="btn btn-primary" style={{ marginTop: '12px' }} onClick={() => saveCalibration()}>Save Calibration</button>
            )}

            <div style={{ marginTop: '24px' }}>
              <span style={{ fontSize: '0.85rem', fontWeight: 500 }}>Live Beacon Signal Strength (RSSI)</span>
              <div className="signal-bar-chart">
                {liveData.filter(d => d.rssi != null).length === 0 ? (
                  <div style={{ color: '#94a3b8', fontSize: '0.8rem', padding: '16px 0' }}>No active beacons to display</div>
                ) : (
                  liveData.filter(d => d.rssi != null).map((d, i) => {
                    // Ensure a minimum height of 5% so the bar is always visible
                    const pct = Math.max(5, Math.min(100, ((d.rssi + 100) / 70) * 100));
                    const color = d.rssi >= nearThreshold ? '#22c55e' : d.rssi >= farThreshold ? '#f59e0b' : '#ef4444';
                    return (
                      <div key={i} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', flex: 1, height: '100%', justifyContent: 'flex-end' }}>
                        <div className="signal-bar" style={{ height: `${pct}%`, width: '100%', backgroundColor: color }} title={`${d.name}: ${d.rssi} dBm`}></div>
                        <div style={{ fontSize: '0.6rem', color: '#64748b', marginTop: '4px', textAlign: 'center', maxWidth: '50px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{d.name?.split(' ')[0] || d.id}</div>
                      </div>
                    );
                  })
                )}
              </div>
            </div>
          </div>

          {/* Password Management */}
          <div className="settings-card">
            <div className="settings-card-header">
              <KeyRound size={20} className="blue" /> Password Management
            </div>
            <form onSubmit={handlePasswordUpdate}>
              <div className="input-group">
                <label style={{ fontSize: '0.85rem', fontWeight: 500 }}>Select Account</label>
                <select value={pwRole} onChange={e => setPwRole(e.target.value)} style={{ width: '100%', padding: '10px 12px', border: '1px solid #e2e8f0', borderRadius: '6px', fontSize: '0.9rem', outline: 'none', backgroundColor: 'white' }}>
                  <option value="admin">Admin</option>
                  <option value="superadmin">Superadmin</option>
                </select>
              </div>
              <div className="input-group">
                <label style={{ fontSize: '0.85rem', fontWeight: 500 }}>New Username (optional)</label>
                <input type="text" placeholder="Leave blank to keep current" value={pwNewUsername} onChange={e => setPwNewUsername(e.target.value)} />
              </div>
              <div className="input-group" style={{ position: 'relative' }}>
                <label style={{ fontSize: '0.85rem', fontWeight: 500 }}>New Password</label>
                <input type={showNewPassword ? 'text' : 'password'} placeholder="Enter new password" value={pwNewPassword} onChange={e => setPwNewPassword(e.target.value)} />
                <button type="button" onClick={() => setShowNewPassword(!showNewPassword)} style={{ position: 'absolute', right: '10px', top: '32px', background: 'none', border: 'none', cursor: 'pointer', color: '#64748b' }}>
                  {showNewPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                </button>
              </div>
              <div className="input-group">
                <label style={{ fontSize: '0.85rem', fontWeight: 500 }}>Confirm Password</label>
                <input type="password" placeholder="Re-enter new password" value={pwConfirmPassword} onChange={e => setPwConfirmPassword(e.target.value)} />
              </div>
              {pwMessage && <div style={{ fontSize: '0.85rem', marginBottom: '12px', color: pwMessage.startsWith('✅') ? '#16a34a' : '#ef4444' }}>{pwMessage}</div>}
              <button type="submit" className="btn btn-primary">Update Credentials</button>
            </form>
          </div>



        </div>
      </div>
    </div>
  );
};


function App() {
  const [activeTab, setActiveTab] = useState('dashboard');
  const [isAdminUnlocked, setIsAdminUnlocked] = useState(false);
  const [isSuperadminUnlocked, setIsSuperadminUnlocked] = useState(false);
  const [liveData, setLiveData] = useState([]);

  // Setup polling to the server every 2 seconds
  useEffect(() => {
    const fetchEquipment = async () => {
      try {
        const response = await fetch(`${API}/api/equipment`);
        const data = await response.json();
        setLiveData(data);
      } catch (err) {
        // If server is off, suppress error to not spam console
      }
    };

    fetchEquipment();
    const interval = setInterval(fetchEquipment, 2000);
    return () => clearInterval(interval);
  }, []);

  const renderHeaderTitle = () => {
    if (activeTab === 'dashboard') return { title: 'Asset Dashboard', subtitle: 'Monitor and track all medical equipment in real-time' };
    if (activeTab === 'equipment') return { title: 'Equipment Management', subtitle: 'Manage all medical equipment and beacon assignments' };
    if (activeTab === 'settings') return { title: 'Admin Settings', subtitle: 'Configure beacons and location mappings' };
    if (activeTab === 'superadmin') return { title: 'System Core', subtitle: 'Signal calibration, system maintenance, and account management' };
  };

  const headerInfo = renderHeaderTitle();

  return (
    <div className="app-container">
      <Sidebar activeTab={activeTab} setActiveTab={setActiveTab} />
      
      <div className="main-content">
        <div className="top-header">
          <div className="header-title-wrapper">
            <div className="header-title">{headerInfo.title}</div>
            <div className="header-subtitle">{headerInfo.subtitle}</div>
          </div>
          <div className="search-bar">
            <Search size={18} color="#94a3b8" />
            <input type="text" placeholder="Search equipment..." />
          </div>
        </div>
        
        {activeTab === 'dashboard' && <DashboardView liveData={liveData} />}
        {activeTab === 'equipment' && <EquipmentView liveData={liveData} />}
        {activeTab === 'settings' && <SettingsView isUnlocked={isAdminUnlocked} setIsUnlocked={setIsAdminUnlocked} liveData={liveData} />}
        {activeTab === 'superadmin' && <SuperadminView isUnlocked={isSuperadminUnlocked} setIsUnlocked={setIsSuperadminUnlocked} liveData={liveData} />}
      </div>
    </div>
  );
}

export default App;
