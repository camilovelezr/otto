import 'package:flutter/material.dart';

class AnimatedGradientBackground extends StatelessWidget {
  final List<Color> colors;
  final Color backgroundColor;
  
  const AnimatedGradientBackground({
    Key? key,
    this.colors = const [
      Color(0xFF6B5AD3), // Purple
      Color(0xFF9747FF), // Bright purple
      Color(0xFF4A3AFF), // Electric blue
      Color(0xFFB144E6), // Purple/magenta
    ],
    this.backgroundColor = Colors.black,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
      ),
      child: _StaticGradient(colors: colors),
    );
  }
}

class _StaticGradient extends StatelessWidget {
  final List<Color> colors;
  
  const _StaticGradient({
    Key? key,
    required this.colors,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
          stops: const [0.0, 0.3, 0.6, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: colors[0].withOpacity(0.2),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Add subtle glowing orbs
          Positioned(
            top: MediaQuery.of(context).size.height * 0.1,
            right: MediaQuery.of(context).size.width * 0.2,
            child: _buildGlowingOrb(30, 0.2),
          ),
          Positioned(
            bottom: MediaQuery.of(context).size.height * 0.15,
            left: MediaQuery.of(context).size.width * 0.1,
            child: _buildGlowingOrb(50, 0.15),
          ),
          Positioned(
            top: MediaQuery.of(context).size.height * 0.5,
            right: MediaQuery.of(context).size.width * 0.05,
            child: _buildGlowingOrb(40, 0.1),
          ),
        ],
      ),
    );
  }
  
  Widget _buildGlowingOrb(double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(opacity),
            blurRadius: 30,
            spreadRadius: 10,
          ),
        ],
      ),
    );
  }
} 