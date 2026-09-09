import 'package:flutter/material.dart';

import '../../core/broken_icons.dart';
import '../../utils/ai_provider_logos.dart';

/// A model exposed by Panda Agent's compact composer picker.
class PandaAgentModelOption {
  const PandaAgentModelOption({
    required this.id,
    required this.label,
    required this.providerId,
    required this.providerLabel,
  });

  final String id;
  final String label;
  final String providerId;
  final String providerLabel;
}

/// Compact model trigger with a provider-grouped picker.
///
/// The picker deliberately lives next to the agent composer rather than in
/// provider settings: choosing a connected model is a chat action, while
/// adding credentials still belongs to the existing Providers page.
class PandaAgentModelSelector extends StatelessWidget {
  const PandaAgentModelSelector({
    super.key,
    required this.models,
    required this.selectedId,
    required this.onSelected,
    this.onAddProvider,
  });

  final List<PandaAgentModelOption> models;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final VoidCallback? onAddProvider;

  PandaAgentModelOption? get _selected {
    for (final option in models) {
      if (option.id == selectedId) return option;
    }
    return models.isEmpty ? null : models.first;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: selected == null
          ? 'Choisir un modèle'
          : '${selected.providerLabel} · ${selected.label}',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: models.isEmpty ? null : () => _showPicker(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected != null)
                  ProviderLogoBadge(providerId: selected.providerId, size: 17)
                else
                  Icon(Broken.cpu, size: 16, color: colors.onSurfaceVariant),
                const SizedBox(width: 5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 78),
                  child: Text(
                    selected?.label ?? 'Model',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: models.isEmpty
                          ? colors.onSurfaceVariant
                          : colors.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Broken.arrow_down_1,
                  size: 13,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showPicker(BuildContext context) async {
    final grouped = <String, List<PandaAgentModelOption>>{};
    for (final model in models) {
      grouped.putIfAbsent(model.providerId, () => []).add(model);
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 560),
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: colors.shadow.withValues(alpha: 0.28),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
                  child: Row(
                    children: [
                      Icon(Broken.cpu_setting,
                          size: 18, color: colors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Modèle de conversation',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fermer',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: Icon(Broken.close_circle,
                            size: 19, color: colors.onSurfaceVariant),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: colors.outlineVariant.withValues(alpha: 0.65),
                ),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    shrinkWrap: true,
                    children: [
                      for (final entry in grouped.entries)
                        _ProviderSection(
                          providerId: entry.key,
                          providerLabel: entry.value.first.providerLabel,
                          models: entry.value,
                          selectedId: selectedId,
                          onSelected: (id) {
                            onSelected(id);
                            Navigator.pop(sheetContext);
                          },
                        ),
                    ],
                  ),
                ),
                if (onAddProvider != null) ...[
                  Divider(
                    height: 1,
                    color: colors.outlineVariant.withValues(alpha: 0.65),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          onAddProvider!();
                        },
                        icon: Icon(Broken.add_circle, size: 17),
                        label: const Text('Ajouter un provider'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(36),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProviderSection extends StatelessWidget {
  const _ProviderSection({
    required this.providerId,
    required this.providerLabel,
    required this.models,
    required this.selectedId,
    required this.onSelected,
  });

  final String providerId;
  final String providerLabel;
  final List<PandaAgentModelOption> models;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 5),
            child: Row(
              children: [
                ProviderLogoBadge(providerId: providerId, size: 20),
                const SizedBox(width: 7),
                Text(
                  providerLabel,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.25,
                  ),
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.24),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                for (final model in models)
                  InkWell(
                    onTap: () => onSelected(model.id),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              model.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.onSurface,
                                fontSize: 12,
                                fontWeight: model.id == selectedId
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (model.id == selectedId)
                            Icon(Broken.tick_circle,
                                size: 17, color: colors.primary),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}