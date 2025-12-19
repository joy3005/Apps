import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'theme.dart';
import 'screens/home_page.dart'; // <--- IMPORTANT: Import your new page

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  WakelockPlus.enable();
  runApp(const JeyamDairyApp());
}

class JeyamDairyApp extends StatelessWidget {
  const JeyamDairyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jeyam Dairy Farms',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // CHANGE HERE: Use HomePage() instead of the "Day 1" placeholder
      home: const HomePage(),
    );
  }
}
