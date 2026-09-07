import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/ui_bloc/ui_bloc.dart';
import '../../utils/ai.dart';
import '../agent/flow_ui/widgets/flow_chat_view.dart';
import '../agent/flow_ui/widgets/flow_composer.dart';
import '../agent/flow_ui/widgets/flow_greeting.dart';
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
          aboveComposer: _statusBar(
            context,
            provider: provider,
            model: model,
            missingKey: missingKey,
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
            leadingActions: [
              _pill(
                context,
                icon: Icons.tune,
                label: controller.chatMode.toUpperCase(),
                onTap: () => _showModes(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statusBar(
    BuildContext context, {
    required String provider,
    required String model,
    required bool missingKey,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Row(
        children: [
          Icon(
            missingKey ? Icons.warning_amber_rounded : Icons.memory_outlined,
            size: 14,
            color: missingKey ? colors.error : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              missingKey
                  ? 'Aucune clé configurée — ouvrez Providers'
                  : (model.isEmpty ? (provider.isEmpty ? 'Provider' : provider) : model),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: missingKey ? colors.error : colors.onSurfaceVariant,
              ),
            ),
          ),
          if (missingKey && onOpenProviders != null)
            IconButton(
              tooltip: 'Ouvrir Providers',
              icon: const Icon(Icons.open_in_new, size: 15),
              onPressed: onOpenProviders,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _pill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: colors.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
          ],
        ),
      ),
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
}