import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/vault_service.dart';

class VaultSetupScreen extends StatefulWidget {
  const VaultSetupScreen({super.key});

  @override
  State<VaultSetupScreen> createState() => _VaultSetupScreenState();
}

class _VaultSetupScreenState extends State<VaultSetupScreen>
    with TickerProviderStateMixin {
  final TextEditingController _mainPasswordController = TextEditingController();
  final TextEditingController _confirmMainController = TextEditingController();
  final TextEditingController _fakePasswordController = TextEditingController();
  final TextEditingController _confirmFakeController = TextEditingController();

  final FocusNode _mainPasswordFocus = FocusNode();
  final FocusNode _confirmMainFocus = FocusNode();
  final FocusNode _fakePasswordFocus = FocusNode();
  final FocusNode _confirmFakeFocus = FocusNode();

  bool _isMainPasswordVisible = false;
  bool _isConfirmMainVisible = false;
  bool _isFakePasswordVisible = false;
  bool _isConfirmFakeVisible = false;

  bool _isLoading = false;
  bool _showError = false;
  String _errorMessage = '';

  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _mainPasswordController.dispose();
    _confirmMainController.dispose();
    _fakePasswordController.dispose();
    _confirmFakeController.dispose();

    _mainPasswordFocus.dispose();
    _confirmMainFocus.dispose();
    _fakePasswordFocus.dispose();
    _confirmFakeFocus.dispose();

    _slideController.dispose();
    _fadeController.dispose();

    super.dispose();
  }

  bool _validatePasswords() {
    if (_mainPasswordController.text.length < VaultService.minPasswordLength) {
      _showErrorMessage('Main password must be at least ${VaultService.minPasswordLength} characters');
      return false;
    }

    if (_mainPasswordController.text != _confirmMainController.text) {
      _showErrorMessage('Main passwords do not match');
      return false;
    }

    if (_fakePasswordController.text.length < VaultService.minPasswordLength) {
      _showErrorMessage('Fake password must be at least ${VaultService.minPasswordLength} characters');
      return false;
    }

    if (_fakePasswordController.text != _confirmFakeController.text) {
      _showErrorMessage('Fake passwords do not match');
      return false;
    }

    if (_mainPasswordController.text == _fakePasswordController.text) {
      _showErrorMessage('Main and fake passwords must be different');
      return false;
    }

    return true;
  }

  void _showErrorMessage(String message) {
    setState(() {
      _showError = true;
      _errorMessage = message;
    });

    unawaited(HapticFeedback.lightImpact());
  }

  Future<void> _setupVault() async {
    if (!_validatePasswords()) return;

    setState(() {
      _isLoading = true;
      _showError = false;
    });

    unawaited(HapticFeedback.mediumImpact());

    final success = await VaultService.setupVault(
      _mainPasswordController.text,
      _fakePasswordController.text,
    );

    if (success) {
      unawaited(HapticFeedback.heavyImpact());

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/vault-auth');
      }
    } else {
      unawaited(HapticFeedback.lightImpact());

      setState(() {
        _isLoading = false;
        _showError = true;
        _errorMessage = 'Failed to setup vault. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = colorScheme.surface;
    final surfaceVariant = colorScheme.surfaceContainerHighest;
    final onSurface = colorScheme.onSurface;
    final onSurfaceVariant = colorScheme.onSurfaceVariant;

    return Scaffold(
      backgroundColor: surface,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [Colors.black, Colors.grey.shade900]
                : [surface, surfaceVariant],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: SlideTransition(
                position: _slideAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    children: [
                      // Vault Icon
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Colors.red.shade800, Colors.red.shade600],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.shade800.withValues(alpha: 0.3),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.security,
                          size: 50,
                          color: Colors.white,
                        ),
                      ),

                      const SizedBox(height: 30),

                      // Title
                      Text(
                        'Setup Private Folder',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: onSurface,
                          letterSpacing: 1.2,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Create passwords to protect your private videos',
                        style: TextStyle(
                          fontSize: 16,
                          color: onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 40),

                      // Main Password Section
                      _buildPasswordSection(
                        title: 'Main Password',
                        subtitle: 'For accessing your private videos',
                        passwordController: _mainPasswordController,
                        confirmController: _confirmMainController,
                        passwordFocus: _mainPasswordFocus,
                        confirmFocus: _confirmMainFocus,
                        isPasswordVisible: _isMainPasswordVisible,
                        isConfirmVisible: _isConfirmMainVisible,
                        onPasswordVisibilityToggle: () {
                          setState(() {
                            _isMainPasswordVisible = !_isMainPasswordVisible;
                          });
                        },
                        onConfirmVisibilityToggle: () {
                          setState(() {
                            _isConfirmMainVisible = !_isConfirmMainVisible;
                          });
                        },
                      ),

                      const SizedBox(height: 30),

                      // Fake Password Section
                      _buildPasswordSection(
                        title: 'Decoy Password',
                        subtitle: 'Opens a different folder for privacy',
                        passwordController: _fakePasswordController,
                        confirmController: _confirmFakeController,
                        passwordFocus: _fakePasswordFocus,
                        confirmFocus: _confirmFakeFocus,
                        isPasswordVisible: _isFakePasswordVisible,
                        isConfirmVisible: _isConfirmFakeVisible,
                        onPasswordVisibilityToggle: () {
                          setState(() {
                            _isFakePasswordVisible = !_isFakePasswordVisible;
                          });
                        },
                        onConfirmVisibilityToggle: () {
                          setState(() {
                            _isConfirmFakeVisible = !_isConfirmFakeVisible;
                          });
                        },
                      ),

                      const SizedBox(height: 20),

                      // Error Message
                      if (_showError)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade900.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.red.shade600.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Colors.red.shade400,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage,
                                  style: TextStyle(
                                    color: Colors.red.shade400,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 40),

                      // Setup Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _setupVault,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text('Setting up...'),
                                  ],
                                )
                              : const Text(
                                  'Create Folder',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Security Info
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.grey.shade900.withValues(alpha: 0.3)
                              : surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.shade700.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Colors.blue.shade400,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Security Tips',
                                    style: TextStyle(
                                      color: Colors.blue.shade400,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '• Use different passwords for main and decoy folders\n'
                              '• Decoy folder provides privacy protection\n'
                              '• Store passwords safely\n'
                              '• Change passwords regularly',
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 12,
                                height: 1.4,
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
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordSection({
    required String title,
    required String subtitle,
    required TextEditingController passwordController,
    required TextEditingController confirmController,
    required FocusNode passwordFocus,
    required FocusNode confirmFocus,
    required bool isPasswordVisible,
    required bool isConfirmVisible,
    required VoidCallback onPasswordVisibilityToggle,
    required VoidCallback onConfirmVisibilityToggle,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = colorScheme.onSurface;
    final onSurfaceVariant = colorScheme.onSurfaceVariant;
    final fieldColor =
        isDark ? Colors.grey.shade900.withValues(alpha: 0.5) : colorScheme.surfaceContainerHighest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(color: onSurfaceVariant, fontSize: 14),
        ),
        const SizedBox(height: 16),

        // Password Field
        Container(
          decoration: BoxDecoration(
            color: fieldColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade700, width: 1),
          ),
          child: TextField(
            controller: passwordController,
            focusNode: passwordFocus,
            obscureText: !isPasswordVisible,
            style: TextStyle(color: onSurface, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Enter password',
              hintStyle: TextStyle(color: onSurfaceVariant),
              prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
              suffixIcon: IconButton(
                onPressed: onPasswordVisibilityToggle,
                icon: Icon(
                  isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey,
                ),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Confirm Password Field
        Container(
          decoration: BoxDecoration(
            color: fieldColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade700, width: 1),
          ),
          child: TextField(
            controller: confirmController,
            focusNode: confirmFocus,
            obscureText: !isConfirmVisible,
            style: TextStyle(color: onSurface, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Confirm password',
              hintStyle: TextStyle(color: onSurfaceVariant),
              prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
              suffixIcon: IconButton(
                onPressed: onConfirmVisibilityToggle,
                icon: Icon(
                  isConfirmVisible ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey,
                ),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
