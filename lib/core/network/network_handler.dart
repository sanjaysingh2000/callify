import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quick_call/core/widgets/app_loader.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

class NetworkHandler extends StatefulWidget {
  const NetworkHandler({required this.child, super.key});

  final Widget child;

  @override
  State<NetworkHandler> createState() => _NetworkHandlerState();
}

class _NetworkHandlerState extends State<NetworkHandler>
    with WidgetsBindingObserver {
  final InternetConnection _connection = InternetConnection();
  StreamSubscription<InternetStatus>? _subscription;
  bool _isConnected = true;
  bool _isChecking = false;
  int _statusRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenForStatusChanges();
    unawaited(_checkConnection());
  }

  void _listenForStatusChanges() {
    _subscription = _connection.onStatusChange.listen(
      (status) => _setConnectionStatus(status == InternetStatus.connected),
      onError: (Object error) {
        debugPrint('Internet status monitoring failed: $error');
        _setConnectionStatus(false);
      },
    );
  }

  void _setConnectionStatus(bool connected) {
    if (!mounted || connected == _isConnected) return;
    _statusRevision++;
    setState(() => _isConnected = connected);
  }

  Future<void> _checkConnection() async {
    final revision = _statusRevision;
    if (mounted) setState(() => _isChecking = true);

    bool connected;
    try {
      connected = await _connection.hasInternetAccess;
    } catch (error) {
      debugPrint('Internet reachability check failed: $error');
      connected = false;
    }

    if (!mounted) return;
    setState(() {
      _isChecking = false;
      if (revision == _statusRevision && connected != _isConnected) {
        _statusRevision++;
        _isConnected = connected;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkConnection());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_isConnected)
          Positioned.fill(
            child: _NoInternetScreen(
              isChecking: _isChecking,
              onRetry: _checkConnection,
            ),
          ),
      ],
    );
  }
}

class _NoInternetScreen extends StatelessWidget {
  const _NoInternetScreen({required this.isChecking, required this.onRetry});

  final bool isChecking;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D171A),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4ADBC4).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    color: Color(0xFF4ADBC4),
                    size: 44,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'No internet connection',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFF3F6F2),
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Check your Wi-Fi or mobile data. We’ll reconnect automatically when internet is available.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 26),
                FilledButton.icon(
                  onPressed: isChecking ? null : onRetry,
                  icon: isChecking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: AppLoader(size: 18),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: Text(isChecking ? 'Checking...' : 'Try again'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0E8B86),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
