import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/vault_service.dart';

class VaultAuthScreen extends StatefulWidget {
  const VaultAuthScreen({super.key});

  @override
  State<VaultAuthScreen> createState() => _VaultAuthScreenState();
}

class _VaultAuthScreenState extends State<VaultAuthScreen>
    with TickerProviderStateMixin {
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _passwordFocusNode = FocusNode();

  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _showError = false;
  String _errorMessage = '';

  late AnimationController _shakeController;
  late AnimationController _fadeController;
  late Animation<double> _shakeAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _shakeAnimation = Tween<double>(begin: 0, end: 10).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _fadeController.forward();

    _passwordFocusNode.addListener(() {
      if (_passwordFocusNode.hasFocus) {
        _fadeController.forward();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final isSetup = await VaultService.isVaultSetup();
      if (!mounted) return;
      if (!isSetup) {
        Navigator.of(context).pushReplacementNamed('/vault-setup');
      }
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    _shakeController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    if (_passwordController.text.isEmpty) return;

    setState(() {
      _isLoading = true;
      _showError = false;
    });

    unawaited(HapticFeedback.lightImpact());

    final result = await VaultService.unlock(_passwordController.text);
    if (!mounted) return;

    if (result.isSuccess) {
      unawaited(HapticFeedback.heavyImpact());

      // Recovery questions protect the main vault only; the decoy vault must
      // never be able to configure them.
      final needsSecuritySetup = !VaultService.isInFakeMode &&
          !await VaultService.isSecuritySetup();
      if (!mounted) return;
      unawaited(
        Navigator.of(context).pushReplacementNamed(
          needsSecuritySetup ? '/vault-security-setup' : '/vault',
        ),
      );
    } else {
      unawaited(HapticFeedback.heavyImpact());

      setState(() {
        _isLoading = false;
        _showError = true;
        _errorMessage = _messageFor(result);
      });

      unawaited(
        _shakeController.forward().then((_) => _shakeController.reverse()),
      );

      _passwordController.clear();
      _passwordFocusNode.requestFocus();
    }
  }

  String _messageFor(VaultAuthResult result) {
    switch (result.status) {
      case VaultAuthStatus.lockedOut:
        final wait = result.retryAfter;
        final amount = wait.inSeconds >= 60
            ? '${(wait.inSeconds / 60).ceil()} min'
            : '${wait.inSeconds + 1} s';
        return 'Too many attempts. Try again in $amount.';
      case VaultAuthStatus.notSetUp:
        return 'Vault is not set up yet';
      case VaultAuthStatus.error:
        return 'Something went wrong. Please try again.';
      case VaultAuthStatus.invalidPassword:
      case VaultAuthStatus.success:
        return 'Incorrect password';
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
            colors: isDark ? [Colors.black, Colors.grey.shade900] : [surface, surfaceVariant],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Vault Icon
                    Container(
                      width: 120,
                      height: 120,
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
                        Icons.lock,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Title
                    Text(
                      'Private Videos',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: onSurface,
                        letterSpacing: 1.2,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'Enter password to access your videos',
                      style: TextStyle(
                        fontSize: 16,
                        color: onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 60),

                    // Password Input
                    AnimatedBuilder(
                      animation: _shakeAnimation,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(
                            _shakeAnimation.value * (_showError ? 1 : -1),
                            0,
                          ),
                          child: child,
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.grey.shade900.withValues(alpha: 0.5)
                              : surfaceVariant,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _showError
                                ? Colors.red.shade600
                                : Colors.grey.shade700,
                            width: 2,
                          ),
                        ),
                        child: TextField(
                          controller: _passwordController,
                          focusNode: _passwordFocusNode,
                          obscureText: !_isPasswordVisible,
                          style: TextStyle(color: onSurface, fontSize: 18),
                          decoration: InputDecoration(
                            hintText: 'Enter password',
                            hintStyle: TextStyle(color: onSurfaceVariant),
                            prefixIcon: const Icon(
                              Icons.lock_outline,
                              color: Colors.grey,
                            ),
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  _isPasswordVisible = !_isPasswordVisible;
                                });
                                unawaited(HapticFeedback.lightImpact());
                              },
                              icon: Icon(
                                _isPasswordVisible
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.grey,
                              ),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 20,
                            ),
                          ),
                          onSubmitted: (_) => _authenticate(),
                        ),
                      ),
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

                    // Login Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _authenticate,
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
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text('Accessing...'),
                                ],
                              )
                            : const Text(
                                'Access Videos',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),

                    SizedBox(height: 30),

                    // Forgot Password Button
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pushNamed('/vault-forgot');
                      },
                      child: Text(
                        'Forgot password?',
                        style: TextStyle(
                          color: onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Hard Reset Button
                    TextButton(
                      onPressed: () => _showHardResetDialog(),
                      child: Text(
                        'Format Vault & Clear All Data',
                        style: TextStyle(
                          color: Colors.red.shade400.withValues(alpha: 0.6),
                          fontSize: 12,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showHardResetDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surface,
        title: Text(
          'Format Vault?',
          style: TextStyle(color: colorScheme.onSurface),
        ),
        content: Text(
          'This will PERMANENTLY delete all files inside the private folder and reset your password. This action cannot be undone.',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);

              navigator.pop();
              await VaultService.hardResetVault();

              if (mounted) {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('Vault cleared successfully')),
                );
                navigator.pushReplacementNamed('/vault-setup');
              }
            },
            child: const Text('FORMAT', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
