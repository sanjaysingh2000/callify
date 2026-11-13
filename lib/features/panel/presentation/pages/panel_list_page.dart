import 'package:flutter/material.dart';
import 'package:quick_call/core/widgets/app_loader.dart';
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
  bool _isCreatingPanel = false;

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
    if (_isCreatingPanel) return;
    final result = await CreatePanelDialog.show(context);
    if (result == null || !mounted) return;

    setState(() => _isCreatingPanel = true);
    try {
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
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Could not create the panel. Check your connection and try again.',
              ),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _isCreatingPanel = false);
    }
  }

  Future<void> _joinPanel(Panel panel) async {
    if (_controller.isRemoved(panel)) return;
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

  Future<void> _requestRejoin(Panel panel) async {
    try {
      await _controller.requestRejoin(panel);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rejoin request sent to the host.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send request: $error')),
        );
      }
    }
  }

  Future<void> _manageRemovedUsers(Panel panel) async {
    final userId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Removed users',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: panel.kickedUserIds.map((id) {
              final requested = panel.rejoinRequestUserIds.contains(id);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: requested
                    ? const Text(
                        'Requested to rejoin',
                        style: TextStyle(color: Color(0xFF67E8F9)),
                      )
                    : null,
                trailing: TextButton(
                  onPressed: () => Navigator.pop(dialogContext, id),
                  child: const Text('Unblock'),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (userId == null || !mounted) return;
    try {
      await _controller.unblockUser(panel, userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User unblocked for this panel.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not unblock user: $error')),
        );
      }
    }
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
          onPressed: _isCreatingPanel ? null : _createPanel,
          backgroundColor: const Color(0xFF0E7490),
          icon: _isCreatingPanel
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.add, color: Colors.white),
          label: Text(
            _isCreatingPanel ? 'Creating…' : 'Create Panel',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: Consumer<PanelListController>(
          builder: (context, controller, _) {
            if (controller.isLoading) {
              return const Center(child: AppLoader());
            }

            if (controller.errorMessage != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off_rounded,
                        color: Colors.white54,
                        size: 40,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        controller.errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: controller.retry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              );
            }

            if (controller.panels.isEmpty) {
              return _buildEmptyState();
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: controller.panels.length,
              itemBuilder: (_, i) {
                final panel = controller.panels[i];
                return _PanelCard(
                  panel: panel,
                  onTap: _joinPanel,
                  isRemoved: controller.isRemoved(panel),
                  isHost: controller.isHost(panel),
                  hasRequestedRejoin: controller.hasRequestedRejoin(panel),
                  onRequestRejoin: () => _requestRejoin(panel),
                  onManageRemoved: () => _manageRemovedUsers(panel),
                );
              },
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
  const _PanelCard({
    required this.panel,
    required this.onTap,
    required this.isRemoved,
    required this.isHost,
    required this.hasRequestedRejoin,
    required this.onRequestRejoin,
    required this.onManageRemoved,
  });

  final Panel panel;
  final void Function(Panel) onTap;
  final bool isRemoved;
  final bool isHost;
  final bool hasRequestedRejoin;
  final VoidCallback onRequestRejoin;
  final VoidCallback onManageRemoved;

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
          onTap: isRemoved ? null : () => onTap(panel),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: isRemoved
                  ? const Color(0xFF20282D)
                  : const Color(0xFF13272D),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isRemoved
                    ? Colors.white.withValues(alpha: 0.12)
                    : const Color(0xFF29444A),
              ),
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
                              color:
                                  (isRemoved
                                          ? const Color(0xFF8B3030)
                                          : const Color(0xFFB64040))
                                      .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isRemoved ? Icons.block : Icons.circle,
                                  color: isRemoved
                                      ? Color(0xFFFF8A8A)
                                      : Color(0xFFFF7272),
                                  size: 8,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  isRemoved ? 'REMOVED' : 'LIVE',
                                  style: TextStyle(
                                    color: isRemoved
                                        ? Color(0xFFFF9C9C)
                                        : Color(0xFFFF8585),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (isRemoved) ...[
                        const SizedBox(height: 3),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: hasRequestedRejoin
                                ? null
                                : onRequestRejoin,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: Icon(
                              hasRequestedRejoin
                                  ? Icons.hourglass_top_rounded
                                  : Icons.mark_email_unread_outlined,
                              size: 14,
                            ),
                            label: Text(
                              hasRequestedRejoin
                                  ? 'REQUEST SENT'
                                  : 'REQUEST TO REJOIN',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
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
                if (isHost && panel.kickedUserIds.isNotEmpty)
                  IconButton(
                    tooltip: 'Manage removed users',
                    onPressed: onManageRemoved,
                    icon: const Icon(Icons.manage_accounts_outlined),
                    color: const Color(0xFF67E8F9),
                  )
                else
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: isRemoved
                        ? Colors.red.shade200
                        : Colors.white.withValues(alpha: 0.4),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
