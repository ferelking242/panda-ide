/**
 * vscode Types — implémentation des classes de base de l'API VSCode.
 *
 * Ces classes sont instanciées par les extensions via new vscode.Uri(...) etc.
 * Elles sont pures JS (pas de dépendance Flutter) — la sérialisation
 * JSON est assurée par les méthodes toJSON() de chaque classe.
 */

'use strict';

// ── Position & Range ──────────────────────────────────────────────────────

class Position {
  constructor(line, character) {
    this.line      = line;
    this.character = character;
  }

  isBefore(other)          { return this.line < other.line || (this.line === other.line && this.character < other.character); }
  isBeforeOrEqual(other)   { return this.isBefore(other) || this.isEqual(other); }
  isAfter(other)           { return other.isBefore(this); }
  isAfterOrEqual(other)    { return other.isBeforeOrEqual(this); }
  isEqual(other)           { return this.line === other.line && this.character === other.character; }
  compareTo(other)         { return this.isBefore(other) ? -1 : this.isEqual(other) ? 0 : 1; }
  translate(lineDelta = 0, characterDelta = 0) {
    return new Position(this.line + lineDelta, this.character + characterDelta);
  }
  with(line = this.line, character = this.character) { return new Position(line, character); }
  toJSON() { return { line: this.line, character: this.character }; }
}

class Range {
  constructor(startOrLine, endOrCharacter, endLine, endCharacter) {
    if (startOrLine instanceof Position) {
      this.start = startOrLine;
      this.end   = endOrCharacter;
    } else {
      this.start = new Position(startOrLine, endOrCharacter);
      this.end   = new Position(endLine, endCharacter);
    }
    // Normalise start ≤ end
    if (this.end.isBefore(this.start)) {
      [this.start, this.end] = [this.end, this.start];
    }
  }

  get isEmpty()        { return this.start.isEqual(this.end); }
  get isSingleLine()   { return this.start.line === this.end.line; }

  contains(positionOrRange) {
    if (positionOrRange instanceof Range) {
      return this.contains(positionOrRange.start) && this.contains(positionOrRange.end);
    }
    return positionOrRange.isAfterOrEqual(this.start) && positionOrRange.isBeforeOrEqual(this.end);
  }

  isEqual(other) { return this.start.isEqual(other.start) && this.end.isEqual(other.end); }

  intersection(range) {
    const start = this.start.isAfter(range.start) ? this.start : range.start;
    const end   = this.end.isBefore(range.end)    ? this.end   : range.end;
    if (start.isAfterOrEqual(end)) return undefined;
    return new Range(start, end);
  }

  union(other) {
    const start = this.start.isBefore(other.start) ? this.start : other.start;
    const end   = this.end.isAfter(other.end)       ? this.end   : other.end;
    return new Range(start, end);
  }

  with(start = this.start, end = this.end) { return new Range(start, end); }
  toJSON() { return { start: this.start.toJSON(), end: this.end.toJSON() }; }
}

class Selection extends Range {
  constructor(anchorOrLine, activeOrCharacter, activeLine, activeCharacter) {
    if (anchorOrLine instanceof Position) {
      super(anchorOrLine, activeOrCharacter);
      this.anchor = anchorOrLine;
      this.active = activeOrCharacter;
    } else {
      super(anchorOrLine, activeOrCharacter, activeLine, activeCharacter);
      this.anchor = new Position(anchorOrLine, activeOrCharacter);
      this.active = new Position(activeLine, activeCharacter);
    }
  }
  get isReversed() { return this.active.isBefore(this.anchor); }
  toJSON() {
    return { ...super.toJSON(), anchor: this.anchor.toJSON(), active: this.active.toJSON() };
  }
}

// ── Uri ───────────────────────────────────────────────────────────────────

class Uri {
  constructor(scheme, authority, path, query, fragment) {
    this.scheme    = scheme    || '';
    this.authority = authority || '';
    this.path      = path      || '';
    this.query     = query     || '';
    this.fragment  = fragment  || '';
  }

