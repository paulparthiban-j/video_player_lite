import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/ui/responsive.dart';
import '../services/vault_service.dart';

class VaultSecuritySetupScreen extends StatefulWidget {
  const VaultSecuritySetupScreen({super.key});

  @override
  State<VaultSecuritySetupScreen> createState() =>
      _VaultSecuritySetupScreenState();
}

class _VaultSecuritySetupScreenState extends State<VaultSecuritySetupScreen> {
  final List<TextEditingController> _questionControllers = [
    TextEditingController(text: 'What was your first pet\'s name?'),
    TextEditingController(text: 'What city were you born in?'),
    TextEditingController(text: 'What is your mother\'s maiden name?'),
  ];

  final List<TextEditingController> _answerControllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];

  final List<FocusNode> _questionFocusNodes = [
    FocusNode(),
    FocusNode(),
    FocusNode(),
  ];

  final List<FocusNode> _answerFocusNodes = [
    FocusNode(),
    FocusNode(),
    FocusNode(),
  ];

  final List<bool> _answerVisibility = [false, false, false];

  bool _isLoading = false;
  bool _showError = false;
  String _errorMessage = '';

  @override
  void dispose() {
    for (final controller in _questionControllers) {
      controller.dispose();
    }
    for (final controller in _answerControllers) {
      controller.dispose();
    }
    for (final focusNode in _questionFocusNodes) {
      focusNode.dispose();
    }
    for (final focusNode in _answerFocusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  bool _validateForm() {
    for (int i = 0; i < 3; i++) {
      if (_questionControllers[i].text.trim().isEmpty) {
        _showErrorMessage('Question ${i + 1} cannot be empty');
        return false;
      }
      if (_answerControllers[i].text.trim().isEmpty) {
        _showErrorMessage('Answer ${i + 1} cannot be empty');
        return false;
      }
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

  Future<void> _setupSecurityQuestions() async {
    if (!_validateForm()) return;

    setState(() {
      _isLoading = true;
      _showError = false;
    });

    unawaited(HapticFeedback.mediumImpact());

    final questions = _questionControllers
        .map((controller) => controller.text.trim())
        .toList();
    final answers = _answerControllers
        .map((controller) => controller.text.trim())
        .toList();

    final success = await VaultService.setSecurityQuestions(questions, answers);

    if (success) {
      unawaited(HapticFeedback.heavyImpact());

      if (!mounted) return;
      unawaited(
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Security Questions Set'),
            content: const Text(
              'Your security questions have been set up successfully!\n\nYou can now use them to reset your password if needed.',
            ),
            backgroundColor: Colors.grey.shade900,
            titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18),
            contentTextStyle: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                  Navigator.of(
                    context,
                  ).pushReplacementNamed('/vault'); // Go to vault
                },
                child: const Text('OK', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ),
      );
    } else {
      unawaited(HapticFeedback.lightImpact());

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _showError = true;
        _errorMessage =
            'Failed to set up security questions. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Security Setup',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Colors.grey.shade900],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: MaxWidthBox(
              maxWidth: 560,
              child: Column(
                children: [
                  const SizedBox(height: 20),

                  Icon(Icons.security, size: 80, color: Colors.red.shade700),

                  const SizedBox(height: 30),

                  const Text(
                    'Set Up Security Questions',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'These questions let you reset your password and still '
                    'decrypt your videos if you forget it. If you set them up '
                    'before, please enter them again to protect your '
                    'encryption key.',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 40),

                  // Security Questions Form
                  ...List.generate(3, (index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade900.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.shade700,
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            // Question Field
                            TextField(
                              controller: _questionControllers[index],
                              focusNode: _questionFocusNodes[index],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Enter security question ${index + 1}',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade500,
                                ),
                                prefixIcon: const Icon(
                                  Icons.help_outline,
                                  color: Colors.grey,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                              ),
                            ),

                            Divider(height: 1, color: Colors.grey.shade700),

                            // Answer Field
                            TextField(
                              controller: _answerControllers[index],
                              focusNode: _answerFocusNodes[index],
                              obscureText: !_answerVisibility[index],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Enter your answer',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade500,
                                ),
                                prefixIcon: const Icon(
                                  Icons.question_answer,
                                  color: Colors.grey,
                                ),
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _answerVisibility[index] =
                                          !_answerVisibility[index];
                                    });
                                    unawaited(HapticFeedback.lightImpact());
                                  },
                                  icon: Icon(
                                    _answerVisibility[index]
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: Colors.grey,
                                  ),
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                  // Error Message
                  if (_showError)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 20),
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

                  // Setup Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _setupSecurityQuestions,
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
                                Text('Setting up...'),
                              ],
                            )
                          : const Text(
                              'Set Up Security Questions',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Security Tips
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900.withValues(alpha: 0.3),
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
                          '• Choose questions with answers you won\'t forget\n'
                          '• Use answers that are not easily guessable\n'
                          '• Store a backup of your answers somewhere safe\n'
                          '• Don\'t use obvious answers that others might know',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
