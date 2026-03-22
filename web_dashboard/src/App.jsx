import React, { useState, useEffect } from 'react';
import { LayoutDashboard, Package, Settings, Search, Box, Radio, AlertTriangle, Lock, Unlock, Edit2 } from 'lucide-react';
import './index.css';

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
            <th>Last Seen</th>
          </tr>
        </thead>
        <tbody>
          {liveData.length === 0 ? (
            <tr><td colSpan="4" style={{textAlign:'center', padding: '32px'}}>Scanning for assets...</td></tr>
          ) : (
             liveData.map((eq) => (
              <tr key={eq.id}>
                <td>{eq.id}</td>
                <td style={{ fontWeight: 500, color: '#1e293b' }}>{eq.name}</td>
                <td>{eq.location || 'Unknown'}</td>
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

const SettingsView = ({ isUnlocked, setIsUnlocked, liveData }) => {
  const [adminId, setAdminId] = useState('');
  const [password, setPassword] = useState('');
  const [nearThreshold, setNearThreshold] = useState(-65);
  const [farThreshold, setFarThreshold] = useState(-85);

  const handleUnlock = (e) => {
    e.preventDefault();
    if (adminId && password) {
      setIsUnlocked(true);
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
              <button type="submit" className="auth-btn">
                <Unlock size={18} /> Unlock Settings
              </button>
            </form>
          </div>
        </div>
      )}

      <div className="content-area" style={{ filter: !isUnlocked ? 'blur(4px)' : 'none', pointerEvents: !isUnlocked ? 'none' : 'auto' }}>
        <div className="settings-grid">
          
          <div className="settings-card">
            <div className="settings-card-header">
              <Settings size={20} className="blue" /> Signal Calibration
            </div>
            
            <div className="slider-group">
              <div className="slider-group-header">
                <span>Near Zone Threshold</span>
                <span className="slider-val">{nearThreshold} dBm</span>
              </div>
              <input type="range" min="-100" max="-30" value={nearThreshold} onChange={e => setNearThreshold(e.target.value)} />
            </div>

            <div className="slider-group">
              <div className="slider-group-header">
                <span>Far Zone Threshold</span>
                <span className="slider-val">{farThreshold} dBm</span>
              </div>
              <input type="range" min="-100" max="-30" value={farThreshold} onChange={e => setFarThreshold(e.target.value)} />
            </div>

            <div style={{ marginTop: '32px' }}>
              <span style={{ fontSize: '0.85rem', fontWeight: 500 }}>Real-time Signal Strength</span>
              <div className="signal-bar-chart">
                {/* Mocking the bars */}
                {[50, 50, 50, 60, 50, 50, 50, 50, 60, 40, 50, 40, 40, 50, 60].map((h, i) => (
                  <div key={i} className="signal-bar" style={{ height: `${h}%` }}></div>
                ))}
              </div>
            </div>
          </div>

          <div className="settings-row">
            <div className="settings-card">
              <div className="settings-card-header" style={{ justifyContent: 'space-between', marginBottom: '16px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <Radio size={20} className="blue" /> Beacon Management
                </div>
                <button className="btn btn-primary">+ Add Beacon</button>
              </div>

              {liveData.slice(0,3).map((eq, i) => (
                <div key={eq.id || i} style={{ display: 'flex', justifyContent: 'space-between', padding: '16px 0', borderBottom: '1px solid #e2e8f0' }}>
                  <div>
                    <div style={{ fontWeight: 500, fontSize: '0.9rem' }}>{eq.beaconId}</div>
                    <div style={{ fontSize: '0.8rem', color: '#64748b', display: 'flex', alignItems: 'center', gap: '4px' }}>
                      <span style={{ width: 6, height: 6, borderRadius: '50%', backgroundColor: eq.status === 'Active' ? '#22c55e' : '#cbd5e1', display: 'inline-block' }}></span> 
                      {eq.location || 'Unknown'}
                    </div>
                  </div>
                  <button style={{ background: 'none', border: 'none', cursor: 'pointer', color: '#94a3b8' }}><Edit2 size={16} /></button>
                </div>
              ))}
            </div>

            <div className="settings-card danger-zone">
               <div className="settings-card-header">
                  <AlertTriangle size={20} /> System Maintenance
               </div>
               <div className="danger-text">
                 <strong>Danger Zone</strong><br/>
                 These actions cannot be undone. Please proceed with caution.
               </div>
               <button className="btn-danger-outline"><AlertTriangle size={16} style={{marginRight: '8px'}} /> Clear History Logs</button>
               <button className="btn-danger-solid"><AlertTriangle size={16} style={{marginRight: '8px'}} /> Factory Reset</button>
            </div>
          </div>

        </div>
      </div>
    </div>
  );
};


function App() {
  const [activeTab, setActiveTab] = useState('dashboard');
  const [isAdminUnlocked, setIsAdminUnlocked] = useState(false);
  const [liveData, setLiveData] = useState([]);

  // Setup polling to the server every 2 seconds
  useEffect(() => {
    const fetchEquipment = async () => {
      try {
        const response = await fetch('http://localhost:3000/api/equipment');
        const data = await response.json();
        setLiveData(data);
      } catch (err) {
        // If server is off, suppress error to not spam console
      }
    };

    fetchEquipment(); // Initial fetch
    const interval = setInterval(fetchEquipment, 2000);
    return () => clearInterval(interval);
  }, []);

  // Derive page title
  const renderHeaderTitle = () => {
    if (activeTab === 'dashboard') return { title: 'Asset Dashboard', subtitle: 'Monitor and track all medical equipment in real-time' };
    if (activeTab === 'equipment') return { title: 'Equipment Management', subtitle: 'Manage all medical equipment and beacon assignments' };
    if (activeTab === 'settings') return { title: 'Admin Settings', subtitle: 'Configure system parameters and manage beacons' };
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
      </div>
    </div>
  );
}

export default App;
