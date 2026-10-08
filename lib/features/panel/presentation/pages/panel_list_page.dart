import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/panel.dart';
import '../controllers/panel_list_controller.dart';
import '../widgets/create_panel_dialog.dart';
import 'panel_room_page.dart';

class PanelListPage extends StatefulWidget {
  const PanelListPage({super.key, required this.displayName});

  final String displayName;

  @override
  State<PanelListPage> createState() => _PanelListPageState();
}

class _PanelListPageState extends State<PanelListPage> {
  late final PanelListController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PanelListController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _createPanel() async {
    final result = await CreatePanelDialog.show(context);
    if (result == null || !mounted) return;

    final panelId = await _controller.createPanel(result, widget.displayName);
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PanelRoomPage(
          panelId: panelId,
          displayName: widget.displayName,
          isHost: true,
        ),
      ),
    );
  }

  Future<void> _joinPanel(Panel panel) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PanelRoomPage(
          panelId: panel.id,
          displayName: widget.displayName,
          isHost: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A1628),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70),
          ),
          title: const Text(
            'Live Panels',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          centerTitle: true,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _createPanel,
          backgroundColor: const Color(0xFF0E7490),
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text(
            'Create Panel',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
        body: Consumer<PanelListController>(
          builder: (context, controller, _) {
            if (controller.isLoading) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF06B6D4)),
              );
            }

            if (controller.panels.isEmpty) {
              return _buildEmptyState();
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: controller.panels.length,
              itemBuilder: (_, i) =>
                  _PanelCard(panel: controller.panels[i], onTap: _joinPanel),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.spatial_audio_off,
            size: 72,
            color: Colors.white.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 16),
          Text(
            'No live panels yet',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create one and start talking!',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Panel Card
// =============================================================================

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.panel, required this.onTap});

  final Panel panel;
  final void Function(Panel) onTap;

  @override
  Widget build(BuildContext context) {
    final durationLabel = panel.durationMinutes % 60 == 0
        ? '${panel.durationMinutes ~/ 60}h'
        : '${panel.durationMinutes}m';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onTap(panel),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFF13272D),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF29444A)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E8B86).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.graphic_eq_rounded,
                    color: Color(0xFF4ADBC4),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              panel.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFF3F6F2),
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFB64040,
                              ).withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.circle,
                                  color: Color(0xFFFF7272),
                                  size: 6,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'LIVE',
                                  style: TextStyle(
                                    color: Color(0xFFFF8585),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'by ${panel.hostDisplayName.isEmpty ? 'Panel host' : panel.hostDisplayName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Icon(
                            Icons.people_alt_outlined,
                            size: 13,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${panel.participantCount} members',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.35),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.schedule_rounded,
                            size: 13,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$durationLabel limit',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
