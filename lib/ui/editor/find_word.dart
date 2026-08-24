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

// Find in file widget
// Extracted from widgets.dart

class FindWordWidget extends StatefulWidget {
  final AppTheme appTheme;
  final TextEditingController findWordController, replaceWordController;
  final ActiveEditorState editorState;
  final TabController? tabController;
  final String workspacePath;
  final void Function(File file, int lineNumber, String searchQuery)?
  onFileOpen;
  const FindWordWidget({
    super.key,
    required this.appTheme,
    required this.findWordController,
    required this.editorState,
    required this.replaceWordController,
    required this.tabController,
    required this.workspacePath,
    this.onFileOpen,
  });

  @override
  State<FindWordWidget> createState() => _FindWordWidgetState();
}

class _FindWordWidgetState extends State<FindWordWidget> {
  final ScrollController _resultsScrollController = ScrollController();
    Timer? _debounceTimer;
    int _searchId = 0;
    final InvertedIndex _invertedIndex = InvertedIndex();

  ActiveEditor? _getActiveEditor() {
    if (widget.editorState.activeEditors.isEmpty) return null;

    if (widget.tabController != null) {
      final index = widget.tabController!.index;
      if (index >= 0 && index < widget.editorState.activeEditors.length) {
        return widget.editorState.activeEditors[index];
      }
    }

    for (final editor in widget.editorState.activeEditors) {
      if (editor.isActive) {
        return editor;
      }
    }

    return widget.editorState.activeEditors.first;
  }

  void _goToMatchNearLine(
    ActiveEditor editor,
    int targetLine,
    String searchQuery,
  ) {
    if (editor.findController == null) return;

    final findController = editor.findController!;
    final codeController = editor.controller;
    final text = codeController.text;

    findController.findInputController.text = searchQuery;
    findController.find(searchQuery);

    if (findController.matchCount == 0) return;

    final lines = text.split('\n');
    int targetCharOffset = 0;
    for (int i = 0; i < targetLine - 1 && i < lines.length; i++) {
      targetCharOffset += lines[i].length + 1;
    }

    int targetLineEnd = targetCharOffset;
    if (targetLine - 1 < lines.length) {
      targetLineEnd += lines[targetLine - 1].length;
    }

    final lowerText = findController.caseSensitive ? text : text.toLowerCase();
    final lowerQuery = findController.caseSensitive
        ? searchQuery
        : searchQuery.toLowerCase();

    final matchPositions = <int>[];
    int pos = 0;
    while (true) {
      final index = lowerText.indexOf(lowerQuery, pos);
      if (index == -1) break;
      matchPositions.add(index);
      pos = index + 1;
    }

    if (matchPositions.isEmpty) return;

    int bestMatchIndex = 0;
    for (int i = 0; i < matchPositions.length; i++) {
      final matchStart = matchPositions[i];

      if (matchStart >= targetCharOffset && matchStart <= targetLineEnd) {
        bestMatchIndex = i;
        break;
      }
    }

    final currentIdx = findController.currentMatchIndex;
    final diff = bestMatchIndex - currentIdx;

    if (diff > 0) {
      for (int i = 0; i < diff; i++) {
        findController.next();
      }
    } else if (diff < 0) {
      for (int i = 0; i < -diff; i++) {
        findController.previous();
      }
    }
  }

  Future<void> _searchWorkspace(
    BuildContext context,
    String query,
    WorkspaceSearchState searchState,
  ) async {
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      if (context.mounted) {
        context.read<WorkspaceSearchBloc>().add(ClearSearchResults());
      }
      return;
    }

    final debounceCompleter = Completer<void>();
    _debounceTimer = Timer(
      const Duration(milliseconds: 300),
      debounceCompleter.complete,
    );
    await debounceCompleter.future;

    if (!context.mounted) return;

    final myId = ++_searchId;

    context.read<WorkspaceSearchBloc>().add(SetSearching(isSearching: true));

