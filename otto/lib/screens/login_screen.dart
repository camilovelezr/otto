import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'dart:math' as math;
import '../services/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  
  // Animation controllers
  late AnimationController _backgroundAnimController;
  late AnimationController _cardsAnimController;
  late AnimationController _fieldsAnimController;
  
  // Animations
  late Animation<double> _backgroundAnim;
  late Animation<double> _cardScaleAnim;
  late Animation<double> _cardOpacityAnim;
  
  @override
  void initState() {
    super.initState();
    
    // Background animation for fluid effect
    _backgroundAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat(reverse: true);
    _backgroundAnim = Tween<double>(begin: 0, end: 1).animate(_backgroundAnimController);
    
    // Card animations
    _cardsAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _cardScaleAnim = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _cardsAnimController, curve: Curves.easeOutCubic)
    );
    _cardOpacityAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _cardsAnimController, curve: Curves.easeOut)
    );
    
    // Fields animation
    _fieldsAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    
    // Start card animation after a short delay
    Future.delayed(const Duration(milliseconds: 300), () {
      _cardsAnimController.forward();
    });
    
    // Start fields animation after cards begin animating
    Future.delayed(const Duration(milliseconds: 500), () {
      _fieldsAnimController.forward();
    });
  }
  
  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _backgroundAnimController.dispose();
    _cardsAnimController.dispose();
    _fieldsAnimController.dispose();
    super.dispose();
  }
  
  void _login() async {
    if (_formKey.currentState!.validate()) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      final success = await authProvider.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );
      
      if (success && mounted) {
        Navigator.of(context).pushReplacementNamed('/');
      }
    }
  }
  
  // Animated form field with enhanced styling
  Widget _buildAnimatedField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    int delay = 0,
  }) {
    return AnimatedBuilder(
      animation: _fieldsAnimController,
      builder: (context, child) {
        // Staggered animation timing
        final double start = delay / 500;
        final double end = start + 0.2;
        
        // Create a staggered interval animation
        final Animation<double> fieldAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _fieldsAnimController,
            curve: Interval(start < 0 ? 0 : start, end > 1 ? 1 : end, curve: Curves.easeOutCubic),
          ),
        );
        
        return Transform.translate(
          offset: Offset(0, 20 * (1 - fieldAnim.value)),
          child: Opacity(
            opacity: fieldAnim.value,
            child: Container(
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: TextFormField(
                controller: controller,
                obscureText: obscureText && !_isPasswordVisible,
                decoration: InputDecoration(
                  labelText: label,
                  labelStyle: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                  prefixIcon: Icon(icon, color: Colors.white70, size: 20),
                  suffixIcon: suffixIcon,
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.07),
                  focusColor: Colors.white.withOpacity(0.1),
                  hoverColor: Colors.white.withOpacity(0.09),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 20,
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Colors.white.withOpacity(0.15),
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Colors.white.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Colors.red.withOpacity(0.5),
                      width: 1.5,
                    ),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Colors.red.withOpacity(0.7),
                      width: 1.5,
                    ),
                  ),
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                cursorColor: Colors.white70,
                validator: validator,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final size = MediaQuery.of(context).size;
    
    return Scaffold(
      backgroundColor: const Color(0xFF6E3CBC),
      body: Stack(
        children: [
          // Animated fluid background
          AnimatedBuilder(
            animation: _backgroundAnim,
            builder: (context, child) {
              return CustomPaint(
                size: Size(size.width, size.height),
                painter: FluidBackgroundPainter(
                  color1: const Color(0xFF5D2CB3),
                  color2: const Color(0xFF8A5CEF),
                  color3: const Color(0xFFAA8CFF),
                  animation: _backgroundAnim.value,
                ),
              );
            },
          ),
          
          // Subtle particle overlay
          Opacity(
            opacity: 0.4,
            child: CustomPaint(
              size: Size(size.width, size.height),
              painter: ParticlesPainter(),
            ),
          ),
          
          // Content
          SafeArea(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // App logo/icon with enhanced styling
                    ScaleTransition(
                      scale: _cardScaleAnim,
                      child: FadeTransition(
                        opacity: _cardOpacityAnim,
                        child: Center(
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.1),
                              gradient: RadialGradient(
                                colors: [
                                  Colors.white.withOpacity(0.2),
                                  Colors.white.withOpacity(0.05),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.chat_outlined,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    // Title
                    ScaleTransition(
                      scale: _cardScaleAnim,
                      child: FadeTransition(
                        opacity: _cardOpacityAnim,
                        child: const Text(
                          "Welcome",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 10),
                    
                    // Subtitle
                    ScaleTransition(
                      scale: _cardScaleAnim,
                      child: FadeTransition(
                        opacity: _cardOpacityAnim,
                        child: Text(
                          "Sign in to continue",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    // Form card with layered effect
                    ScaleTransition(
                      scale: _cardScaleAnim,
                      child: FadeTransition(
                        opacity: _cardOpacityAnim,
                        child: Stack(
                          children: [
                            // Shadow card (bottom layer)
                            Positioned(
                              left: 5,
                              right: 5,
                              top: 5,
                              bottom: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  color: Colors.black.withOpacity(0.1),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 15,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            
                            // Main card
                            Container(
                              padding: const EdgeInsets.all(28.0),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.white.withOpacity(0.12),
                                    Colors.white.withOpacity(0.08),
                                  ],
                                ),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.15),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // Username field
                                    _buildAnimatedField(
                                      label: 'Username',
                                      icon: Icons.person_outline,
                                      controller: _usernameController,
                                      delay: 0,
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Please enter your username';
                                        }
                                        return null;
                                      },
                                    ),
                                    
                                    // Password field
                                    _buildAnimatedField(
                                      label: 'Password',
                                      icon: Icons.lock_outline,
                                      controller: _passwordController,
                                      obscureText: true,
                                      delay: 100,
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Please enter your password';
                                        }
                                        return null;
                                      },
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                          color: Colors.white70,
                                          size: 20,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _isPasswordVisible = !_isPasswordVisible;
                                          });
                                        },
                                      ),
                                    ),
                                    
                                    // Forgot password with enhanced styling
                                    AnimatedBuilder(
                                      animation: _fieldsAnimController,
                                      builder: (context, child) {
                                        final Animation<double> forgotAnim = Tween<double>(
                                          begin: 0.0, 
                                          end: 1.0
                                        ).animate(
                                          CurvedAnimation(
                                            parent: _fieldsAnimController,
                                            curve: const Interval(0.4, 0.6, curve: Curves.easeOut),
                                          ),
                                        );
                                        
                                        return Opacity(
                                          opacity: forgotAnim.value,
                                          child: Transform.translate(
                                            offset: Offset(0, 20 * (1 - forgotAnim.value)),
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: TextButton(
                                                onPressed: () {
                                                  // Handle forgot password
                                                },
                                                style: TextButton.styleFrom(
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets.only(right: 8.0),
                                                  textStyle: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                child: const Text('Forgot Password?'),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    
                                    const SizedBox(height: 10),
                                    
                                    // Error message with animation
                                    if (authProvider.error != null)
                                      AnimatedBuilder(
                                        animation: _fieldsAnimController,
                                        builder: (context, child) {
                                          final Animation<double> errorAnim = Tween<double>(
                                            begin: 0.0, 
                                            end: 1.0
                                          ).animate(
                                            CurvedAnimation(
                                              parent: _fieldsAnimController,
                                              curve: const Interval(0.5, 0.7, curve: Curves.easeOut),
                                            ),
                                          );
                                          
                                          return Opacity(
                                            opacity: errorAnim.value,
                                            child: Container(
                                              margin: const EdgeInsets.only(bottom: 20),
                                              padding: const EdgeInsets.symmetric(
                                                vertical: 12, 
                                                horizontal: 16,
                                              ),
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(12),
                                                color: Colors.red.withOpacity(0.15),
                                                border: Border.all(
                                                  color: Colors.red.withOpacity(0.3),
                                                  width: 1,
                                                ),
                                              ),
                                              child: Text(
                                                authProvider.error!.replaceAll(RegExp(r'Exception: '), ''),
                                                style: TextStyle(
                                                  color: Colors.red[200],
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    
                                    const SizedBox(height: 20),
                                    
                                    // Sign in button with animation
                                    AnimatedBuilder(
                                      animation: _fieldsAnimController,
                                      builder: (context, child) {
                                        final Animation<double> buttonAnim = Tween<double>(
                                          begin: 0.0, 
                                          end: 1.0
                                        ).animate(
                                          CurvedAnimation(
                                            parent: _fieldsAnimController,
                                            curve: const Interval(0.6, 0.8, curve: Curves.easeOut),
                                          ),
                                        );
                                        
                                        return Opacity(
                                          opacity: buttonAnim.value,
                                          child: Transform.translate(
                                            offset: Offset(0, 20 * (1 - buttonAnim.value)),
                                            child: Container(
                                              height: 56,
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(16),
                                                gradient: const LinearGradient(
                                                  colors: [
                                                    Color(0xFF9C7CF3),
                                                    Color(0xFF8A5CEF),
                                                  ],
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: const Color(0xFF9C7CF3).withOpacity(0.5),
                                                    blurRadius: 10,
                                                    spreadRadius: 0,
                                                    offset: const Offset(0, 5),
                                                  ),
                                                ],
                                              ),
                                              child: ElevatedButton(
                                                onPressed: authProvider.isLoading ? null : _login,
                                                style: ElevatedButton.styleFrom(
                                                  foregroundColor: Colors.white,
                                                  backgroundColor: Colors.transparent,
                                                  shadowColor: Colors.transparent,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(16),
                                                  ),
                                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                                ),
                                                child: authProvider.isLoading
                                                    ? const SizedBox(
                                                        height: 24,
                                                        width: 24,
                                                        child: CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.white,
                                                        ),
                                                      )
                                                    : const Text(
                                                        'Sign In',
                                                        style: TextStyle(
                                                          fontSize: 16,
                                                          fontWeight: FontWeight.w600,
                                                          letterSpacing: 0.5,
                                                        ),
                                                      ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 30),
                    
                    // Sign up option
                    AnimatedBuilder(
                      animation: _fieldsAnimController,
                      builder: (context, child) {
                        final Animation<double> signupAnim = Tween<double>(
                          begin: 0.0, 
                          end: 1.0
                        ).animate(
                          CurvedAnimation(
                            parent: _fieldsAnimController,
                            curve: const Interval(0.7, 0.9, curve: Curves.easeOut),
                          ),
                        );
                        
                        return Opacity(
                          opacity: signupAnim.value,
                          child: Center(
                            child: TextButton(
                              onPressed: () {
                                Navigator.of(context).pushReplacementNamed('/register');
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                textStyle: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              child: RichText(
                                text: TextSpan(
                                  text: "Don't have an account? ",
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontWeight: FontWeight.w400,
                                  ),
                                  children: const [
                                    TextSpan(
                                      text: 'Create Account',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
                                        decorationThickness: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Fluid Background Painter
class FluidBackgroundPainter extends CustomPainter {
  final Color color1;
  final Color color2;
  final Color color3;
  final double animation;
  
  FluidBackgroundPainter({
    required this.color1,
    required this.color2,
    required this.color3,
    required this.animation,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    
    // Create the base gradient background
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [color1, color2],
      stops: const [0.3, 1.0],
    );
    
    paint.shader = gradient.createShader(rect);
    canvas.drawRect(rect, paint);
    
    // Add fluid shapes
    final path1 = Path();
    final path2 = Path();
    
    // First wave
    double amplitude1 = size.height * 0.05;
    double x1 = 0;
    path1.moveTo(x1, size.height * 0.4 + math.sin(animation * math.pi) * amplitude1);
    
    while (x1 < size.width) {
      double y1 = size.height * 0.4 + 
                 math.sin((x1 / size.width * 2 * math.pi) + (animation * math.pi * 2)) * amplitude1;
      path1.lineTo(x1, y1);
      x1 += 1;
    }
    
    path1.lineTo(size.width, size.height);
    path1.lineTo(0, size.height);
    path1.close();
    
    // Second wave
    double amplitude2 = size.height * 0.03;
    double x2 = 0;
    path2.moveTo(x2, size.height * 0.7 + math.cos(animation * math.pi) * amplitude2);
    
    while (x2 < size.width) {
      double y2 = size.height * 0.7 + 
                 math.cos((x2 / size.width * 3 * math.pi) + (animation * math.pi * 2) + 1) * amplitude2;
      path2.lineTo(x2, y2);
      x2 += 1;
    }
    
    path2.lineTo(size.width, size.height);
    path2.lineTo(0, size.height);
    path2.close();
    
    // Draw the paths with gradients
    paint.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [color2.withOpacity(0.7), color3.withOpacity(0.3)],
    ).createShader(rect);
    canvas.drawPath(path1, paint);
    
    paint.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [color3.withOpacity(0.5), color3.withOpacity(0.1)],
    ).createShader(rect);
    canvas.drawPath(path2, paint);
  }
  
  @override
  bool shouldRepaint(FluidBackgroundPainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}

// Particle Painter
class ParticlesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..style = PaintingStyle.fill;
    
    // Create a random distribution of small particles
    final random = math.Random(42); // Fixed seed for consistency
    for (int i = 0; i < 80; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final radius = random.nextDouble() * 1.5 + 0.5;
      final opacity = random.nextDouble() * 0.4 + 0.1;
      
      paint.color = Colors.white.withOpacity(opacity);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
} 