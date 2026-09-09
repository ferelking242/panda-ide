import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/agent_settings_service.dart';

const _pandaBg = Color(0xff1e1e1e);
const _pandaPanel = Color(0xff252526);
const _pandaPanelRaised = Color(0xff2a2a2b);
const _pandaBorder = Color(0xff363638);
const _pandaMuted = Color(0xffa6a6aa);
const _pandaBlue = Color(0xff1683f7);
const _pandaGreen = Color(0xff65d98a);

enum PandaWorkspaceToolPage { files, skills, secrets }

class PandaFilesPage extends StatefulWidget {
  const PandaFilesPage({super.key, this.workspacePath = ''});

  final String workspacePath;

  @override
  State<PandaFilesPage> createState() => _PandaFilesPageState();
}

class _PandaFilesPageState extends State<PandaFilesPage> {
  final _searchController = TextEditingController();
  List<FileSystemEntity> _entries = const [];
  bool _showHidden = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    final path = widget.workspacePath.trim();
    List<FileSystemEntity> entries = [];
    if (path.isNotEmpty) {
      try {
        final directory = Directory(path);
        if (await directory.exists()) {
          entries = await directory.list(followLinks: false).toList();
        }
      } catch (_) {}
    }
    entries = entries
        .where((entry) =>
            _showHidden || !entry.uri.pathSegments.last.startsWith('.'))
        .toList()
      ..sort((a, b) {
        final aDir = a is Directory ? 0 : 1;
        final bDir = b is Directory ? 0 : 1;
        return aDir == bDir
            ? a.path.toLowerCase().compareTo(b.path.toLowerCase())
            : aDir.compareTo(bDir);
      });
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  List<FileSystemEntity> get _visibleEntries {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _entries;
    return _entries
        .where((entry) =>
            _displayName(entry).toLowerCase().contains(query))
        .toList();
  }

  String _displayName(FileSystemEntity entry) {
    final segments = entry.uri.pathSegments;
    return segments.isEmpty ? entry.path : segments.last.replaceAll('/', '');
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 12)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _createEntry({required bool folder}) async {
    if (widget.workspacePath.trim().isEmpty) {
      _notice(folder
          ? 'Ouvrez un workspace pour créer un dossier.'
          : 'Ouvrez un workspace pour créer un fichier.');
      return;
    }
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(folder ? 'New folder' : 'New file'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: folder ? 'Folder name' : 'File name',
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    try {
      final target = '${widget.workspacePath}${Platform.pathSeparator}$name';
      if (folder) {
        await Directory(target).create(recursive: false);
      } else {
        await File(target).create(recursive: false);
      }
      await _loadEntries();
      _notice('${folder ? 'Folder' : 'File'} created.');
    } catch (error) {
      _notice('Unable to create entry: $error');
    }
  }

  Future<void> _rename(FileSystemEntity entry) async {
    final controller = TextEditingController(text: _displayName(entry));
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || name == _displayName(entry)) return;
    try {
      final target =
          '${Directory(entry.path).parent.path}${Platform.pathSeparator}$name';
      await entry.rename(target);
      await _loadEntries();
    } catch (error) {
      _notice('Unable to rename entry: $error');
    }
  }

