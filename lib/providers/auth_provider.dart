// providers/auth_provider.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:getready_bmx/services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  User? _user;

  User? get user => _user;
  bool get isAuthenticated => _user != null;

  AuthProvider() {
    _authService.authStateChanges.listen((user) {
      _user = user;
      notifyListeners();
    });
  }

  Future<void> signInWithEmail(BuildContext context, String email, String password) async {
    await _authService.signInWithEmail(context, email, password);
  }

  Future<void> registerWithEmail(BuildContext context, String email, String password, String pilotName) async {
    await _authService.registerWithEmail(context, email, password, pilotName);
  }

  Future<void> signOut() async {
    await _authService.signOut();
    notifyListeners();
  }
}
