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
  List<TextEditingController> pilotControllers = [TextEditingController()];
  
  bool isRegistering = false;
  bool isTrainer = false; // Nuevo: para el checkbox

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
                  // Encabezado con imagen
                  Container(
                    width: double.infinity,
                    height: constraints.maxHeight * 0.35,
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
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          SizedBox(height: 30),
                          Text(
                            isRegistering ? 'Registro' : 'Login',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 20),

                          // Email
                          TextField(
                            controller: emailController,
                            decoration: InputDecoration(
                              labelText: 'Email',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          SizedBox(height: 12),

                          // Contraseña
                          TextField(
                            controller: passwordController,
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              border: OutlineInputBorder(),
                            ),
                            obscureText: true,
                          ),
                          SizedBox(height: 12),

                          // Solo mostramos la parte del piloto si está registrando y NO es entrenador
                          if (isRegistering && !isTrainer)
                            TextField(
                              controller: pilotController,
                              decoration: InputDecoration(
                                labelText: 'Nombre del piloto',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          SizedBox(height: 12),

                          // Checkbox: ¿Es Entrenador?
                          if (isRegistering)
                            Row(
                              children: [
                                Checkbox(
                                  value: isTrainer,
                                  onChanged: (value) {
                                    setState(() {
                                      isTrainer = value ?? false;
                                      // Si se marca, vaciamos el piloto y lo deshabilitamos
                                      if (isTrainer) {
                                        pilotController.clear();
                                      }
                                    });
                                  },
                                ),
                                Text("¿Es Entrenador?")
                              ],
                            ),
                          SizedBox(height: 20),

                          // Botón principal (Registrar o Iniciar Sesión)
                          ElevatedButton(
                            onPressed: () async {
                              List<String> pilots = [];
                              
                              if (isRegistering) {
                                // Solo tomamos pilotos si NO es entrenador
                                if (!isTrainer) {
                                  pilots = pilotControllers
                                      .map((c) => c.text.trim())
                                      .where((text) => text.isNotEmpty)
                                      .toList();

                                  String singlePilot = pilotController.text.trim();
                                  if (singlePilot.isNotEmpty) {
                                    pilots.add(singlePilot);
                                  }

                                  if (pilots.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text("Debes agregar al menos un piloto o indicar un nombre")),
                                    );
                                    return;
                                  }
                                }
                              }

                              bool result;
                              if (isRegistering) {
                                // Aquí pasamos el role según sea entrenador o usuario normal
                                final roleToAssign = isTrainer ? 'trainer' : 'user';

                                result = await authProvider.registerWithEmail(
                                  context,
                                  emailController.text.trim(),
                                  passwordController.text.trim(),
                                  pilots, // Pilotos (vacío si es trainer)
                                  roleToAssign, // Se lo pasamos para que lo guarde en Firestore
                                );
                              } else {
                                // Login normal
                                result = await authProvider.signInWithEmail(
                                  context,
                                  emailController.text.trim(),
                                  passwordController.text.trim(),
                                );
                              }

                              if (result == true) {
                                Navigator.of(context).pushReplacementNamed('/home');
                              }
                            },
                            child: Text(isRegistering ? 'Registrar' : 'Iniciar sesión'),
                          ),

                          TextButton(
                            onPressed: () {
                              setState(() {
                                isRegistering = !isRegistering;
                                // Si cambiamos a registro, desmarcamos isTrainer
                                if (!isRegistering) {
                                  isTrainer = false;
                                }
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
