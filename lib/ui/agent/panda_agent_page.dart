import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/ui_bloc/ui_bloc.dart';
import '../../core/broken_icons.dart';
import '../agent/flow_ui/widgets/flow_chat_view.dart';
import '../agent/flow_ui/widgets/flow_composer.dart';
import '../agent/flow_ui/widgets/flow_greeting.dart';
import '../agent/flow_ui/widgets/flow_pill.dart';
import '../agent/flow_ui/models/flow_attachment_options.dart';
import '../agent/flow_ui/utils/flow_file_picker.dart';
import 'panda_agent_controller.dart';
import 'panda_agent_composer_extras.dart';
import 'panda_agent_flow_widgets.dart';
import 'panda_agent_model_selector.dart';
import 'flow_ui/styles/flow_pill_style.dart';

class PandaAgentPage extends StatelessWidget {
  const PandaAgentPage({
    super.key,
    required this.controller,
    required this.workspacePath,
    this.onOpenProviders,
    this.onOpenSecrets,
  });

  final PandaAgentController controller;
  final String Function() workspacePath;
  final VoidCallback? onOpenProviders;
  final VoidCallback? onOpenSecrets;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final aiState = context.watch<AIBloc>().state;
        final profile = controller.selectedProfile(aiState);
        final config = profile?.value is Map
            ? Map<String, dynamic>.from(profile!.value as Map)
            : null;
        final model = controller.modelName(config);
        final modelOptions = <PandaAgentModelOption>[];
        for (final entry in aiState.config.entries) {
          if (entry.value is! Map) continue;
          final value = Map<String, dynamic>.from(entry.value as Map);
          final providerName = controller.providerName(value);
          final providerId = providerName.isEmpty ? 'custom' : providerName;
          if (providerId.isEmpty) continue;

          final available = (value['availableModels'] as List?)
                  ?.whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .map((item) => (
                        id: (item['id'] ?? item['name'] ?? '').toString().trim(),
                        label: (item['displayName'] ?? item['name'] ?? item['id'] ?? '')
                            .toString()
                            .trim(),
                      ))
                  .where((item) => item.id.isNotEmpty)
                  .toList() ??
              const <({String id, String label})>[];

          final models = available.isEmpty
              ? <({String id, String label})>[
                  (id: controller.modelName(value), label: controller.modelName(value)),
                ]
              : available;

          for (final item in models) {
            final optionId = '${entry.key}::${item.id}';
            modelOptions.add(
              PandaAgentModelOption(
                id: optionId,
                label: item.label.isEmpty ? item.id : item.label,
                providerId: providerId,
                providerLabel: controller.providerLabel(providerName),
              ),
            );
          }
        }
        final selectedProfileId = profile?.key;
        final selectedModelId = model.isEmpty ? '' : model;
        final selectedOptionId = selectedProfileId == null
            ? aiState.modelSelected['chat']?.toString()
            : '$selectedProfileId::$selectedModelId';
        final pendingRevision = controller.messages.isEmpty
            ? 0
            : ((controller.messages.last['blocks'] as List?)?.length ?? 0);

        final thread = controller.messages.isEmpty
            ? null
            : PandaAgentFlowChat(
                messages: controller.messages,
                scrollController: controller.scrollController,
                isGenerating: controller.isGenerating,
                onRetry: controller.retry,
                onToolApproval: controller.resolveApproval,
                onAlwaysAllowTools: () => controller.setApprovalMode('autopilot'),
              );

