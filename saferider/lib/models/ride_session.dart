class RideSession {
  final String rideId;
  final DateTime startTime;
  final DateTime? endTime;
  final double totalDistance; // km
  final double finalScore; // 0-100
  final String userId;
  final bool isActive;

  RideSession({
    required this.rideId,
    required this.startTime,
    this.endTime,
    required this.totalDistance,
    required this.finalScore,
    required this.userId,
    this.isActive = true,
  });

  // Duration of the ride in seconds
  int get durationInSeconds {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime).inSeconds;
  }

  // Average score during ride
  double get avgScore => finalScore;

  // Convert to JSON for API sync
  Map<String, dynamic> toJson() {
    return {
      'ride_id': rideId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'total_distance': totalDistance,
      'final_score': finalScore,
      'user_id': userId,
      'duration_seconds': durationInSeconds,
    };
  }

  // Create from JSON
  factory RideSession.fromJson(Map<String, dynamic> json) {
    return RideSession(
      rideId: json['ride_id'] as String,
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: json['end_time'] != null
          ? DateTime.parse(json['end_time'] as String)
          : null,
      totalDistance: (json['total_distance'] as num).toDouble(),
      finalScore: (json['final_score'] as num).toDouble(),
      userId: json['user_id'] as String,
      isActive: json['is_active'] as bool? ?? false,
    );
  }

  // Convert to SQLite map
  Map<String, dynamic> toSQLiteMap() {
    return {
      'ride_id': rideId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'total_distance': totalDistance,
      'final_score': finalScore,
      'user_id': userId,
      'is_active': isActive ? 1 : 0,
    };
  }

  // Create from SQLite map
  factory RideSession.fromSQLiteMap(Map<String, dynamic> map) {
    return RideSession(
      rideId: map['ride_id'] as String,
      startTime: DateTime.parse(map['start_time'] as String),
      endTime: map['end_time'] != null
          ? DateTime.parse(map['end_time'] as String)
          : null,
      totalDistance: (map['total_distance'] as num).toDouble(),
      finalScore: (map['final_score'] as num).toDouble(),
      userId: map['user_id'] as String,
      isActive: (map['is_active'] as int) == 1,
    );
  }

  // Copy with updates
  RideSession copyWith({
    String? rideId,
    DateTime? startTime,
    DateTime? endTime,
    double? totalDistance,
    double? finalScore,
    String? userId,
    bool? isActive,
  }) {
    return RideSession(
      rideId: rideId ?? this.rideId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      totalDistance: totalDistance ?? this.totalDistance,
      finalScore: finalScore ?? this.finalScore,
      userId: userId ?? this.userId,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  String toString() {
    return 'RideSession(rideId: $rideId, score: $finalScore/100, distance: $totalDistance km)';
  }
}
