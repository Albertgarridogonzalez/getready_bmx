// services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<bool> signInWithEmail(
      BuildContext context, String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return true; // Éxito
    } on FirebaseAuthException catch (e) {
      _showErrorSnackbar(context, _getErrorMessage(e.code));
      return false; // Error
    }
  }

  Future<bool> registerWithEmail(
    BuildContext context,
    String email,
    String password,
    List<String> pilots,
    String role,
  ) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Guarda en Firestore con el rol indicado
      await _db.collection('users').doc(result.user!.uid).set({
        'email': email,
        'pilots': pilots,
        'role': role, // Puede ser 'trainer' o 'user'
      });

      return true;
    } on FirebaseAuthException catch (e) {
      _showErrorSnackbar(context, _getErrorMessage(e.code));
      return false;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  void _showErrorSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  String _getErrorMessage(String errorCode) {
    switch (errorCode) {
      case 'invalid-credential':
        return 'Las credenciales proporcionadas son incorrectas o han expirado.';
      case 'user-not-found':
        return 'No se encontró un usuario con ese correo.';
      case 'wrong-password':
        return 'Contraseña incorrecta. Intenta nuevamente.';
      case 'email-already-in-use':
        return 'Este correo ya está registrado.';
      case 'weak-password':
        return 'La contraseña es demasiado débil.';
      default:
        return 'Ocurrió un error. Intenta nuevamente.';
    }
  }
}
