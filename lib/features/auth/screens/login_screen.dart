import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/motifs.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final error = await signIn(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;

    if (error != null) {
      setState(() {
        _loading = false;
        _errorMessage = error;
      });
    } else {
      // Router redirect will handle navigation based on role
      context.go('/login'); // Triggers redirect
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppGradients.dawn),
        child: Stack(
          children: [
            // Feather watermarks, echoing Krsna's crown.
            Positioned(
              top: -30,
              left: -40,
              child: Transform.rotate(
                angle: -0.5,
                child: const PeacockFeather(size: 170, opacity: 0.13),
              ),
            ),
            Positioned(
              bottom: -50,
              right: -45,
              child: Transform.rotate(
                angle: 2.7,
                child: const PeacockFeather(size: 200, opacity: 0.10),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Lotus emblem
                        Container(
                          width: 112,
                          height: 112,
                          decoration: BoxDecoration(
                            gradient: AppGradients.sacred,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.saffronDark.withValues(
                                  alpha: 0.28,
                                ),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const Center(child: LotusIcon.light(size: 62)),
                        ),
                        const SizedBox(height: 26),

                        // Greeting
                        Text(
                          'Hare Krishna!',
                          style: Theme.of(context).textTheme.displayMedium
                              ?.copyWith(color: AppColors.tealDark),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'IYS Attendance',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: AppColors.onSurfaceVariant,
                                letterSpacing: 1.2,
                              ),
                        ),
                        const SizedBox(height: 14),
                        const _MantraRule(),
                        const SizedBox(height: 34),

                        // Login form
                        Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  hintText: 'Enter your email',
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter your email';
                                  }
                                  if (!value.contains('@')) {
                                    return 'Please enter a valid email';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _handleLogin(),
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  hintText: 'Enter your password',
                                  prefixIcon: const Icon(Icons.lock_outlined),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter your password';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),

                              // Error message
                              if (_errorMessage != null)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.error.withValues(
                                      alpha: 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: AppColors.error,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: AppColors.error,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              const SizedBox(height: 28),

                              // Login button
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton(
                                  onPressed: _loading ? null : _handleLogin,
                                  child: _loading
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text('Log In'),
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
          ],
        ),
      ),
    );
  }
}

/// A slim saffron rule with a lotus at its centre, used to separate the
/// greeting from the form.
class _MantraRule extends StatelessWidget {
  const _MantraRule();

  @override
  Widget build(BuildContext context) {
    Widget line(List<Color> colors) => Expanded(
      child: Container(
        height: 1.5,
        decoration: BoxDecoration(gradient: LinearGradient(colors: colors)),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        line([AppColors.saffron.withValues(alpha: 0), AppColors.saffron]),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: LotusIcon(size: 18),
        ),
        line([AppColors.saffron, AppColors.saffron.withValues(alpha: 0)]),
      ],
    );
  }
}
