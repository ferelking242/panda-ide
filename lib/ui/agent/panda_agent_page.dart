import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/ui_bloc/ui_bloc.dart';
import '../agent/flow_ui/widgets/flow_chat_view.dart';
import '../agent/flow_ui/widgets/flow_composer.dart';
import '../agent/flow_ui/widgets/flow_greeting.dart';
import '../agent/flow_ui/widgets/flow_model_selector.dart';
import '../agent/flow_ui/widgets/flow_pill.dart';
import '../agent/flow_ui/models/flow_attachment_options.dart';
import '../agent/flow_ui/widgets/flow_suggestion.dart';
import 'panda_agent_controller.dart';
import 'panda_agent_composer_extras.dart';
import 'panda_agent_flow_widgets.dart';

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
                return FlowModelOption(
                  id: entry.key,
                  label: name.isEmpty ? entry.key : name,
                  description: providerName.isEmpty ? null : providerName,
                );
              },
            )
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
          suggestions: FlowSuggestionGroup(
            suggestions: [
              FlowSuggestion(
                label: 'Explique la structure de ce projet',
                icon: Icons.account_tree_outlined,
                onTap: () => controller.inputController.text =
                    'Explique la structure de ce projet',
              ),
              FlowSuggestion(
                label: 'Analyse le fichier ouvert',
                icon: Icons.search_outlined,
                onTap: () => controller.inputController.text =
                    'Analyse le fichier ouvert',
              ),
            ],
          ),
          aboveComposer: PandaAgentPendingChangesBar(
            key: ValueKey(
              'pending-$pendingRevision-${controller.phase.name}-${controller.messages.length}',
            ),
            workspacePath: workspacePath(),
            revision: pendingRevision,
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
            onAttachmentsPicked: controller.addAttachments,
            onAttachmentsPasted: controller.addAttachments,
            onRemoveAttachment: controller.removeAttachment,
            attachmentOptions: FlowAttachmentOptions.any,
            attachTooltip: 'Ajouter un fichier ou une image',
            leadingActions: [
              FlowPill(
                icon: Icons.auto_awesome,
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
                FlowModelSelector(
                  models: modelOptions,
                  selectedId: aiState.modelSelected['chat']?.toString(),
                  compact: true,
                  onSelected: (id) {
                    final selected = Map<String, dynamic>.from(
                      aiState.modelSelected,
                    )..['chat'] = id;
                    context.read<AIBloc>().add(ModelSelectEvent(selected));
                  },
                  tooltip: model.isEmpty ? 'Choisir un modèle' : model,
                  sheetTitle: 'Choisir un modèle',
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
            onApprovalTap: () => _showApprovalModes(context),
          ),
        );
      },
    );
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
              ('default', 'Demander une approbation', 'Valider les outils sensibles'),
              ('autopilot', 'Toujours autoriser', 'Exécuter sans interrompre le flux'),
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