import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:panda/bloc/repo_bloc/repo_bloc.dart';
import 'package:panda/ui/mdview.dart';
import 'package:panda/utils/constants.dart';
import 'webview.dart';
import '../../bloc/ui_bloc/ui_bloc.dart';
import '../../extensions/extension_host.dart';
import '../../terminal/terminal.dart';
import '../../utils/languages.dart';
import '../../utils/functions.dart';
import '../../utils/themes.dart';
import 'editor/status_bar.dart';
import 'widgets.dart';

// Preview panes (Image, SVG, PDF)
// Extracted from editor_page.dart

  Widget _buildImagePreviewPane(ActiveEditor editor, AppTheme appTheme) {
    return Container(
      color: appTheme.editorPageDrawerBg,
      alignment: Alignment.center,
      child: InteractiveViewer(
        minScale: 0.2,
        maxScale: 8,
        child: Image.file(
          editor.file,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image_outlined, size: 44),
                  const SizedBox(height: 8),
                  Text(
                    'Failed to load image preview',
                    style: TextStyle(color: appTheme.selectScreenCardTextColor),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSvgPreviewPane(ActiveEditor editor, AppTheme appTheme) {
    return _SvgPreviewPane(file: editor.file, appTheme: appTheme);
  }

  Widget _buildPreviewPane(ActiveEditor editor, AppTheme appTheme) {

class _PdfPreviewPane extends StatefulWidget {
  final String filePath;
  final AppTheme appTheme;

  const _PdfPreviewPane({
    required this.filePath,
    required this.appTheme,
  });

  @override
  State<_PdfPreviewPane> createState() => _PdfPreviewPaneState();
}

class _SvgPreviewPane extends StatefulWidget {
  final File file;
  final AppTheme appTheme;

  const _SvgPreviewPane({
    required this.file,
    required this.appTheme,
  });

  @override
  State<_SvgPreviewPane> createState() => _SvgPreviewPaneState();
}

class _SvgPreviewPaneState extends State<_SvgPreviewPane> {
  late Future<String> _svgTextFuture;

  @override
  void initState() {
    super.initState();
    _svgTextFuture = _loadSvgText();
  }

  @override
  void didUpdateWidget(covariant _SvgPreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _svgTextFuture = _loadSvgText();
    }
  }

  bool _isGzipData(Uint8List data) {
    return data.length >= 2 && data[0] == 0x1f && data[1] == 0x8b;
  }

  Future<String> _loadSvgText() async {
    if (!await widget.file.exists()) {
      throw Exception('SVG file not found.');
    }

    final bytes = await widget.file.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('SVG file is empty.');
    }

    final ext = path.extension(widget.file.path).toLowerCase();
    final shouldDecompress = ext == '.svgz' || _isGzipData(bytes);

    final rawBytes = shouldDecompress
        ? Uint8List.fromList(gzip.decode(bytes))
        : bytes;

    final svgText = utf8.decode(rawBytes, allowMalformed: true);
    if (svgText.trim().isEmpty) {
      throw Exception('SVG content is empty.');
    }
    return svgText;
  }

  Widget _buildError(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined, size: 44),
          const SizedBox(height: 10),
          Text(
            'Failed to load SVG preview',
            style: TextStyle(
              color: widget.appTheme.selectScreenCardTextColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.appTheme.editorPageDrawerBg,
      alignment: Alignment.center,
      child: FutureBuilder<String>(
        future: _svgTextFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              width: 42,
              height: 42,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            );
          }

          if (snapshot.hasError) {
            return _buildError(snapshot.error.toString());
          }

          final svgText = snapshot.data;
          if (svgText == null || svgText.trim().isEmpty) {
            return _buildError('No SVG data available.');
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : 480.0;
              final maxHeight = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : 640.0;

              final viewWidth = maxWidth > 240 ? maxWidth * 0.92 : maxWidth;
              final viewHeight =
                  maxHeight > 240 ? maxHeight * 0.92 : maxHeight;

              return InteractiveViewer(
                minScale: 0.2,
                maxScale: 8,
                child: SizedBox(
                  width: viewWidth > 0 ? viewWidth : 320,
                  height: viewHeight > 0 ? viewHeight : 320,
                  child: SvgPicture.string(
                    svgText,
                    fit: BoxFit.contain,
                    allowDrawingOutsideViewBox: true,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _PdfPreviewPaneState extends State<_PdfPreviewPane> {
  bool _isReady = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    if (!File(widget.filePath).existsSync()) {
      return Center(
        child: Text(
          'PDF file not found.',
          style: TextStyle(color: widget.appTheme.selectScreenCardTextColor),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.picture_as_pdf_outlined, size: 44),
              const SizedBox(height: 8),
              Text(
                'Failed to load PDF preview',
                style: TextStyle(color: widget.appTheme.selectScreenCardTextColor),
              ),
              const SizedBox(height: 4),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        PDFView(
          key: ValueKey(widget.filePath),
          filePath: widget.filePath,
          enableSwipe: true,
          swipeHorizontal: false,
          autoSpacing: true,
          pageFling: true,
          fitPolicy: FitPolicy.BOTH,
          onRender: (_) {
            if (!mounted) return;
            setState(() {
              _isReady = true;
            });
          },
          onError: (error) {
            if (!mounted) return;
            setState(() {
              _errorMessage = error.toString();
              _isReady = true;
            });
          },
          onPageError: (page, error) {
            if (!mounted) return;
            setState(() {
              _errorMessage = 'Page $page: $error';
              _isReady = true;
            });
          },
        ),
        if (!_isReady)
          const Center(
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }
}