// screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:getready_bmx/providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController pilotController = TextEditingController();
  bool isRegistering = false;

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(title: Text(isRegistering ? 'Registro' : 'Login')),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: emailController,
              decoration: InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: passwordController,
              decoration: InputDecoration(labelText: 'Contraseña'),
              obscureText: true,
            ),
            if (isRegistering)
              TextField(
                controller: pilotController,
                decoration: InputDecoration(labelText: 'Nombre del piloto'),
              ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                if (isRegistering) {
                  await authProvider.registerWithEmail(
                    context,
                    emailController.text,
                    passwordController.text,
                    pilotController.text,
                  );
                } else {
                  await authProvider.signInWithEmail(
                    context,
                    emailController.text,
                    passwordController.text,
                  );
                }
                Navigator.of(context).pushReplacementNamed('/home');
              },
              child: Text(isRegistering ? 'Registrar' : 'Iniciar sesión'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  isRegistering = !isRegistering;
                });
              },
              child: Text(isRegistering ? '¿Ya tienes cuenta? Iniciar sesión' : 'Crear una cuenta'),
            ),
          ],
        ),
      ),
    );
  }
}