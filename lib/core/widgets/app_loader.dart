import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Shared loading animation. Add the supplied Lottie JSON at [assetPath].
class AppLoader extends StatelessWidget {
  const AppLoader({
    super.key,
    this.size = 100,
    this.color = const Color(0xFF06B6D4),
    this.assetPath = animationAsset,
  });

  static const animationAsset = 'assets/animations/loader.json';

  final double size;
  final Color color;
  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Lottie.asset(
        assetPath,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Center(
          child: SizedBox.square(
            dimension: size * 0.90,
            child: CircularProgressIndicator(color: color, strokeWidth: 2.5),
          ),
        ),
      ),
    );
  }
}

