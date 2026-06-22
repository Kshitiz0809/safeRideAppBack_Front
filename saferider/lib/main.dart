import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'config/demo_config.dart';
import 'firebase_config.dart';
import 'providers/theme_provider.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/active_ride_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final currentUser = FirebaseAuth.instance.currentUser;
    if (DemoConfig.isDemoEmail(currentUser?.email)) {
      await FirebaseAuth.instance.signOut();
    }
  } catch (e) {
    debugPrint("Firebase initialization skipped for local testing: $e");
  }
  runApp(const ProviderScope(child: SafeRiderApp()));
}

class SafeRiderApp extends ConsumerWidget {
  const SafeRiderApp({Key? key}) : super(key: key);

  ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blueAccent,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: Colors.grey[50],
      cardColor: Colors.white,
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blueAccent,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF121212),
      cardColor: const Color(0xFF1E1E1E),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'SafeRider',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      home: const AuthGate(),
      routes: {
        '/login': (context) => LoginScreen(onSuccess: () {
          Navigator.pushReplacementNamed(context, '/dashboard');
        }),
        '/signup': (context) => SignupScreen(onSuccess: () {
          Navigator.pushReplacementNamed(context, '/dashboard');
        }),
        '/dashboard': (context) => const DashboardScreen(),
        '/active-ride': (context) {
          final rideId = ModalRoute.of(context)?.settings.arguments as String?;
          return ActiveRideScreen(rideId: rideId ?? 'new_ride');
        },
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          return const DashboardScreen();
        }

        return LoginScreen(onSuccess: () {
          Navigator.pushReplacementNamed(context, '/dashboard');
        });
      },
    );
  }
}
