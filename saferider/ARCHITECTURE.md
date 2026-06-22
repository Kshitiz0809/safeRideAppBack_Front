# SafeRider - Offline-First Two-Wheeler Telemetry & Rider Scoring System

## Overview
SafeRider is a Flutter-based prototype for real-time telemetry collection, kinematic feature derivation, and rider behavior scoring on two-wheelers. It uses sensor fusion, offline-first architecture, and heuristic-based scoring to provide riders with immediate feedback on their driving safety.

## Architecture

### Core Components

#### 1. **RideEngineService** (`lib/services/ride_engine_service.dart`)
The heart of the system that implements all mathematical derivations:
- **3-Second Sliding Window**: Real-time processing of sensor data
- **Sensor Fusion**: Complementary filter combining accelerometer (0.02) and gyroscope (0.98) for accurate roll angle
- **Feature Derivations**:
  - Resultant acceleration: √(ax² + ay² + az²)
  - Instantaneous jerk: (current_ares - previous_ares) / dt
  - Fused roll angle: 0.98 × (prev_roll + gyro_rate × dt) + 0.02 × accel_roll
  - Cornering intensity: |ax| × |fused_roll|

#### 2. **Heuristic Scoring Engine**
Evaluates 3-second windows with:
- **Base Score**: 100
- **Cornering Deduction**: (max_intensity - 150) / 10 if > 150
- **Jerk Deduction**: (jerk_variance - 15) × 1.5 if > 15
- **Final Score**: Clamped to [0, 100]

#### 3. **Status Badge Rules**
- `Speed > 80 km/h AND brake_count ≥ 3` → "Rapid braking and high speed detected"
- `Speed > 80 km/h` → "Unsafe due to high speed"
- `Cornering intensity > 150 OR jerk_variance > 15` → "Aggressive maneuver detected"
- Default → "Safe driving"

#### 4. **DatabaseHelper** (`lib/services/database_helper.dart`)
SQLite-based local storage:
- `telemetry_windows`: Raw sensor-derived metrics (id, timestamp, speed, roll, cornering_intensity, jerk_variance, score, is_synced)
- `ride_sessions`: Aggregated ride data (ride_id, user_id, start_time, end_time, total_distance, final_score)

#### 5. **SyncService** (`lib/services/sync_service.dart`)
Offline-first synchronization:
- Monitors connectivity via `connectivity_plus`
- Queues unsynchronized telemetry windows
- Packages into JSON payloads on connectivity restoration
- POSTs to mock API: `https://api.saferider.mock/sync`
- Marks windows as synced on 200 OK response

#### 6. **Firebase Authentication** 
Email/Password login with state management via `flutter_riverpod`

### Data Models

#### TelemetryWindow
```dart
- id: String (UUID)
- timestamp: DateTime
- speed: double (km/h)
- maxRoll: double (degrees)
- maxCorneringIntensity: double
- jerkVariance: double
- windowScore: double (0-100)
- isSynced: bool
- rideId: String (foreign key)
```

#### RideSession
```dart
- rideId: String (UUID)
- userId: String (Firebase UID)
- startTime: DateTime
- endTime: DateTime?
- totalDistance: double (km)
- finalScore: double (0-100)
- isActive: bool
```

## UI Screens

### 1. **Login / Sign-Up Screens**
- Firebase Authentication
- Email/Password validation
- Error handling

### 2. **Dashboard Screen**
- Welcome card with user info
- "Start New Ride" button
- Line chart showing score trends (`fl_chart`)
- Ride history with scores, distance, duration

### 3. **Active Ride Screen**
- **Live Score Display**: Large circular indicator (0-100) with color gradient
  - Green: 80+
  - Orange: 60-79
  - Red: <60
- **Status Badge**: Dynamic color-coded driving status
- **Real-Time Metrics**:
  - Current speed (km/h)
  - Jerk variance
  - Cornering intensity
  - Roll angle (degrees)
  - Brake event counter
- **Stop Ride Button**: Saves session and triggers sync

## Sensor Mapping

| Sensor | Hardware Source | Variable | Unit |
|--------|-----------------|----------|------|
| **GPS** | `geolocator` | speed | m/s (converted to km/h) |
| **Accelerometer** | `sensors_plus.userAccelerometerEvents` | ax, ay, az | m/s² (gravity removed) |
| **Gyroscope** | `sensors_plus.gyroscopeEvents` | ωy | rad/s (converted to deg/s) |

## Math Implementation Details

### Complementary Filter (Roll Angle Fusion)
```
accel_roll = atan2(ax, √(ay² + az²)) × (180/π)
gyro_rate = ωy × (180/π)
fused_roll_n = 0.98 × (fused_roll_n-1 + gyro_rate × dt) + 0.02 × accel_roll
```
The 0.98/0.02 weighting prioritizes gyroscope integration (smooth) while correcting drift with accelerometer (stable).

### Jerk Calculation
```
jerk = (ares[n] - ares[n-1]) / dt
jerk_variance = Var(jerk_array) over 3-second window
```
High jerk variance indicates abrupt acceleration or braking.

