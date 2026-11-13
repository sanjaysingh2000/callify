import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:quick_call/features/ai_calling/screen/call_screen.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../call/presentation/pages/call_page.dart';
import '../../../panel/presentation/pages/panel_list_page.dart';
import '../../../friends/presentation/friends_page.dart';
import '../../../friends/data/friend_data_source.dart';
import '../../../../core/utils/device_id_store.dart';
import '../../../profile/data/google_auth_service.dart';
import '../../../profile/data/user_profile_store.dart';
import '../../../profile/presentation/pages/profile_settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.displayName});

  final String displayName;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  late String _displayName;
  late Future<String> _userId;
  String? _friendRequestsUserId;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _friendRequestsStream;
  bool _friendRequestsStreamResolved = false;
  bool _entranceStarted = false;

  @override
  void initState() {
    super.initState();
    _displayName = widget.displayName;
    _userId = DeviceIdStore().getOrCreateDeviceId();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _entranceController.value = 1;
      _entranceStarted = true;
    } else if (!_entranceStarted) {
      _entranceStarted = true;
      _entranceController.forward();
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  void _startPractice(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const CallPage()));

  void _openPanels(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PanelListPage(displayName: _displayName),
      ),
    );
  }

  Future<void> _editProfile() async {
    final updated = await Navigator.of(context).push<ProfileDetails>(
      MaterialPageRoute<ProfileDetails>(
        builder: (_) => const ProfileSettingsPage(),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _displayName = updated.displayName);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Profile saved.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
    }
  }

  void _openAiCall(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.push<void>(
      MaterialPageRoute<void>(builder: (_) => const AiCallScreen()),
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
                      _buildEntrance(
                        start: 0,
                        end: 0.52,
                        child: _buildBrandHeader(),
                      ),
                      const SizedBox(height: 18),
                      _buildEntrance(
                        start: 0.08,
                        end: 0.62,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                              _displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFF3F6F2),
                                fontSize: 30,
                                height: 1.1,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildEntrance(
                        start: 0.16,
                        end: 0.7,
                        child: _buildPracticeAction(context),
                      ),
                      const SizedBox(height: 22),
                      _buildEntrance(
                        start: 0.24,
                        end: 0.76,
                        child: Row(
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
                      ),
                      const SizedBox(height: 10),
                      _buildEntrance(
                        start: 0.32,
                        end: 0.84,
                        child: _buildSpaceAction(
                          icon: Icons.spatial_audio_rounded,
                          title: 'Explore Live Panels',
                          category: 'COMMUNITY',
                          color: const Color(0xFF4ADBC4),
                          onTap: () => _openPanels(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildEntrance(
                        start: 0.4,
                        end: 0.92,
                        child: _buildSpaceAction(
                          icon: Icons.auto_awesome_rounded,
                          title: 'Talk with AI',
                          category: 'AI PARTNER',
                          color: const Color(0xFFF2C14E),
                          onTap: () => _openAiCall(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildEntrance(
                        start: 0.48,
                        end: 1,
                        child: FutureBuilder<String>(
                          future: _userId,
                          builder: (context, userSnapshot) {
                            final userId = userSnapshot.data;
                            if (userId == null) {
                              return _friendListAction(context, 0);
                            }
                            final requestsStream = _incomingFriendRequests(
                              userId,
                            );
                            if (requestsStream == null) {
                              return _friendListAction(context, 0);
                            }
                            return StreamBuilder<
                              QuerySnapshot<Map<String, dynamic>>
                            >(
                              stream: requestsStream,
                              builder: (context, requestsSnapshot) =>
                                  _friendListAction(
                                    context,
                                    requestsSnapshot.data?.docs.length ?? 0,
                                  ),
                            );
                          },
                        ),
                      ),
                      // FutureBuilder<LastCall?>(
                      //   future: _lastCall,
                      //   builder: (context, snapshot) {
                      //     final lastCall = snapshot.data;
                      //     if (lastCall == null) return const SizedBox.shrink();
                      //     return Padding(
                      //       padding: const EdgeInsets.only(top: 8),
                      //       child: _buildSpaceAction(
                      //         icon: Icons.replay_rounded,
                      //         title: 'Reconnect to last user',
                      //         category: 'BOTH USERS TAP RECONNECT',
                      //         color: const Color(0xFF61D6A8),
                      //         onTap: () => Navigator.of(context).push(
                      //           MaterialPageRoute(
                      //             builder: (_) => CallPage(lastCall: lastCall),
                      //           ),
                      //         ),
                      //       ),
                      //     );
                      //   },
                      // ),
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

  Widget _buildEntrance({
    required double start,
    required double end,
    required Widget child,
  }) {
    final animation = _entranceController.drive(
      CurveTween(curve: Interval(start, end, curve: Curves.easeOutCubic)),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  Widget _friendListAction(
    BuildContext context,
    int pendingCount,
  ) => _buildSpaceAction(
    icon: Icons.people_alt_rounded,
    title: pendingCount == 0
        ? 'Friend List'
        : 'Friend List ($pendingCount request${pendingCount == 1 ? '' : 's'})',
    category: 'YOUR PEOPLE',
    color: const Color(0xFF79A8FF),
    onTap: () => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FriendsPage())),
  );

  Stream<QuerySnapshot<Map<String, dynamic>>>? _incomingFriendRequests(
    String userId,
  ) {
    if (_friendRequestsStreamResolved && _friendRequestsUserId == userId) {
      return _friendRequestsStream;
    }
    _friendRequestsUserId = userId;
    _friendRequestsStreamResolved = true;
    try {
      _friendRequestsStream = FriendDataSource().incomingRequests(userId);
    } catch (error) {
      // Firebase may not be initialized in previews or offline startup.
      debugPrint('[HomePage] Friend requests are unavailable: $error');
      _friendRequestsStream = null;
    }
    return _friendRequestsStream;
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
        const Spacer(),
        PopupMenuButton<String>(
          tooltip: 'Account',
          color: const Color(0xFF172629),
          icon: const Icon(
            Icons.account_circle_outlined,
            color: Color(0xFFB5C6C5),
            size: 27,
          ),
          onSelected: (value) {
            if (value == 'profile') _editProfile();
            if (value == 'sign_out') _signOut();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'profile',
              child: Row(
                children: [
                  Icon(
                    Icons.person_outline_rounded,
                    size: 18,
                    color: Color(0xFF63DCC8),
                  ),
                  SizedBox(width: 10),
                  Text('Profile', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'sign_out',
              child: Row(
                children: [
                  Icon(
                    Icons.logout_rounded,
                    size: 18,
                    color: Color(0xFFB5C6C5),
                  ),
                  SizedBox(width: 10),
                  Text('Sign out', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _signOut() async {
    try {
      await GoogleAuthService().signOut();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not sign out. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
