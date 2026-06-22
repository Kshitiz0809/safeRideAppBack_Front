import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import '../models/telemetry_window.dart';
import '../models/ride_session.dart';
import 'database_helper.dart';
import 'package:uuid/uuid.dart';

/// Aggregates phone sensors into fixed [windowDurationSeconds] windows.
///
/// Calibration phase (first [calibrationDurationSeconds]): collects baseline
/// accel magnitude to establish a noise floor; gyro median-filtered throughout.
/// Per-sample: roll from gravity accel; jerk from filtered user-accel magnitude
/// with dead-band suppression; cornering from lateral accel scaled by speed.
/// Per-window: max roll, max cornering, RMS(trimmed jerk), soft-penalty score.
class RideEngineService extends ChangeNotifier {
  static const double windowDurationSeconds = 3.0;
  static const double calibrationDurationSeconds = 5.0;
  static const int _gyroMedianWindowSize = 5;

  static const double jerkVarianceThreshold = 18.0;
  static const double corneringIntensityThreshold = 35.0;
  static const double movingSpeedThreshold = 5.0;
  static const double lowConfidenceScoreCap = 82.0;
  static const double accelerationFilterTau = 0.35;
  static const double minimumSensorDtSeconds = 0.02;
  static const double maximumJerkSample = 80.0;

  String? _currentRideId;
  bool _isRecording = false;
  double _currentFusedRoll = 0.0;
  int _totalBrakeCount = 0;
  DateTime? _lastUserAccelTime;
  DateTime? _lastGyroTime;
  double _totalDistance = 0.0;
  Position? _lastPosition;

  // Calibration state
  bool _isCalibrating = false;
  int _calibrationSecondsRemaining = 0;
  final List<double> _calibAccelSamples = [];
  Timer? _calibrationTimer;

  // Noise cancellation
  final List<double> _gyroBuffer = [];

  final List<double> _jerkValues = [];
  final List<double> _rollAngles = [];
  final List<double> _corneringIntensities = [];
  final List<double> _speeds = [];
  final List<double> _windowScores = [];
  double _lastAres = 0.0;
  double _filteredAres = 0.0;
  bool _hasFilteredAcceleration = false;
  int _totalWindowCount = 0;
  int _movingWindowCount = 0;

  StreamSubscription? _gravityAccelSubscription;
  StreamSubscription? _userAccelSubscription;
  StreamSubscription? _gyroSubscription;
  StreamSubscription? _gpsSubscription;
  Timer? _windowTimer;
  Timer? _demoTickTimer;

  bool _isDemoMode = false;
  bool _isPaused = false;
  int _demoElapsedSeconds = 0;
  int _demoWindowIndex = 0;
  DateTime? _rideStartTime;
  DateTime? _pausedAt;
  Duration _totalPausedDuration = Duration.zero;
  final List<double> _speedSamples = [];

  double _currentScore = 85.0;
  String _statusBadge = "Calibrating";
  double _currentSpeed = 0.0;
  double _currentJerkVariance = 0.0;
  double _currentMaxCorneringIntensity = 0.0;
  double _currentMaxRoll = 0.0;

  String? get currentRideId => _currentRideId;
  bool get isRecording => _isRecording;
  bool get isDemoMode => _isDemoMode;
  bool get isPaused => _isPaused;
  bool get isCalibrating => _isCalibrating;
  int get calibrationSecondsRemaining => _calibrationSecondsRemaining;
  double get totalDistance => _totalDistance;
  DateTime? get rideStartTime => _rideStartTime;
  double get averageSpeed {
    if (_speedSamples.isEmpty) return _currentSpeed;
    return _speedSamples.reduce((a, b) => a + b) / _speedSamples.length;
  }