        return FlowChatView(
          empty: controller.messages.isEmpty,
          thread: thread,
          threadController: controller.scrollController,
          greeting: const FlowGreeting(
             icon: Broken.magicpen,
            text: 'Comment puis-je vous aider ?',
          ),
          suggestions: null,
          aboveComposer: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (controller.messages.isEmpty)
                _PandaAgentSuggestions(
                  onSend: (text) => controller.send(
                    context: context,
                    aiState: aiState,
                    workspacePath: workspacePath(),
                    text: text,
                  ),
                ),
              PandaAgentPendingChangesBar(
                key: ValueKey(
                  'pending-$pendingRevision-${controller.phase.name}-${controller.messages.length}',
                ),
                workspacePath: workspacePath(),
                revision: pendingRevision,
              ),
              PandaAgentQueueBar(
                items: controller.queuedPrompts,
                onRemove: controller.removeQueued,
                onEdit: controller.editQueued,
              ),
            ],
          ),
          composer: FlowComposer(
            controller: controller.inputController,
            isStreaming: controller.isGenerating,
            // Use the value delivered by FlowComposer. The composer clears
            // its controller after this callback; reading the controller
            // again here could turn a valid tap into an empty request.
            onSend: (text) => controller.send(
              context: context,
              aiState: aiState,
              workspacePath: workspacePath(),
              text: text,
            ),
            onStop: controller.stop,
            placeholder: 'Écrire un message à Panda Agent…',
            submitOnEnter: true,
            maxLines: 2,
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            attachments: controller.pendingAttachments,
            onAttach: () => _showAddMenu(context, controller),
            onAttachmentsPasted: controller.addAttachments,
            onAttachmentsDropped: controller.addAttachments,
            onRemoveAttachment: controller.removeAttachment,
            attachmentOptions: FlowAttachmentOptions.any,
            attachTooltip: 'Ajouter un fichier ou une image',
            leadingActions: [
              FlowPill(
                icon: Broken.magicpen,
                label: controller.chatMode == 'agent'
                    ? 'Agent'
                    : controller.chatMode == 'plan'
                        ? 'Plan'
                        : 'Ask',
                tooltip: 'Mode ${controller.chatMode}',
                showLabel: true,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                borderRadius: BorderRadius.circular(6),
                style: const FlowPillStyle(
                  backgroundColor: Colors.transparent,
                  hoverColor: Color(0x14141414),
                  borderColor: Colors.transparent,
                ),
                onTap: () => _showModes(context),
              ),
              if (modelOptions.isNotEmpty)
                PandaAgentModelSelector(
                  models: modelOptions,
                   selectedId: selectedOptionId,
                  onSelected: (id) => controller.selectModel(context, id),
                  onAddProvider: onOpenProviders,
                ),
              if (modelOptions.isEmpty)
                FlowPill(
                  icon: Broken.cpu,
                  label: model.isEmpty ? 'Model' : model,
                  showLabel: true,
                  tooltip: 'Modèle actuel',
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  borderRadius: BorderRadius.circular(6),
                  style: const FlowPillStyle(
                    backgroundColor: Colors.transparent,
                    hoverColor: Color(0x14141414),
                    borderColor: Colors.transparent,
                  ),
                  onTap: onOpenProviders,
                ),
            ],
            trailingActions: [
              _PandaAgentMicButton(
                isListening: controller.isListening,
                onPressed: controller.toggleListening,
              ),
            ],
          ),
          belowComposer: PandaAgentComposerFooter(
            approvalMode: controller.approvalMode,
            usedTokens: controller.usedTokens,
            maxTokens: controller.maxTokens,
            onApprovalTap: () => _showApprovalModes(context),
          ),
        );
      },
    );
  }

  Future<void> _showAddMenu(
    BuildContext context,
    PandaAgentController controller,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Broken.document_upload),
              title: const Text('Ajouter un fichier'),
              subtitle: const Text('Joindre un fichier au prochain message'),
              onTap: () => Navigator.pop(sheetContext, 'file'),
            ),
            ListTile(
              leading: const Icon(Broken.briefcase),
              title: const Text('Provider / intégration'),
              subtitle: const Text('Ouvrir la page Providers'),
              onTap: () => Navigator.pop(sheetContext, 'provider'),
            ),
            ListTile(
              leading: const Icon(Broken.key),
              title: const Text('Secrets et variables'),
              subtitle: const Text('Gérer les accès de l’agent'),
               onTap: () => Navigator.pop(sheetContext, 'secrets'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'file') {
      final picked = await showFlowAttachmentPicker(
        options: FlowAttachmentOptions.any,
      );
      if (picked.isNotEmpty) controller.addAttachments(picked);
      return;
    }
    if (action == 'secrets') {
      onOpenSecrets?.call();
    } else {
      onOpenProviders?.call();
    }
  }

  void _showModes(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in const [
              ('ask', 'Ask', 'Répondre sans modifier le projet'),
              ('plan', 'Plan', 'Préparer un plan avec lecture seule'),
              ('agent', 'Agent', 'Exécuter les outils autorisés'),
            ])
              ListTile(
                leading: Icon(
                  mode.$1 == controller.chatMode
                       ? Broken.record_circle
                       : Broken.radio,
                ),
                title: Text(mode.$2),
                subtitle: Text(mode.$3),
                onTap: () {
                  controller.setMode(mode.$1);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showApprovalModes(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in const [
              ('default', 'Approbation des actions sensibles', 'Demander uniquement pour les commandes destructives'),
              ('every', 'Demander chaque outil', 'Confirmer chaque lecture, édition ou commande'),
              ('autopilot', 'Autopilot', 'Exécuter sans demander, y compris les commandes destructives'),
            ])
              ListTile(
                leading: Icon(
                  mode.$1 == controller.approvalMode
                       ? Broken.record_circle
                       : Broken.radio,
                ),
                title: Text(mode.$2),
                subtitle: Text(mode.$3),
                onTap: () {
                  controller.setApprovalMode(mode.$1);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _PandaAgentSuggestions extends StatelessWidget {
  const _PandaAgentSuggestions({required this.onSend});

  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final suggestions = [
      ('Explique la structure de ce projet', Broken.tree),
      ('Analyse le fichier ouvert', Broken.search_normal),
      ('Propose les prochaines étapes', Broken.task),
    ];
    return Container(
      width: double.infinity,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(9, 7, 0, 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 3, bottom: 4),
            child: Text(
              'Suggestions',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: colors.onSurfaceVariant,
                letterSpacing: 0.3,
              ),
            ),
          ),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 9),
              itemCount: suggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final suggestion = suggestions[index];
                return _PandaSuggestionCard(
                  label: suggestion.$1,
                  icon: suggestion.$2,
                  onStart: () => onSend(suggestion.$1),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PandaSuggestionCard extends StatelessWidget {
  const _PandaSuggestionCard({
    required this.label,
    required this.icon,
    required this.onStart,
  });

  final String label;
  final IconData icon;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 218,
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.72)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 9),
          Icon(icon, size: 17, color: colors.onSurfaceVariant),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: onStart,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: colors.primary,
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }
}

class _PandaAgentMicButton extends StatelessWidget {
  const _PandaAgentMicButton({
    required this.isListening,
    required this.onPressed,
  });

  final bool isListening;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: isListening ? 'Arrêter la dictée' : 'Dicter un message',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: isListening
              ? colors.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 220),
          scale: isListening ? 1.08 : 1,
          child: IconButton(
            onPressed: onPressed,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(
                isListening ? Broken.microphone : Broken.microphone_slash,
                key: ValueKey(isListening),
                size: 19,
                color: isListening ? colors.primary : colors.onSurfaceVariant,
              ),
            ),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }
}