  Future<void> _delete(FileSystemEntity entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${_displayName(entry)}?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await entry.delete(recursive: entry is Directory);
      await _loadEntries();
    } catch (error) {
      _notice('Unable to delete entry: $error');
    }
  }

  void _copy(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    _notice(message);
  }

  PopupMenuButton<String> _entryMenu(FileSystemEntity entry) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20, color: _pandaMuted),
      color: _pandaPanelRaised,
      onSelected: (value) async {
        switch (value) {
          case 'rename':
            await _rename(entry);
            break;
          case 'new-file':
            await _createEntry(folder: false);
            break;
          case 'new-folder':
            await _createEntry(folder: true);
            break;
          case 'path':
            _copy(entry.path, 'File path copied.');
            break;
          case 'link':
            _copy(entry.uri.toString(), 'File link copied.');
            break;
          case 'delete':
            await _delete(entry);
            break;
          case 'shell':
          case 'download':
            _notice(value == 'shell'
                ? 'Open shell is available from the workspace terminal.'
                : 'Folder download queued.');
            break;
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'rename', child: Text('Rename')),
        PopupMenuItem(
          value: 'new-file',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.note_add_outlined, size: 18),
            title: Text('Add file'),
          ),
        ),
        PopupMenuItem(
          value: 'new-folder',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.create_new_folder_outlined, size: 18),
            title: Text('Add folder'),
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'shell',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.terminal, size: 18),
            title: Text('Open shell here'),
          ),
        ),
        PopupMenuItem(
          value: 'path',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.copy_outlined, size: 18),
            title: Text('Copy file path'),
          ),
        ),
        PopupMenuItem(
          value: 'link',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.link, size: 18),
            title: Text('Copy link'),
          ),
        ),
        PopupMenuItem(
          value: 'download',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.download_outlined, size: 18),
            title: Text('Download folder'),
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
            title: Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _visibleEntries;
    return Container(
      color: _pandaBg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: _PandaSearchField(
                    controller: _searchController,
                    hintText: 'Search files and code',
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: _pandaMuted),
                  color: _pandaPanelRaised,
                  onSelected: (value) async {
                    switch (value) {
                      case 'file':
                        await _createEntry(folder: false);
                        break;
                      case 'folder':
                        await _createEntry(folder: true);
                        break;
                      case 'upload':
                        _notice('File picker opened.');
                        break;
                      case 'zip':
                        _notice('Workspace download queued.');
                        break;
                      case 'hidden':
                        setState(() => _showHidden = !_showHidden);
                        await _loadEntries();
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'file',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.note_add_outlined, size: 18),
                        title: Text('New file'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'folder',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.create_new_folder_outlined, size: 18),
                        title: Text('New folder'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'upload',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.upload_file, size: 18),
                        title: Text('Upload files'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'zip',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.download_outlined, size: 18),
                        title: Text('Download as zip'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'hidden',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          _showHidden
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                        ),
                        title: Text(_showHidden
                            ? 'Hide hidden files'
                            : 'Show hidden files'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? const Center(
                    child: Text(
                      'No files found',
                      style: TextStyle(color: _pandaMuted, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: entries.length,
                    itemBuilder: (_, index) {
                      final entry = entries[index];
                      final isDirectory = entry is Directory;
                      return InkWell(
                        onTap: () => _notice(isDirectory
                            ? 'Folder selected: ${_displayName(entry)}'
                            : 'File selected: ${_displayName(entry)}'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isDirectory
                                    ? Icons.folder_outlined
                                    : Icons.insert_drive_file_outlined,
                                color: isDirectory
                                    ? _pandaMuted
                                    : Colors.blue[300],
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _displayName(entry),
                                  style: TextStyle(
                                    color: isDirectory
                                        ? _pandaGreen
                                        : Colors.white,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              _entryMenu(entry),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class PandaAgentSkillsPage extends StatefulWidget {
  const PandaAgentSkillsPage({super.key});

  @override
  State<PandaAgentSkillsPage> createState() => _PandaAgentSkillsPageState();
}

class _PandaAgentSkillsPageState extends State<PandaAgentSkillsPage> {
  final _searchController = TextEditingController();
  String _query = '';
  String _tab = 'Project';
  List<String> _installed = [];

  static const _communitySkills = [
    (
      name: 'Find Skills',
      repo: 'vercel-labs/skills',
      installs: '19.3K installs',
      description:
          'Helps users discover and install agent skills when they ask questions like “how do I do X”, “find a skill for X”, or “is there a skill that can…”',
    ),
    (
      name: 'Vercel React Best Practices',
      repo: 'vercel-labs/agent-skills',
      installs: '13.1K installs',
      description:
          'React composition patterns that scale. Use when refactoring components, working with boolean prop proliferation, building flexible component libraries, or reviewing React code.',
    ),
    (
      name: 'Web Design Guidelines',
      repo: 'vercel-labs/agent-skills',
      installs: '18.5K installs',
      description:
          'Review UI code for Web Interface Guidelines compliance. Use when asked to review my UI, check accessibility, audit design, or review UX.',
    ),
    (
      name: 'Remotion Best Practices',
      repo: 'remotion-dev/skills',
      installs: '10.3K installs',
      description: 'Best practices for Remotion - Video creation in React',
    ),
    (
      name: 'Frontend Design',
      repo: 'anthropics/skills',
      installs: '22.3K installs',
      description:
          'Create distinctive, production-grade frontend interfaces with high design quality.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadInstalled();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInstalled() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('panda_agent_skills_json');
    if (!mounted) return;
    final installed = stored == null ? <String>[] : await AgentSettingsService.getSkills();
    if (!mounted) return;
    setState(() => _installed = installed);
  }

  Future<void> _install(String name) async {
    final next = {..._installed, name}.toList();
    await AgentSettingsService.setSkills(next);
    if (!mounted) return;
    setState(() => _installed = next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name installed.', style: const TextStyle(fontSize: 12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<({String name, String repo, String installs, String description})>
      get _filteredCommunity {
    final query = _query.trim().toLowerCase();
    return _communitySkills
        .where((skill) =>
            query.isEmpty ||
            skill.name.toLowerCase().contains(query) ||
            skill.description.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isCommunity = _tab == 'Community';
    return Container(
      color: _pandaBg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          const Text(
            'Agent skills',
            style: TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Skills extend what Agent can do. Manage installed skills here.',
            style: TextStyle(color: _pandaMuted, fontSize: 13),
          ),
          const SizedBox(height: 7),
          GestureDetector(
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Skills are reusable instructions for Panda Agent.'),
              ),
            ),
            child: const Text(
              'Learn more about skills',
              style: TextStyle(color: _pandaBlue, fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final tab in const ['Project', 'Workspace', 'Community'])
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _tab = tab),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            tab == 'Community'
                                ? Icons.language_outlined
                                : tab == 'Workspace'
                                    ? Icons.account_tree_outlined
                                    : Icons.folder_outlined,
                            size: 16,
                            color: _tab == tab ? Colors.white : _pandaMuted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            tab,
                            style: TextStyle(
                              color: _tab == tab ? Colors.white : _pandaMuted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Container(height: 1, color: _pandaBorder),
          if (isCommunity) ...[
            const SizedBox(height: 16),
            const Text(
              'Discover skills',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              'Find skills to add to your Agent.',
              style: TextStyle(color: _pandaMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _PandaSearchField(
              controller: _searchController,
              hintText: 'Search skills...',
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 10),
            for (final skill in _filteredCommunity)
              _CommunitySkillCard(
                skill: skill,
                installed: _installed.contains(skill.name),
                onInstall: () => _install(skill.name),
              ),
          ] else if (_installed.isEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _pandaPanel,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _pandaBorder),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No skills installed yet',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Skills are reusable instructions that teach Agent how to perform specific tasks. Ask Agent to create a skill from a chat.',
                    style: TextStyle(
                      color: _pandaMuted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 14),
            for (final name in _installed)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.extension_outlined, color: _pandaBlue),
                title: Text(name, style: const TextStyle(color: Colors.white)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: _pandaMuted),
                  onPressed: () async {
                    final next = _installed.where((item) => item != name).toList();
                    await AgentSettingsService.setSkills(next);
                    if (mounted) setState(() => _installed = next);
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CommunitySkillCard extends StatelessWidget {
  const _CommunitySkillCard({
    required this.skill,
    required this.installed,
    required this.onInstall,
  });

  final ({
    String name,
    String repo,
    String installs,
    String description
  }) skill;
  final bool installed;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 11, 8, 10),
      decoration: BoxDecoration(
        color: _pandaPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _pandaBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  skill.name,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
              TextButton.icon(
                onPressed: installed ? null : onInstall,
                icon: const Icon(Icons.download_outlined, size: 14),
                label: Text(installed ? 'Installed' : 'Install'),
                style: TextButton.styleFrom(
                  foregroundColor: installed ? _pandaMuted : Colors.white,
                  backgroundColor: _pandaPanelRaised,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${skill.repo} • ${skill.installs}',
            style: const TextStyle(color: _pandaMuted, fontSize: 11),
          ),
          const SizedBox(height: 8),
          Text(
            skill.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _pandaMuted,
              fontSize: 11,
              height: 1.35,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_down, color: _pandaMuted),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(skill.name),
                  content: Text(skill.description),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PandaSecretsPage extends StatefulWidget {
  const PandaSecretsPage({super.key});

  @override
  State<PandaSecretsPage> createState() => _PandaSecretsPageState();
}

class _PandaSecretsPageState extends State<PandaSecretsPage> {
  final _searchController = TextEditingController();
  Map<String, String> _secrets = {};
  String _query = '';
  String? _openMenu;

  @override
  void initState() {
    super.initState();
    _loadSecrets();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSecrets() async {
    final saved = await AgentSettingsService.getSecrets();
    final env = <String, String>{};
    for (final key in Platform.environment.keys) {
      final normalized = key.toUpperCase();
      if (normalized.contains('TOKEN') ||
          normalized.contains('KEY') ||
          normalized.contains('SECRET') ||
          normalized.contains('PAT') ||
          normalized.contains('GITHUB')) {
        env[key] = '';
      }
    }
    if (!mounted) return;
    setState(() => _secrets = {...env, ...saved});
  }

  Future<void> _save() => AgentSettingsService.setSecrets(_secrets);

  List<String> get _visibleNames {
    final query = _query.trim().toLowerCase();
    return _secrets.keys
        .where((name) => query.isEmpty || name.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _newSecret({String? existingName}) async {
    final nameController = TextEditingController(text: existingName);
    final valueController = TextEditingController(
      text: existingName == null ? '' : (_secrets[existingName] ?? ''),
    );
    final result = await showDialog<({String name, String value})>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existingName == null ? 'New Secret' : 'Edit Secret'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              enabled: existingName == null,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: valueController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Value'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              (
                name: nameController.text.trim(),
                value: valueController.text,
              ),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    nameController.dispose();
    valueController.dispose();
    if (result == null || result.name.isEmpty || result.value.isEmpty) return;
    setState(() {
      if (existingName != null && existingName != result.name) {
        _secrets.remove(existingName);
      }
      _secrets[result.name] = result.value;
    });
    await _save();
  }

  Future<void> _deleteSecret(String name) async {
    setState(() => _secrets.remove(name));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final names = _visibleNames;
    return Container(
      color: _pandaBg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Secrets',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.link, color: _pandaMuted, size: 20),
                onPressed: () => _notice(context, 'Secret link copied.'),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: _pandaMuted),
                color: _pandaPanelRaised,
                onSelected: (value) {
                  if (value == 'add') _newSecret();
                  if (value == 'refresh') _loadSecrets();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'add', child: Text('New Secret')),
                  PopupMenuItem(value: 'refresh', child: Text('Refresh')),
                ],
              ),
              FilledButton.icon(
                onPressed: () => _newSecret(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Secret'),
                style: FilledButton.styleFrom(
                  backgroundColor: _pandaBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 34),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xff17304b),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: const Color(0xff2e5b82)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.white, size: 17),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Secrets are accessible to anyone who has access to this App. To restrict secret access, you must update App invite permissions.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _PandaSearchField(
            controller: _searchController,
            hintText: 'Filter Secrets by name',
            onChanged: (value) => setState(() => _query = value),
            suffixIcon: Icons.search,
          ),
          const SizedBox(height: 8),
          if (names.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No secrets configured',
                  style: TextStyle(color: _pandaMuted, fontSize: 13),
                ),
              ),
            ),
          for (final name in names) _secretRow(name),
          const SizedBox(height: 24),
          const Text(
            'Configurations',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Configurations are similar to secrets, but should only be used for non-sensitive information.',
            style: TextStyle(color: _pandaMuted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _secretRow(String name) {
    final isOpen = _openMenu == name;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: _pandaPanel,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.all(9),
            child: Icon(Icons.copy_outlined, color: _pandaMuted, size: 17),
          ),
          Expanded(
            child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
          const Text(
            '••••••••',
            style: TextStyle(color: _pandaMuted, letterSpacing: 1),
          ),
          IconButton(
            icon: const Icon(Icons.visibility_outlined, color: _pandaMuted, size: 18),
            onPressed: () => _notice(context, 'Secret values stay hidden.'),
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              color: isOpen ? Colors.white : _pandaMuted,
              size: 20,
            ),
            color: _pandaPanelRaised,
            onOpened: () => setState(() => _openMenu = name),
            onCanceled: () => setState(() => _openMenu = null),
            onSelected: (value) async {
              setState(() => _openMenu = null);
              switch (value) {
                case 'edit':
                  await _newSecret(existingName: name);
                  break;
                case 'usage':
                  _notice(context, 'No usages found for $name.');
                  break;
                case 'delete':
                  await _deleteSecret(name);
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined, size: 18),
                  title: Text('Edit'),
                ),
              ),
              PopupMenuItem(
                value: 'usage',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.search, size: 18),
                  title: Text('Find Usages'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                  title: Text('Delete', style: TextStyle(color: Colors.redAccent)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _notice(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _PandaSearchField extends StatelessWidget {
  const _PandaSearchField({
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final IconData? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: _pandaMuted, fontSize: 12),
        suffixIcon: Icon(suffixIcon ?? Icons.search, color: _pandaMuted, size: 19),
        filled: true,
        fillColor: _pandaPanel,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _pandaBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _pandaBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _pandaBlue),
        ),
      ),
    );
  }
}