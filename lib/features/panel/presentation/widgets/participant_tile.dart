import 'package:flutter/material.dart';

import '../../domain/entities/panel_participant.dart';

/// Displays a single participant with avatar, name, role badge, and mic status.
class ParticipantTile extends StatelessWidget {
  const ParticipantTile({
    super.key,
    required this.participant,
    this.onTap,
    this.compact = false,
  });

  final PanelParticipant participant;
  final VoidCallback? onTap;
  final bool compact;

  Color _roleColor(PanelRole role) {
    switch (role) {
      case PanelRole.host:
        return const Color(0xFF06B6D4);
      case PanelRole.coHost:
        return const Color(0xFF8B5CF6);
      case PanelRole.speaker:
        return const Color(0xFF10B981);
      case PanelRole.audience:
        return Colors.grey;
    }
  }

  String _roleLabel(PanelRole role) {
    switch (role) {
      case PanelRole.host:
        return 'HOST';
      case PanelRole.coHost:
        return 'CO-HOST';
      case PanelRole.speaker:
        return 'SPEAKER';
      case PanelRole.audience:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _roleColor(participant.role);
    final label = _roleLabel(participant.role);
    final size = compact ? 48.0 : 64.0;
    final fontSize = compact ? 10.0 : 12.0;
    final avatarFontSize = compact ? 18.0 : 22.0;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: compact ? 70 : 85,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar with mic indicator.
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withValues(alpha: 0.7),
                        color.withValues(alpha: 0.3),
                      ],
                    ),
                    border: Border.all(
                      color: color.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      participant.displayName.isNotEmpty
                          ? participant.displayName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: avatarFontSize,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                // Mic indicator (only for speakers).
                if (participant.canSpeak)
                  Container(
                    width: compact ? 18 : 22,
                    height: compact ? 18 : 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: participant.isMuted
                          ? Colors.red.shade600
                          : const Color(0xFF10B981),
                      border: Border.all(
                        color: const Color(0xFF0A1628),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      participant.isMuted ? Icons.mic_off : Icons.mic,
                      size: compact ? 10 : 12,
                      color: Colors.white,
                    ),
                  ),
                // Mic request indicator (for audience who requested).
                if (participant.role == PanelRole.audience &&
                    participant.micRequested)
                  Container(
                    width: compact ? 18 : 22,
                    height: compact ? 18 : 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.amber.shade700,
                      border: Border.all(
                        color: const Color(0xFF0A1628),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.front_hand,
                      size: compact ? 10 : 12,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 6),

            // Name.
            Text(
              participant.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
              ),
            ),

            // Role badge.
            if (label.isNotEmpty) ...[
              const SizedBox(height: 2),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