    if (_invertedIndex.isReady &&
        !searchState.isRegex &&
        searchState.matchWholeWord &&
        query.length >= 3 &&
        !query.contains(RegExp(r'\s'))) {
      final hit = _invertedIndex.lookup(query);
      if (hit != null) {
        final results = <SearchResultData>[];
        for (final entry in hit.entries) {
          final relativePath =
              entry.key.replaceFirst('${widget.workspacePath}/', '');
          try {
            int lineNo = 0;
            await for (final line in File(entry.key)
                .openRead()
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
              lineNo++;
              if (entry.value.contains(lineNo)) {
                results.add(SearchResultData(
                  filePath:     entry.key,
                  relativePath: relativePath,
                  lineNumber:   lineNo,
                  lineContent:  line.trim(),
                ));
              }
            }
          } catch (_) {}
        }

        if (!context.mounted || _searchId != myId) return;
        context.read<WorkspaceSearchBloc>().add(
          UpdateSearchResults(results: results, query: query),
        );
        return;
      }
    }

    final params = SearchParams(
      workspacePath: widget.workspacePath,
      query: query,
      matchCase: searchState.matchCase,
      matchWholeWord: searchState.matchWholeWord,
      isRegex: searchState.isRegex,
    );

    List<RawResult> rawResults;
    try {
      rawResults = await compute(searchIsolate, params);
    } catch (_) {
      rawResults = const [];
    }

    if (!context.mounted || _searchId != myId) return;

    final results = rawResults
      .map((r) => SearchResultData(
        filePath: r.filePath,
        relativePath: r.relativePath,
        lineNumber: r.lineNumber,
        lineContent: r.lineContent,
      )).toList();

