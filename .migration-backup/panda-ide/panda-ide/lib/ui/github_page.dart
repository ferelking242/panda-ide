import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:panda/bloc/repo_bloc/repo_bloc.dart';
import 'package:panda/bloc/ui_bloc/ui_bloc.dart';
import 'package:panda/ui/editor_page.dart';
import 'package:panda/utils/constants.dart';
import 'package:panda/utils/functions.dart';
import 'package:panda/utils/github_language_colors.dart';
import 'package:panda/utils/themes.dart';

class GithubPage extends StatefulWidget {
  /// When [embedded] is true the widget skips the outer Scaffold and renders
  /// only the body — suitable for embedding as an editor tab.
  final bool embedded;
  const GithubPage({super.key, this.embedded = false});

  @override
  State<GithubPage> createState() => _GithubPageState();
}

class _GithubPageState extends State<GithubPage> {
  bool _isSigningIn = false;
  String? _token;
  Map<String, dynamic>? _userInfo;
  List<dynamic> _repos = [];
  bool _isLoadingRepos = false;
  bool _isLoadingUser = false;
  String _selectedFilter = 'all';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadToken() async {
    final storage = const FlutterSecureStorage();
    final token = await storage.read(key: 'github_access_token');
    if (token != null && token.isNotEmpty) {
      setState(() => _token = token);
      await _loadUserInfo();
      await _loadRepos();
    }
  }

