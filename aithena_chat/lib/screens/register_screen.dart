import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'package:simple_animations/simple_animations.dart';
import '../services/auth_provider.dart';
import '../widgets/animated_gradient_background.dart';
import '../widgets/custom_button.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  
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
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _register() async {
    if (_formKey.currentState!.validate()) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      final success = await authProvider.register(
        _usernameController.text.trim(),
        _passwordController.text,
        _nameController.text.trim(),
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
                      // Back button
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Logo and title section
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: _buildHeaderSection(theme),
                        ),
                      ),
                      
                      const SizedBox(height: 30),
                      
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
  
  Widget _buildHeaderSection(ThemeData theme) {
    return Column(
      children: [
        Text(
          'Create Account',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Join AIthena and start the conversation',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: Colors.white.withOpacity(0.7),
          ),
          textAlign: TextAlign.center,
        ),
      ],
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
                // Display name field with staggered animation
                _buildAnimatedFormField(
                  controller: _nameController,
                  label: 'Display Name',
                  icon: Icons.person_outline,
                  delay: 200,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 16),
                
                // Username field with staggered animation
                _buildAnimatedFormField(
                  controller: _usernameController,
                  label: 'Username',
                  icon: Icons.alternate_email,
                  delay: 400,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a username';
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
                  delay: 600,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a password';
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
                
                const SizedBox(height: 16),
                
                // Confirm Password field with staggered animation
                _buildAnimatedFormField(
                  controller: _confirmPasswordController,
                  label: 'Confirm Password',
                  icon: Icons.lock_outline,
                  isPassword: true,
                  delay: 800,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please confirm your password';
                    }
                    if (value != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isConfirmPasswordVisible ? Icons.visibility : Icons.visibility_off,
                      color: Colors.white70,
                    ),
                    onPressed: () {
                      setState(() {
                        _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                      });
                    },
                  ),
                ),
                
                const SizedBox(height: 24),
                
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
                
                // Register button with animation
                _buildAnimatedFormField(
                  delay: 1000,
                  child: CustomButton(
                    label: 'Create Account',
                    isLoading: authProvider.isLoading,
                    onPressed: _register,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF33E1ED), Color(0xFF6B5AD3)],
                    ),
                    elevation: 0,
                    borderRadius: 12,
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Login option
                _buildAnimatedFormField(
                  delay: 1100,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account?',
                        style: TextStyle(color: Colors.white.withOpacity(0.7)),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          'Login',
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
              obscureText: isPassword && (
                controller == _passwordController ? !_isPasswordVisible : !_isConfirmPasswordVisible
              ),
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