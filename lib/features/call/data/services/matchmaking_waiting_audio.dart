import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

abstract interface class MatchmakingWaitingAudio {
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}

class AssetMatchmakingWaitingAudio implements MatchmakingWaitingAudio {
  AssetMatchmakingWaitingAudio({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  static const String assetPath = 'audio/matchmaking_waiting.mp3';
  static const double volume = 0.24;

  final AudioPlayer _player;
  int _generation = 0;
  bool _startRequested = false;
  bool _isDisposed = false;
  bool _hasLoggedAssetError = false;

  @override
  Future<void> start() async {
    if (_isDisposed || _startRequested) return;
    _startRequested = true;
    final generation = ++_generation;

    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      if (!_isCurrent(generation)) return;

      await _player.play(AssetSource(assetPath), volume: volume);
    } catch (error) {
      if (!_hasLoggedAssetError) {
        _hasLoggedAssetError = true;
        debugPrint('[MatchmakingAudio] Could not play waiting music: $error');
      }
    }
  }

  @override
  Future<void> stop() async {
    ++_generation;
    if (!_startRequested || _isDisposed) return;
    _startRequested = false;
    try {
      await _player.stop();
    } catch (error) {
      debugPrint('[MatchmakingAudio] Could not stop waiting music: $error');
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    await stop();
    _isDisposed = true;
    await _player.dispose();
  }

  bool _isCurrent(int generation) =>
      !_isDisposed && _startRequested && generation == _generation;
}
