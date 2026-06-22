import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import '../config/demo_config.dart';
import '../providers/ride_provider.dart';
import '../providers/theme_provider.dart';
import '../services/database_helper.dart';
import '../services/ride_engine_service.dart';
import '../widgets/live_tracking/animated_score_ring.dart';
import '../widgets/live_tracking/metric_glass_card.dart';
import '../widgets/live_tracking/telemetry_waveform.dart';

class ActiveRideScreen extends ConsumerStatefulWidget {
  final String rideId;
  const ActiveRideScreen({super.key, required this.rideId});

  @override
  ConsumerState<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends ConsumerState<ActiveRideScreen>
    with TickerProviderStateMixin {
  bool _isStopping = false;
  Timer? _durationTimer;
  int _highlightMetricIndex = -1;
  String _previousMetricSignature = '';

  late final AnimationController _entryController;
  late final AnimationController _pulseController;
  late final Animation<double> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  late final List<Animation<double>> _metricAnimations;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat(reverse: true);

    _slideAnimation = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.0, 0.75, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.0, 0.65, curve: Curves.easeIn),
    );
    _metricAnimations = List.generate(
      4,
      (i) => CurvedAnimation(
        parent: _entryController,
        curve: Interval(0.30 + (i * 0.10), 0.95, curve: Curves.easeOutCubic),
      ),
    );
    _entryController.forward();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
    WidgetsBinding.instance.addPostFrameCallback((_) => _startRide());
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _entryController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startRide() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in before starting a ride')),
        );
        Navigator.pop(context);
      }
      return;
    }

    // Check location services
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Location services are off. Please enable GPS.'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: Geolocator.openLocationSettings,
            ),
          ),
        );
        Navigator.pop(context);
      }
      return;
    }

    // Request runtime location permission (required on Android 6+)
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Location permission required for speed & distance tracking.'),
            action: permission == LocationPermission.deniedForever
                ? SnackBarAction(label: 'Settings', onPressed: Geolocator.openAppSettings)
                : null,
          ),
        );
        Navigator.pop(context);
      }
      return;
    }

    if (!mounted) return;
    ref.read(rideEngineServiceProvider).startRide(
      user.uid,
      demoMode: DemoConfig.isDemoEmail(user.email),
    );
  }

  Future<void> _confirmEndRide() async {
    if (_isStopping) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _EndRideSheet(isDark: ref.read(themeModeProvider) == ThemeMode.dark),
    );
    if (confirmed == true && mounted) await _stopRide();
  }

  Future<void> _stopRide() async {
    if (_isStopping) return;
    setState(() => _isStopping = true);

    final rideEngine = ref.read(rideEngineServiceProvider);
    final rideId = rideEngine.currentRideId;
    await rideEngine.stopRide();

    final isDemoRide = DemoConfig.isDemoEmail(FirebaseAuth.instance.currentUser?.email);
    if (!isDemoRide) {
      try {
        final syncService = await ref.read(syncServiceProvider.future);
        final backendScore = await syncService.syncPendingData(rideId: rideId);
        if (backendScore != null && rideId != null) {
          final db = DatabaseHelper();
          final session = await db.getRideSessionById(rideId);
          if (session != null) {
            await db.updateRideSession(session.copyWith(finalScore: backendScore));
          }
        }
      } catch (e) {
        debugPrint('Error during final sync: $e');
      }
    } else {
      await Future.delayed(const Duration(milliseconds: 600));
    }
    if (mounted) Navigator.pop(context);
  }

  void _togglePause() {
    final engine = ref.read(rideEngineServiceProvider);
    if (engine.isPaused) { engine.resumeRide(); } else { engine.pauseRide(); }
  }

  Color _scoreColor(double score) {
    if (score >= 75) return const Color(0xFF00C853);
    if (score >= 50) return const Color(0xFFFFAB00);
    return const Color(0xFFFF1744);
  }

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$mm:$ss';
  }

  void _checkMetricHighlight(String signature) {
    if (_previousMetricSignature.isEmpty) { _previousMetricSignature = signature; return; }
    if (signature == _previousMetricSignature) return;
    final next = signature.split('|');
    final prev = _previousMetricSignature.split('|');
    _previousMetricSignature = signature;
    for (var i = 0; i < 4 && i < next.length && i < prev.length; i++) {
      if (next[i] != prev[i]) {
        setState(() => _highlightMetricIndex = i);
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) setState(() => _highlightMetricIndex = -1);
        });
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final isPaused = ref.watch(isPausedProvider);
    final isCalibrating = ref.watch(isCalibratingProvider);
    final calibrationSecs = ref.watch(calibrationSecondsRemainingProvider);
    final score = ref.watch(currentScoreProvider);
    final statusBadge = ref.watch(statusBadgeProvider);
    final speed = ref.watch(currentSpeedProvider);
    final jerk = ref.watch(currentJerkVarianceProvider);
    final cornering = ref.watch(currentMaxCorneringIntensityProvider);
    final roll = ref.watch(currentMaxRollProvider);
    final brakes = ref.watch(totalBrakeCountProvider);
    final distance = ref.watch(totalDistanceProvider);
    final avgSpeed = ref.watch(averageSpeedProvider);
    final duration = ref.watch(rideDurationProvider);

    final scoreColor = _scoreColor(score);
    final stabilityLabel = cornering > 100 ? 'Low' : 'High';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkMetricHighlight('$brakes|${roll.toStringAsFixed(1)}|${jerk.toStringAsFixed(1)}|$stabilityLabel');
    });

    // Theme tokens
    final bgTop = isDark ? const Color(0xFF080D18) : const Color(0xFFECF0FB);
    final bgBottom = isDark ? const Color(0xFF040609) : const Color(0xFFF5F7FF);
    final surface = isDark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.88);
    final border = isDark ? Colors.white.withValues(alpha: 0.09) : Colors.black.withValues(alpha: 0.04);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F1729);
    final textSecondary = isDark ? Colors.white54 : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgBottom,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background gradient
          AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [bgTop, bgBottom, bgTop.withValues(alpha: 0.7)],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),
          // Subtle score-tinted radial glow
          Positioned(
            top: -60,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 800),
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      scoreColor.withValues(alpha: isDark ? 0.12 : 0.07),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Main content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
                      .animate(_slideAnimation),
                  child: Column(
                    children: [
                      // Header
                      SizedBox(height: 44, child: _buildHeader(isDark, textPrimary)),
                      const SizedBox(height: 8),

                      // Score hero
                      _buildScoreHero(
                        isDark: isDark,
                        score: score,
                        scoreColor: scoreColor,
                        speed: speed,
                        statusBadge: statusBadge,
                        isPaused: isPaused,
                        surface: surface,
                        border: border,
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                      ),
                      const SizedBox(height: 10),

                      // Metrics 2x2
                      _buildMetricsGrid(
                        isDark: isDark,
                        brakes: brakes,
                        roll: roll,
                        jerk: jerk,
                        stabilityLabel: stabilityLabel,
                        textSecondary: textSecondary,
                      ),
                      const SizedBox(height: 10),

                      // Trip stats strip
                      _buildTripStrip(
                        isDark: isDark,
                        distance: distance,
                        duration: duration,
                        avgSpeed: avgSpeed,
                        surface: surface,
                        border: border,
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                      ),
                      const SizedBox(height: 10),

                      // Waveform
                      Expanded(
                        child: _buildWaveformCard(
                          isDark: isDark,
                          speed: speed,
                          jerk: jerk,
                          accent: scoreColor,
                          surface: surface,
                          border: border,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Actions
                      _buildBottomActions(isDark, isPaused),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Calibration overlay
          if (isCalibrating)
            _CalibrationOverlay(secondsRemaining: calibrationSecs, isDark: isDark),

          // Stopping overlay
          if (_isStopping)
            _buildStoppingOverlay(isDark, textPrimary),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark, Color textPrimary) {
    return Row(
      children: [
        _HeaderButton(
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: _isStopping ? null : _confirmEndRide,
          isDark: isDark,
          color: textPrimary,
        ),
        Expanded(
          child: Text(
            'Live Ride',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
        ),
        _HeaderButton(
          icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          onTap: () => ref.read(themeModeProvider.notifier).toggle(),
          isDark: isDark,
          color: textPrimary,
        ),
      ],
    );
  }

  Widget _buildScoreHero({
    required bool isDark,
    required double score,
    required Color scoreColor,
    required double speed,
    required String statusBadge,
    required bool isPaused,
    required Color surface,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: surface,
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.06),
                blurRadius: 24,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              // Score ring
              ScaleTransition(
                scale: Tween<double>(begin: 0.75, end: 1.0).animate(
                  CurvedAnimation(parent: _entryController, curve: Curves.easeOutBack),
                ),
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (_, _) {
                    final pulse = isPaused ? 1.0 : 1.0 + (_pulseController.value * 0.025);
                    return AnimatedScoreRing(
                      score: score,
                      color: scoreColor,
                      size: 104,
                      pulse: pulse,
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              // Speed + status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Speed
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: speed),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, _) => Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            v.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.w800,
                              color: textPrimary,
                              height: 1.0,
                              letterSpacing: -1.5,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              'km/h',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Status pill
                    _StatusPill(badge: statusBadge),
                    const SizedBox(height: 8),
                    // Live indicator
                    Row(
                      children: [
                        _LiveDot(active: !isPaused, color: const Color(0xFF00C853)),
                        const SizedBox(width: 6),
                        Text(
                          isPaused ? 'Paused' : 'Live Telemetry',
                          style: TextStyle(fontSize: 12, color: textSecondary, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricsGrid({
    required bool isDark,
    required int brakes,
    required double roll,
    required double jerk,
    required String stabilityLabel,
    required Color textSecondary,
  }) {
    final cards = [
      (icon: Icons.emergency_rounded,     label: 'Braking',    value: brakes.toString(),             color: const Color(0xFFFF1744)),
      (icon: Icons.screen_rotation_rounded, label: 'Roll Angle', value: '${roll.toStringAsFixed(1)}°', color: const Color(0xFFFF9100)),
      (icon: Icons.bolt_rounded,           label: 'Jerk',       value: jerk.toStringAsFixed(1),       color: const Color(0xFF2979FF)),
      (icon: Icons.shield_rounded,         label: 'Stability',  value: stabilityLabel,                color: const Color(0xFF00C853)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(
            'LIVE METRICS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: textSecondary,
            ),
          ),
        ),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.75,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: List.generate(cards.length, (i) {
            final c = cards[i];
            return MetricGlassCard(
              icon: c.icon,
              label: c.label,
              value: c.value,
              subtitle: '',
              accentColor: c.color,
              isDark: isDark,
              animation: _metricAnimations[i],
              highlight: _highlightMetricIndex == i,
              compact: true,
            );
          }),
        ),
      ],
    );
  }

  Widget _buildTripStrip({
    required bool isDark,
    required double distance,
    required Duration duration,
    required double avgSpeed,
    required Color surface,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: surface,
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              _TripStat(
                icon: Icons.route_rounded,
                label: 'Distance',
                value: '${distance.toStringAsFixed(2)} km',
                textPrimary: textPrimary,
                textSecondary: textSecondary,
              ),
              _VerticalDivider(isDark: isDark),
              _TripStat(
                icon: Icons.timer_rounded,
                label: 'Duration',
                value: _formatDuration(duration),
                textPrimary: textPrimary,
                textSecondary: textSecondary,
              ),
              _VerticalDivider(isDark: isDark),
              _TripStat(
                icon: Icons.speed_rounded,
                label: 'Avg Speed',
                value: '${avgSpeed.toStringAsFixed(1)} km/h',
                textPrimary: textPrimary,
                textSecondary: textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWaveformCard({
    required bool isDark,
    required double speed,
    required double jerk,
    required Color accent,
    required Color surface,
    required Color border,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: surface,
            border: Border.all(color: border),
          ),
          child: TelemetryWaveform(speed: speed, jerk: jerk, isDark: isDark, accentColor: accent),
        ),
      ),
    );
  }

  Widget _buildBottomActions(bool isDark, bool isPaused) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            label: isPaused ? 'Resume' : 'Pause',
            icon: isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            onTap: _isStopping ? null : _togglePause,
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: _EndRideButton(
            label: _isStopping ? 'Ending...' : 'End Ride',
            onTap: _isStopping ? null : _confirmEndRide,
          ),
        ),
      ],
    );
  }

  Widget _buildStoppingOverlay(bool isDark, Color textPrimary) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
      child: Container(
        color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.55),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 16),
              Text(
                'Calculating final score...',
                style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Calibration overlay
// ---------------------------------------------------------------------------

class _CalibrationOverlay extends StatefulWidget {
  final int secondsRemaining;
  final bool isDark;

  const _CalibrationOverlay({required this.secondsRemaining, required this.isDark});

  @override
  State<_CalibrationOverlay> createState() => _CalibrationOverlayState();
}

class _CalibrationOverlayState extends State<_CalibrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _radarController;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
  }

  @override
  void dispose() {
    _radarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark
        ? Colors.black.withValues(alpha: 0.78)
        : Colors.white.withValues(alpha: 0.82);
    final textPrimary = widget.isDark ? Colors.white : const Color(0xFF0F1729);
    final textSecondary = widget.isDark ? Colors.white60 : const Color(0xFF64748B);
    const accent = Color(0xFF2979FF);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        color: bg,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Radar rings
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: AnimatedBuilder(
                      animation: _radarController,
                      builder: (_, _) {
                        return CustomPaint(
                          painter: _RadarPainter(
                            progress: _radarController.value,
                            color: accent,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Calibrating Sensors',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hold your phone steady on the bike',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  // Progress bar
                  Container(
                    height: 6,
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      color: accent.withValues(alpha: 0.15),
                    ),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: 1.0,
                        end: widget.secondsRemaining /
                            RideEngineService.calibrationDurationSeconds,
                      ),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, _) => FractionallySizedBox(
                        widthFactor: v.clamp(0.0, 1.0),
                        alignment: Alignment.centerLeft,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2979FF), Color(0xFF00B0FF)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${widget.secondsRemaining}s remaining',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RadarPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const rings = 3;

    for (var i = 0; i < rings; i++) {
      final phase = ((progress + i / rings) % 1.0);
      final radius = phase * (size.width / 2);
      final alpha = (1.0 - phase).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = color.withValues(alpha: alpha * 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(center, radius, paint);
    }

    // Center icon background
    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 28, bgPaint);

    // Center icon border
    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, 28, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => old.progress != progress;
}

// ---------------------------------------------------------------------------
// Small reusable widgets
// ---------------------------------------------------------------------------

class _StatusPill extends StatelessWidget {
  final String badge;
  const _StatusPill({required this.badge});

  Color get _color {
    if (badge.contains('Aggressive') || badge.contains('High Speed') || badge.contains('Unsafe')) {
      return const Color(0xFFFF1744);
    }
    if (badge.contains('Idle') || badge.contains('Calibrating')) return const Color(0xFFFFAB00);
    return const Color(0xFF00C853);
  }

  IconData get _icon {
    if (badge.contains('Aggressive')) return Icons.warning_rounded;
    if (badge.contains('High Speed')) return Icons.speed_rounded;
    if (badge.contains('Idle') || badge.contains('Calibrating')) return Icons.hourglass_top_rounded;
    return Icons.check_circle_rounded;
  }

  String get _label {
    if (badge.contains('Aggressive')) return 'Risk Detected';
    if (badge.contains('High Speed')) return 'High Speed';
    if (badge.contains('Idle') || badge.contains('Calibrating')) return 'Calibrating';
    return 'Safe Riding';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 13, color: _color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              _label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _color, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  final bool active;
  final Color color;
  const _LiveDot({required this.active, required this.color});

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _LiveDot old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) { _c.repeat(reverse: true); }
    else if (!widget.active) { _c.stop(); }
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        width: 8, height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: widget.active ? 0.5 + _c.value * 0.5 : 0.3),
          boxShadow: widget.active
              ? [BoxShadow(color: widget.color.withValues(alpha: 0.4), blurRadius: 6, spreadRadius: 1)]
              : null,
        ),
      ),
    );
  }
}

