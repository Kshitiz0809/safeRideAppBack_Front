import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../config/demo_config.dart';
import '../services/demo_data_service.dart';
import '../services/database_helper.dart';
import '../models/ride_session.dart';
import '../providers/theme_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late final DatabaseHelper _db;
  late Future<List<RideSession>> _ridesFuture;

  @override
  void initState() {
    super.initState();
    _db = DatabaseHelper();
    _initializeDashboard();
  }

  Future<void> _initializeDashboard() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && DemoConfig.isDemoEmail(user.email)) {
      final rides = await _db.getRideSessionsByUserId(user.uid);
      if (rides.isEmpty) {
        await DemoDataService().prepareDemoDashboard(user.uid);
      }
    }
    if (!mounted) return;
    setState(() {
      _ridesFuture = _loadRides();
    });
  }

  Future<List<RideSession>> _loadRides() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return [];

      final rides = await _db.getRideSessionsByUserId(user.uid);
      rides.sort((a, b) => a.startTime.compareTo(b.startTime));
      return Future.wait(rides.map(_normalizeStoredRideScore));
    } catch (e) {
      return [];
    }
  }

  Future<RideSession> _normalizeStoredRideScore(RideSession ride) async {
    if (ride.totalDistance < 0.02 && ride.finalScore >= 99.0) {
      final updatedRide = ride.copyWith(finalScore: 82.0);
      await _db.updateRideSession(updatedRide);
      return updatedRide;
    }
    return ride;
  }

  Future<void> _startNewRide() async {
    await Navigator.pushNamed(context, '/active-ride', arguments: 'new_ride');
    if (!mounted) return;
    setState(() {
      _ridesFuture = _loadRides();
    });
  }

  void _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  void _showNotifications() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No new safety notifications')),
    );
  }

  void _showAllTrips(List<RideSession> rides) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        if (rides.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No trips recorded yet')),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          itemCount: rides.length,
          itemBuilder: (context, index) => _buildRideItem(rides[index]),
        );
      },
    );
  }

  String _formatRideDate(DateTime date) {
    return DateFormat('MMM d').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = theme.cardColor;
    final borderColor = isDark ? Colors.white12 : Colors.grey[200]!;
    final mutedText = isDark ? Colors.white60 : Colors.grey[600];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: cardColor,
        foregroundColor: theme.colorScheme.onSurface,
        title: Text(
          'SafeRider',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
            icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded),
            onPressed: _showNotifications,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: PopupMenuButton<String>(
              icon: Icon(Icons.account_circle_outlined, color: theme.colorScheme.onSurface),
              onSelected: (value) {
                if (value == 'logout') _logout();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: false,
                  child: Text('Profile: ${user?.email ?? "Guest"}'),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: Text('Logout', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {
            _ridesFuture = _loadRides();
          });
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSummaryHeader(mutedText),
              const SizedBox(height: 24),
              _buildActionCard(),
              const SizedBox(height: 32),
              _buildChartSection(cardColor, borderColor, mutedText, isDark),
              const SizedBox(height: 32),
              _buildHistorySection(cardColor, borderColor, mutedText),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryHeader(Color? mutedText) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hello, Rider!',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          'Your driving score is looking great today.',
          style: TextStyle(color: mutedText),
        ),
      ],
    );
  }

  Widget _buildActionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.blueAccent, Colors.blue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.motorcycle_rounded, size: 48, color: Colors.white),
          const SizedBox(height: 16),
          const Text(
            'Ready for a ride?',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Monitor your safety in real-time.',
            style: TextStyle(color: Colors.white.withOpacity(0.9)),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _startNewRide,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.blueAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
              ),
              child: const Text('START TRACKING', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartSection(Color cardColor, Color borderColor, Color? mutedText, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Performance Trend',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Y-axis: safety score (0–100) · X-axis: trip number (oldest → newest)',
          style: TextStyle(color: mutedText, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Container(
          height: 280,
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
          ),
          child: FutureBuilder<List<RideSession>>(
            future: _ridesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final rides = snapshot.data ?? [];
              if (rides.isEmpty) {
                return Center(
                  child: Text(
                    'Your score trend will appear after your first ride',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: mutedText),
                  ),
                );
              }
              return Column(
                children: [
                  Expanded(
                    child: LineChart(_buildLineChartData(rides, isDark, mutedText)),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 12,
                        height: 3,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Colors.blue, Colors.lightBlueAccent]),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('Safety score per trip', style: TextStyle(fontSize: 11, color: mutedText)),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHistorySection(Color cardColor, Color borderColor, Color? mutedText) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Trips',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            FutureBuilder<List<RideSession>>(
              future: _ridesFuture,
              builder: (context, snapshot) {
                final rides = (snapshot.data ?? []).reversed.toList();
                return TextButton(
                  onPressed: () => _showAllTrips(rides),
                  child: const Text('See All'),
                );
              },
            ),
          ],
        ),
        FutureBuilder<List<RideSession>>(
          future: _ridesFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox();
            final rides = snapshot.data!.reversed.toList();
            if (rides.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: Text(
                  'Start tracking to record your first trip.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: mutedText),
                ),
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rides.length > 3 ? 3 : rides.length,
              itemBuilder: (context, index) {
                final ride = rides[index];
                return _buildRideItem(ride);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildRideItem(RideSession ride) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    Color scoreColor = Colors.green;
    if (ride.finalScore < 80) scoreColor = Colors.orange;
    if (ride.finalScore < 60) scoreColor = Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scoreColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.route_outlined, color: scoreColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trip on ${_formatRideDate(ride.startTime)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${ride.totalDistance.toStringAsFixed(1)} km · ${ride.durationInSeconds ~/ 60} min',
                  style: TextStyle(color: isDark ? Colors.white60 : Colors.grey[600], fontSize: 13),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${ride.finalScore.toInt()}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: scoreColor,
                ),
              ),
              Text(
                'Score',
                style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  LineChartData _buildLineChartData(List<RideSession> rides, bool isDark, Color? mutedText) {
    final spots = rides.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble() + 1, e.value.finalScore);
    }).toList();

    final gridColor = isDark ? Colors.white12 : Colors.grey[200]!;
    final axisTextColor = mutedText ?? Colors.grey;

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 25,
        getDrawingHorizontalLine: (value) => FlLine(color: gridColor, strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          axisNameWidget: Text(
            'Score',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: axisTextColor),
          ),
          axisNameSize: 20,
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            interval: 25,
            getTitlesWidget: (value, meta) {
              if (value % 25 != 0) return const SizedBox.shrink();
              return Text(
                value.toInt().toString(),
                style: TextStyle(fontSize: 10, color: axisTextColor),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          axisNameWidget: Text(
            'Trip #',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: axisTextColor),
          ),
          axisNameSize: 20,
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            interval: 1,
            getTitlesWidget: (value, meta) {
              final tripNum = value.toInt();
              if (tripNum < 1 || tripNum > rides.length) return const SizedBox.shrink();
              if (rides.length > 6 && tripNum % 2 != 0 && tripNum != rides.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '$tripNum',
                  style: TextStyle(fontSize: 10, color: axisTextColor),
                ),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border(
          left: BorderSide(color: gridColor),
          bottom: BorderSide(color: gridColor),
        ),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) {
            return spots.map((spot) {
              final tripIndex = spot.x.toInt() - 1;
              if (tripIndex < 0 || tripIndex >= rides.length) return null;
              final ride = rides[tripIndex];
              return LineTooltipItem(
                'Trip ${spot.x.toInt()}\nScore: ${spot.y.toInt()}\n${_formatRideDate(ride.startTime)}',
                TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              );
            }).toList();
          },
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          gradient: const LinearGradient(colors: [Colors.blue, Colors.lightBlueAccent]),
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              radius: 3,
              color: Colors.blueAccent,
              strokeWidth: 1,
              strokeColor: isDark ? Colors.white : Colors.white,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [Colors.blue.withOpacity(isDark ? 0.25 : 0.15), Colors.blue.withOpacity(0.0)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
      minX: 1,
      maxX: rides.length.toDouble(),
      minY: 0,
      maxY: 100,
    );
  }
}
