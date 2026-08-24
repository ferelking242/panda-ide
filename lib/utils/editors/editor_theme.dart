import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:code_forge/code_forge.dart';
import 'package:cryptography/cryptography.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:path_provider/path_provider.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:panda/utils/themes.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../../terminal/terminal.dart';
import '../constants.dart';
import '../languages.dart';

// Custom editor theme and recent file normalization
// Extracted from functions.dart

class CustomEditorTheme {
  final Color bg, fg;
  final TextStyle keyword, literal, symbol, name, link, builtIn;
  final TextStyle type, number, class_, string, metaString, regexp;
  final TextStyle templateTag, subst, function, title, params;
  final TextStyle formula, comment, quote, doctag, meta, metaKeyword;
  final TextStyle tag, variable, templateVariable, attr, attribute;
  final TextStyle section, emphasis, strong, bullet, selectorTag;
  final TextStyle selectorId, selectorClass, selectorAttr, selectorPseudo;
  final TextStyle addition, deletion;

  const CustomEditorTheme({
    this.bg = const Color(0xff000000),
    this.fg = const Color(0xffffffff),
    this.keyword = const TextStyle(color: Colors.white),
    this.literal = const TextStyle(color: Colors.white),
    this.symbol = const TextStyle(color: Colors.white),
    this.name = const TextStyle(color: Colors.white),
    this.link = const TextStyle(color: Colors.white),
    this.builtIn = const TextStyle(color: Colors.white),
    this.type = const TextStyle(color: Colors.white),
    this.number = const TextStyle(color: Colors.white),
    this.class_ = const TextStyle(color: Colors.white),
    this.string = const TextStyle(color: Color(0xffD69D85)),
    this.metaString = const TextStyle(color: Color(0xffD69D85)),
    this.regexp = const TextStyle(color: Colors.white),
    this.templateTag = const TextStyle(color: Colors.white),
    this.subst = const TextStyle(color: Colors.white),
    this.function = const TextStyle(color: Colors.white),
    this.title = const TextStyle(color: Colors.white),
    this.params = const TextStyle(color: Colors.white),
    this.formula = const TextStyle(color: Colors.white),
    this.comment = const TextStyle(color: Colors.green),
    this.quote = const TextStyle(color: Color(0xffD69D85)),
    this.doctag = const TextStyle(color: Colors.white),
    this.meta = const TextStyle(color: Colors.white),
    this.metaKeyword = const TextStyle(color: Colors.white),
    this.tag = const TextStyle(color: Colors.white),
    this.variable = const TextStyle(color: Colors.white),
    this.templateVariable = const TextStyle(color: Colors.white),
    this.attr = const TextStyle(color: Colors.white),
    this.attribute = const TextStyle(color: Colors.white),
    this.section = const TextStyle(color: Colors.white),
    this.emphasis = const TextStyle(color: Colors.white),
    this.strong = const TextStyle(color: Colors.white),
    this.bullet = const TextStyle(color: Colors.white),
    this.selectorTag = const TextStyle(color: Colors.white),
    this.selectorId = const TextStyle(color: Colors.white),
    this.selectorClass = const TextStyle(color: Colors.white),
    this.selectorAttr = const TextStyle(color: Colors.white),
    this.selectorPseudo = const TextStyle(color: Colors.white),
    this.addition = const TextStyle(color: Colors.white),
    this.deletion = const TextStyle(color: Colors.white),
  });

  Map<String, TextStyle> toMap() => {
    'root': TextStyle(
      color: fg,
      backgroundColor: bg,
    ),
    'keyword': keyword,
    'literal': literal,
    'symbol': symbol,
    'name': name,
    'link': link,
    'built_in': builtIn,
    'type': type,
    'number': number,
    'class': class_,
    'string': string,
    'meta-string': metaString,
    'regexp': regexp,
    'template-tag': templateTag,
    'subst': subst,
    'function': function,
    'title': title,
    'params': params,
    'formula': formula,
    'comment': comment,
    'quote': quote,
    'doctag': doctag,
    'meta': meta,
    'meta-keyword': metaKeyword,
    'tag': tag,
    'variable': variable,
    'template-variable': templateVariable,
    'attr': attr,
    'attribute': attribute,
    'section': section,
    'emphasis': emphasis,
    'strong': strong,
    'bullet': bullet,
    'selector-tag': selectorTag,
    'selector-id': selectorId,
    'selector-class': selectorClass,
    'selector-attr': selectorAttr,
    'selector-pseudo': selectorPseudo,
    'addition': addition,
    'deletion': deletion,
  };

