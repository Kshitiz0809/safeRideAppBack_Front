# SafeRider - Offline-First Two-Wheeler Telemetry System

> A real-time Flutter prototype for collecting, processing, and scoring two-wheeler riding behavior using sensor fusion, kinematic derivations, and offline-first synchronization.

## 🎯 Project Status

✅ **Phase 1-5 Complete**: All core components implemented and compilation-verified
- Project scaffold & dependencies
- Data models & SQLite database
- Telemetry engine with mathematical derivations
- Heuristic scoring system
- Complete UI layer (Auth, Dashboard, Active Ride)
- Offline-first sync service
- State management with Riverpod

## 🚀 Quick Start

### Prerequisites
```bash
Flutter 3.x+, Dart 3.x+, Firebase Project
```

### Setup
```bash
# 1. Navigate to project
cd d:\Rash_Driving_Pipeline2\saferider

# 2. Install dependencies
flutter pub get

# 3. Configure Firebase
flutterfire configure

# 4. Run the app
flutter run
```

## 📊 Core Features

### Real-Time Telemetry Processing
- **3-Second Sliding Window** for feature evaluation
- **Sensor Fusion** (Complementary Filter): 98% gyroscope + 2% accelerometer
- **Jerk Calculation**: Detects sudden acceleration/braking
- **Cornering Intensity**: Combines lateral acceleration + roll angle

### Intelligent Scoring (0-100)
```
Base: 100
- IF cornering_intensity > 150: deduct (intensity - 150) / 10
- IF jerk_variance > 15: deduct (variance - 15) × 1.5
Result: Clamped to [0, 100]
```

### Status Badges
- 🔴 "Rapid braking & high speed" (Speed > 80 km/h + Brake events ≥ 3)
- 🟠 "Aggressive maneuver" (High cornering intensity or jerk)
- 🟢 "Safe driving" (Optimal conditions)

### Offline-First Architecture
- ✅ Local SQLite queuing
- ✅ Automatic sync on connectivity restoration
- ✅ JSON payload packaging
- ✅ HTTP POST to backend

## 📐 Mathematical Formulas

### Resultant Acceleration
```
a_res = √(ax² + ay² + az²)
```

### Instantaneous Jerk
```
J = (a_res[current] - a_res[previous]) / dt
```

### Sensor Fusion for Roll Angle
```
accel_roll = atan2(ax, √(ay² + az²)) × (180/π)
gyro_rate = ωy × (180/π)
fused_roll = 0.98 × (prev_roll + gyro_rate × dt) + 0.02 × accel_roll
```

### Cornering Intensity
```
CI = |ax| × |fused_roll|
```

## 🏗️ Architecture

```
┌─────────────────────┐
│   Sensors (GPS, Accel, Gyro)
└──────────┬──────────┘
           │
     ┌─────▼─────┐
     │   Engine  │ ← Derivations & Fusion
     └─────┬─────┘
           │
    ┌──────▼──────┐
    │  Scoring    │ ← Heuristic Rules
    └──────┬──────┘
           │
     ┌─────▼─────┐
     │  SQLite   │ ← Local Queue
     └─────┬─────┘
           │
     ┌─────▼─────┐
     │  Sync     │ ← Offline-First
     └─────┬─────┘
           │
  ┌────────▼────────┐
  │  Backend API    │
  └─────────────────┘
```

## 📂 Project Structure

```
lib/
├── main.dart                      # Entry point & routing
├── firebase_config.dart           # Firebase setup
├── models/
│   ├── telemetry_window.dart     # 3-sec metrics
│   └── ride_session.dart          # Ride aggregates
├── services/
│   ├── database_helper.dart       # SQLite CRUD
│   ├── ride_engine_service.dart   # Telemetry engine
│   └── sync_service.dart          # Connectivity & sync
├── providers/
│   └── ride_provider.dart         # Riverpod state
├── screens/
│   ├── login_screen.dart
│   ├── signup_screen.dart
│   ├── dashboard_screen.dart      # Ride history
│   └── active_ride_screen.dart    # Live telemetry
└── widgets/
    ├── status_badge.dart          # Status display
    └── live_score_display.dart    # Score circle
```

