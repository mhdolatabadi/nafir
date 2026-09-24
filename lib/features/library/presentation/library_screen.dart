import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  Future<void> _signOut() => Supabase.instance.client.auth.signOut();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SOT موسیقی'),
        actions: [
          IconButton(
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
            tooltip: 'خروج',
          ),
        ],
      ),
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
                'مرحلهٔ بعد، آپلود موسیقی و پخش استریم‌شده است.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
