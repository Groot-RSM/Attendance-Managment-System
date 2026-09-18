import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;
import '../services/auth_service.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLogin;

  const LoginScreen({Key? key, required this.onLogin}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _showPassword = false;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _rememberMe = false;
  bool _isLoading = false;
  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E293B), // slate-800
      body: Stack(
        children: [
          // Particles Background
          Positioned.fill(
            child: Opacity(
              opacity: 0.2,
              child: CustomPaint(
                painter: ParticlesPainter(),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24.0, vertical: 40.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo
                    const HexLogo(),
                    const SizedBox(height: 16),
                    RichText(
                      textAlign: TextAlign.center,
                      text: const TextSpan(
                        style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5),
                        children: [
                          TextSpan(
                              text: 'SMART ',
                              style: TextStyle(color: Colors.white)),
                          TextSpan(
                              text: 'ATTENDANCE',
                              style: TextStyle(
                                  color: Color(0xFF0EA5E9))), // sky-500
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Fingerprint · IoT · Smart School',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          letterSpacing: 0.5), // slate-400
                    ),
                    const SizedBox(height: 48),

                    // Login Form
                    const Text(
                      'Login',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Welcome back! 👋\nPlease sign in to continue',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                    ),
                    const SizedBox(height: 32),

                    // Email Field
                    const Text('Email / Phone',
                        style: TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: 12,
                            fontWeight: FontWeight.w500)), // slate-300
                    const SizedBox(height: 6),
                    TextField(
                      controller: _emailController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Enter email or phone',
                        hintStyle: const TextStyle(
                            color: Color(0xFF64748B)), // slate-500
                        filled: true,
                        fillColor: Colors.transparent,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFF475569)), // slate-600
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFF0EA5E9)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Password Field
                    const Text('Password',
                        style: TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _passwordController,
                      obscureText: !_showPassword,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Enter password',
                        hintStyle: const TextStyle(color: Color(0xFF64748B)),
                        filled: true,
                        fillColor: Colors.transparent,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFF475569)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFF0EA5E9)),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: const Color(0xFF94A3B8),
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _showPassword = !_showPassword;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Options
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: _rememberMe,
                                onChanged: (val) {
                                  setState(() {
                                    _rememberMe = val ?? false;
                                  });
                                },
                                activeColor: const Color(0xFF0EA5E9),
                                checkColor: Colors.white,
                                side:
                                    const BorderSide(color: Color(0xFF94A3B8)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('Remember me',
                                style: TextStyle(
                                    color: Color(0xFF94A3B8), fontSize: 12)),
                          ],
                        ),
                        TextButton(
                          onPressed: () {},
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Forgot Password?',
                              style: TextStyle(
                                  color: Color(0xFF38BDF8),
                                  fontSize: 12)), // sky-400
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Login Button
                    ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : () async {
                              final email = _emailController.text.trim();
                              final password = _passwordController.text;

                              if (email.isEmpty || password.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Please enter email and password')),
                                );
                                return;
                              }

                              setState(() => _isLoading = true);

                              try {
                                final user = await _authService.loginWithEmail(
                                    email, password);
                                if (mounted) {
                                  setState(() => _isLoading = false);
                                  if (user != null) {
                                    widget.onLogin();
                                  }
                                }
                              } on FirebaseAuthException catch (e) {
                                if (mounted) {
                                  setState(() => _isLoading = false);
                                  String message = 'Login failed';
                                  if (e.code == 'user-not-found' ||
                                      e.code == 'wrong-password' ||
                                      e.code == 'invalid-credential') {
                                    message = 'Invalid email or password';
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(message)));
                                }
                              } catch (e) {
                                if (mounted) {
                                  setState(() => _isLoading = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'An unexpected error occurred')));
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0EA5E9),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Login',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 20),

                    // Divider
                    Row(
                      children: [
                        Expanded(
                            child: Container(
                                height: 1,
                                color: Colors.white.withOpacity(0.1))),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12.0),
                          child: Text('or continue with',
                              style: TextStyle(
                                  color: Color(0xFF64748B), fontSize: 12)),
                        ),
                        Expanded(
                            child: Container(
                                height: 1,
                                color: Colors.white.withOpacity(0.1))),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Google Button
                    OutlinedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () async {
                              setState(() => _isLoading = true);
                              try {
                                final user =
                                    await _authService.signInWithGoogle();
                                if (mounted) {
                                  setState(() => _isLoading = false);
                                  if (user != null) {
                                    widget.onLogin();
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Failed to sign in with Google')),
                                    );
                                  }
                                }
                              } catch (e) {
                                if (mounted) {
                                  setState(() => _isLoading = false);
                                  if (e
                                      .toString()
                                      .contains('profile-not-found')) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Please sign up manually first to provide your details.')),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'An unexpected error occurred')),
                                    );
                                  }
                                }
                              }
                            },
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF0EA5E9)))
                          : const Icon(Icons.g_mobiledata,
                              color: Colors.white,
                              size: 28), // Placeholder for Google Icon
                      label: Text(_isLoading ? 'Signing in...' : 'Google',
                          style: const TextStyle(
                              color: Color(0xFFCBD5E1), fontSize: 14)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Color(0xFF475569)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Signup
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Don't have an account? ",
                            style: TextStyle(
                                color: Color(0xFF64748B), fontSize: 12)),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    SignupScreen(onSignup: widget.onLogin),
                              ),
                            );
                          },
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Sign up',
                              style: TextStyle(
                                  color: Color(0xFF38BDF8), fontSize: 12)),
                        ),
                      ],
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

