import '../config/demo_config.dart';
import '../models/ride_session.dart';
import 'database_helper.dart';

class DemoDataService {
  final DatabaseHelper _db = DatabaseHelper();

  /// Resets seeded demo history so each login starts with a clean graph for recording.
  Future<void> prepareDemoDashboard(String userId) async {
    await _db.deleteAllRideDataForUser(userId);

    final now = DateTime.now();
    const dayOffsets = [14, 12, 10, 7, 4, 1];
    const distances = [8.4, 5.2, 11.6, 6.8, 9.1, 14.3];
    const durationsMinutes = [18, 12, 24, 15, 20, 28];

    for (var i = 0; i < DemoConfig.seedScores.length; i++) {
      final startTime = now.subtract(Duration(days: dayOffsets[i], hours: 2 + i));
      final duration = Duration(minutes: durationsMinutes[i]);
      await _db.insertRideSession(
        RideSession(
          rideId: '${DemoConfig.seedRideIdPrefix}$i',
          userId: userId,
          startTime: startTime,
          endTime: startTime.add(duration),
          totalDistance: distances[i],
          finalScore: DemoConfig.seedScores[i],
          isActive: false,
        ),
      );
    }
  }
}