### Cornering Intensity
```
ci = |ax| × |fused_roll|
```
Combines lateral acceleration magnitude with lean angle for aggressiveness measure.

## State Management (Riverpod)

### Providers
- `rideEngineServiceProvider`: ChangeNotifier for live telemetry
- `syncServiceProvider`: FutureProvider for async sync initialization
- `databaseHelperProvider`: Singleton database instance
- UI providers: Score, status, speed, jerk, etc. (watch from rideEngineServiceProvider)

## API Integration

### Mock Endpoint
**POST** `https://api.saferider.mock/sync`

**Request Payload**:
```json
{
  "timestamp": "2026-06-11T15:12:59.675Z",
  "windows": [
    {
      "id": "uuid",
      "timestamp": "2026-06-11T15:12:50.000Z",
      "speed": 45.5,
      "max_roll": 12.3,
      "max_cornering_intensity": 98.5,
      "jerk_variance": 8.2,
      "window_score": 92.1,
      "ride_id": "ride_uuid"
    }
  ]
}
```

**Response**: 200 OK marks windows as synced

## Setup Instructions

### Prerequisites
- Flutter 3.x+
- Dart 3.x+
- Android SDK 28+ / iOS 13+

### Installation

1. **Clone and navigate**:
   ```bash
   cd d:\Rash_Driving_Pipeline2\saferider
   ```

2. **Get dependencies**:
   ```bash
   flutter pub get
   ```

3. **Configure Firebase**:
   ```bash
   flutterfire configure
   ```
   Replace placeholders in `lib/firebase_config.dart` with actual credentials.

4. **Android permissions** (`android/app/src/main/AndroidManifest.xml`):
   ```xml
   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
   <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
   <uses-permission android:name="android.permission.INTERNET" />
   ```

5. **iOS permissions** (`ios/Runner/Info.plist`):
   ```xml
   <key>NSLocationWhenInUseUsageDescription</key>
   <string>SafeRider needs location to track speed and distance</string>
   <key>NSMotionUsageDescription</key>
   <string>SafeRider needs motion sensors for riding analysis</string>
   ```

6. **Run**:
   ```bash
   flutter run
   ```

## Testing Checklist

- [ ] Login/Sign-up with Firebase
- [ ] Start ride - sensors subscribe, engine initializes
- [ ] Live score updates every 3 seconds
- [ ] Status badge changes based on speed/jerk/cornering
- [ ] Metrics display real-time values
- [ ] Stop ride - saves session, triggers sync
- [ ] Offline mode - data queued, syncs on reconnect
- [ ] Dashboard shows ride history and chart

## Performance Considerations

- **Window Size**: 3 seconds balances responsiveness vs. noise
- **Complementary Filter**: 98% gyro / 2% accel optimal for mobile sensors
- **SQLite Indexing**: Indexes on ride_id and is_synced for fast queries
- **Sensor Polling**: ~60Hz (0.016s default dt)

## Future Enhancements

1. **Machine Learning Scoring**: Replace heuristics with trained model
2. **Real Backend**: Production API with authentication and user profiles
3. **Leaderboards**: Compare scores with other riders
4. **Trip Playback**: Visualize sensor data playback
5. **Advanced Analytics**: Trip breakdown, hotspots, improvement areas
6. **Notifications**: Real-time alerts for unsafe behavior

## Known Limitations

- Mock API endpoint (non-functional)
- GPS requires outdoor environment
- Sensor accuracy depends on device hardware
- Heuristic thresholds hardcoded (future: configurable)
- No trip averaging (each window scored independently)

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter` | SDK | Framework |
| `riverpod` | 2.4.0 | State management |
| `sqflite` | 2.3.0 | Local database |
| `sensors_plus` | 1.4.0 | Accelerometer/Gyroscope |
| `geolocator` | 9.0.2 | GPS/Speed |
| `firebase_auth` | 4.15.0 | Authentication |
| `fl_chart` | 0.64.0 | Dashboard charts |
| `connectivity_plus` | 5.0.0 | Connectivity monitoring |
| `http` | 1.1.0 | API requests |
| `uuid` | 4.0.0 | ID generation |

## File Structure

```
lib/
├── main.dart                    # Entry point, routing
├── firebase_config.dart         # Firebase configuration
├── models/
│   ├── telemetry_window.dart   # Sensor-derived metrics model
│   └── ride_session.dart        # Ride aggregation model
├── services/
│   ├── database_helper.dart     # SQLite CRUD
│   ├── ride_engine_service.dart # Core telemetry engine
│   └── sync_service.dart        # Offline-first sync
├── providers/
│   └── ride_provider.dart       # Riverpod state providers
├── screens/
│   ├── login_screen.dart        # Authentication
│   ├── signup_screen.dart       # Registration
│   ├── dashboard_screen.dart    # Ride history & analytics
│   └── active_ride_screen.dart  # Live telemetry UI
└── widgets/
    ├── status_badge.dart        # Dynamic status display
    └── live_score_display.dart  # Circular score indicator
```

---

**Version**: 0.1.0  
**Last Updated**: 2026-06-11  
**Status**: Prototype (Ready for testing)
