import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/router/app_router.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/user_repository.dart';
import '../../providers/pending_requests_provider.dart';
import '../../widgets/common/app_avatar.dart';
import '../../widgets/common/app_text_field.dart';

/// Contacts + chat-request management: search users, send requests, and
/// accept/reject incoming ones.
class ContactsScreen extends ConsumerStatefulWidget {
  /// Tab to open on: 0 Friends, 1 Search, 2 Requests (e.g. from a push tap).
  final int initialTab;
  const ContactsScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen>
    with SingleTickerProviderStateMixin {
  final _repo = UserRepository();
  final _searchCtrl = TextEditingController();
  late final TabController _tabs;

  List<UserModel> _contacts = [];
  List<UserModel> _results = [];
  List<dynamic> _incoming = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final contacts = await _repo.getContacts();
      final requests = await _repo.getChatRequests();
      final incoming = requests['incoming'] as List? ?? [];
      setState(() {
        _contacts = contacts;
        _incoming = incoming;
      });
      // Keep the global Profile-tab badge in sync.
      ref.read(pendingRequestsProvider.notifier).set(incoming.length);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    final res = await _repo.search(q.trim());
    setState(() => _results = res);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.friends),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            const Tab(text: 'Friends'),
            const Tab(text: 'Search'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Requests'),
                  if (_incoming.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _incoming.length > 9 ? '9+' : '${_incoming.length}',
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _buildContacts(),
                _buildSearch(),
                _buildRequests(),
              ],
            ),
    );
  }

  Widget _buildContacts() {
    if (_contacts.isEmpty) {
      return Center(
          child: Text('No friends yet', style: AppTextStyles.bodySecondary));
    }
    return ListView(
      children: _contacts
          .map((u) => ListTile(
                leading: AppAvatar(
                  name: u.displayName,
                  imageUrl: u.avatar,
                  showOnlineDot: true,
                  isOnline: u.isOnline,
                ),
                title: Text(u.displayName, style: AppTextStyles.body),
                subtitle: Text('@${u.username}',
                    style: AppTextStyles.bodySecondary),
              ))
          .toList(),
    );
  }

  Widget _buildSearch() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: AppTextField(
            label: 'Find people',
            hint: 'Search username',
            controller: _searchCtrl,
            onChanged: _search,
          ),
        ),
        Expanded(
          child: ListView(
            children: _results
                .map((u) => ListTile(
                      leading:
                          AppAvatar(name: u.displayName, imageUrl: u.avatar),
                      title: Text(u.displayName, style: AppTextStyles.body),
                      subtitle: Text('@${u.username}',
                          style: AppTextStyles.bodySecondary),
                      trailing: Icon(Icons.chevron_right,
                          color: AppColors.textMuted),
                      // Open their profile — request/chat actions live there.
                      onTap: () =>
                          context.push('${Routes.profile}?userId=${u.id}'),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildRequests() {
    if (_incoming.isEmpty) {
      return Center(
          child:
              Text('No pending requests', style: AppTextStyles.bodySecondary));
    }
    return ListView(
      children: _incoming.map((req) {
        final from = req['from'] as Map<String, dynamic>;
        final username = from['username'] as String?;
        return ListTile(
          leading: AppAvatar(
            name: from['displayName'] as String? ?? '?',
            imageUrl: from['avatar'] as String?,
          ),
          title: Text(from['displayName'] as String? ?? '?',
              style: AppTextStyles.body),
          subtitle: Text(username != null ? '@$username' : 'wants to chat',
              style: AppTextStyles.bodySecondary),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RequestAction(
                label: AppStrings.reject,
                onPressed: () => _reject(req['_id'].toString()),
              ),
              const SizedBox(width: 8),
              _RequestAction(
                label: AppStrings.accept,
                primary: true,
                onPressed: () => _accept(req['_id'].toString(), from),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Future<void> _accept(String requestId, Map<String, dynamic> from) async {
    try {
      // Server creates the DM room; both sides derive the key from its id.
      final roomId = await _repo.acceptChatRequest(requestId);
      if (!mounted) return;
      context.push(
        Routes.chat,
        extra: ChatArgs(
          isEphemeral: false,
          roomId: roomId,
          title: from['displayName'] as String? ?? 'Chat',
          otherUserId: from['_id']?.toString(),
          avatarUrl: from['avatar'] as String?,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not accept: $e')),
        );
      }
    }
    await _load();
  }

  Future<void> _reject(String requestId) async {
    await _repo.rejectChatRequest(requestId);
    await _load();
  }
}

/// Compact Accept (filled) / Decline (outlined error) pill for a request row.
class _RequestAction extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onPressed;

  const _RequestAction({
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? AppColors.primary : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: primary
            ? BorderSide.none
            : BorderSide(color: AppColors.error, width: 0.5),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: AppTextStyles.label.copyWith(
              color: primary ? AppColors.onPrimary : AppColors.error,
            ),
          ),
        ),
      ),
    );
  }
}
