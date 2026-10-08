import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/utils/device_id_store.dart';
import '../../data/datasources/panel_data_source.dart';
import '../../domain/entities/panel.dart';

/// Manages the list of live panels and panel creation.
class PanelListController extends ChangeNotifier {
  PanelListController({
    PanelDataSource? panelDataSource,
    DeviceIdStore? deviceIdStore,
  })  : _dataSource = panelDataSource ?? PanelDataSource(),
        _deviceIdStore = deviceIdStore ?? DeviceIdStore() {
    _startListening();
  }

  final PanelDataSource _dataSource;
  final DeviceIdStore _deviceIdStore;

  // Firestore se aayi poori list (expired bhi)
  List<Panel> _allPanels = [];

  List<Panel> _panels = [];
  List<Panel> get panels => _panels;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  StreamSubscription? _panelsSub;

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


  void _startListening() {
    _panelsSub = _dataSource.livePanelsStream().listen(
      (panels) {
        _allPanels = panels;
        _applyFilter();
        _isLoading = false;
        notifyListeners();
      },
      onError: (e) {
        debugPrint('[PanelListController] Stream error: $e');
        _isLoading = false;
        notifyListeners();
      },
    );
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
    return _dataSource.createPanel(title, userId, displayName);
  }

  /// Gets the current user's device ID.
  Future<String> getUserId() => _deviceIdStore.getOrCreateDeviceId();

  @override
  void dispose() {
    _panelsSub?.cancel();
    super.dispose();
  }
}
