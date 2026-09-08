import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/ui_bloc/ui_bloc.dart';
import '../../core/broken_icons.dart';
import '../agent/flow_ui/widgets/flow_chat_view.dart';
import '../agent/flow_ui/widgets/flow_composer.dart';
import '../agent/flow_ui/widgets/flow_greeting.dart';
import '../agent/flow_ui/widgets/flow_pill.dart';
import '../agent/flow_ui/models/flow_attachment_options.dart';
import '../agent/flow_ui/widgets/flow_suggestion.dart';
import '../agent/flow_ui/utils/flow_file_picker.dart';
import 'panda_agent_controller.dart';
import 'panda_agent_composer_extras.dart';
import 'panda_agent_flow_widgets.dart';
import 'panda_agent_model_selector.dart';

class PandaAgentPage extends StatelessWidget {
  const PandaAgentPage({
    super.key,
    required this.controller,
    required this.workspacePath,
    this.onOpenProviders,
  });

  final PandaAgentController controller;
  final String Function() workspacePath;
  final VoidCallback? onOpenProviders;

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
        final modelOptions = aiState.config.entries
            .where((entry) => entry.value is Map)
            .map(
              (entry) {
                final value = Map<String, dynamic>.from(entry.value as Map);
                final name = controller.modelName(value);
                final providerName = controller.providerName(value);
                return PandaAgentModelOption(
                  id: entry.key,
                  label: name.isEmpty ? entry.key : name,
                  providerId: providerName.isEmpty ? 'custom' : providerName,
                  providerLabel: controller.providerLabel(providerName),
                );
              },
            )
            .where((option) => option.providerId.isNotEmpty)
            .toList();
        final pendingRevision = controller.messages.isEmpty
            ? 0
            : ((controller.messages.last['blocks'] as List?)?.length ?? 0);

        final thread = controller.messages.isEmpty
            ? null
            : PandaAgentFlowChat(
                messages: controller.messages,
                scrollController: controller.scrollController,
                isGenerating: controller.isGenerating,
                phase: controller.phase.name,
                currentTool: controller.currentTool,
                onRetry: controller.retry,
                onToolApproval: controller.resolveApproval,
                onAlwaysAllowTools: () => controller.setApprovalMode('autopilot'),
              );

        return FlowChatView(
          empty: controller.messages.isEmpty,
          thread: thread,
          threadController: controller.scrollController,
          greeting: const FlowGreeting(
            icon: Icons.auto_awesome,
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
            onSend: (_) => controller.send(
              context: context,
              aiState: aiState,
              workspacePath: workspacePath(),
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
            errorMessage: controller.lastError,
            onErrorDismiss: controller.clearError,
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
                onTap: () => _showModes(context),
              ),
              if (modelOptions.isNotEmpty)
                PandaAgentModelSelector(
                  models: modelOptions,
                  selectedId: aiState.modelSelected['chat']?.toString(),
                  onSelected: (id) => controller.selectModel(context, id),
                  onAddProvider: onOpenProviders,
                ),
              if (modelOptions.isEmpty)
                FlowPill(
                  icon: Icons.memory_outlined,
                  label: model.isEmpty ? 'Model' : model,
                  showLabel: true,
                  tooltip: 'Modèle actuel',
                ),
            ],
            trailingActions: [
              IconButton(
                tooltip: controller.isListening
                    ? 'Arrêter la dictée'
                    : 'Dicter un message',
                onPressed: controller.toggleListening,
                icon: Icon(
                  controller.isListening ? Icons.mic : Icons.mic_none,
                  size: 19,
                  color: controller.isListening
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                visualDensity: VisualDensity.compact,
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
              onTap: () => Navigator.pop(sheetContext, 'provider'),
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
    onOpenProviders?.call();
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
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
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
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(11),
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
          FlowSuggestionGroup(
            layout: FlowSuggestionLayout.wrap,
            spacing: 6,
            suggestions: [
              FlowSuggestion(
                label: 'Explique la structure de ce projet',
                icon: Broken.tree,
                outlined: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onTap: () => onSend('Explique la structure de ce projet'),
              ),
              FlowSuggestion(
                label: 'Analyse le fichier ouvert',
                icon: Broken.search_normal,
                outlined: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onTap: () => onSend('Analyse le fichier ouvert'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}