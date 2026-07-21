import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/router/app_router.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/user_repository.dart';
import '../widgets/common/app_avatar.dart';

/// Dedicated Search tab — find people by username and open their profile
/// (where the request / message actions live). Mirrors the Stitch Search screen
/// including its empty state.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _userRepo = UserRepository();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  String _query = '';
  List<UserModel> _results = [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value.trim());
    _debounce?.cancel();
    if (_query.length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), _runSearch);
  }

  Future<void> _runSearch() async {
    setState(() => _searching = true);
    try {
      final res = await _userRepo.search(_query);
      if (mounted) setState(() => _results = res);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            Icon(Icons.shield, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('CypherFy', style: AppTextStyles.subheading),
            const Spacer(),
            Text('SECURE',
                style: AppTextStyles.monoLabel
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                onChanged: _onQueryChanged,
                autofocus: true,
                textInputAction: TextInputAction.search,
                style: AppTextStyles.body,
                decoration: InputDecoration(
                  hintText: 'Search by username...',
                  prefixIcon:
                      Icon(Icons.search, color: AppColors.textSecondary),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            _onQueryChanged('');
                          },
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_query.isEmpty) return _emptyState();
    if (_searching && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      return Center(
        child: Text('No users found for "$_query"',
            style: AppTextStyles.bodySecondary),
      );
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, i) {
        final u = _results[i];
        return Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: AppColors.border, width: 0.5),
          ),
          child: ListTile(
            leading: AppAvatar(
              name: u.displayName,
              imageUrl: u.avatar,
              showOnlineDot: true,
              isOnline: u.isOnline,
            ),
            title: Text(u.displayName, style: AppTextStyles.body),
            subtitle: Text('@${u.username}',
                style: AppTextStyles.monoLabel
                    .copyWith(color: AppColors.textSecondary)),
            trailing:
                Icon(Icons.chevron_right, color: AppColors.textMuted),
            onTap: () => context.push('${Routes.profile}?userId=${u.id}'),
          ),
        );
      },
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search,
              size: 48, color: AppColors.surfaceContainerHighest),
          const SizedBox(height: 16),
          Text('Search for people', style: AppTextStyles.subheading),
          const SizedBox(height: 4),
          SizedBox(
            width: 250,
            child: Text(
              'Find users by their exact username to initiate a secure '
              'connection.',
              style: AppTextStyles.bodySecondary,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