  Map<String, dynamic> toJson() => {
    "bg": bg.toARGB32(),
    "fg": fg.toARGB32(),
    "styles": {
      "keyword": _styleToJson(keyword),
      "literal": _styleToJson(literal),
      "symbol": _styleToJson(symbol),
      "name": _styleToJson(name),
      "link": _styleToJson(link),
      "built_in": _styleToJson(builtIn),
      "type": _styleToJson(type),
      "number": _styleToJson(number),
      "class": _styleToJson(class_),
      "string": _styleToJson(string),
      "meta-string": _styleToJson(metaString),
      "regexp": _styleToJson(regexp),
      "template-tag": _styleToJson(templateTag),
      "subst": _styleToJson(subst),
      "function": _styleToJson(function),
      "title": _styleToJson(title),
      "params": _styleToJson(params),
      "formula": _styleToJson(formula),
      "comment": _styleToJson(comment),
      "quote": _styleToJson(quote),
      "doctag": _styleToJson(doctag),
      "meta": _styleToJson(meta),
      "meta-keyword": _styleToJson(metaKeyword),
      "tag": _styleToJson(tag),
      "variable": _styleToJson(variable),
      "template-variable": _styleToJson(templateVariable),
      "attr": _styleToJson(attr),
      "attribute": _styleToJson(attribute),
      "section": _styleToJson(section),
      "emphasis": _styleToJson(emphasis),
      "strong": _styleToJson(strong),
      "bullet": _styleToJson(bullet),
      "selector-tag": _styleToJson(selectorTag),
      "selector-id": _styleToJson(selectorId),
      "selector-class": _styleToJson(selectorClass),
      "selector-attr": _styleToJson(selectorAttr),
      "selector-pseudo": _styleToJson(selectorPseudo),
      "addition": _styleToJson(addition),
      "deletion": _styleToJson(deletion),
    }
  };

  static CustomEditorTheme fromMap(Map<String, TextStyle> map) {
    final root = map['root'] ?? const TextStyle();

    return CustomEditorTheme(
      bg: root.backgroundColor ?? const Color(0xff000000),
      fg: root.color ?? const Color(0xffffffff),
      keyword: map['keyword'] ?? const TextStyle(color: Colors.white),
      literal: map['literal'] ?? const TextStyle(color: Colors.white),
      symbol: map['symbol'] ?? const TextStyle(color: Colors.white),
      name: map['name'] ?? const TextStyle(color: Colors.white),
      link: map['link'] ?? const TextStyle(color: Colors.white),
      builtIn: map['built_in'] ?? const TextStyle(color: Colors.white),
      type: map['type'] ?? const TextStyle(color: Colors.white),
      number: map['number'] ?? const TextStyle(color: Colors.white),
      class_: map['class'] ?? const TextStyle(color: Colors.white),
      string: map['string'] ?? const TextStyle(color: Colors.white),
      metaString: map['meta-string'] ?? const TextStyle(color: Colors.white),
      regexp: map['regexp'] ?? const TextStyle(color: Colors.white),
      templateTag: map['template-tag'] ?? const TextStyle(color: Colors.white),
      subst: map['subst'] ?? const TextStyle(color: Colors.white),
      function: map['function'] ?? const TextStyle(color: Colors.white),
      title: map['title'] ?? const TextStyle(color: Colors.white),
      params: map['params'] ?? const TextStyle(color: Colors.white),
      formula: map['formula'] ?? const TextStyle(color: Colors.white),
      comment: map['comment'] ?? const TextStyle(color: Colors.white),
      quote: map['quote'] ?? const TextStyle(color: Colors.white),
      doctag: map['doctag'] ?? const TextStyle(color: Colors.white),
      meta: map['meta'] ?? const TextStyle(color: Colors.white),
      metaKeyword: map['meta-keyword'] ?? const TextStyle(color: Colors.white),
      tag: map['tag'] ?? const TextStyle(color: Colors.white),
      variable: map['variable'] ?? const TextStyle(color: Colors.white),
      templateVariable: map['template-variable'] ?? const TextStyle(color: Colors.white),
      attr: map['attr'] ?? const TextStyle(color: Colors.white),
      attribute: map['attribute'] ?? const TextStyle(color: Colors.white),
      section: map['section'] ?? const TextStyle(color: Colors.white),
      emphasis: map['emphasis'] ?? const TextStyle(color: Colors.white),
      strong: map['strong'] ?? const TextStyle(color: Colors.white),
      bullet: map['bullet'] ?? const TextStyle(color: Colors.white),
      selectorTag: map['selector-tag'] ?? const TextStyle(color: Colors.white),
      selectorId: map['selector-id'] ?? const TextStyle(color: Colors.white),
      selectorClass: map['selector-class'] ?? const TextStyle(color: Colors.white),
      selectorAttr: map['selector-attr'] ?? const TextStyle(color: Colors.white),
      selectorPseudo: map['selector-pseudo'] ?? const TextStyle(color: Colors.white),
      addition: map['addition'] ?? const TextStyle(color: Colors.white),
      deletion: map['deletion'] ?? const TextStyle(color: Colors.white),
    );
  }

