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

// Find/replace panel
// Extracted from widgets.dart

class FindPanelWidget extends StatelessWidget implements PreferredSizeWidget {
  final FindController controller;
  final VoidCallback? onClose;

  const FindPanelWidget({super.key, required this.controller, this.onClose});

  @override
  Size get preferredSize => Size(
    double.infinity,
    !controller.isActive ? 0 : (controller.isReplaceMode ? _kReplacePanelHeight : _kFindPanelHeight + 2) + 10,
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        if (!controller.isActive) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.only(right: 8, top: 4),
          alignment: Alignment.topRight,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Focus(
              canRequestFocus: false,
              onKeyEvent: (n, e) {
                if (e.logicalKey == LogicalKeyboardKey.escape) {
                  controller.isActive = false;
                  onClose?.call();
                  return KeyEventResult.handled;
                }
                if (e.logicalKey == LogicalKeyboardKey.tab &&
                    controller.isReplaceMode &&
                    controller.findInputFocusNode.hasFocus) {
                  controller.replaceInputFocusNode.requestFocus();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                width: _kFindPanelWidth,
                decoration: BoxDecoration(
                  color: const Color(0xff252526),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(80),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        controller.isReplaceMode
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        color: Colors.grey[400],
                        size: 20,
                      ),
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(
                        maxWidth: 22,
                        minHeight: preferredSize.height,
                        maxHeight: preferredSize.height,
                      ),
                      tooltip: 'Toggle Replace',
                      onPressed: controller.toggleReplaceMode,
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildFindRow(context),
                          if (controller.isReplaceMode)
                            _buildReplaceRow(context),
                          if (!controller.isReplaceMode)
                            const SizedBox(height: 2),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFindRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: _kFindPanelHeight,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _buildTextField(
                  focusNode: controller.findInputFocusNode,
                  controller: controller.findInputController,
                  iconsWidth: 60,
                  padding: const EdgeInsets.only(
                    left: 3,
                    right: 5,
                    top: 4,
                    bottom: 2,
                  ),
                  hintText: 'Find',
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildCheckText(
                      context: context,
                      text: 'Aa',
                      tooltip: 'Match Case',
                      checked: controller.caseSensitive,
                      onPressed: controller.toggleCaseSensitive,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: _buildCheckText(
                        context: context,
                        text: 'W',
                        tooltip: 'Match Whole Word',
                        checked: controller.matchWholeWord,
                        onPressed: controller.toggleMatchWholeWord,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _buildCheckText(
                        context: context,
                        text: '\u2022\u2731',
                        tooltip: 'Use Regular Expression',
                        checked: controller.isRegex,
                        onPressed: controller.toggleRegex,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        _buildResultText(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildIconButton(
              icon: Icons.arrow_upward,
              tooltip: 'Previous (Shift+Enter)',
              onPressed: controller.matchCount == 0
                  ? null
                  : controller.previous,
            ),
            _buildIconButton(
              icon: Icons.arrow_downward,
              tooltip: 'Next (Enter)',
              onPressed: controller.matchCount == 0 ? null : controller.next,
            ),
            _buildIconButton(
              icon: Icons.close,
              tooltip: 'Close (Escape)',
              onPressed: () {
                controller.toggleActive();
                onClose?.call();
              },
            ),
            const SizedBox(width: 4),
          ],
        ),
      ],
    );
  }

  Widget _buildReplaceRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: _kFindPanelHeight,
            child: _buildTextField(
              focusNode: controller.replaceInputFocusNode,
              controller: controller.replaceInputController,
              padding: const EdgeInsets.only(
                left: 3,
                right: 5,
                top: 2,
                bottom: 4,
              ),
              hintText: 'Replace',
              onSubmit: (_) {
                controller.replace();
                controller.replaceInputFocusNode.requestFocus();
              },
            ),
          ),
        ),
        _buildIconButton(
          icon: Icons.done,
          tooltip: 'Replace',
          onPressed: controller.matchCount == 0 ? null : controller.replace,
        ),
        _buildIconButton(
          icon: Icons.done_all,
          tooltip: 'Replace All',
          onPressed: controller.matchCount == 0 ? null : controller.replaceAll,
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    double iconsWidth = 0,
    EdgeInsets padding = EdgeInsets.zero,
    String? hintText,
    ValueChanged<String>? onSubmit,
  }) {
    return Padding(
      padding: padding,
      child: TextField(
        controller: controller,
        maxLines: 1,
        focusNode: focusNode,
        autofocus: false,
        style: const TextStyle(
          fontSize: _kFindInputFontSize,
          color: Colors.white,
        ),
        onSubmitted: onSubmit,
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xff3c3c3c),
          hintText: hintText,
          hintStyle: TextStyle(
            color: Colors.grey[600],
            fontSize: _kFindInputFontSize,
          ),
          contentPadding: EdgeInsets.fromLTRB(8, 5, iconsWidth, 5),
          enabledBorder: OutlineInputBorder(
            borderRadius: const BorderRadius.all(Radius.circular(4)),
            borderSide: BorderSide(width: 0.5, color: Colors.grey[700]!),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
            borderSide: BorderSide(width: 1, color: Color(0xff0178b9)),
          ),
        ),
      ),
    );
  }

  Widget _buildCheckText({
    required BuildContext context,
    required String text,
    required String tooltip,
    required bool checked,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onPressed,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Text(
              text,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: _kFindInputFontSize,
                color: checked ? const Color(0xff0178b9) : Colors.grey[500],
                fontWeight: checked ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    VoidCallback? onPressed,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: _kFindIconSize,
            color: onPressed != null ? Colors.grey[400] : Colors.grey[700],
          ),
        ),
      ),
    );
  }

  Widget _buildResultText() {
    final text = controller.matchCount == 0
        ? 'No results'
        : '${controller.currentMatchIndex + 1}/${controller.matchCount}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: _kFindResultFontSize,
          color: controller.matchCount == 0
              ? Colors.red[300]
              : Colors.grey[400],
        ),
      ),
    );
  }
}

class EditorArea extends StatefulWidget {
