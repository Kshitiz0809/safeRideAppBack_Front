class TelemetryWindow {
  final String id;
  final DateTime timestamp;
  final double speed; // km/h
  final double maxRoll; // degrees
  final double maxCorneringIntensity;
  /// Root-mean-square of per-sample jerk values in the window (API key: jerk_variance).
  final double jerkVariance;
  final double windowScore; // 0-100
  final bool isSynced;
  final String? rideId;

  TelemetryWindow({
    required this.id,
    required this.timestamp,
    required this.speed,
    required this.maxRoll,
    required this.maxCorneringIntensity,
    required this.jerkVariance,
    required this.windowScore,
    this.isSynced = false,
    this.rideId,
  });

  // Convert to JSON for API sync
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'speed': speed,
      'max_roll': maxRoll,
      'max_cornering_intensity': maxCorneringIntensity,
      'jerk_variance': jerkVariance,
      'window_score': windowScore,
      'ride_id': rideId,
    };
  }

  // Convert from JSON (for API responses)
  factory TelemetryWindow.fromJson(Map<String, dynamic> json) {
    return TelemetryWindow(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      speed: (json['speed'] as num).toDouble(),
      maxRoll: (json['max_roll'] as num).toDouble(),
      maxCorneringIntensity: (json['max_cornering_intensity'] as num).toDouble(),
      jerkVariance: (json['jerk_variance'] as num).toDouble(),
      windowScore: (json['window_score'] as num).toDouble(),
      isSynced: json['is_synced'] as bool? ?? false,
      rideId: json['ride_id'] as String?,
    );
  }

  // Convert to SQLite map
  Map<String, dynamic> toSQLiteMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'speed': speed,
      'max_roll': maxRoll,
      'max_cornering_intensity': maxCorneringIntensity,
      'jerk_variance': jerkVariance,
      'window_score': windowScore,
      'is_synced': isSynced ? 1 : 0,
      'ride_id': rideId,
    };
  }

  // Create from SQLite map
  factory TelemetryWindow.fromSQLiteMap(Map<String, dynamic> map) {
    return TelemetryWindow(
      id: map['id'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      speed: (map['speed'] as num).toDouble(),
      maxRoll: (map['max_roll'] as num).toDouble(),
      maxCorneringIntensity: (map['max_cornering_intensity'] as num).toDouble(),
      jerkVariance: (map['jerk_variance'] as num).toDouble(),
      windowScore: (map['window_score'] as num).toDouble(),
      isSynced: (map['is_synced'] as int) == 1,
      rideId: map['ride_id'] as String?,
    );
  }

  @override
  String toString() {
    return 'TelemetryWindow(id: $id, timestamp: $timestamp, speed: $speed km/h, score: $windowScore/100)';
  }
}