  factory CustomEditorTheme.fromJson(Map<String, dynamic> json) {
    final styles = json["styles"] as Map<String, dynamic>;

    TextStyle style(String key) => _styleFromJson(styles[key] as Map<String, dynamic>);

    return CustomEditorTheme(
      bg: Color(json["bg"]),
      fg: Color(json["fg"]),
      keyword: style("keyword"),
      literal: style("literal"),
      symbol: style("symbol"),
      name: style("name"),
      link: style("link"),
      builtIn: style("built_in"),
      type: style("type"),
      number: style("number"),
      class_: style("class"),
      string: style("string"),
      metaString: style("meta-string"),
      regexp: style("regexp"),
      templateTag: style("template-tag"),
      subst: style("subst"),
      function: style("function"),
      title: style("title"),
      params: style("params"),
      formula: style("formula"),
      comment: style("comment"),
      quote: style("quote"),
      doctag: style("doctag"),
      meta: style("meta"),
      metaKeyword: style("meta-keyword"),
      tag: style("tag"),
      variable: style("variable"),
      templateVariable: style("template-variable"),
      attr: style("attr"),
      attribute: style("attribute"),
      section: style("section"),
      emphasis: style("emphasis"),
      strong: style("strong"),
      bullet: style("bullet"),
      selectorTag: style("selector-tag"),
      selectorId: style("selector-id"),
      selectorClass: style("selector-class"),
      selectorAttr: style("selector-attr"),
      selectorPseudo: style("selector-pseudo"),
      addition: style("addition"),
      deletion: style("deletion"),
    );
  }

  Map<String, dynamic> _styleToJson(TextStyle style) => {
    "color": style.color?.toARGB32(),
    "backgroundColor": style.backgroundColor?.toARGB32(),
    "fontStyle": style.fontStyle?.name,
    "fontWeight": style.fontWeight?.value,
  };

  static TextStyle _styleFromJson(Map<String, dynamic> json) {
    return TextStyle(
      color: json["color"] != null ? Color(json["color"]) : null,
      backgroundColor: json["backgroundColor"] != null
        ? Color(json["backgroundColor"])
        : null,
      fontStyle: switch (json["fontStyle"]) {
        "italic" => FontStyle.italic,
        "normal" => FontStyle.normal,
        _ => null,
      },
      fontWeight: json["fontWeight"] != null
        ? FontWeight.values.firstWhere(
            (w) => w.value == json["fontWeight"],
          )
        : null,
    );
  }
}
/// Utilitaire partagé — normalise une entrée "récente" (recent files/folders)
/// vers le format canonique { type, path, rootDir }.
/// Retourne null si l'entrée est invalide.
Map<String, dynamic>? normalizeRecentEntry(dynamic rawEntry) {
  if (rawEntry is Map &&
      rawEntry['type'] is String &&
      rawEntry['path'] is String) {
    return {
      'type': rawEntry['type'],
      'path': rawEntry['path'],
      'rootDir': rawEntry['rootDir'] ?? rawEntry['path'],
    };
  }
  if (rawEntry is Map && rawEntry.length == 1) {
    final dynamic key = rawEntry.keys.first;
    if (key is String) {
      return {'type': 'file', 'path': key, 'rootDir': rawEntry[key]};
    }
  }
  return null;
}

Future<void> checkAndRequestMissingPermissions(BuildContext context) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

  final storagePermission = Platform.isAndroid &&
          ((Platform.operatingSystemVersion).contains('Android 11') ||
              _isAndroid11PlusSafer())
      ? Permission.manageExternalStorage
      : Permission.storage;

  final storageStatus = await storagePermission.status;
  final notifStatus = await Permission.notification.status;
  final overlayStatus = Platform.isAndroid
      ? await Permission.systemAlertWindow.status
      : PermissionStatus.granted;

  if (storageStatus != PermissionStatus.granted ||
      notifStatus != PermissionStatus.granted ||
      (Platform.isAndroid && overlayStatus != PermissionStatus.granted)) {
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xff181c24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      builder: (bCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: Color(0xff5090c8), size: 24),
                    SizedBox(width: 10),
                    Text(
                      'Permissions requises',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Certaines autorisations sont nécessaires pour que l\'IDE fonctionne à 100% (accès stockage pour PRoot/Alpine, notifications de build, superposition pour l\'Agent, etc.).',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 45,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xff5090c8),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      Navigator.of(bCtx).pop();
                      if (storageStatus != PermissionStatus.granted) {
                        await storagePermission.request();
                      }
                      if (notifStatus != PermissionStatus.granted) {
                        await Permission.notification.request();
                      }
                      if (Platform.isAndroid && overlayStatus != PermissionStatus.granted) {
                        await Permission.systemAlertWindow.request();
                      }
                    },
                    child: const Text('Accorder les autorisations manquantes'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

bool _isAndroid11PlusSafer() {
  try {
    return Platform.isAndroid;
  } catch (_) {
    return false;
  }
}