## 🔌 Sensor Mapping

| Sensor | Source | Variable | Units |
|--------|--------|----------|-------|
| GPS | `geolocator` | speed | m/s → km/h |
| Accelerometer | `sensors_plus.userAccelerometerEvents` | ax, ay, az | m/s² |
| Gyroscope | `sensors_plus.gyroscopeEvents` | ωy | rad/s → deg/s |

## 💾 Database Schema

### telemetry_windows
```sql
id (TEXT, PK), ride_id (TEXT), timestamp, speed, max_roll, 
max_cornering_intensity, jerk_variance, window_score, 
is_synced (0/1), created_at
Indexes: ride_id, is_synced
```

### ride_sessions
```sql
ride_id (TEXT, PK), user_id, start_time, end_time, 
total_distance, final_score, is_active (0/1), created_at
Indexes: user_id
```

## 🔄 Sync Flow

```
1. Ride Active → Telemetry queued with is_synced=0
2. Ride Stopped → Final sync attempt triggered
3. Offline Check → If no connectivity, remain queued
4. Connectivity Restored → SyncService.syncPendingData()
5. HTTP POST → Package unsync'd windows + send to API
6. 200 OK → Mark windows as is_synced=1
7. Retry Logic → Exponential backoff on 5xx errors
```

## 🧪 Testing

Run the app and:
1. ✅ Create account (Firebase Auth)
2. ✅ Start a ride (tap "Start New Ride")
3. ✅ Observe live score updates (every 3s)
4. ✅ Check status badge changes
5. ✅ View metrics (speed, jerk, cornering, etc.)
6. ✅ Stop ride & observe session save
7. ✅ Toggle airplane mode to test offline sync
8. ✅ Return to dashboard to see ride history chart

## 📋 Implementation Checklist

- [x] Flutter project initialization
- [x] Dependencies added (pubspec.yaml)
- [x] Data models (TelemetryWindow, RideSession)
- [x] SQLite database with CRUD operations
- [x] RideEngineService with mathematical derivations
- [x] Heuristic scoring engine
- [x] Status badge logic
- [x] Firebase Auth (Login/Sign-up)
- [x] Dashboard screen with history & chart
- [x] Active Ride screen with live telemetry
- [x] SyncService with connectivity monitoring
- [x] Riverpod providers for state management
- [x] UI widgets (Score display, Status badge)
- [x] Code compilation (flutter analyze)

## ⚠️ Known Limitations

- **Mock API**: `https://api.saferider.mock/sync` is non-functional (for testing only)
- **Firebase Config**: Requires manual setup with real credentials
- **Thresholds**: Hardcoded values (future: configurable)
- **GPS**: Requires outdoor environment; inaccurate indoors
- **Sensor Delay**: Some lag in real-time updates (~100ms)

## 🔮 Future Enhancements

1. **ML Scoring** - Replace heuristics with trained neural network
2. **Production Backend** - Real API with user profiles and analytics
3. **Leaderboards** - Social features and competitive scores
4. **Trip Playback** - Visualize sensor data over map
5. **Alerts** - Push notifications for unsafe behavior
6. **Export** - PDF reports and data downloads
7. **Advanced Filters** - Time-based, location-based analytics

## 📚 Documentation

- **ARCHITECTURE.md** - Detailed technical design
- **pubspec.yaml** - Dependency specifications
- **Code Comments** - Inline documentation

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| **Framework** | Flutter |
| **State Management** | Riverpod |
| **Database** | SQLite (sqflite) |
| **Sensors** | sensors_plus, geolocator |
| **Auth** | Firebase Auth |
| **UI** | Material Design 3, fl_chart |
| **Networking** | http, connectivity_plus |

## 📞 Support

For issues or questions:
1. Check ARCHITECTURE.md for detailed explanations
2. Review inline code comments
3. Verify Firebase credentials in firebase_config.dart
4. Ensure all Android/iOS permissions are granted

## 📄 License

Prototype for educational/demonstration purposes.

---

**Version**: 0.1.0 | **Status**: Ready for Testing | **Last Updated**: 2026-06-11
