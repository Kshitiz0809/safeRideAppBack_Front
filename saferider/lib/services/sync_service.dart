import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../models/telemetry_window.dart';
import 'database_helper.dart';

class SyncService extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();
  final Connectivity _connectivity = Connectivity();
  
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  bool _isOnline = false;
  bool _isSyncing = false;
  String? _lastSyncStatus;
  
  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
  String? get lastSyncStatus => _lastSyncStatus;

  Future<void> init() async {
    final result = await _connectivity.checkConnectivity();
    _updateConnectivityStatus(result);

    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> result) {
        _updateConnectivityStatus(result);
        if (_isOnline) {
          syncPendingData();
        }
      },
    );
  }

  void _updateConnectivityStatus(List<ConnectivityResult> results) {
    _isOnline = results.any((result) => result != ConnectivityResult.none);
    notifyListeners();
  }

  /// Returns the overall score from backend if successful
  Future<double?> syncPendingData({String? rideId}) async {
    if (_isSyncing) return null;
    if (!_isOnline) {
      final result = await _connectivity.checkConnectivity();
      _updateConnectivityStatus(result);
      if (!_isOnline) return null;
    }

    _isSyncing = true;
    _lastSyncStatus = 'Syncing...';
    notifyListeners();

    try {
      final allUnSyncedWindows = await _db.getUnSyncedTelemetryWindows();
      final unSyncedWindows = rideId == null
          ? allUnSyncedWindows
          : allUnSyncedWindows.where((w) => w.rideId == rideId).toList();

      if (unSyncedWindows.isEmpty) {
        _lastSyncStatus = 'No data to sync';
        _isSyncing = false;
        notifyListeners();
        return null;
      }

      final groupedWindows = _groupWindowsByRide(unSyncedWindows);
      double? requestedRideScore;
      int syncedWindowCount = 0;

      for (final entry in groupedWindows.entries) {
        final windows = entry.value;
        final payload = {
          'timestamp': DateTime.now().toIso8601String(),
          'ride_id': entry.key,
          'user_id': FirebaseAuth.instance.currentUser?.uid,
          'windows': windows.map((w) => w.toJson()).toList(),
        };

        final responseData = await _sendToBackend(payload);

        if (responseData == null) {
          _lastSyncStatus = 'Sync failed';
          continue;
        }

        final windowIds = windows.map((w) => w.id).toList();
        await _db.markTelemetryWindowsAsSynced(windowIds);
        syncedWindowCount += windowIds.length;

        final overallScore = (responseData['overallScore'] as num).toDouble();
        if (rideId == null || entry.key == rideId) {
          requestedRideScore = overallScore;
        }
      }

      if (syncedWindowCount > 0) {
        _lastSyncStatus = requestedRideScore == null
            ? 'Synced $syncedWindowCount windows'
            : 'Synced $syncedWindowCount windows. Score: $requestedRideScore';
        _isSyncing = false;
        notifyListeners();
        return requestedRideScore;
      }
    } catch (e) {
      _lastSyncStatus = 'Error: $e';
      debugPrint('Sync error: $e');
    }

    _isSyncing = false;
    notifyListeners();
    return null;
  }

  Map<String, List<TelemetryWindow>> _groupWindowsByRide(List<TelemetryWindow> windows) {
    final grouped = <String, List<TelemetryWindow>>{};
    for (final window in windows) {
      final key = window.rideId ?? 'unknown_ride';
      grouped.putIfAbsent(key, () => []).add(window);
    }
    return grouped;
  }

  Future<Map<String, dynamic>?> _sendToBackend(Map<String, dynamic> payload) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      final idToken = await currentUser?.getIdToken();
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (idToken != null) 'Authorization': 'Bearer $idToken',
      };

      final response = await http.post(
        AppConfig.apiUri('/sync'),
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 30));

      debugPrint('API Response: ${response.statusCode} - ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Error sending to backend: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }
}