class _TripStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color textPrimary;
  final Color textSecondary;

  const _TripStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 14, color: textSecondary),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary),
            ),
          ),
          const SizedBox(height: 1),
          Text(label, style: TextStyle(fontSize: 10, color: textSecondary)),
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  final bool isDark;
  const _VerticalDivider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.07),
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isDark;
  final Color color;

  const _HeaderButton({required this.icon, required this.onTap, required this.isDark, required this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.04),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isDark;

  const _ActionButton({required this.label, required this.icon, required this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isDark ? Colors.white.withValues(alpha: 0.09) : Colors.white.withValues(alpha: 0.92),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _EndRideButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _EndRideButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(colors: [Color(0xFFFF1744), Color(0xFFD50000)]),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD50000).withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.stop_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _EndRideSheet extends StatelessWidget {
  final bool isDark;
  const _EndRideSheet({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF131820) : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF0F1729);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(28)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.30),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFF1744).withValues(alpha: 0.12),
            ),
            child: const Icon(Icons.stop_circle_rounded, color: Color(0xFFFF1744), size: 28),
          ),
          const SizedBox(height: 14),
          Text('End this ride?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: text)),
          const SizedBox(height: 8),
          Text(
            'Your safety score and trip data will be saved.',
            textAlign: TextAlign.center,
            style: TextStyle(color: isDark ? Colors.white54 : const Color(0xFF64748B), height: 1.4),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: const Text('Keep Riding'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF1744),
                    minimumSize: const Size(0, 48),
                  ),
                  child: const Text('End Ride'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

