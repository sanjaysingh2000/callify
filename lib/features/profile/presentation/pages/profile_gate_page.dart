import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:quick_call/core/widgets/app_loader.dart';

import '../../../home/presentation/pages/home_page.dart';
import '../../data/google_auth_service.dart';
import '../../data/user_profile_store.dart';

class ProfileGatePage extends StatefulWidget {
  const ProfileGatePage({super.key, this.profileStore, this.authService});

  // Kept injectable so profile persistence can be isolated in app previews.
  final UserProfileStore? profileStore;
  final GoogleAuthService? authService;

  @override
  State<ProfileGatePage> createState() => _ProfileGatePageState();
}

class _ProfileGatePageState extends State<ProfileGatePage> {
  late final GoogleAuthService _authService;
  late final UserProfileStore _profileStore;
  late final Stream<User?> _authChanges;
  final Map<String, Future<String>> _profiles = {};
  bool _signingIn = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? GoogleAuthService();
    _profileStore = widget.profileStore ?? UserProfileStore();
    _authChanges = _authService.authStateChanges;
  }

  Future<void> _signIn() async {
    if (_signingIn) return;
    setState(() {
      _signingIn = true;
      _errorMessage = null;
    });
    try {
      await _authService.signInWithGoogle();
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = _friendlyAuthError(error));
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _errorMessage = error is StateError
              ? error.message
              : 'Google sign-in could not be completed. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  String _friendlyAuthError(FirebaseAuthException error) =>
      switch (error.code) {
        'account-exists-with-different-credential' =>
          'This email is already linked to another sign-in method.',
        'network-request-failed' => 'Check your connection and try again.',
        'popup-closed-by-user' ||
        'web-context-canceled' => 'Sign-in was canceled.',
        _ => 'Google sign-in could not be completed. Please try again.',
      };

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: _authChanges,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const _LoadingPage();
      }
      final user = snapshot.data;
      if (user == null) {
        return _SignInPage(
          isLoading: _signingIn,
          errorMessage: _errorMessage,
          onSignIn: _signIn,
        );
      }

      final profile = _profiles.putIfAbsent(
        user.uid,
        () => _profileStore.saveAuthenticatedUser(user),
      );
      return FutureBuilder<String>(
        future: profile,
        builder: (context, profileSnapshot) {
          if (profileSnapshot.hasError) {
            final fallback = user.displayName?.trim().isNotEmpty == true
                ? user.displayName!.trim()
                : user.email?.split('@').first ?? 'Callify user';
            return HomePage(displayName: fallback);
          }
          if (!profileSnapshot.hasData) return const _LoadingPage();
          return HomePage(displayName: profileSnapshot.data!);
        },
      );
    },
  );
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0D171A),
      body: Center(child: AppLoader()),
    );
  }
}

class _SignInPage extends StatelessWidget {
  const _SignInPage({
    required this.isLoading,
    required this.errorMessage,
    required this.onSignIn,
  });

  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0D171A),
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF14272A), Color(0xFF0D171A), Color(0xFF18242B)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF48D6C2), Color(0xFF0E8B86)],
                        ),
                      ),
                      child: const Icon(
                        Icons.graphic_eq_rounded,
                        color: Color(0xFF082321),
                        size: 40,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Meet someone new.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Sign in to start a conversation and keep in touch with friends.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF9BAEB0),
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      onPressed: isLoading ? null : onSignIn,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF202124),
                        disabledBackgroundColor: Colors.white.withValues(
                          alpha: .8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 21,
                              height: 21,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF0E8B86),
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'G',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF4285F4),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Continue with Google',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFFF9B8F),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
