import 'package:flutter/material.dart';

/// Full-screen loading state that matches the web splash in web/index.html,
/// so startup looks like one continuous screen.
class AppLoadingScreen extends StatelessWidget {
  const AppLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFF1A73E8),
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
              child: SizedBox.square(
                dimension: 72,
                child: Icon(Icons.music_note, size: 40, color: Colors.white),
              ),
            ),
            SizedBox(height: 20),
            Text('نفیر',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            SizedBox(height: 20),
            SizedBox.square(
              dimension: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}
