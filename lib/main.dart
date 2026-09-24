import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: SotApp()));
}

class SotApp extends StatelessWidget {
  const SotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SOT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const LibraryScreen(),
    );
  }
}

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SOT موسیقی')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_queue_outlined, size: 64),
              SizedBox(height: 16),
              Text('کتابخانهٔ شما خالی است', style: TextStyle(fontSize: 20)),
              SizedBox(height: 8),
              Text(
                'پس از ورود، موسیقی‌هایت را آپلود کن و بدون اشغال حافظهٔ گوشی پخش کن.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
