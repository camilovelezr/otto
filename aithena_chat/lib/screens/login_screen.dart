import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'package:simple_animations/simple_animations.dart';
import '../services/auth_provider.dart';
import '../widgets/animated_gradient_background.dart';
import '../widgets/custom_button.dart';

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
  late AnimationController _fadeController;
  late AnimationController _slideController;

  // Animations
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    
    // Setup fade animation
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut)
    );
    
    // Setup slide animation
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutQuint,
    ));
    
    // Start animations with a small delay
    Future.delayed(const Duration(milliseconds: 200), () {
      _fadeController.forward();
      _slideController.forward();
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final size = MediaQuery.of(context).size;
    final theme = Theme.of(context);
    
    return Scaffold(
      body: Stack(
        children: [
          // Animated background
          const AnimatedGradientBackground(),
          
          // Main content
          SafeArea(
            child: SingleChildScrollView(
              child: SizedBox(
                height: size.height - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo and title section
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: _buildLogoSection(theme),
                        ),
                      ),
                      
                      const SizedBox(height: 40),
                      
                      // Glassmorphism card for form
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: _buildGlassCard(authProvider, theme),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLogoSection(ThemeData theme) {
    return Column(
      children: [
        // Animated AI logo
        Container(
          height: 100,
          width: 100,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Pulsing circles
                _buildPulsingCircle(80, 2.5),
                _buildPulsingCircle(60, 1.8, delay: 400),
                _buildPulsingCircle(40, 1.2, delay: 800),
                
                // Center icon
                Icon(
                  Icons.psychology_outlined,
                  size: 40,
                  color: Colors.white.withOpacity(0.9),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'AIthena',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your intelligent conversation partner',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: Colors.white.withOpacity(0.7),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
  
  Widget _buildPulsingCircle(double size, double duration, {int delay = 0}) {
    return PlayAnimation<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(seconds: duration.toInt()),
      delay: Duration(milliseconds: delay),
      curve: Curves.easeInOut,
      builder: (context, child, value) {
        return Opacity(
          opacity: (1.0 - value) * 0.4,
          child: Container(
            width: size * value,
            height: size * value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.8),
                width: 2.0,
              ),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildGlassCard(AuthProvider authProvider, ThemeData theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Welcome Back',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to continue the conversation',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 32),
                
                // Username field with staggered animation
                _buildAnimatedFormField(
                  controller: _usernameController,
                  label: 'Username',
                  icon: Icons.person_outline,
                  delay: 200,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your username';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 16),
                
                // Password field with staggered animation
                _buildAnimatedFormField(
                  controller: _passwordController,
                  label: 'Password',
                  icon: Icons.lock_outline,
                  isPassword: true,
                  delay: 400,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                      color: Colors.white70,
                    ),
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
                  ),
                ),
                
                // Forgot password
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      // Navigate to forgot password screen
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white.withOpacity(0.8),
                    ),
                    child: const Text('Forgot Password?'),
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Error message
                if (authProvider.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Text(
                        authProvider.error!,
                        style: TextStyle(color: Colors.red[300]),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                
                const SizedBox(height: 8),
                
                // Login button with animation
                _buildAnimatedFormField(
                  delay: 600,
                  child: CustomButton(
                    label: 'Login',
                    isLoading: authProvider.isLoading,
                    onPressed: _login,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF33E1ED), Color(0xFF6B5AD3)],
                    ),
                    elevation: 0,
                    borderRadius: 12,
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Register option
                _buildAnimatedFormField(
                  delay: 700,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account?",
                        style: TextStyle(color: Colors.white.withOpacity(0.7)),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pushNamed('/register');
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          'Register',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildAnimatedFormField({
    TextEditingController? controller,
    String? label,
    IconData? icon,
    bool isPassword = false,
    int delay = 0,
    String? Function(String?)? validator,
    Widget? suffixIcon,
    Widget? child,
  }) {
    return PlayAnimation<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      delay: Duration(milliseconds: delay),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutQuad,
      builder: (context, _, value) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child ?? TextFormField(
              controller: controller,
              obscureText: isPassword && !_isPasswordVisible,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.7)),
                suffixIcon: suffixIcon,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF33E1ED)),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.red.shade300),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.red.shade300, width: 2),
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                errorStyle: TextStyle(color: Colors.red.shade300),
              ),
              validator: validator,
            ),
          ),
        );
      },
    );
  }
} 