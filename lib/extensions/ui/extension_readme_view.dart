import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:markdown/markdown.dart' as md;

/// One README renderer for marketplace and installed extensions.
///
/// Rendering Markdown as HTML keeps GitHub-style constructs (tables, task
/// lists, nested links, emphasis and fenced code) together instead of relying
/// on the small default subset of MarkdownWidget.
class ExtensionReadmeView extends StatelessWidget {
  final String content;
  final bool isHtml;

  const ExtensionReadmeView({
    super.key,
    required this.content,
    this.isHtml = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: false,
        transparentBackground: true,
        supportZoom: true,
      ),
      initialData: InAppWebViewInitialData(
        data: extensionReadmeHtml(content, cs, isHtml: isHtml),
        mimeType: 'text/html',
        encoding: 'utf-8',
      ),
    );
  }
}

String extensionReadmeHtml(
  String content,
  ColorScheme cs, {
  bool isHtml = false,
}) {
  final background = _color(cs.surface);
  final foreground = _color(cs.onSurface);
  final muted = _color(cs.onSurfaceVariant);
  final source = isHtml
      ? (RegExp(r'<body\b[^>]*>([\s\S]*?)</body>', caseSensitive: false)
              .firstMatch(content)
              ?.group(1) ??
          content)
      : md.markdownToHtml(
          content,
          extensionSet: md.ExtensionSet.gitHubWeb,
          encodeHtml: false,
        );

  // A README is untrusted extension content. Keep formatting and links, but
  // do not execute scripts or inline event handlers in the WebView.
  final safe = source
      .replaceAll(
        RegExp(r'<script\b[^>]*>[\s\S]*?</script>', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(r'\son\w+\s*=\s*"[^"]*"', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(r"\son\w+\s*=\s*'[^']*'", caseSensitive: false),
        '',
      );

  return '''<!doctype html>
<html><head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root { color-scheme: ${cs.brightness == Brightness.dark ? 'dark' : 'light'}; }
body { background: $background; color: $foreground; font-family: sans-serif; font-size: 14px; line-height: 1.55; padding: 16px; margin: 0; overflow-wrap: anywhere; }
h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.1em 0 .55em; }
h1 { font-size: 1.7em; } h2 { font-size: 1.4em; } h3 { font-size: 1.2em; }
p, ul, ol, blockquote, table, pre { margin: .75em 0; }
ul, ol { padding-left: 1.6em; } li { margin: .2em 0; }
blockquote { border-left: 3px solid $muted; padding: .1em 1em; color: $muted; }
hr { border: 0; border-top: 1px solid $muted; opacity: .35; }
a { color: #5090c8; text-decoration: underline; }
img { max-width: 100%; height: auto; border-radius: 6px; }
pre { overflow-x: auto; padding: 12px; border-radius: 7px; background: rgba(127,127,127,.15); }
code { font-family: monospace; font-size: .92em; }
:not(pre) > code { padding: 2px 4px; border-radius: 4px; background: rgba(127,127,127,.15); }
table { border-collapse: collapse; width: 100%; display: block; overflow-x: auto; }
th, td { border: 1px solid $muted; padding: 6px 9px; text-align: left; }
th { background: rgba(127,127,127,.15); }
input[type="checkbox"] { accent-color: #5090c8; }
</style></head><body>$safe</body></html>''';
}

String _color(Color color) =>
    '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';