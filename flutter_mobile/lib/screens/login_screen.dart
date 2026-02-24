import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  String _statusText = 'AWAITING AUTHENTICATION';

  // The Native Google Sign-In instance (does not require external browser + localhost loop)
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: '901086875987-462a9467nqo682h4cqne48e1mmgrt5qm.apps.googleusercontent.com',
    clientId: '901086875987-462a9467nqo682h4cqne48e1mmgrt5qm.apps.googleusercontent.com',
  );

  Future<void> _handleSignIn() async {
    setState(() {
      _isLoading = true;
      _statusText = 'CONTACTING GOOGLE OAUTH...';
    });

    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      
      if (account != null) {
        final GoogleSignInAuthentication auth = await account.authentication;
        final String? idToken = auth.idToken;

        if (idToken != null) {
          // In a real app, send ID token to backend to get the DriveNet JWT back.
          // For scaffolding, we accept the token.
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('drivenet_jwt', idToken);
          await prefs.setString('drivenet_user', account.email);

          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const DashboardScreen()),
            );
          }
        }
      } else {
        setState(() {
          _statusText = 'AUTH CANCELLED';
          _isLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _statusText = 'ERROR: $error';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_sync, color: Color(0xFFFF4655), size: 80),
              const SizedBox(height: 20),
              const Text(
                'DRIVENET MOBILE',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'NATIVE FLUTTER CLIENT',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                  letterSpacing: 3.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 60),
              Text(
                _statusText,
                style: const TextStyle(
                  color: Color(0xFFFF4655), 
                  fontFamily: 'Courier', 
                  fontSize: 12, 
                  fontWeight: FontWeight.bold
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF4655)))
                    : ElevatedButton(
                        onPressed: _handleSignIn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF4655),
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text(
                          'SIGN IN OAUTH2',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2.0),
                        ),
                      ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
