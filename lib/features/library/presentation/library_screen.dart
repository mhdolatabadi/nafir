import 'package:flutter/material.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nafir موسیقی'),
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
