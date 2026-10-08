import 'package:flutter/material.dart';

import '../../../home/presentation/pages/home_page.dart';
import '../../data/user_profile_store.dart';


class ProfileGatePage extends StatefulWidget {
  const ProfileGatePage({super.key, this.profileStore});

  final UserProfileStore? profileStore;

  @override
  State<ProfileGatePage> createState() => _ProfileGatePageState();
}

class _ProfileGatePageState extends State<ProfileGatePage> {
  late final UserProfileStore _profileStore;
  late Future<String?> _displayName;

  @override
  void initState() {
    super.initState();
    _profileStore = widget.profileStore ?? UserProfileStore();
    _displayName = _profileStore.loadDisplayName();
  }

  void _onNameSaved(String displayName) {
    final normalizedName = displayName.trim();
    if (normalizedName.isEmpty) return;

    setState(() => _displayName = Future.value(normalizedName));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _displayName,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingPage();
        }

        final displayName = snapshot.data?.trim();
        if (displayName != null && displayName.isNotEmpty) {
          return HomePage(displayName: displayName);
        }

        if (snapshot.hasError) {
          return _FirstNamePage(
            profileStore: _profileStore,
            onNameSaved: _onNameSaved,
          );
        }

        return _FirstNamePage(
          profileStore: _profileStore,
          onNameSaved: _onNameSaved,
        );
      },
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0A1628),
      body: Center(child: CircularProgressIndicator(color: Color(0xFF06B6D4))),
    );
  }
}

class _FirstNamePage extends StatefulWidget {
  const _FirstNamePage({required this.profileStore, required this.onNameSaved});

  final UserProfileStore profileStore;
  final ValueChanged<String> onNameSaved;

  @override
  State<_FirstNamePage> createState() => _FirstNamePageState();
}

class _FirstNamePageState extends State<_FirstNamePage> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;

    final trimmedInput = _nameController.text.trim();
    if (trimmedInput.isEmpty) {
      setState(() {
        _errorMessage = 'Enter your name';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final displayName = await widget.profileStore.saveDisplayName(trimmedInput);
      if (!mounted) return;
      widget.onNameSaved(displayName);
    } on ArgumentError {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Enter your name';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Could not save your name. Check your connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.record_voice_over,
                    color: Color(0xFF06B6D4),
                    size: 64,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'What should people call you?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You only need to do this once.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60),
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _nameController,
                    autofocus: true,
                    maxLength: 32,
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _save(),
                    decoration: const InputDecoration(
                      hintText: 'Your name',
                      counterText: '',
                      filled: true,
                      fillColor: Color(0xFF1E293B),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter your name'
                        : null,
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    child: Text(_isSaving ? 'Saving...' : 'Continue'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
