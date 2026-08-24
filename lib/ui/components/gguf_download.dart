import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:code_forge/code_forge.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_json/flutter_json.dart';
import 'package:flutter_svg/svg.dart';
import 'package:http/http.dart' as http;
import '../../utils/llama_wrapper.dart';
import 'package:markdown_widget/config/configs.dart';
import 'package:markdown_widget/widget/all.dart';
import 'package:path/path.dart' as path;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:re_highlight/re_highlight.dart' show Mode;
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:panda/utils/agentic_tools.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../bloc/repo_bloc/repo_bloc.dart';
import '../../bloc/ui_bloc/ui_bloc.dart';
import '../../terminal/terminal.dart';
import '../../utils/ai.dart';
import '../../utils/copilot_chat.dart';
import '../../utils/functions.dart';
import '../../utils/languages.dart';
import '../../utils/themes.dart';
import '../../utils/constants.dart';

// GGUF model download manager
// Extracted from widgets.dart

class GgufDownloadManager extends StatefulWidget {
  final List<GgufModel> availableModels;

  const GgufDownloadManager({super.key, required this.availableModels});

  @override
  State<GgufDownloadManager> createState() => _GgufDownloadManagerState();
}

class _GgufDownloadManagerState extends State<GgufDownloadManager>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerUnregisteredCompletedTasks(context);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _registerUnregisteredCompletedTasks(BuildContext context) async {
    final cubit = context.read<GgufDownloadCubit>();
    for (final task in cubit.state.tasks) {
      if (task.status == GgufDownloadStatus.completed && !task.registered) {
        final result = await GgufModel.registerGgufModelWithAI(task);
        if (context.mounted) {
          context.read<AIBloc>().add(AIConfigEvent(result.aiConfig));
          context.read<AIBloc>().add(ModelSelectEvent(result.modelSelected));
          cubit.markTaskRegistered(task.taskId);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = context.watch<AppThemeBloc>().state.appTheme;
    final isDark = appTheme.isDark;
    final textColor = appTheme.selectScreenCardTextColor;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xff2b2b2b) : Colors.white,
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_download, color: Colors.lightBlue, size: 28),
                const SizedBox(width: 12),
                Text(
                  'GGUF Model Manager',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TabBar(
              controller: _tabController,
              labelColor: Colors.lightBlue,
              unselectedLabelColor: textColor.withAlpha(150),
              indicatorColor: Colors.lightBlue,
              tabs: const [
                Tab(text: 'Available Models'),
                Tab(text: 'Downloads'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAvailableTab(context, appTheme),
                  _buildDownloadsTab(context, appTheme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvailableTab(BuildContext context, AppTheme appTheme) {
    final isDark = appTheme.isDark;

    String hardwareLevel(double params) {
      if (params <= 1.5) return "Light";
      if (params <= 3) return "Medium";
      return "Heavy";
    }

    Color hardwareColor(double params) {
      if (params <= 1.5) return Colors.green;
      if (params <= 3) return Colors.orange;
      return Colors.redAccent;
    }

    String hardwareNote(double params) {
      if (params <= 1.5) return "Runs on most phones";
      if (params <= 3) return "Needs decent RAM";
      return "High-end device needed";
    }

    Widget buildChip(String text, IconData icon) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(
                color: appTheme.selectScreenCardTextColor,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return BlocBuilder<GgufDownloadCubit, GgufDownloadState>(
      builder: (context, state) {
        final cubit = context.read<GgufDownloadCubit>();

        return ListView.builder(
          itemCount: widget.availableModels.length,
          itemBuilder: (_, i) {
            final model = widget.availableModels[i];

            GgufDownloadTask? existing;
            for (var task in state.tasks) {
              if (task.url == model.url) {
                existing = task;
                break;
              }
            }

            final isCompleted = existing?.status == GgufDownloadStatus.completed;

            final isDownloading = existing?.status == GgufDownloadStatus.downloading;

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: isDark
                  ? appTheme.editorPageToolbarBg.withAlpha(150)
                  : Colors.grey.shade50,
                border: Border.all(
                  color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey.shade300,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Image.network(model.imageUrl, width: 20, height: 20)
                      ),

                      const SizedBox(width: 10),

                      Expanded(
                        child: Text(
                          model.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: appTheme.selectScreenCardTextColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      buildChip("${model.paramSize}B", Icons.storage),
                      buildChip(model.quant, Icons.compress),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: hardwareColor(model.paramSize).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          hardwareLevel(model.paramSize),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: hardwareColor(model.paramSize),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  Text(
                    hardwareNote(model.paramSize),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Align(
                    alignment: Alignment.centerRight,
                    child: isCompleted
                      ? const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                        )
                      : isDownloading
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color:
                                    appTheme.selectScreenCardTextColor,
                              ),
                            )
                          : ElevatedButton.icon(
                              onPressed: () {
                                cubit.startDownload(model);
                                _tabController.animateTo(1);
                              },
                              icon: const Icon(
                                Icons.download,
                                size: 16,
                              ),
                              label: const Text("Download"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color(0xff007acc),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(10),
                                ),
                              ),
                            ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDownloadsTab(BuildContext context, AppTheme appTheme) {
    return BlocBuilder<GgufDownloadCubit, GgufDownloadState>(
      builder: (context, downldState) {
        final tasks = downldState.tasks.where((t) => t.status != GgufDownloadStatus.completed).toList();
        final completed = downldState.tasks.where((t) => t.status == GgufDownloadStatus.completed).toList();

        if (tasks.isEmpty && completed.isEmpty) {
          return Center(
            child: Text(
              'No downloads yet',
              style: TextStyle(color: appTheme.selectScreenCardTextColor.withAlpha(150)),
            ),
          );
        }

        return ListView(
          children: [
            if (tasks.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Active Downloads', style: TextStyle(color: appTheme.selectScreenCardTextColor, fontWeight: FontWeight.w600)),
              ),
              ...tasks.map((task) => _buildTaskTile(task, appTheme, context.read<GgufDownloadCubit>())),
            ],
            if (completed.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Completed', style: TextStyle(color: appTheme.selectScreenCardTextColor, fontWeight: FontWeight.w600)),
              ),
              ...completed.map((task) => _buildTaskTile(task, appTheme, context.read<GgufDownloadCubit>())),
            ],
          ],
        );
      },
    );
  }

  Widget _buildTaskTile(GgufDownloadTask task, AppTheme appTheme, GgufDownloadCubit cubit) {
    final isDark = appTheme.isDark;
    final isActive = task.status == GgufDownloadStatus.downloading;
    final isCompleted = task.status == GgufDownloadStatus.completed;
    final isFailed = task.status == GgufDownloadStatus.failed;
    final progress = task.progress.clamp(0.0, 100.0);
    final hasAccurateProgress = progress > 0.0 && progress < 100.0;

    return BlocBuilder<GgufDownloadCubit, GgufDownloadState>(
      builder: (context, downldState) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          elevation: 0,
          color: isDark ? const Color(0xff1e1e2e) : Colors.grey.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isCompleted ? Icons.check_circle : (isFailed ? Icons.error : Icons.downloading),
                      color: isCompleted ? Colors.green : (isFailed ? Colors.red : Colors.lightBlue),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        task.modelName,
                        style: TextStyle(
                          color: appTheme.selectScreenCardTextColor,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if(!isCompleted) IconButton(
                      icon: Icon(Icons.close, size: 18, color: Colors.grey.shade600),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: isDark ? const Color(0xff2b2b2b) : Colors.white,
                            title: Text(
                              'Cancel download?',
                              style: TextStyle(color: appTheme.selectScreenCardTextColor),
                            ),
                            content: Text(
                              'Remove "${task.modelName}" from the list? The downloaded file will also be deleted.',
                              style: TextStyle(color: appTheme.selectScreenCardTextColor.withAlpha(180)),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () async{
                                  Navigator.of(ctx).pop();
                                  if(downldState.id != null){
                                    final msg = await GgufDownloadCubit.cancelGGUFDownload(downldState.id!);
                                    if(context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Canceled $msg')),
                                      );
                                    }
                                  }
                                  cubit.deleteTask(task.taskId);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                                ),
                                child: const Text('Remove'),
                              ),
                            ],
                          ),
                        );
                      },
                      tooltip: 'Remove from list and delete file',
                    ),
                  ],
                ),
                if (isActive) ...[
                  const SizedBox(height: 8),
                  if (hasAccurateProgress)
                    LinearPercentIndicator(
                      progressColor: Colors.lightBlue,
                      percent: progress / 100,
                      lineHeight: 8,
                      barRadius: const Radius.circular(4),
                    )
                  else
                    const LinearProgressIndicator(),
                  const SizedBox(height: 4),
                  Text(
                    hasAccurateProgress ? '${progress.toStringAsFixed(1)}%' : 'Downloading…',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
                if (isFailed) ...[
                  const SizedBox(height: 8),
                  Text('Download failed.', style: TextStyle(color: Colors.red.shade300, fontSize: 12)),
                ],
                Wrap(
                  spacing: 8,
                  children: [
                    if (isFailed)
                      ElevatedButton.icon(
                        onPressed: () => cubit.retryDownload(task),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.lightBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    if (isCompleted)
                      ElevatedButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: appTheme.isDark ? const Color(0xff181A26) : null,
                              title: Text(
                                'Delete model?',
                                style: TextStyle(
                                  color: appTheme.selectScreenCardTextColor,
                                  fontSize: 20,
                                ),
                              ),
                              content: Text(
                                'Are you sure you want to delete this model? This action cannot be undone.',
                                style: TextStyle(
                                  color: appTheme.selectScreenCardTextColor.withAlpha(150),
                                  fontSize: 16,
                                ),
                              ),
                              actions: [
                                ElevatedButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () async {
                                    final aiState = context.read<AIBloc>();
                                    final entries = Map<String, dynamic>.from(aiState.config);

                                    final configKey = entries.keys.firstWhere(
                                      (key) => key.startsWith("LocalLlama-") &&
                                        entries[key] is Map &&
                                        entries[key]['modelName'] == task.modelName,
                                      orElse: () => '',
                                    );

                                    if (configKey.isNotEmpty) {
                                      final updatedConfig = Map<String, dynamic>.from(aiState.config)
                                        ..remove(configKey);
                                      final prefs = await SharedPreferences.getInstance();
                                      await prefs.setString('aiConfig', jsonEncode(updatedConfig));

                                      final updatedModelSelected = Map<String, dynamic>.from(aiState.modelSelected);
                                      var modelSelectionChanged = false;
                                      if (updatedModelSelected['code'] == configKey) {
                                        updatedModelSelected['code'] = '';
                                        modelSelectionChanged = true;
                                      }
                                      if (updatedModelSelected['chat'] == configKey) {
                                        updatedModelSelected['chat'] = '';
                                        modelSelectionChanged = true;
                                        await prefs.remove('ai_selected_chat_model_id');
                                      }
                                      if (modelSelectionChanged) {
                                        await prefs.setString('modelSelected', jsonEncode(updatedModelSelected));
                                      }

                                      if (context.mounted) {
                                        context.read<AIBloc>().add(AIConfigEvent(updatedConfig));
                                        if (modelSelectionChanged) {
                                          context.read<AIBloc>().add(ModelSelectEvent(updatedModelSelected));
                                        }
                                      }
                                    }

                                    try {
                                      await File(task.localPath).delete();
                                    } catch (_) {}

                                    cubit.deleteTask(task.taskId);

                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Successfully deleted model ${task.modelName}')
                                        ),
                                      );
                                      Navigator.of(context).pop(true);
                                    }
                                  },
                                  style: ButtonStyle(
                                    backgroundColor: WidgetStateProperty.all<Color>(Colors.red),
                                  ),
                                  child: const Text('Delete', style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: const Icon(Icons.delete, size: 16),
                        label: const Text('Delete file'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class FlutterSwitch extends StatefulWidget {
