import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/ui_bloc/ui_bloc.dart';
import '../../utils/ai.dart';
import '../agent/flow_ui/widgets/flow_chat_view.dart';
import '../agent/flow_ui/widgets/flow_composer.dart';
import '../agent/flow_ui/widgets/flow_greeting.dart';
import '../agent/flow_ui/widgets/flow_model_selector.dart';
import '../agent/flow_ui/widgets/flow_pill.dart';
import '../agent/flow_ui/styles/flow_pill_style.dart';
import '../agent/flow_ui/models/flow_attachment_options.dart';
import '../agent/flow_ui/widgets/flow_suggestion.dart';
import 'panda_agent_controller.dart';
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
        final provider = controller.providerName(config);
        final model = controller.modelName(config);
        final missingKey = controller.providerNeedsKey(provider) &&
            Models.resolveApiKey(config ?? const <String, dynamic>{}).isEmpty;
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

        final thread = controller.messages.isEmpty
            ? null
            : PandaAgentFlowChat(
                messages: controller.messages,
                scrollController: controller.scrollController,
                isGenerating: controller.isGenerating,
                phase: controller.phase.name,
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
                icon: Icons.tune,
                label: controller.chatMode.toUpperCase(),
                tooltip: 'Mode ${controller.chatMode}',
                showLabel: false,
                onTap: () => _showModes(context),
              ),
              FlowPill(
                icon: Icons.verified_user_outlined,
                label: controller.approvalMode == 'autopilot'
                    ? 'AUTO'
                    : 'APP',
                tooltip: 'Mode d’approbation',
                showLabel: false,
                onTap: () => _showApprovalModes(context),
              ),
              if (missingKey)
                FlowPill(
                  icon: Icons.warning_amber_rounded,
                  label: 'Provider',
                  tooltip: 'Provider non configuré',
                  showLabel: false,
                  style: const FlowPillStyle(
                    iconColor: Colors.amber,
                    borderColor: Colors.amber,
                  ),
                  onTap: onOpenProviders,
                ),
            ],
            trailingActions: [
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
            if (onOpenProviders != null)
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('Configurer les providers'),
                onTap: () {
                  Navigator.pop(context);
                  onOpenProviders!();
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