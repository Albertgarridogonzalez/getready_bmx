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
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: Container(
              width: double.infinity,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  // Encabezado con imagen (puedes ajustar altura, opacidad, etc.)
                  Container(
                    width: double.infinity,
                    height: constraints.maxHeight * 0.45,
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      image: DecorationImage(
                        image: AssetImage('assets/imagenes/mi_imagen.png'),
                        fit: BoxFit.cover,
                        opacity: 0.8,
                      ),
                    ),
                  ),

                  // Formulario de Login / Registro
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(height: 16),
                          Text(
                            isRegistering ? 'Registro' : 'Login',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 20),
                          TextField(
                            controller: emailController,
                            decoration: InputDecoration(
                              labelText: 'Email',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          SizedBox(height: 12),
                          TextField(
                            controller: passwordController,
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              border: OutlineInputBorder(),
                            ),
                            obscureText: true,
                          ),
                          SizedBox(height: 12),
                          if (isRegistering)
                            TextField(
                              controller: pilotController,
                              decoration: InputDecoration(
                                labelText: 'Nombre del piloto',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: () async {
                              bool result;
                              if (isRegistering) {
                                // Intenta registrar
                                result = await authProvider.registerWithEmail(
                                  context,
                                  emailController.text.trim(),
                                  passwordController.text.trim(),
                                  pilotController.text.trim(),
                                );
                              } else {
                                // Intenta iniciar sesión
                                result = await authProvider.signInWithEmail(
                                  context,
                                  emailController.text.trim(),
                                  passwordController.text.trim(),
                                );
                              }
                              
                              // Navega solo si result == true (éxito)
                              if (result == true) {
                                Navigator.of(context)
                                    .pushReplacementNamed('/home');
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              minimumSize: Size(double.infinity, 48),
                            ),
                            child: Text(
                              isRegistering ? 'Registrar' : 'Iniciar sesión',
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                isRegistering = !isRegistering;
                              });
                            },
                            child: Text(
                              isRegistering
                                  ? '¿Ya tienes cuenta? Iniciar sesión'
                                  : 'Crear una cuenta',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
