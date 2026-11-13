import 'dart:convert';
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/profile_image_compressor.dart';
import '../../data/user_profile_store.dart';

class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({super.key});

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  static const _background = Color(0xFF0D171A);
  static const _mint = Color(0xFF63DCC8);

  final _store = UserProfileStore();
  late Future<ProfileDetails> _profile;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _profile = _loadProfile();
  }

  Future<ProfileDetails> _loadProfile() {
    final user = FirebaseAuth.instance.currentUser;
    return user == null
        ? Future.error(StateError('You need to sign in to edit your profile.'))
        : _store.loadProfile(
            userId: user.uid,
            fallbackName:
                user.displayName ?? user.email?.split('@').first ?? '',
          );
  }

  void _retryProfileLoad() {
    setState(() => _profile = _loadProfile());
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_isBusy,
    child: Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _isBusy ? null : () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
        title: const Text(
          'Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: FutureBuilder<ProfileDetails>(
                  future: _profile,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.cloud_off_rounded,
                                color: Colors.white.withValues(alpha: .55),
                                size: 36,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Could not load your profile. Check your connection and try again.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .7),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextButton.icon(
                                onPressed: _retryProfileLoad,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Try again'),
                                style: TextButton.styleFrom(
                                  foregroundColor: _mint,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(color: _mint),
                      );
                    }
                    return _ProfileEditor(
                      initial: snapshot.data!,
                      store: _store,
                      onBusyChanged: (isBusy) {
                        if (mounted && _isBusy != isBusy) {
                          setState(() => _isBusy = isBusy);
                        }
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({
    required this.initial,
    required this.store,
    required this.onBusyChanged,
  });

  final ProfileDetails initial;
  final UserProfileStore store;
  final ValueChanged<bool> onBusyChanged;

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  static const _surface = Color(0xFF172629);
  static const _mint = Color(0xFF63DCC8);

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _ageController;
  String? _profileImageBase64;
  String? _gender;
  String? _busyMessage;

  bool get _isBusy => _busyMessage != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial.displayName);
    _ageController = TextEditingController(
      text: widget.initial.age?.toString() ?? '',
    );
    _profileImageBase64 = widget.initial.profileImageBase64;
    _gender = widget.initial.gender;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _isBusy) return;
    final saveStartedAt = DateTime.now();
    _setBusyMessage('Saving your profile…');
    ProfileDetails? updated;
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        throw StateError('Your session expired. Sign in again to continue.');
      }
      updated = await widget.store.updateProfile(
        userId: userId,
        current: widget.initial,
        displayName: _nameController.text,
        age: int.tryParse(_ageController.text.trim()),
        gender: _gender,
        profileImageBase64: _profileImageBase64,
      );
    } catch (error) {
      if (mounted) _showMessage(_saveErrorMessage(error));
    } finally {
      if (mounted) {
        final elapsed = DateTime.now().difference(saveStartedAt);
        const minimumLoadingTime = Duration(milliseconds: 350);
        final remaining = minimumLoadingTime - elapsed;
        if (!remaining.isNegative) await Future<void>.delayed(remaining);
        if (mounted) _setBusyMessage(null);
      }
    }
    if (updated != null && mounted) Navigator.of(context).pop(updated);
  }

  Future<void> _pickProfileImage() async {
    if (_isBusy) return;
    _setBusyMessage('Opening your photos…');
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;
      _setBusyMessage('Preparing your photo…');
      final compressed = await compute(
        ProfileImageCompressor.compressToBase64,
        await image.readAsBytes(),
      );
      if (mounted) setState(() => _profileImageBase64 = compressed);
    } catch (error) {
      if (mounted) _showMessage(_photoErrorMessage(error));
    } finally {
      if (mounted) _setBusyMessage(null);
    }
  }

  void _setBusyMessage(String? message) {
    setState(() => _busyMessage = message);
    widget.onBusyChanged(message != null);
  }

  String _saveErrorMessage(Object error) {
    if (error is StateError) return error.message.toString();
    if (error is TimeoutException) {
      return 'Saving took too long. Check your connection and try again.';
    }
    if (error is FirebaseException) {
      return 'Could not save your profile. Check your connection and try again.';
    }
    if (error is ArgumentError) {
      return error.message?.toString() ?? 'Invalid profile details.';
    }
    return 'Could not save your profile. Please try again.';
  }

  String _photoErrorMessage(Object error) {
    if (error is StateError || error is FormatException) {
      return error.toString();
    }
    if (error is PlatformException) {
      return 'Could not open your photos. Check app permissions and try again.';
    }
    return 'Could not load this photo. Please try another image.';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF24433F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  Widget _profileImage() {
    final encoded = _profileImageBase64;
    if (encoded == null || encoded.isEmpty) {
      return const Icon(Icons.person_rounded, color: _mint, size: 48);
    }
    try {
      return Image.memory(
        base64Decode(encoded),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.person_rounded, color: _mint, size: 48),
      );
    } on FormatException {
      return const Icon(Icons.person_rounded, color: _mint, size: 48);
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      AbsorbPointer(
        absorbing: _isBusy,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF183033),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _mint.withValues(alpha: .14)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: _mint, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'These details appear on your Live Panels profile.',
                          style: TextStyle(
                            color: Color(0xFFB5C6C5),
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .07),
                    ),
                  ),
                  child: Column(
                    children: [
                      ClipOval(
                        child: Container(
                          width: 104,
                          height: 104,
                          color: const Color(0xFF183033),
                          alignment: Alignment.center,
                          child: _profileImage(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: _isBusy ? null : _pickProfileImage,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(
                          _profileImageBase64 == null
                              ? 'Add profile photo'
                              : 'Change profile photo',
                        ),
                        style: TextButton.styleFrom(foregroundColor: _mint),
                      ),
                      Text(
                        'You can change your photo anytime. Save your profile to apply it.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .07),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'PERSONAL DETAILS',
                        style: TextStyle(
                          color: Color(0xFF9BAEB0),
                          fontSize: 10,
                          letterSpacing: 1.15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _fieldLabel('Name', widget.initial.displayNameChangeUsed),
                      const SizedBox(height: 7),
                      TextFormField(
                        controller: _nameController,
                        enabled: !widget.initial.displayNameChangeUsed,
                        maxLength: 32,
                        textCapitalization: TextCapitalization.words,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: _decoration(hint: 'Your name', counter: ''),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter your name'
                            : null,
                      ),
                      const SizedBox(height: 15),
                      _fieldLabel('Age', widget.initial.ageChangeUsed),
                      const SizedBox(height: 7),
                      TextFormField(
                        controller: _ageController,
                        enabled: !widget.initial.ageChangeUsed,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: _decoration(hint: 'Age', counter: ''),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty) return null;
                          final age = int.tryParse(text);
                          if (age == null || age < 1 || age > 120) {
                            return 'Enter an age from 1 to 120';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 15),
                      _fieldLabel('Gender', widget.initial.genderChangeUsed),
                      const SizedBox(height: 7),
                      DropdownButtonFormField<String>(
                        initialValue: _gender,
                        hint: const Text(
                          'Choose an option',
                          style: TextStyle(color: Color(0xFF718587)),
                        ),
                        dropdownColor: _surface,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: _decoration(hint: 'Choose an option'),
                        items: const [
                          DropdownMenuItem(
                            value: 'Female',
                            child: Text('Female'),
                          ),
                          DropdownMenuItem(value: 'Male', child: Text('Male')),
                          DropdownMenuItem(
                            value: 'Non-binary',
                            child: Text('Non-binary'),
                          ),
                          DropdownMenuItem(
                            value: 'Prefer not to say',
                            child: Text('Prefer not to say'),
                          ),
                        ],
                        onChanged: widget.initial.genderChangeUsed
                            ? null
                            : (value) => setState(() => _gender = value),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Name, age, and gender can each be changed once. Your photo can be changed anytime.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .5),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 48,
                        child: FilledButton(
                          onPressed: _isBusy ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: _mint,
                            foregroundColor: const Color(0xFF0D2725),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                          child: _busyMessage == 'Saving your profile…'
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF0D2725),
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'Saving…',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                )
                              : const Text(
                                  'Save profile',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      if (_isBusy)
        Positioned.fill(
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.48),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 280),
                margin: const EdgeInsets.all(28),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _mint.withValues(alpha: 0.24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        color: _mint,
                        strokeWidth: 3,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _busyMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_busyMessage == 'Saving your profile…') ...[
                      const SizedBox(height: 8),
                      Text(
                        'Please keep the app open.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _fieldLabel(String title, bool changeUsed) => Row(
    children: [
      Text(
        title,
        style: const TextStyle(
          color: Color(0xFFE2EBE9),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const Spacer(),
      Text(
        changeUsed ? 'LOCKED' : '1 CHANGE AVAILABLE',
        style: TextStyle(
          color: changeUsed ? const Color(0xFF718587) : _mint,
          fontSize: 9,
          letterSpacing: .5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );

  InputDecoration _decoration({required String hint, String? counter}) =>
      InputDecoration(
        hintText: hint,
        counterText: counter,
        hintStyle: const TextStyle(color: Color(0xFF718587)),
        helperStyle: const TextStyle(color: Color(0xFF718587), fontSize: 11),
        filled: true,
        fillColor: _surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: .06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _mint),
        ),
      );
}
