import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ride_engine_service.dart';
import '../services/sync_service.dart';
import '../services/database_helper.dart';

// Singleton providers for services
final rideEngineServiceProvider = ChangeNotifierProvider((ref) {
  return RideEngineService();
});

final syncServiceProvider = FutureProvider<SyncService>((ref) async {
  final syncService = SyncService();
  await syncService.init();
  ref.onDispose(() => syncService.dispose());
  return syncService;
});

final databaseHelperProvider = Provider((ref) {
  return DatabaseHelper();
});

// State providers for current ride
final currentRideIdProvider = StateProvider<String?>((ref) => null);

final currentScoreProvider = Provider((ref) {
  final rideEngine = ref.watch(rideEngineServiceProvider);
  return rideEngine.currentScore;
});

final statusBadgeProvider = Provider((ref) {
  final rideEngine = ref.watch(rideEngineServiceProvider);
  return rideEngine.statusBadge;
});

final currentSpeedProvider = Provider((ref) {
  final rideEngine = ref.watch(rideEngineServiceProvider);
  return rideEngine.currentSpeed;
});

final isRecordingProvider = Provider((ref) {
  final rideEngine = ref.watch(rideEngineServiceProvider);
  return rideEngine.isRecording;
});

final currentJerkVarianceProvider = Provider((ref) {
  final rideEngine = ref.watch(rideEngineServiceProvider);
  return rideEngine.currentJerkVariance;
});

final currentMaxCorneringIntensityProvider = Provider((ref) {
  final rideEngine = ref.watch(rideEngineServiceProvider);
  return rideEngine.currentMaxCorneringIntensity;
});

final currentMaxRollProvider = Provider((ref) {
  final rideEngine = ref.watch(rideEngineServiceProvider);
  return rideEngine.currentMaxRoll;
});

final totalBrakeCountProvider = Provider((ref) {
  final rideEngine = ref.watch(rideEngineServiceProvider);
  return rideEngine.totalBrakeCount;
});

final isPausedProvider = Provider((ref) {
  final rideEngine = ref.watch(rideEngineServiceProvider);
  return rideEngine.isPaused;
});

final totalDistanceProvider = Provider((ref) {
  final rideEngine = ref.watch(rideEngineServiceProvider);
  return rideEngine.totalDistance;
});

final rideDurationProvider = Provider((ref) {
  final rideEngine = ref.watch(rideEngineServiceProvider);
  return rideEngine.rideDuration;
});

final averageSpeedProvider = Provider((ref) {
  final rideEngine = ref.watch(rideEngineServiceProvider);
  return rideEngine.averageSpeed;
});

final isCalibratingProvider = Provider((ref) {
  return ref.watch(rideEngineServiceProvider).isCalibrating;
});

final calibrationSecondsRemainingProvider = Provider((ref) {
  return ref.watch(rideEngineServiceProvider).calibrationSecondsRemaining;
});

// Sync status providers
final isOnlineProvider = FutureProvider<bool>((ref) async {
  final syncService = await ref.watch(syncServiceProvider.future);
  return syncService.isOnline;
});

final isSyncingProvider = FutureProvider<bool>((ref) async {
  final syncService = await ref.watch(syncServiceProvider.future);
  return syncService.isSyncing;
});

final lastSyncStatusProvider = FutureProvider<String?>((ref) async {
  final syncService = await ref.watch(syncServiceProvider.future);
  return syncService.lastSyncStatus;
});
