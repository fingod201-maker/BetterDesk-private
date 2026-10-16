import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'screens/unattended_access.dart';

const String kBakedServerHost = String.fromEnvironment('SERVER_HOST', defaultValue: '');
const bool kBakedUseHttps = bool.fromEnvironment('USE_HTTPS', defaultValue: false);
const int kListenPort = 21122;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BetterDeskClientApp());
}

class BetterDeskClientApp extends StatelessWidget {
  const BetterDeskClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BetterDesk Client',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F62FE)),
      ),
      home: const UnattendedAccessScreen(),
    );
  }
}

