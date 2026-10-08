import 'package:flutter/material.dart';
import 'package:quick_call/features/ai_calling/screen/call_screen.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../call/data/datasources/last_call_store.dart';
import '../../../call/presentation/pages/call_page.dart';
import '../../../ludo/presentation/pages/ludo_list_page.dart';
import '../../../panel/presentation/pages/panel_list_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.displayName});

  final String displayName;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<LastCall?> _lastCall;

  @override
  void initState() {
    super.initState();
    _lastCall = LastCallStore().load();
  }

  Future<void> _startPractice(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CallPage()));
    if (mounted) {
      setState(() => _lastCall = LastCallStore().load());
    }
  }

  void _openPanels(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PanelListPage(displayName: widget.displayName),
      ),
    );
  }

  void _openLudo(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LudoListPage(displayName: widget.displayName),
      ),
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$feature is coming soon'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF183D42),
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          child: LayoutBuilder(
            builder: (context, constraints) => Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildBrandHeader(),
                      const SizedBox(height: 18),
                      Text(
                        'Welcome back',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFF3F6F2),
                          fontSize: 30,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildPracticeAction(context),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Text(
                            'MORE SPACES',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.46),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildSpaceAction(
                        icon: Icons.spatial_audio_rounded,
                        title: 'Explore Live Panels',
                        category: 'COMMUNITY',
                        color: const Color(0xFF4ADBC4),
                        onTap: () => _openPanels(context),
                      ),
                      const SizedBox(height: 8),
                      _buildSpaceAction(
                        icon: Icons.casino_rounded,
                        title: 'Play Ludo with Voice',
                        category: 'TABLE GAMES',
                        color: const Color(0xFFFF9B72),
                        onTap: () => _showComingSoon(context, 'Play Ludo with Voice'),
                        // _openLudo(context),
                      ),
                      const SizedBox(height: 8),
                      _buildSpaceAction(
                        icon: Icons.auto_awesome_rounded,
                        title: 'Talk with AI',
                        category: 'AI PARTNER',
                        color: const Color(0xFFF2C14E),
                        onTap: () =>Navigator.push(context, MaterialPageRoute(builder: (context) => AiCallScreen(),))
                        //  _showComingSoon(context, 'Talk with AI'),
                      ),
                      const SizedBox(height: 8),
                      _buildSpaceAction(
                        icon: Icons.people_alt_rounded,
                        title: 'Friend List',
                        category: 'YOUR PEOPLE',
                        color: const Color(0xFF79A8FF),
                        onTap: () => _showComingSoon(context, 'Friend List'),
                      ),
                      FutureBuilder<LastCall?>(
                        future: _lastCall,
                        builder: (context, snapshot) {
                          final lastCall = snapshot.data;
                          if (lastCall == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: _buildSpaceAction(
                              icon: Icons.replay_rounded,
                              title: 'Reconnect to last user',
                              category: 'BOTH USERS TAP RECONNECT',
                              color: const Color(0xFF61D6A8),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CallPage(lastCall: lastCall),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandHeader() {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF48D6C2), Color(0xFF0E8B86)],
            ),
          ),
          child: const Icon(
            Icons.graphic_eq_rounded,
            color: Color(0xFF082321),
            size: 28,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          AppConstants.appName,
          style: const TextStyle(
            color: Color(0xFFF3F6F2),
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildPracticeAction(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _startPractice(context),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 92,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0E7490), Color(0xFF0E8B86)],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x3323D5C2),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.call_rounded,
                  color: Colors.white,
                  size: 27,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Start Practice',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 23,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpaceAction({
    required IconData icon,
    required String title,
    required String category,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF172529),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 23),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFF3F6F2),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      category,
                      style: TextStyle(
                        color: color.withValues(alpha: 0.9),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white.withValues(alpha: 0.42),
                size: 15,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