class HexLogo extends StatelessWidget {
  const HexLogo({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 88,
      child: CustomPaint(
        painter: HexLogoPainter(),
      ),
    );
  }
}

class HexLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..shader = const LinearGradient(
        colors: [
          Color(0x400EA5E9),
          Color(0x260369A1)
        ], // sky-500 25%, sky-700 15%
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    path.moveTo(size.width * 0.5, size.height * 0.02);
    path.lineTo(size.width * 0.95, size.height * 0.25);
    path.lineTo(size.width * 0.95, size.height * 0.75);
    path.lineTo(size.width * 0.5, size.height * 0.98);
    path.lineTo(size.width * 0.05, size.height * 0.75);
    path.lineTo(size.width * 0.05, size.height * 0.25);
    path.close();

    canvas.drawPath(path, paint);

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = const LinearGradient(
        colors: [Color(0xFF38BDF8), Color(0xFF0EA5E9)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(path, strokePaint);

    // Fingerprint arcs and checkmark could be drawn here, keeping it simple for now
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF38BDF8)
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(
          center: Offset(size.width * 0.5, size.height * 0.5), radius: 10),
      math.pi,
      math.pi,
      false,
      arcPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(
          center: Offset(size.width * 0.5, size.height * 0.5), radius: 15),
      math.pi * 0.8,
      math.pi * 1.4,
      false,
      arcPaint..color = const Color(0xFF7DD3FC),
    );

    final checkPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF22C55E);

    final checkCenter = Offset(size.width * 0.67, size.height * 0.7);
    canvas.drawCircle(checkCenter, 8, checkPaint);

    final checkStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final checkPath = Path();
    checkPath.moveTo(checkCenter.dx - 3, checkCenter.dy);
    checkPath.lineTo(checkCenter.dx - 1, checkCenter.dy + 3);
    checkPath.lineTo(checkCenter.dx + 4, checkCenter.dy - 2);
    canvas.drawPath(checkPath, checkStroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ParticlesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF38BDF8).withOpacity(0.6)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = const Color(0xFF38BDF8).withOpacity(0.4)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    final dots = List.generate(28, (i) {
      return Offset(
        (i * 37 + 11) % 100 * size.width / 100,
        (i * 61 + 19) % 100 * size.height / 100,
      );
    });

    for (var i = 0; i < dots.length; i++) {
      final r = i % 3 == 0 ? 2.5 : 1.5;
      canvas.drawCircle(dots[i], r, paint);
    }

    for (var i = 0; i < 14; i++) {
      final d1 = dots[i];
      final d2 = dots[(i + 5) % dots.length];
      canvas.drawLine(d1, d2, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
