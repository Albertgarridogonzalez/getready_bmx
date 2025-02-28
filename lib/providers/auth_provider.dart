// auth_provider.dart
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

  Future<bool> signInWithEmail(BuildContext context, String email, String password) async {
    bool ok = await _authService.signInWithEmail(context, email, password);
    return ok;
  }

  Future<bool> registerWithEmail(
  BuildContext context,
  String email,
  String password,
  List<String> pilots, 
  String role,
) async {
  bool ok = await _authService.registerWithEmail(context, email, password, pilots, role);
  return ok;
}



  Future<void> signOut() async {
    await _authService.signOut();
    notifyListeners();
  }
}
