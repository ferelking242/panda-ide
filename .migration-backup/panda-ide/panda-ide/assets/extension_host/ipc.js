/**
 * IPC bridge côté Node.js — newline-delimited JSON sur stdin/stdout.
 *
 * Flutter → Node.js : { id, type:"call",      method, params }
 * Node.js → Flutter : { id, type:"apiCall",   method, params }
 * Node.js → Flutter : { id, type:"ret",        result }
 * Node.js → Flutter : { id, type:"error",      error }
 * Flutter → Node.js : { id, type:"apiReturn",  result }
 * Flutter → Node.js : { id, type:"apiError",   error }
 * Any → Any          : { id:0, type:"event",   method, params }
 */

'use strict';

const readline = require('readline');

let _nextId = 1;
const _pendingApiCalls = new Map(); // id → { resolve, reject }
const _callHandlers    = new Map(); // method → async fn(params) → result
const _eventHandlers   = new Map(); // event  → [fn(data)]

// ── Envoi ─────────────────────────────────────────────────────────────────

function _send(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n');
}

/**
 * Appelle une API Flutter (vscode.*) et attend la réponse.
 * Retourne une Promise avec le résultat.
 */
function callFlutter(method, params = []) {
  return new Promise((resolve, reject) => {
    const id = _nextId++;
    _pendingApiCalls.set(id, { resolve, reject });
    _send({ id, type: 'apiCall', method, params });

    // Timeout de 30s pour les appels API
    setTimeout(() => {
      if (_pendingApiCalls.has(id)) {
        _pendingApiCalls.delete(id);
        reject(new Error(`API call "${method}" timed out after 30s`));
      }
    }, 30_000);
  });
}

/**
 * Émet un event vers Flutter (unidirectionnel).
 */
function fireEvent(event, data) {
  _send({ id: 0, type: 'event', method: event, params: data !== undefined ? [data] : [] });
}

// ── Enregistrement de handlers ────────────────────────────────────────────

/**
 * Enregistre un handler pour un call venant de Flutter.
 * (ex: 'activate', 'deactivate', ou tout event éditeur)
 */
function onCall(method, handler) {
  _callHandlers.set(method, handler);
}

/**
 * Écoute un event venant de Flutter.
 */
function onEvent(event, handler) {
  if (!_eventHandlers.has(event)) _eventHandlers.set(event, []);
  _eventHandlers.get(event).push(handler);
}

// ── Réception ─────────────────────────────────────────────────────────────

const _rl = readline.createInterface({
  input: process.stdin,
  crlfDelay: Infinity,
  terminal: false,
});

_rl.on('line', (line) => {
  if (!line.trim()) return;

  let msg;
  try {
    msg = JSON.parse(line);
  } catch (e) {
    return; // ligne non-JSON ignorée
  }

  switch (msg.type) {
    case 'call': {
      // Flutter appelle une méthode de l'extension (activate, deactivate, etc.)
      const handler = _callHandlers.get(msg.method);
      if (!handler) {
        _send({ id: msg.id, type: 'error', method: msg.method,
                error: `No handler registered for "${msg.method}"` });
        return;
      }
      Promise.resolve()
        .then(() => handler(...(msg.params || [])))
        .then((result) => _send({ id: msg.id, type: 'ret', method: msg.method, result: result ?? null }))
        .catch((err) => _send({ id: msg.id, type: 'error', method: msg.method,
                                 error: err?.message || String(err) }));
      break;
    }

    case 'apiReturn': {
      // Flutter répond à un de nos apiCall
      const pending = _pendingApiCalls.get(msg.id);
      if (pending) {
        _pendingApiCalls.delete(msg.id);
        pending.resolve(msg.result);
      }
      break;
    }

    case 'error': {
      // Flutter signale une erreur sur un de nos apiCall
      const pending = _pendingApiCalls.get(msg.id);
      if (pending) {
        _pendingApiCalls.delete(msg.id);
        pending.reject(new Error(msg.error || 'Unknown error from Flutter'));
      }
      break;
    }

    case 'event': {
      // Event venant de Flutter (onDidChangeTextDocument, etc.)
      const handlers = _eventHandlers.get(msg.method) || [];
      const data = msg.params?.[0];
      for (const h of handlers) {
        try { h(data); } catch (e) {
          // ignore erreurs dans event handlers pour ne pas bloquer le bridge
        }
      }
      break;
    }

    default:
      break;
  }
});

_rl.on('close', () => {
  // stdin fermé = Flutter a fermé la connexion → on sort proprement
  process.exit(0);
});

module.exports = { callFlutter, fireEvent, onCall, onEvent };
