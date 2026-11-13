import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/services/panel_notification_sender.dart';
import '../../../../core/utils/device_id_store.dart';
import '../../data/datasources/panel_data_source.dart';
import '../../domain/entities/panel.dart';

/// Manages the list of live panels and panel creation.
class PanelListController extends ChangeNotifier {
  PanelListController({
    PanelDataSource? panelDataSource,
    DeviceIdStore? deviceIdStore,
  }) : _dataSource = panelDataSource ?? PanelDataSource(),
       _deviceIdStore = deviceIdStore ?? DeviceIdStore() {
    unawaited(_startListening());
  }

  final PanelDataSource _dataSource;
  final DeviceIdStore _deviceIdStore;

  // Firestore se aayi poori list (expired bhi)
  List<Panel> _allPanels = [];

  List<Panel> _panels = [];
  List<Panel> get panels => _panels;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? _currentUserId;

  bool isRemoved(Panel panel) =>
      _currentUserId != null && panel.kickedUserIds.contains(_currentUserId);

  bool isHost(Panel panel) =>
      _currentUserId != null && panel.hostId == _currentUserId;

  bool hasRequestedRejoin(Panel panel) =>
      _currentUserId != null &&
      panel.rejoinRequestUserIds.contains(_currentUserId);

  Future<void> requestRejoin(Panel panel) async {
    if (!isRemoved(panel) || hasRequestedRejoin(panel)) return;
    await _dataSource.requestRejoin(panel.id, _currentUserId!);
  }

  Future<void> unblockUser(Panel panel, String userId) async {
    if (!isHost(panel) || !panel.kickedUserIds.contains(userId)) return;
    await _dataSource.unblockUser(panel.id, userId, hostId: _currentUserId!);
  }

  StreamSubscription? _panelsSub;
  bool _isDisposed = false;

  bool _isExpired(Panel p, DateTime now) {
    final end = p.createdAt.add(Duration(minutes: p.durationMinutes));
    return !end.isAfter(now);
  }

  bool _applyFilter() {
    final now = DateTime.now();
    final filtered = _allPanels.where((p) => !_isExpired(p, now)).toList();
    final changed = filtered.length != _panels.length;
    _panels = filtered;
    return changed;
  }

  Future<void> _startListening() async {
    try {
      _currentUserId = await _deviceIdStore.getOrCreateDeviceId();
      if (_isDisposed) return;
    } catch (e) {
      debugPrint('[PanelListController] Could not load device ID: $e');
      if (_isDisposed) return;
      _errorMessage = 'Could not load live panels. Check your connection.';
      _isLoading = false;
      notifyListeners();
      return;
    }

    await _panelsSub?.cancel();
    _panelsSub = _dataSource.livePanelsStream().listen(
      (panels) {
        if (_isDisposed) return;
        _allPanels = panels;
        _applyFilter();
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
      },
      onError: (e) {
        debugPrint('[PanelListController] Stream error: $e');
        if (_isDisposed) return;
        _errorMessage = 'Could not load live panels. Check your connection.';
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<void> retry() async {
    if (_isDisposed || _isLoading) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    await _startListening();
  }

  // void _startListening() {
  //   _panelsSub = _dataSource.livePanelsStream().listen(
  //     (panels) {
  //       _panels = panels;
  //       _isLoading = false;
  //       notifyListeners();
  //     },
  //     onError: (e) {
  //       debugPrint('[PanelListController] Stream error: $e');
  //       _isLoading = false;
  //       notifyListeners();
  //     },
  //   );
  // }

  /// Creates a new panel and returns its ID.
  Future<String> createPanel(String title, String displayName) async {
    final userId = await _deviceIdStore.getOrCreateDeviceId();
    final panelId = await _dataSource.createPanel(title, userId, displayName);
    // Fire-and-forget notification to all users.
    PanelNotificationSender.notifyNewPanel(
      title: title,
      hostName: displayName,
      hostId: userId,
      panelId: panelId,
    );
    return panelId;
  }

  /// Gets the current user's device ID.
  Future<String> getUserId() => _deviceIdStore.getOrCreateDeviceId();

  @override
  void dispose() {
    _isDisposed = true;
    _panelsSub?.cancel();
    super.dispose();
  }
}
