import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:getready_bmx/providers/auth_provider.dart';
import 'package:getready_bmx/providers/theme_provider.dart';
import 'package:google_fonts/google_fonts.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController pilotController = TextEditingController();
  List<TextEditingController> pilotControllers = [TextEditingController()];

  bool isRegistering = false;
  bool isTrainer = false;

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final primary = themeProvider.primaryColor;

    return Scaffold(
      body: Stack(
        children: [
          // Background Image with Dark Overlay
          Positioned.fill(
            child: Image.asset(
              'assets/imagenes/mi_imagen.png',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.3),
                    Colors.black.withOpacity(0.8),
                    Colors.black,
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 40),
                        // Logo/Title
                        Text(
                          "GATE READY",
                          style: GoogleFonts.orbitron(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 4,
                          ),
                        ),
                        Text(
                          "BMX PERFORMANCE",
                          style: GoogleFonts.orbitron(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: primary,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 60),

                        // Glassmorphism Container
                        ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.all(30),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.2)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    isRegistering ? 'REGISTRO' : 'LOGIN',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.orbitron(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 30),
                                  _buildTextField(
                                    controller: emailController,
                                    label: 'Email',
                                    icon: Icons.email_outlined,
                                    primary: primary,
                                  ),
                                  const SizedBox(height: 16),
                                  _buildTextField(
                                    controller: passwordController,
                                    label: 'Contraseña',
                                    icon: Icons.lock_outline,
                                    obscure: true,
                                    primary: primary,
                                  ),
                                  if (isRegistering && !isTrainer) ...[
                                    const SizedBox(height: 16),
                                    _buildTextField(
                                      controller: pilotController,
                                      label: 'Nombre del piloto',
                                      icon: Icons.person_outline,
                                      primary: primary,
                                    ),
                                  ],
                                  if (isRegistering) ...[
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Theme(
                                          data: ThemeData(
                                              unselectedWidgetColor:
                                                  Colors.white70),
                                          child: Checkbox(
                                            value: isTrainer,
                                            activeColor: primary,
                                            onChanged: (value) {
                                              setState(() {
                                                isTrainer = value ?? false;
                                                if (isTrainer)
                                                  pilotController.clear();
                                              });
                                            },
                                          ),
                                        ),
                                        const Text(
                                          "¿Es Entrenador?",
                                          style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 13),
                                        )
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 30),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(15)),
                                      elevation: 0,
                                    ),
                                    onPressed: () async {
                                      List<String> pilots = [];
                                      if (isRegistering && !isTrainer) {
                                        pilots = pilotControllers
                                            .map((c) => c.text.trim())
                                            .where((t) => t.isNotEmpty)
                                            .toList();
                                        if (pilotController.text
                                            .trim()
                                            .isNotEmpty)
                                          pilots
                                              .add(pilotController.text.trim());
                                        if (pilots.isEmpty) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                                  content: Text(
                                                      "Debes agregar al menos un piloto")));
                                          return;
                                        }
                                      }

                                      bool result;
                                      if (isRegistering) {
                                        result = await authProvider
                                            .registerWithEmail(
                                          context,
                                          emailController.text.trim(),
                                          passwordController.text.trim(),
                                          pilots,
                                          isTrainer ? 'trainer' : 'user',
                                        );
                                      } else {
                                        result =
                                            await authProvider.signInWithEmail(
                                          context,
                                          emailController.text.trim(),
                                          passwordController.text.trim(),
                                        );
                                      }

                                      if (result == true)
                                        Navigator.of(context)
                                            .pushReplacementNamed('/home');
                                    },
                                    child: Text(
                                      isRegistering ? 'CREAR CUENTA' : 'ENTRAR',
                                      style: GoogleFonts.orbitron(
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        isRegistering = !isRegistering;
                                        if (!isRegistering) isTrainer = false;
                                      });
                                    },
                                    child: Text(
                                      isRegistering
                                          ? '¿YA TIENES CUENTA? LOGIN'
                                          : 'CREAR UNA CUENTA',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 12,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    required Color primary,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
        prefixIcon: Icon(icon, color: primary.withOpacity(0.8), size: 20),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: primary.withOpacity(0.5)),
        ),
      ),
    );
  }
}
