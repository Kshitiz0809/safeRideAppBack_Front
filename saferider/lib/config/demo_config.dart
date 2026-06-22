/// Demo account for screen recordings and presentations.
class DemoConfig {
  static const String email = 'demo@saferider.app';
  static const String password = 'SafeRideDemo2026';

  static const String seedRideIdPrefix = 'demo-seed-';

  /// Historical scores shown on the performance graph (oldest → newest).
  static const List<double> seedScores = [82, 45, 68, 60, 55, 90];

  static bool isDemoEmail(String? email) {
    if (email == null) return false;
    return email.trim().toLowerCase() == DemoConfig.email.toLowerCase();
  }

  static bool isDemoUser(String? email) => isDemoEmail(email);
}