  Duration get rideDuration {
    if (_rideStartTime == null) return Duration.zero;
    final elapsed = DateTime.now().difference(_rideStartTime!) - _totalPausedDuration;
    if (_isPaused && _pausedAt != null) {
      return elapsed - DateTime.now().difference(_pausedAt!);
    }
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  double get currentScore => _currentScore;
  String get statusBadge => _statusBadge;
  double get currentSpeed => _currentSpeed;
  int get totalBrakeCount => _totalBrakeCount;
  double get currentJerkVariance => _currentJerkVariance;
  double get currentMaxCorneringIntensity => _currentMaxCorneringIntensity;
  double get currentMaxRoll => _currentMaxRoll;

  final DatabaseHelper _db = DatabaseHelper();

  Future<void> startRide(String userId, {bool demoMode = false}) async {
    if (_isRecording) return;
    _isDemoMode = demoMode;
    _isPaused = false;
    _rideStartTime = DateTime.now();
    _pausedAt = null;
    _totalPausedDuration = Duration.zero;
    _speedSamples.clear();
    _currentRideId = const Uuid().v4();
    _isRecording = true;
    _currentFusedRoll = 0.0;
    _totalBrakeCount = 0;
    _totalDistance = demoMode ? 0.4 : 0.0;
    _lastPosition = null;
    _lastAres = 0.0;
    _filteredAres = 0.0;
    _hasFilteredAcceleration = false;
    _totalWindowCount = 0;
    _movingWindowCount = 0;
    _demoElapsedSeconds = 0;
    _demoWindowIndex = 0;
    _currentScore = demoMode ? 82.0 : 85.0;
    _statusBadge = demoMode ? "Safe driving" : "Calibrating";
    _currentSpeed = demoMode ? 44.0 : 0.0;
    _currentJerkVariance = demoMode ? 8.0 : 0.0;
    _currentMaxCorneringIntensity = demoMode ? 22.0 : 0.0;
    _currentMaxRoll = demoMode ? 4.0 : 0.0;
    _lastUserAccelTime = DateTime.now();
    _lastGyroTime = DateTime.now();
    _clearBuffers();
    _windowScores.clear();
    _gyroBuffer.clear();

    // Calibration phase (real rides only)
    if (!demoMode) {
      _isCalibrating = true;
      _calibrationSecondsRemaining = calibrationDurationSeconds.toInt();
      _calibAccelSamples.clear();
      _startCalibrationCountdown();
    } else {
      _isCalibrating = false;
    }

    await _db.insertRideSession(RideSession(
      rideId: _currentRideId!,
      userId: userId,
      startTime: DateTime.now(),
      totalDistance: _totalDistance,
      finalScore: _currentScore,
      isActive: true,
    ));

    if (demoMode) {
      _demoTickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickDemoRide());
      _windowTimer = Timer.periodic(const Duration(seconds: 3), (_) => _evaluateDemoWindow());
    } else {
      _subscribeToSensors();
      _windowTimer = Timer.periodic(const Duration(seconds: 3), (_) => _evaluateWindow());
    }
    notifyListeners();
  }

