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
            // The app icon: a red nafir on black.
            ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(16)),
              child: Image(
                image: AssetImage('assets/icon/nafir.png'),
                width: 72,
                height: 72,
              ),
            ),
            SizedBox(height: 24),
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
