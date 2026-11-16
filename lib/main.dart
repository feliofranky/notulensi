import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI overlay style (clean dark status bar)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF181B21),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize Indonesian locale formatting for dates
  try {
    await initializeDateFormatting('id', null);
  } catch (_) {}

  runApp(const HerzNoteApp());
}

class HerzNoteApp extends StatelessWidget {
  const HerzNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HerzNote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1115),
        cardColor: const Color(0xFF181B21),
        canvasColor: const Color(0xFF0F1115),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981), // Emerald Teal - clean flat accent
          secondary: Color(0xFF38BDF8),
          surface: Color(0xFF181B21),
          surfaceContainer: Color(0xFF181B21),
          onPrimary: Colors.white,
          onSurface: Color(0xFFF1F5F9),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF181B21),
          foregroundColor: Color(0xFFF1F5F9),
          elevation: 0,
          centerTitle: false,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFFF1F5F9)),
          bodyMedium: TextStyle(color: Color(0xFFF1F5F9)),
          bodySmall: TextStyle(color: Color(0xFF94A3B8)),
        ),
        dividerColor: const Color(0xFF262A34),
      ),
      home: const HomeScreen(),
    );
  }
}