  void _startCalibrationCountdown() {
    _calibrationTimer?.cancel();
    _calibrationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isRecording) {
        timer.cancel();
        return;
      }
      _calibrationSecondsRemaining--;
      if (_calibrationSecondsRemaining <= 0) {
        timer.cancel();
        _calibAccelSamples.clear();
        _isCalibrating = false;
        _statusBadge = "Safe driving";
      }
      notifyListeners();
    });
  }

  Future<void> stopRide() async {
    if (!_isRecording || _currentRideId == null) return;
    _isCalibrating = false;
    _calibrationTimer?.cancel();

    if (_isDemoMode) {
      await _evaluateDemoWindow();
    } else {
      await _evaluateWindow();
    }
    final session = await _db.getRideSessionById(_currentRideId!);
    if (session != null) {
      final localFinalScore = _calculateFinalRideScore();
      await _db.updateRideSession(session.copyWith(
        endTime: DateTime.now(),
        isActive: false,
        totalDistance: _totalDistance,
        finalScore: localFinalScore,
      ));
    }
    _isRecording = false;
    _isDemoMode = false;
    _isPaused = false;
    _rideStartTime = null;
    _unsubscribeFromSensors();
    _windowTimer?.cancel();
    _demoTickTimer?.cancel();
    notifyListeners();
  }

  void pauseRide() {
    if (!_isRecording || _isPaused) return;
    _isPaused = true;
    _pausedAt = DateTime.now();
    _windowTimer?.cancel();
    _demoTickTimer?.cancel();
    if (!_isDemoMode) {
      _unsubscribeFromSensors();
    }
    notifyListeners();
  }

  void resumeRide() {
    if (!_isRecording || !_isPaused) return;
    if (_pausedAt != null) {
      _totalPausedDuration += DateTime.now().difference(_pausedAt!);
    }
    _isPaused = false;
    _pausedAt = null;
    if (_isDemoMode) {
      _demoTickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickDemoRide());
      _windowTimer = Timer.periodic(const Duration(seconds: 3), (_) => _evaluateDemoWindow());
    } else {
      _subscribeToSensors();
      _windowTimer = Timer.periodic(const Duration(seconds: 3), (_) => _evaluateWindow());
    }
    notifyListeners();
  }

  void _tickDemoRide() {
    if (!_isRecording || !_isDemoMode || _isPaused) return;
    _demoElapsedSeconds++;
    _totalDistance += 0.08;

    final phase = _demoPhaseForElapsedSeconds(_demoElapsedSeconds);
    _currentScore = phase.score;
    _statusBadge = phase.status;
    _currentSpeed = phase.speed;
    _speedSamples.add(phase.speed);
    _currentJerkVariance = phase.jerk;
    _currentMaxCorneringIntensity = phase.cornering;
    _currentMaxRoll = phase.roll;
    notifyListeners();
  }

  _DemoRidePhase _demoPhaseForElapsedSeconds(int elapsedSeconds) {
    if (elapsedSeconds <= 6) {
      return const _DemoRidePhase(score: 82, status: 'Safe driving', speed: 44, jerk: 8, cornering: 22, roll: 4);
    }
    if (elapsedSeconds <= 9) {
      return const _DemoRidePhase(score: 56, status: 'Aggressive Maneuver', speed: 52, jerk: 29, cornering: 98, roll: 14);
    }
    if (elapsedSeconds <= 12) {
      return const _DemoRidePhase(score: 49, status: 'High Speed Warning', speed: 86, jerk: 16, cornering: 38, roll: 6);
    }
    if (elapsedSeconds <= 15) {
      return const _DemoRidePhase(score: 53, status: 'Aggressive Maneuver', speed: 58, jerk: 31, cornering: 105, roll: 16);
    }
    return const _DemoRidePhase(score: 76, status: 'Safe driving', speed: 46, jerk: 10, cornering: 24, roll: 5);
  }

  _DemoRidePhase _demoPhaseForWindow(int windowIndex) {
    switch (windowIndex) {
      case 0:
      case 1:
        return const _DemoRidePhase(score: 82, status: 'Safe driving', speed: 44, jerk: 8, cornering: 22, roll: 4);
      case 2:
        return const _DemoRidePhase(score: 56, status: 'Aggressive Maneuver', speed: 52, jerk: 29, cornering: 98, roll: 14, countBrake: true);
      case 3:
        return const _DemoRidePhase(score: 49, status: 'High Speed Warning', speed: 86, jerk: 16, cornering: 38, roll: 6);
      case 4:
        return const _DemoRidePhase(score: 53, status: 'Aggressive Maneuver', speed: 58, jerk: 31, cornering: 105, roll: 16, countBrake: true);
      default:
        return const _DemoRidePhase(score: 76, status: 'Safe driving', speed: 46, jerk: 10, cornering: 24, roll: 5);
    }
  }

  Future<void> _evaluateDemoWindow() async {
    if (!_isRecording || _currentRideId == null || !_isDemoMode || _isPaused) return;

    final phase = _demoPhaseForWindow(_demoWindowIndex);
    _currentScore = phase.score;
    _statusBadge = phase.status;
    _currentSpeed = phase.speed;
    _speedSamples.add(phase.speed);
    _currentJerkVariance = phase.jerk;
    _currentMaxCorneringIntensity = phase.cornering;
    _currentMaxRoll = phase.roll;

    if (phase.countBrake) _totalBrakeCount++;
    _totalWindowCount++;
    _movingWindowCount++;
    _windowScores.add(phase.score);
    _totalDistance += 0.35;

    await _db.insertTelemetryWindow(TelemetryWindow(
      id: const Uuid().v4(),
      timestamp: DateTime.now(),
      speed: phase.speed,
      maxRoll: phase.roll,
      maxCorneringIntensity: phase.cornering,
      jerkVariance: phase.jerk,
      windowScore: phase.score,
      isSynced: true,
      rideId: _currentRideId,
    ));

    _demoWindowIndex++;
    notifyListeners();
  }

  void _subscribeToSensors() {
    _gravityAccelSubscription = accelerometerEventStream()
        .listen((event) => _onGravityAccelerometerData(event.x, event.y, event.z));
    _userAccelSubscription = userAccelerometerEventStream()
        .listen((event) => _onUserAccelerometerData(event.x, event.y, event.z));
    _gyroSubscription = gyroscopeEventStream()
        .listen((event) => _onGyroscopeData(event.y));
    _gpsSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 1),
    ).listen((pos) => _onGPSData(position: pos));
  }

  void _onGravityAccelerometerData(double ax, double ay, double az) {
    if (!_isRecording || _isPaused) return;
    final accelRoll = atan2(ax, sqrt(ay * ay + az * az)) * (180 / pi);
    _currentMaxRoll = accelRoll.abs();
    _rollAngles.add(_currentMaxRoll);
    notifyListeners();
  }

  void _onUserAccelerometerData(double ax, double ay, double az) {
    if (!_isRecording || _isPaused) return;
    final now = DateTime.now();
    final dt = _calculateDeltaTime(now, _lastUserAccelTime);
    final ares = sqrt(ax * ax + ay * ay + az * az);

    // During calibration: collect baseline, do not compute jerk
    if (_isCalibrating) {
      _calibAccelSamples.add(ares);
      _filteredAres = ares;
      _lastAres = ares;
      _hasFilteredAcceleration = true;
      _lastUserAccelTime = now;
      return;
    }

    if (!_hasFilteredAcceleration) {
      _filteredAres = ares;
      _lastAres = ares;
      _hasFilteredAcceleration = true;
      _lastUserAccelTime = now;
      return;
    }

    final alpha = dt / (accelerationFilterTau + dt);
    _filteredAres = _filteredAres + alpha * (ares - _filteredAres);

    final jerk = ((_filteredAres - _lastAres).abs() / dt).clamp(0.0, maximumJerkSample);
    _jerkValues.add(jerk);
    _lastAres = _filteredAres;

    final speedFactor = max(1.0, _currentSpeed / 20.0);
    final lateralAcceleration = sqrt(ax * ax + ay * ay);
    _corneringIntensities.add(lateralAcceleration * speedFactor * 10.0);

    _lastUserAccelTime = now;
    notifyListeners();
  }

  void _onGyroscopeData(double omegaY) {
    if (!_isRecording || _isPaused) return;
    final now = DateTime.now();
    final dt = _calculateDeltaTime(now, _lastGyroTime);

    // Median filter to suppress gyro spikes
    _gyroBuffer.add(omegaY);
    if (_gyroBuffer.length > _gyroMedianWindowSize) _gyroBuffer.removeAt(0);
    final filteredOmega = _medianOf(_gyroBuffer);

    final gyroRate = filteredOmega * (180 / pi);
    final accelRoll = _rollAngles.isNotEmpty ? _rollAngles.last : 0.0;
    _currentFusedRoll = 0.98 * (_currentFusedRoll + gyroRate * dt) + 0.02 * accelRoll;
    _lastGyroTime = now;
  }

  void _onGPSData({required Position position}) {
    if (!_isRecording || _isPaused) return;
    _currentSpeed = position.speed * 3.6;
    _speeds.add(_currentSpeed);
    _speedSamples.add(_currentSpeed);
    if (_lastPosition != null) {
      _totalDistance += Geolocator.distanceBetween(
        _lastPosition!.latitude, _lastPosition!.longitude,
        position.latitude, position.longitude,
      ) / 1000.0;
    }
    _lastPosition = position;
    notifyListeners();
  }

  Future<void> _evaluateWindow() async {
    if (!_isRecording || _currentRideId == null || _isPaused) return;
    if (_jerkValues.isEmpty && _corneringIntensities.isEmpty) return;

    double avgSpeed = _speeds.isEmpty ? 0.0 : _speeds.reduce((a, b) => a + b) / _speeds.length;
    final isLowMotionWindow = avgSpeed < movingSpeedThreshold && _totalDistance < 0.02;

    _currentJerkVariance = isLowMotionWindow || _jerkValues.isEmpty
        ? 0.0
        : _calculateRms(_trimOutliers(_jerkValues));
    _currentMaxCorneringIntensity =
        _corneringIntensities.isEmpty ? 0.0 : _corneringIntensities.reduce(max);
    _currentMaxRoll = _rollAngles.isEmpty ? 0.0 : _rollAngles.reduce(max);
    if (isLowMotionWindow) _currentMaxCorneringIntensity = 0.0;

    if (!isLowMotionWindow && _currentJerkVariance > jerkVarianceThreshold) _totalBrakeCount++;
    _totalWindowCount++;
    if (avgSpeed >= movingSpeedThreshold) _movingWindowCount++;

    _currentScore = _calculateWindowScore(
      ci: _currentMaxCorneringIntensity,
      jv: _currentJerkVariance,
      avgSpeed: avgSpeed,
      isLowMotionWindow: isLowMotionWindow,
    );
    _windowScores.add(_currentScore);
    _statusBadge = _evaluateStatusBadge(avgSpeed, _currentMaxCorneringIntensity, _currentJerkVariance);

    await _db.insertTelemetryWindow(TelemetryWindow(
      id: const Uuid().v4(),
      timestamp: DateTime.now(),
      speed: avgSpeed,
      maxRoll: _currentMaxRoll,
      maxCorneringIntensity: _currentMaxCorneringIntensity,
      jerkVariance: _currentJerkVariance,
      windowScore: _currentScore,
      isSynced: false,
      rideId: _currentRideId,
    ));

    notifyListeners();
    _clearBuffers();
  }

  double _calculateWindowScore({
    required double ci,
    required double jv,
    required double avgSpeed,
    required bool isLowMotionWindow,
  }) {
    if (isLowMotionWindow) return lowConfidenceScoreCap;
    double score = 100.0;
    score -= _softPenalty(jv, threshold: 18.0, scale: 26.0, maxPenalty: 32.0);
    score -= _softPenalty(ci, threshold: 45.0, scale: 35.0, maxPenalty: 24.0);
    score -= _softPenalty(avgSpeed, threshold: 80.0, scale: 18.0, maxPenalty: 18.0);
    return score.clamp(0.0, 100.0);
  }

  double _softPenalty(double value, {required double threshold, required double scale, required double maxPenalty}) {
    if (value <= threshold) return 0.0;
    final normalizedExcess = (value - threshold) / scale;
    return maxPenalty * (1.0 - exp(-normalizedExcess));
  }

  String _evaluateStatusBadge(double speed, double ci, double jv) {
    if (speed < movingSpeedThreshold && _totalDistance < 0.02) return "Idle / calibrating";
    if (ci > corneringIntensityThreshold || jv > 25.0) return "Aggressive Maneuver";
    if (speed > 80.0) return "High Speed Warning";
    return "Safe driving";
  }

  void _unsubscribeFromSensors() {
    _gravityAccelSubscription?.cancel();
    _userAccelSubscription?.cancel();
    _gyroSubscription?.cancel();
    _gpsSubscription?.cancel();
  }

  void _clearBuffers() {
    _jerkValues.clear();
    _corneringIntensities.clear();
    _rollAngles.clear();
    _speeds.clear();
  }

  List<double> _trimOutliers(List<double> values) {
    if (values.isEmpty) return [];
    if (values.length < 5) return values;
    final sorted = [...values]..sort();
    final trimCount = max(1, (sorted.length * 0.1).floor());
    if (trimCount * 2 >= sorted.length) return sorted;
    return sorted.sublist(trimCount, sorted.length - trimCount);
  }

  /// RMS: sqrt(mean(x_i^2)). Stored as jerk_variance in TelemetryWindow.
  double _calculateRms(List<double> values) {
    if (values.isEmpty) return 0.0;
    final meanSquares = values.map((v) => v * v).reduce((a, b) => a + b) / values.length;
    return sqrt(meanSquares);
  }

  double _medianOf(List<double> values) {
    if (values.isEmpty) return 0.0;
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  double _calculateFinalRideScore() {
    if (_windowScores.isEmpty) return lowConfidenceScoreCap;
    final avgScore = _windowScores.reduce((a, b) => a + b) / _windowScores.length;
    final lowestScore = _windowScores.reduce(min);
    var finalScore = (avgScore * 0.85) + (lowestScore * 0.15);

    final movingRatio = _totalWindowCount == 0 ? 0.0 : _movingWindowCount / _totalWindowCount;
    if (_totalDistance < 0.02 || movingRatio < 0.25) {
      finalScore = min(finalScore, lowConfidenceScoreCap);
    }
    return finalScore.clamp(0.0, 100.0);
  }

  double _calculateDeltaTime(DateTime now, DateTime? previous) {
    if (previous == null) return minimumSensorDtSeconds;
    final dt = now.difference(previous).inMilliseconds / 1000.0;
    return dt > minimumSensorDtSeconds ? dt : minimumSensorDtSeconds;
  }
}

class _DemoRidePhase {
  final double score;
  final String status;
  final double speed;
  final double jerk;
  final double cornering;
  final double roll;
  final bool countBrake;

  const _DemoRidePhase({
    required this.score,
    required this.status,
    required this.speed,
    required this.jerk,
    required this.cornering,
    required this.roll,
    this.countBrake = false,
  });
}