    context.read<WorkspaceSearchBloc>().add(
      UpdateSearchResults(results: results, query: query),
    );
  }

  Future<void> _replaceInWorkspace(
    BuildContext context,
    String findText,
    String replaceText,
    WorkspaceSearchState searchState,
  ) async {
    if (findText.isEmpty || searchState.results.isEmpty) return;

    final filesModified = <String>{};

    for (final result in searchState.results) {
      try {
        final file = File(result.filePath);
        String content = await file.readAsString();
        String newContent;

        if (searchState.isRegex) {
          try {
            final regex = RegExp(
              findText,
              caseSensitive: searchState.matchCase,
            );
            newContent = content.replaceAll(regex, replaceText);
          } catch (_) {
            continue;
          }
        } else if (searchState.matchWholeWord) {
          final pattern = RegExp(
            '\\b${RegExp.escape(findText)}\\b',
            caseSensitive: searchState.matchCase,
          );
          newContent = content.replaceAll(pattern, replaceText);
        } else {
          if (searchState.matchCase) {
            newContent = content.replaceAll(findText, replaceText);
          } else {
            newContent = content.replaceAll(
              RegExp(RegExp.escape(findText), caseSensitive: false),
              replaceText,
            );
          }
        }

        if (content != newContent) {
          await file.writeAsString(newContent);
          filesModified.add(result.filePath);
        }
      } catch (_) {}
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Replaced in ${filesModified.length} file(s)'),
          duration: const Duration(seconds: 2),
        ),
      );

      _searchWorkspace(context, findText, searchState);
    }
  }


  @override
  void initState() {
    super.initState();
    _invertedIndex.build(widget.workspacePath);
  }


  @override
  void dispose() {
    _debounceTimer?.cancel();
    _resultsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WorkspaceSearchBloc, WorkspaceSearchState>(
      builder: (context, searchState) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 17, bottom: 15),
                child: Text(
                  "SEARCH",
                  style: TextStyle(
                    fontWeight: widget.appTheme.isDark
                      ? FontWeight.w300
                      : FontWeight.w500,
                    color: widget.appTheme.selectScreenCardTextColor,
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final activeEditor = _getActiveEditor();
                      if (activeEditor != null && activeEditor.findController != null) {
                        Navigator.of(context).pop();

                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          activeEditor.findController!.isActive = true;
                          activeEditor.findController!.findInputFocusNode.requestFocus();
                        });
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No active editor'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      }
                    },
                    icon: Icon(
                      Icons.article_outlined,
                      color: widget.appTheme.selectScreenCardTextColor,
                      size: 18,
                    ),
                    label: Text(
                      "Find in Current File",
                      style: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor,
                        fontSize: 13,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: widget.appTheme.selectScreenCardTextColor.withAlpha(100),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 15),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  "Search in Workspace",
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor.withAlpha(180),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildOptionButton(
                      'Aa',
                      'Match Case',
                      searchState.matchCase,
                      () {
                        context.read<WorkspaceSearchBloc>().add(
                          UpdateSearchOptions(
                            matchCase: !searchState.matchCase,
                            matchWholeWord: searchState.matchWholeWord,
                            isRegex: searchState.isRegex,
                          ),
                        );
                        if (widget.findWordController.text.isNotEmpty) {
                          _searchWorkspace(
                            context,
                            widget.findWordController.text,
                            searchState.copyWith(
                              matchCase: !searchState.matchCase,
                            ),
                          );
                        }
                      },
                    ),
                    _buildOptionButton(
                      'ab',
                      'Match Word',
                      searchState.matchWholeWord,
                      () {
                        context.read<WorkspaceSearchBloc>().add(
                          UpdateSearchOptions(
                            matchCase: searchState.matchCase,
                            matchWholeWord: !searchState.matchWholeWord,
                            isRegex: searchState.isRegex,
                          ),
                        );
                        if (widget.findWordController.text.isNotEmpty) {
                          _searchWorkspace(
                            context,
                            widget.findWordController.text,
                            searchState.copyWith(
                              matchWholeWord: !searchState.matchWholeWord,
                            ),
                          );
                        }
                      },
                      underline: true,
                    ),
                    _buildOptionButton(
                      '\u2022\u2731',
                      'Regex',
                      searchState.isRegex,
                      () {
                        context.read<WorkspaceSearchBloc>().add(
                          UpdateSearchOptions(
                            matchCase: searchState.matchCase,
                            matchWholeWord: searchState.matchWholeWord,
                            isRegex: !searchState.isRegex,
                          ),
                        );
                        if (widget.findWordController.text.isNotEmpty) {
                          _searchWorkspace(
                            context,
                            widget.findWordController.text,
                            searchState.copyWith(isRegex: !searchState.isRegex),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),

              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                title: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: widget.findWordController,
                    onChanged: (value) {
                      if (value.length >= 2) {
                        _searchWorkspace(context, value, searchState);
                      } else if (value.isEmpty) {
                        context.read<WorkspaceSearchBloc>().add(
                          ClearSearchResults(),
                        );
                      }
                    },
                    onSubmitted: (value) =>
                        _searchWorkspace(context, value, searchState),
                    cursorColor: Colors.grey,
                    style: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintStyle: TextStyle(
                        color: widget.appTheme.selectScreenCardTextColor
                            .withAlpha(120),
                        fontSize: 14,
                      ),
                      hintText: "Search",
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: const OutlineInputBorder(),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xff0178b9)),
                      ),
                      suffixIcon: widget.findWordController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.clear,
                                size: 18,
                                color: widget.appTheme.selectScreenCardTextColor
                                    .withAlpha(150),
                              ),
                              onPressed: () {
                                widget.findWordController.clear();
                                context.read<WorkspaceSearchBloc>().add(
                                  ClearSearchResults(),
                                );
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),

              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                title: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: TextField(
                          controller: widget.replaceWordController,
                          cursorColor: Colors.grey,
                          style: TextStyle(
                            color: widget.appTheme.selectScreenCardTextColor,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintStyle: TextStyle(
                              color: widget.appTheme.selectScreenCardTextColor
                                  .withAlpha(120),
                              fontSize: 14,
                            ),
                            hintText: "Replace",
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: const OutlineInputBorder(),
                            focusedBorder: const OutlineInputBorder(
                              borderSide: BorderSide(color: Color(0xff0178b9)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: searchState.results.isNotEmpty
                          ? () => _replaceInWorkspace(
                              context,
                              widget.findWordController.text,
                              widget.replaceWordController.text,
                              searchState,
                            )
                          : null,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: searchState.results.isNotEmpty
                              ? const Color(0xff0e639c)
                              : Colors.grey[700],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        height: 38,
                        width: 38,
                        child: const Icon(
                          Icons.find_replace,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              if (searchState.isSearching)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 17),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.appTheme.selectScreenCardTextColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Searching...",
                        style: TextStyle(
                          color: widget.appTheme.selectScreenCardTextColor
                              .withAlpha(150),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              else if (searchState.results.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 17),
                  child: Text(
                    "${searchState.results.length} result${searchState.results.length == 1 ? '' : 's'} found",
                    style: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor
                          .withAlpha(150),
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 8),

              Expanded(
                child: searchState.results.isEmpty
                    ? Center(
                        child: Text(
                          widget.findWordController.text.isEmpty
                              ? "Enter search term"
                              : searchState.isSearching
                              ? ""
                              : "No results found",
                          style: TextStyle(
                            color: widget.appTheme.selectScreenCardTextColor
                                .withAlpha(100),
                            fontSize: 13,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _resultsScrollController,
                        itemCount: searchState.results.length,
                        itemBuilder: (context, index) {
                          final result = searchState.results[index];
                          return _buildResultTile(result, searchState.query);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOptionButton(
    String text,
    String tooltip,
    bool isActive,
    VoidCallback onTap, {
    bool underline = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xff0178b9).withAlpha(100)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive
                  ? widget.appTheme.selectScreenCardTextColor
                  : Colors.transparent,
              width: 0.5,
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: widget.appTheme.selectScreenCardTextColor,
              fontSize: 13,
              decoration: underline ? TextDecoration.underline : null,
              decorationColor: widget.appTheme.selectScreenCardTextColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultTile(SearchResultData result, String searchQuery) {
    return InkWell(
      onTap: () {
        final file = File(result.filePath);

        final existingIndex = widget.editorState.activeEditors.indexWhere(
          (editor) => editor.file.path == file.path,
        );

        if (existingIndex >= 0) {
          if (widget.tabController != null) {
            widget.tabController!.animateTo(existingIndex);
          }
          Navigator.of(context).pop();

          WidgetsBinding.instance.addPostFrameCallback((_) {
            final editor = widget.editorState.activeEditors[existingIndex];
            if (editor.findController != null) {
              _goToMatchNearLine(editor, result.lineNumber, searchQuery);
            }
          });
        } else {
          Navigator.of(context).pop();
          widget.onFileOpen?.call(file, result.lineNumber, searchQuery);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: widget.appTheme.selectScreenCardTextColor.withAlpha(30),
              width: 0.5,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  height: 14,
                  width: 14,
                  child: (() {
                    try {
                      final ext = path
                          .extension(result.filePath)
                          .replaceAll('.', '');
                      return languages
                          .singleWhere((lang) => lang.extension.contains(ext))
                          .icon;
                    } catch (_) {
                      return langtxt.icon;
                    }
                  })(),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    result.relativePath,
                    style: TextStyle(
                      color: widget.appTheme.selectScreenCardTextColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  ':${result.lineNumber}',
                  style: TextStyle(
                    color: widget.appTheme.selectScreenCardTextColor.withAlpha(
                      120,
                    ),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              result.lineContent,
              style: TextStyle(
                color: widget.appTheme.selectScreenCardTextColor.withAlpha(180),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