  Future<void> _loadUserInfo() async {
    if (_token == null) return;
    setState(() => _isLoadingUser = true);
    
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/user'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Accept': 'application/vnd.github.v3+json',
        },
      );
      
      if (response.statusCode == 200) {
        setState(() => _userInfo = jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('Failed to load user info: $e');
    } finally {
      setState(() => _isLoadingUser = false);
    }
  }

  Future<void> _loadRepos() async {
    if (_token == null) return;
    setState(() => _isLoadingRepos = true);
    
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/user/repos?per_page=100&sort=updated'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Accept': 'application/vnd.github.v3+json',
        },
      );
      
      if (response.statusCode == 200) {
        setState(() => _repos = jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('Failed to load repos: $e');
    } finally {
      setState(() => _isLoadingRepos = false);
    }
  }

  Future<void> _signOut() async {
    final storage = const FlutterSecureStorage();
    await storage.delete(key: 'github_access_token');
    await clearGitCredentials();
    if(mounted){
      context.read<GithubAuthCubit>().logout();
      setState(() {
        _token = null;
        _userInfo = null;
        _repos = [];
      });
    }
  }

  void _showErrorDialog(BuildContext context, String title, String message, AppTheme appTheme) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: appTheme.isDark ? const Color(0xff2b2b2b) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red[400], size: 28),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                color: appTheme.selectScreenCardTextColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.8),
            fontSize: 14,
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: appTheme.scaffoldBg,
              shape: RoundedRectangleBorder(borderRadius: .circular(10))
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _cloneRepository(BuildContext context, Map<String, dynamic> repo, AppTheme appTheme) async {
    String repoUrl = repo['clone_url'] as String;
    final repoName = repo['name'] as String;
    final progressController = StreamController<double>();
    
    if (repo['private'] == true && _token != null) {
      repoUrl = repoUrl.replaceFirst('https://', 'https://$_token@');
    }

    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: appTheme.isDark ? const Color(0xff2b2b2b) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: StreamBuilder<double>(
          stream: progressController.stream,
          initialData: 0.0,
          builder: (context, snapshot) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                FaIcon(
                  FontAwesomeIcons.github,
                  size: 48,
                  color: appTheme.selectScreenCardTextColor,
                ),
                const SizedBox(height: 20),
                Text(
                  'Cloning Repository',
                  style: TextStyle(
                    color: appTheme.selectScreenCardTextColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  repoName,
                  style: TextStyle(
                    color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: 200,
                  height: 8,
                  decoration: BoxDecoration(
                    color: appTheme.isDark 
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 200 * snapshot.data!.clamp(0.0, 1.0),
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xff238636),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${(snapshot.data! * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

    final targetDir = Directory("$projectDir/$repoName");
    
    if (targetDir.existsSync()) {
      navigator.pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Directory "$repoName" already exists'),
            backgroundColor: Colors.orange,
          ),
        );
        
        await Future.delayed(const Duration(milliseconds: 500));
        navigator.push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => 
              EditorPage(rootDir: targetDir.path, isCloned: true, languageDetails: null, isProject: true,),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return SizeTransition(sizeFactor: animation, child: child);
            },
          ),
        );
      }
      return;
    }

    try {
      await cloneRepo(projectDir, repoUrl, (progress) {
        progressController.add(progress);
      });
      
      progressController.add(1.0);
      navigator.pop();
      await Future.delayed(const Duration(milliseconds: 300));
      final clonedDir = Directory("$projectDir/$repoName");
      debugPrint('Navigating to folder: ${clonedDir.path}');
      debugPrint('Directory exists: ${clonedDir.existsSync()}');
      
      await navigator.push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => 
            EditorPage(rootDir: clonedDir.path, isCloned: true, languageDetails: null, isProject: true),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SizeTransition(sizeFactor: animation, child: child);
          },
        ),
      );
    } catch (e) {
      debugPrint('Clone error: $e');
      navigator.pop();
      if (context.mounted) {
        _showErrorDialog(context, 'Clone Failed', e.toString(), appTheme);
      }
    } finally {
      await progressController.close();
    }
  }

  List<dynamic> get _filteredRepos {
    var filtered = _repos;
    
    if (_selectedFilter == 'public') {
      filtered = filtered.where((r) => r['private'] == false).toList();
    } else if (_selectedFilter == 'private') {
      filtered = filtered.where((r) => r['private'] == true).toList();
    } else if (_selectedFilter == 'forks') {
      filtered = filtered.where((r) => r['fork'] == true).toList();
    }
    
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((r) {
        final name = (r['name'] as String).toLowerCase();
        final desc = (r['description'] as String?)?.toLowerCase() ?? '';
        return name.contains(_searchQuery.toLowerCase()) ||  desc.contains(_searchQuery.toLowerCase());
      }).toList();
    }
    
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = context.read<AppThemeBloc>().state.appTheme;
    
    final body = _token == null
        ? _buildSignInPage(appTheme)
        : _buildClientPage(appTheme);

    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: appTheme.isDark ? const Color(0xff1a1a1a) : const Color(0xfff5f5f5),
      body: body,
    );
  }

  Widget _buildSignInPage(AppTheme appTheme) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 450),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: appTheme.isDark 
                    ? [const Color(0xff2d2d2d), const Color(0xff1a1a1a)]
                    : [Colors.white, const Color(0xfff0f0f0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: appTheme.isDark 
                      ? Colors.black.withValues(alpha: 0.4)
                      : Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child: FaIcon(
                  FontAwesomeIcons.github,
                  size: 64,
                  color: appTheme.isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
            
            const SizedBox(height: 48),
            
            Text(
              "Connect to GitHub",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: appTheme.selectScreenCardTextColor,
                letterSpacing: -0.5,
              ),
            ),
            
            const SizedBox(height: 16),
            
            Text(
              "Sign in with GitHub to unlock powerful features",
              style: TextStyle(
                fontSize: 16,
                color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.7),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 40),
            
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: appTheme.isDark 
                  ? const Color(0xff242424)
                  : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: appTheme.isDark 
                      ? Colors.black.withValues(alpha: 0.3)
                      : Colors.black.withValues(alpha: 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildFeatureItem(
                    icon: Icons.cloud_sync_rounded,
                    title: "Repository Management",
                    description: "Clone, push, and pull repositories",
                    appTheme: appTheme,
                  ),
                  const SizedBox(height: 20),
                  _buildFeatureItem(
                    icon: Icons.merge_type_rounded,
                    title: "Version Control",
                    description: "Commit changes and manage branches",
                    appTheme: appTheme,
                  ),
                  const SizedBox(height: 20),
                  _buildFeatureItem(
                    icon: Icons.people_rounded,
                    title: "Collaboration",
                    description: "Work seamlessly with your team",
                    appTheme: appTheme,
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 48),
            
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isSigningIn ? null : () async {
                  setState(() => _isSigningIn = true);
                  try {
                    final result = await gitHubSignIn();
                    if (result == "success") {
                      await _loadToken();
                      if(mounted){
                        context.read<GithubAuthCubit>().refresh();
                      }
                    } else {
                      if (mounted) {
                        _showErrorDialog(context, 'Sign In Failed', result, appTheme);
                      }
                    }
                  } finally {
                    if (mounted) {
                      setState(() => _isSigningIn = false);
                    }
                  }
                },
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.disabled)) {
                      return Colors.grey;
                    }
                    return const Color(0xff238636);
                  }),
                  foregroundColor: const WidgetStatePropertyAll(Colors.white),
                  elevation: const WidgetStatePropertyAll(0),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  overlayColor: WidgetStatePropertyAll(
                    Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: _isSigningIn
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FaIcon(FontAwesomeIcons.github, size: 22),
                        SizedBox(width: 12),
                        Text(
                          "Sign in with GitHub",
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 8),
                Text(
                  "Your credentials are securely stored",
                  style: TextStyle(
                    fontSize: 13,
                    color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClientPage(AppTheme appTheme) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _buildProfileHeader(appTheme),
        ),
        
        SliverToBoxAdapter(
          child: _buildSearchAndFilters(appTheme),
        ),
        
        if (_isLoadingRepos) const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
        else if (_filteredRepos.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.folder_off_outlined,
                    size: 64,
                    color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No repositories found',
                    style: TextStyle(
                      color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.6),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildRepoCard(_filteredRepos[index], appTheme),
                childCount: _filteredRepos.length,
              ),
            ),
          ),
        
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _buildProfileHeader(AppTheme appTheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 13),
      child: Container(
        padding: const EdgeInsets.all(20),
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: appTheme.isDark
              ? [const Color(0xff2d2d2d), const Color(0xff242424)]
              : [Colors.white, const Color(0xfff8f8f8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: appTheme.isDark 
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: _isLoadingUser
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                // Avatar
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xff238636),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xff238636).withValues(alpha: 0.3),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: _userInfo?['avatar_url'] != null
                      ? Image.network(
                          _userInfo!['avatar_url'],
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.person,
                            size: 40,
                            color: appTheme.selectScreenCardTextColor,
                          ),
                        )
                      : Icon(
                          Icons.person,
                          size: 40,
                          color: appTheme.selectScreenCardTextColor,
                        ),
                  ),
                ),
                
                const SizedBox(width: 16),
                
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _userInfo?['name'] ?? _userInfo?['login'] ?? 'GitHub User',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: appTheme.selectScreenCardTextColor,
                        ),
                      ),
                      if (_userInfo?['login'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '@${_userInfo!['login']}',
                          style: TextStyle(
                            fontSize: 14,
                            color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildStatBadge(
                            icon: Icons.book_outlined,
                            label: '${_userInfo?['public_repos'] ?? 0}',
                            tooltip: 'Public repos',
                            appTheme: appTheme,
                          ),
                          const SizedBox(width: 12),
                          _buildStatBadge(
                            icon: Icons.people_outline,
                            label: '${_userInfo?['followers'] ?? 0}',
                            tooltip: 'Followers',
                            appTheme: appTheme,
                          ),
                          const SizedBox(width: 12),
                          _buildStatBadge(
                            icon: Icons.person_add_outlined,
                            label: '${_userInfo?['following'] ?? 0}',
                            tooltip: 'Following',
                            appTheme: appTheme,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                IconButton(
                  onPressed: () => _showSignOutDialog(appTheme),
                  icon: Icon(
                    Icons.logout_rounded,
                    color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.6),
                  ),
                  tooltip: 'Sign out',
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildStatBadge({
    required IconData icon,
    required String label,
    required String tooltip,
    required AppTheme appTheme,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: appTheme.isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.7)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters(AppTheme appTheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: appTheme.isDark
                ? const Color(0xff242424)
                : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: appTheme.isDark
                    ? Colors.black.withValues(alpha: 0.2)
                    : Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              style: TextStyle(color: appTheme.selectScreenCardTextColor),
              decoration: InputDecoration(
                hintText: 'Search repositories...',
                hintStyle: TextStyle(
                  color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.5),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.5),
                ),
                suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.clear,
                        color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.5),
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All', 'all', appTheme),
                const SizedBox(width: 8),
                _buildFilterChip('Public', 'public', appTheme),
                const SizedBox(width: 8),
                _buildFilterChip('Private', 'private', appTheme),
                const SizedBox(width: 8),
                _buildFilterChip('Forks', 'forks', appTheme),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: Icon(
                    Icons.refresh,
                    size: 18,
                    color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.7),
                  ),
                  label: Text(
                    'Refresh',
                    style: TextStyle(
                      color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.7),
                    ),
                  ),
                  backgroundColor: appTheme.isDark
                    ? const Color(0xff242424)
                    : Colors.white,
                  side: BorderSide(
                    color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.2),
                  ),
                  onPressed: _loadRepos,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          Text(
            '${_filteredRepos.length} repositories',
            style: TextStyle(
              fontSize: 13,
              color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.6),
            ),
          ),
          
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String filter, AppTheme appTheme) {
    final isSelected = _selectedFilter == filter;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedFilter = filter),
      backgroundColor: appTheme.isDark
        ? const Color(0xff242424)
        : Colors.white,
      selectedColor: const Color(0xff238636).withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: isSelected 
          ? const Color(0xff238636)
          : appTheme.selectScreenCardTextColor.withValues(alpha: 0.7),
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      side: BorderSide(
        color: isSelected 
          ? const Color(0xff238636)
          : appTheme.selectScreenCardTextColor.withValues(alpha: 0.2),
      ),
      checkmarkColor: const Color(0xff238636),
    );
  }

  Future<int?> _getSubscribers(String owner, String repo) async {
    final response = await http.get(
      Uri.parse('https://api.github.com/repos/$owner/$repo'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Accept': 'application/vnd.github.v3+json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['subscribers_count'];
    }

    return null;
  }

  Widget _buildRepoCard(Map<String, dynamic> repo, AppTheme appTheme) {
    final isPrivate = repo['private'] == true;
    final isFork = repo['fork'] == true;
    final language = repo['language'] as String?;
    final description = repo['description'] as String?;
    final starCount = repo['stargazers_count'] ?? 0;
    final forkCount = repo['forks_count'] ?? 0;
    final updatedAt = DateTime.tryParse(repo['updated_at'] ?? '');
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: appTheme.isDark
          ? const Color(0xff242424)
          : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: appTheme.isDark
              ? Colors.black.withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showRepoDetails(repo, appTheme),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    isFork ?  FaIcon(
                      FontAwesomeIcons.codeFork,
                      size: 16,
                      color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.7),
                    ): Icon(
                      Icons.book_outlined,
                        size: 20,
                        color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        repo['name'] ?? 'Unknown',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xff58a6ff),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isPrivate)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Text(
                          'Private',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
                
                if (description != null && description.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.7),
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                
                const SizedBox(height: 14),
                
                Row(
                  children: [
                    if (language != null) ...[
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _getLanguageColor(language),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        language,
                        style: TextStyle(
                          fontSize: 12,
                          color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                    Icon(
                      Icons.star_border,
                      size: 16,
                      color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$starCount',
                      style: TextStyle(
                        fontSize: 12,
                        color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(width: 16),
                    FaIcon(
                      FontAwesomeIcons.codeFork,
                      size: 11,
                      color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$forkCount',
                      style: TextStyle(
                        fontSize: 12,
                        color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.7),
                      ),
                    ),
                    const Spacer(),
                    if (updatedAt != null)
                      Text(
                        _formatDate(updatedAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.5),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showRepoDetails(Map<String, dynamic> repo, AppTheme appTheme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: appTheme.isDark ? const Color(0xff1a1a1a) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            Row(
              children: [
                Icon(
                  repo['fork'] == true ? Icons.fork_right : Icons.book_outlined,
                  size: 28,
                  color: const Color(0xff58a6ff),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        repo['full_name'] ?? repo['name'] ?? 'Unknown',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: appTheme.selectScreenCardTextColor,
                        ),
                      ),
                      if (repo['private'] == true)
                        const Text(
                          'Private repository',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            
            if (repo['description'] != null) ...[
              const SizedBox(height: 16),
              Text(
                repo['description'],
                style: TextStyle(
                  fontSize: 14,
                  color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.8),
                  height: 1.5,
                ),
              ),
            ],
            
            const SizedBox(height: 24),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildDetailStat(Icons.star_border, '${repo['stargazers_count'] ?? 0}', 'Stars', appTheme),
                _buildDetailStat(FontAwesomeIcons.codeFork, '${repo['forks_count'] ?? 0}', 'Forks', appTheme),
                FutureBuilder<int?>(
                  future: _getSubscribers(repo['owner']['login'] ?? '', repo['name'] ?? ''),
                  builder:(context, subSnapshot) {
                    if(subSnapshot.connectionState == .waiting) {
                      return const SizedBox(
                        width: 25,
                        height: 25,
                        child: CircularProgressIndicator()
                      );
                    }
                    if(subSnapshot.hasData) {
                      return _buildDetailStat(Icons.remove_red_eye_outlined, '${subSnapshot.data}', 'Watchers', appTheme);
                    } else if(subSnapshot.hasError || subSnapshot.data == null) {
                      return _buildDetailStat(Icons.remove_red_eye_outlined, '0', 'Watchers', appTheme);
                    }
                    return _buildDetailStat(Icons.remove_red_eye_outlined, '0', 'Watchers', appTheme);
                  },
                ),
                if (repo['open_issues_count'] != null) _buildDetailStat(Icons.adjust, '${repo['open_issues_count']}', 'Issues', appTheme),
              ],
            ),
            
            const SizedBox(height: 24),
            
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _cloneRepository(context, repo, appTheme);
                },
                icon: const Icon(Icons.download_rounded),
                label: const Text(
                  'Clone Repository',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff238636),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 12),
            
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () async{
                  await launchUrl(Uri.parse(repo['html_url'] as String));
                  if(context.mounted){
                    Navigator.pop(context);
                  }
                },
                icon: FaIcon(
                  FontAwesomeIcons.github,
                  size: 18,
                  color: appTheme.selectScreenCardTextColor,
                ),
                label: Text(
                  'View on GitHub',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: appTheme.selectScreenCardTextColor,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.3),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailStat(dynamic icon, String value, String label, AppTheme appTheme) {
    return Column(
      children: [
        if(icon is IconData) Icon(
          icon,
          size: 24,
          color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.7)
        )
        else if(icon is FaIconData) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: FaIcon(
            icon,
            size: 19,
            color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.7)
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: appTheme.selectScreenCardTextColor,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  void _showSignOutDialog(AppTheme appTheme) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: appTheme.isDark ? const Color(0xff2b2b2b) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Sign Out',
          style: TextStyle(color: appTheme.selectScreenCardTextColor),
        ),
        content: Text(
          'Are you sure you want to sign out of GitHub?',
          style: TextStyle(color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.7)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _signOut();
            },
            child: const Text(
              'Sign Out',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Color _getLanguageColor(String language) {
    return githubLanguageColors[language] ?? Colors.grey;
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else if (diff.inDays < 30) {
      return '${(diff.inDays / 7).floor()}w ago';
    } else if (diff.inDays < 365) {
      return '${(diff.inDays / 30).floor()}mo ago';
    }
    return '${(diff.inDays / 365).floor()}y ago';
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
    required AppTheme appTheme,
  }) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xff238636).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: const Color(0xff238636),
            size: 24,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: appTheme.selectScreenCardTextColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: appTheme.selectScreenCardTextColor.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}