  static parse(value) {
    // Parsing simplifié — couvre les cas courants (file://, https://)
    const m = value.match(/^([a-zA-Z][a-zA-Z0-9+\-.]*):\/\/([^/?#]*)([^?#]*)(?:\?([^#]*))?(?:#(.*))?$/);
    if (m) return new Uri(m[1], m[2], m[3], m[4] || '', m[5] || '');
    // file path sans scheme
    if (value.startsWith('/')) return Uri.file(value);
    return new Uri('', '', value, '', '');
  }

  static file(path) {
    return new Uri('file', '', path.replace(/\\/g, '/'), '', '');
  }

  static joinPath(base, ...pathSegments) {
    const joined = [base.path, ...pathSegments].join('/').replace(/\/+/g, '/');
    return new Uri(base.scheme, base.authority, joined, '', '');
  }

  with({ scheme, authority, path, query, fragment } = {}) {
    return new Uri(
      scheme    !== undefined ? scheme    : this.scheme,
      authority !== undefined ? authority : this.authority,
      path      !== undefined ? path      : this.path,
      query     !== undefined ? query     : this.query,
      fragment  !== undefined ? fragment  : this.fragment,
    );
  }

  get fsPath() {
    // Retourne le chemin filesystem (sans scheme)
    return this.path;
  }

  toString(skipEncoding = false) {
    let result = this.scheme ? `${this.scheme}:` : '';
    if (this.authority || this.scheme === 'file') result += `//${this.authority}`;
    result += this.path;
    if (this.query)    result += `?${this.query}`;
    if (this.fragment) result += `#${this.fragment}`;
    return result;
  }

  toJSON() {
    return { scheme: this.scheme, authority: this.authority, path: this.path,
             query: this.query, fragment: this.fragment, fsPath: this.fsPath };
  }
}

// ── Disposable ────────────────────────────────────────────────────────────

class Disposable {
  constructor(callOnDispose) {
    this._callOnDispose = callOnDispose;
  }
  dispose() {
    if (typeof this._callOnDispose === 'function') this._callOnDispose();
  }
  static from(...disposables) {
    return new Disposable(() => {
      for (const d of disposables) if (d && typeof d.dispose === 'function') d.dispose();
    });
  }
}

// ── EventEmitter ─────────────────────────────────────────────────────────

class EventEmitter {
  constructor() {
    this._listeners = [];
    this.event = (listener, thisArg, disposables) => {
      this._listeners.push({ listener, thisArg });
      const d = new Disposable(() => {
        this._listeners = this._listeners.filter(l => l.listener !== listener);
      });
      if (Array.isArray(disposables)) disposables.push(d);
      return d;
    };
  }
  fire(data) {
    for (const { listener, thisArg } of [...this._listeners]) {
      try { listener.call(thisArg, data); } catch (e) { /* ignore */ }
    }
  }
  dispose() { this._listeners = []; }
}

// ── Enums VSCode ──────────────────────────────────────────────────────────

const ViewColumn = Object.freeze({
  Active: -1, Beside: -2, One: 1, Two: 2, Three: 3,
  Four: 4, Five: 5, Six: 6, Seven: 7, Eight: 8, Nine: 9,
});

const StatusBarAlignment = Object.freeze({ Left: 1, Right: 2 });

const DiagnosticSeverity = Object.freeze({ Error: 0, Warning: 1, Information: 2, Hint: 3 });

const DiagnosticTag = Object.freeze({ Unnecessary: 1, Deprecated: 2 });

const CompletionItemKind = Object.freeze({
  Text: 0, Method: 1, Function: 2, Constructor: 3, Field: 4, Variable: 5,
  Class: 6, Interface: 7, Module: 8, Property: 9, Unit: 10, Value: 11,
  Enum: 12, Keyword: 13, Snippet: 14, Color: 15, File: 16, Reference: 17,
  Folder: 18, EnumMember: 19, Constant: 20, Struct: 21, Event: 22,
  Operator: 23, TypeParameter: 24,
});

const CompletionItemTag = Object.freeze({ Deprecated: 1 });

const CompletionTriggerKind = Object.freeze({ Invoke: 0, TriggerCharacter: 1, TriggerForIncompleteCompletions: 2 });

const SymbolKind = Object.freeze({
  File: 0, Module: 1, Namespace: 2, Package: 3, Class: 4, Method: 5, Property: 6,
  Field: 7, Constructor: 8, Enum: 9, Interface: 10, Function: 11, Variable: 12,
  Constant: 13, String: 14, Number: 15, Boolean: 16, Array: 17, Object: 18,
  Key: 19, Null: 20, EnumMember: 21, Struct: 22, Event: 23, Operator: 24, TypeParameter: 25,
});

const CodeActionKind = {
  Empty: '', QuickFix: 'quickfix', Refactor: 'refactor',
  RefactorExtract: 'refactor.extract', RefactorInline: 'refactor.inline',
  RefactorRewrite: 'refactor.rewrite', Source: 'source',
  SourceOrganizeImports: 'source.organizeImports', SourceFixAll: 'source.fixAll',
};

const TextEditorRevealType = Object.freeze({ Default: 0, InCenter: 1, InCenterIfOutsideViewport: 2, AtTop: 3 });

const OverviewRulerLane = Object.freeze({ Left: 1, Center: 2, Right: 4, Full: 7 });

const FileType = Object.freeze({ Unknown: 0, File: 1, Directory: 2, SymbolicLink: 64 });

const EndOfLine = Object.freeze({ LF: 1, CRLF: 2 });

const TextEditorCursorStyle = Object.freeze({
  Line: 1, Block: 2, Underline: 3, LineThin: 4, BlockOutline: 5, UnderlineThin: 6,
});

const TextEditorLineNumbersStyle = Object.freeze({ Off: 0, On: 1, Relative: 2, Interval: 3 });

const IndentAction = Object.freeze({ None: 0, Indent: 1, IndentOutdent: 2, Outdent: 3 });

const ProgressLocation = Object.freeze({ SourceControl: 1, Window: 10, Notification: 15 });

const ExtensionKind = Object.freeze({ UI: 1, Workspace: 2 });

const LogLevel = Object.freeze({ Off: 0, Trace: 1, Debug: 2, Info: 3, Warning: 4, Error: 5 });

const QuickPickItemKind = Object.freeze({ Separator: -1, Default: 0 });

// ── Diagnostic ────────────────────────────────────────────────────────────

class Diagnostic {
  constructor(range, message, severity = DiagnosticSeverity.Error) {
    this.range    = range;
    this.message  = message;
    this.severity = severity;
    this.source   = undefined;
    this.code     = undefined;
    this.tags     = [];
    this.relatedInformation = [];
  }
  toJSON() {
    return {
      range: this.range.toJSON(), message: this.message, severity: this.severity,
      source: this.source, code: this.code, tags: this.tags,
    };
  }
}

class DiagnosticRelatedInformation {
  constructor(location, message) {
    this.location = location;
    this.message  = message;
  }
}

class Location {
  constructor(uri, rangeOrPosition) {
    this.uri   = uri;
    this.range = rangeOrPosition instanceof Position
      ? new Range(rangeOrPosition, rangeOrPosition)
      : rangeOrPosition;
  }
  toJSON() { return { uri: this.uri.toJSON(), range: this.range.toJSON() }; }
}

// ── CompletionItem ────────────────────────────────────────────────────────

class CompletionItem {
  constructor(label, kind = CompletionItemKind.Text) {
    this.label            = label;
    this.kind             = kind;
    this.detail           = undefined;
    this.documentation    = undefined;
    this.sortText         = undefined;
    this.filterText       = undefined;
    this.preselect        = false;
    this.insertText       = undefined;
    this.range            = undefined;
    this.commitCharacters = [];
    this.keepWhitespace   = false;
    this.command          = undefined;
    this.tags             = [];
  }
}

class CompletionList {
  constructor(items = [], isIncomplete = false) {
    this.items        = items;
    this.isIncomplete = isIncomplete;
  }
}

// ── Hover & SignatureHelp ─────────────────────────────────────────────────

class Hover {
  constructor(contents, range) {
    this.contents = Array.isArray(contents) ? contents : [contents];
    this.range    = range;
  }
}

class MarkdownString {
  constructor(value = '', supportThemeIcons = false) {
    this.value             = value;
    this.isTrusted         = false;
    this.supportThemeIcons = supportThemeIcons;
    this.supportHtml       = false;
  }
  appendText(value)     { this.value += value.replace(/[\\`*_{}[\]()#+\-.!]/g, '\\$&'); return this; }
  appendMarkdown(value) { this.value += value; return this; }
  appendCodeblock(value, language = '') { this.value += `\n\`\`\`${language}\n${value}\n\`\`\`\n`; return this; }
}

// ── TextEdit & WorkspaceEdit ──────────────────────────────────────────────

class TextEdit {
  constructor(range, newText) {
    this.range   = range;
    this.newText = newText;
  }
  static replace(range, newText)              { return new TextEdit(range, newText); }
  static insert(position, newText)            { return new TextEdit(new Range(position, position), newText); }
  static delete(range)                        { return new TextEdit(range, ''); }
  static setEndOfLine(eol)                    { const e = new TextEdit(new Range(0, 0, 0, 0), ''); e._eol = eol; return e; }
  toJSON() { return { range: this.range.toJSON(), newText: this.newText }; }
}

class WorkspaceEdit {
  constructor() { this._edits = []; this._metadata = new Map(); }
  replace(uri, range, newText, metadata)    { this._edits.push({ type: 'replace', uri, range, newText }); }
  insert(uri, position, newText, metadata)  { this._edits.push({ type: 'insert', uri, position, newText }); }
  delete(uri, range, metadata)              { this._edits.push({ type: 'delete', uri, range }); }
  has(uri)    { return this._edits.some(e => e.uri.toString() === uri.toString()); }
  set(uri, edits) { for (const e of edits) this._edits.push({ uri, ...e }); }
  get(uri)    { return this._edits.filter(e => e.uri.toString() === uri.toString()); }
  entries()   { return this._edits; }
  get size()  { return this._edits.length; }
  toJSON()    { return this._edits.map(e => ({ ...e, uri: e.uri?.toJSON?.() ?? e.uri })); }
}

// ── CodeAction ────────────────────────────────────────────────────────────

class CodeAction {
  constructor(title, kind) {
    this.title       = title;
    this.kind        = kind;
    this.diagnostics = [];
    this.edit        = undefined;
    this.command     = undefined;
    this.isPreferred = false;
  }
}

// ── CodeLens ─────────────────────────────────────────────────────────────

class CodeLens {
  constructor(range, command) {
    this.range   = range;
    this.command = command;
  }
  get isResolved() { return !!this.command; }
}

// ── SymbolInformation & DocumentSymbol ───────────────────────────────────

class SymbolInformation {
  constructor(name, kind, containerName, locationOrUri, range) {
    this.name          = name;
    this.kind          = kind;
    this.containerName = containerName;
    if (locationOrUri instanceof Location) {
      this.location = locationOrUri;
    } else {
      this.location = new Location(locationOrUri, range);
    }
  }
}

class DocumentSymbol {
  constructor(name, detail, kind, range, selectionRange) {
    this.name           = name;
    this.detail         = detail;
    this.kind           = kind;
    this.range          = range;
    this.selectionRange = selectionRange;
    this.children       = [];
  }
}

// ── StatusBarItem (stub) ──────────────────────────────────────────────────

class StatusBarItem {
  constructor(id, alignment, priority, ipc) {
    this.id        = id;
    this.alignment = alignment;
    this.priority  = priority;
    this._ipc      = ipc;
    this.text      = '';
    this.tooltip   = '';
    this.color     = undefined;
    this.command   = undefined;
    this._visible  = false;
  }
  show()    { this._visible = true;  this._sync(); }
  hide()    { this._visible = false; this._sync(); }
  dispose() { this._ipc.callFlutter('vscode.window.statusBarItem.dispose', [this.id]); }
  _sync()   { this._ipc.callFlutter('vscode.window.statusBarItem.update', [{ id: this.id, text: this.text, tooltip: this.tooltip, color: this.color, command: this.command, visible: this._visible }]); }
}

// ── OutputChannel (stub) ─────────────────────────────────────────────────

class OutputChannel {
  constructor(name, ipc) {
    this.name = name;
    this._ipc = ipc;
  }
  append(value)      { this._ipc.callFlutter('vscode.window.outputChannel.append',      [this.name, value]); }
  appendLine(value)  { this._ipc.callFlutter('vscode.window.outputChannel.appendLine',  [this.name, value]); }
  clear()            { this._ipc.callFlutter('vscode.window.outputChannel.clear',        [this.name]); }
  show(preserveFocus) { this._ipc.callFlutter('vscode.window.outputChannel.show',        [this.name, !!preserveFocus]); }
  hide()             { this._ipc.callFlutter('vscode.window.outputChannel.hide',         [this.name]); }
  dispose()          { this._ipc.callFlutter('vscode.window.outputChannel.dispose',      [this.name]); }
}

// ── FileSystemWatcher (stub) ──────────────────────────────────────────────

class FileSystemWatcher {
  constructor(globPattern, ipc) {
    this.globPattern = globPattern;
    this._ipc        = ipc;
    const em1 = new EventEmitter();
    const em2 = new EventEmitter();
    const em3 = new EventEmitter();
    this.onDidCreate = em1.event;
    this.onDidChange = em2.event;
    this.onDidDelete = em3.event;
    this._emitters   = [em1, em2, em3];
    this.ignoreCreateEvents = false;
    this.ignoreChangeEvents = false;
    this.ignoreDeleteEvents = false;
  }
  dispose() {
    this._ipc.callFlutter('vscode.workspace.fileWatcher.dispose', [this.globPattern]);
    this._emitters.forEach(e => e.dispose());
  }
}

// ── DiagnosticCollection ─────────────────────────────────────────────────

class DiagnosticCollection {
  constructor(name, ipc) {
    this.name = name;
    this._ipc = ipc;
    this._map = new Map();
  }
  set(uri, diagnostics) {
    const key = uri.toString();
    if (diagnostics == null) {
      this._map.delete(key);
    } else {
      this._map.set(key, diagnostics);
    }
    this._ipc.callFlutter('vscode.languages.diagnostics.set', [
      this.name, key, diagnostics ? diagnostics.map(d => d.toJSON()) : null,
    ]);
  }
  delete(uri)  { this.set(uri, null); }
  clear()      { this._map.clear(); this._ipc.callFlutter('vscode.languages.diagnostics.clear', [this.name]); }
  forEach(cb)  { this._map.forEach((diags, uriStr) => cb(Uri.parse(uriStr), diags, this)); }
  get(uri)     { return this._map.get(uri.toString()); }
  has(uri)     { return this._map.has(uri.toString()); }
  dispose()    { this.clear(); }
}

module.exports = {
  Position, Range, Selection, Uri, Disposable, EventEmitter,
  ViewColumn, StatusBarAlignment, DiagnosticSeverity, DiagnosticTag,
  CompletionItemKind, CompletionItemTag, CompletionTriggerKind,
  SymbolKind, CodeActionKind, TextEditorRevealType, OverviewRulerLane,
  FileType, EndOfLine, TextEditorCursorStyle, TextEditorLineNumbersStyle,
  IndentAction, ProgressLocation, ExtensionKind, LogLevel, QuickPickItemKind,
  Diagnostic, DiagnosticRelatedInformation, Location,
  CompletionItem, CompletionList, Hover, MarkdownString,
  TextEdit, WorkspaceEdit, CodeAction, CodeLens,
  SymbolInformation, DocumentSymbol,
  StatusBarItem, OutputChannel, FileSystemWatcher, DiagnosticCollection,
};
