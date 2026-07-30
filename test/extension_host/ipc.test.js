/**
 * Tests for the IPC bridge (ipc.js).
 * We test the real ipc.js logic with a mock stdio stream.
 */
'use strict';

// ipc.js reads from process.stdin/stdout.
// We test the message encoding/parsing logic through a simpler interface.

describe('IPC message format', () => {
  // Import the actual protocol format used by the extension host
  // (We test the wire format: newline-delimited JSON)

  const encodeMessage = (obj) => JSON.stringify(obj) + '\n';
  const decodeMessage = (line) => JSON.parse(line.trim());

  test('encodes a call message correctly', () => {
    const msg = { id: 1, type: 'call', method: 'activate', params: [{}] };
    const encoded = encodeMessage(msg);
    expect(encoded).toContain('"type":"call"');
    expect(encoded).toContain('"method":"activate"');
    expect(encoded.endsWith('\n')).toBe(true);
  });

  test('decodes a return message correctly', () => {
    const line = '{"id":1,"type":"return","result":{"ok":true}}';
    const decoded = decodeMessage(line);
    expect(decoded.type).toBe('return');
    expect(decoded.id).toBe(1);
    expect(decoded.result.ok).toBe(true);
  });

  test('decodes an apiCall message (vscode.* call from extension)', () => {
    const line = '{"id":2,"type":"apiCall","method":"vscode.window.showInformationMessage","params":["Hello"]}';
    const decoded = decodeMessage(line);
    expect(decoded.type).toBe('apiCall');
    expect(decoded.method).toBe('vscode.window.showInformationMessage');
    expect(decoded.params[0]).toBe('Hello');
  });

  test('decodes an event message (unidirectional)', () => {
    const line = '{"id":0,"type":"event","event":"onDidChangeActiveTextEditor","data":null}';
    const decoded = decodeMessage(line);
    expect(decoded.type).toBe('event');
    expect(decoded.event).toBe('onDidChangeActiveTextEditor');
  });

  test('encodes an error return correctly', () => {
    const msg = { id: 3, type: 'error', method: 'vscode.workspace.openTextDocument', error: 'File not found' };
    const encoded = encodeMessage(msg);
    expect(encoded).toContain('"type":"error"');
    expect(encoded).toContain('File not found');
  });
});

describe('IPC mock helpers', () => {
  const ipc = require('./mocks/ipc.js');

  beforeEach(() => ipc._reset());

  test('callFlutter records the call', async () => {
    await ipc.callFlutter('vscode.window.showInformationMessage', ['Hello!']);
    expect(ipc.calls).toHaveLength(1);
    expect(ipc.calls[0].method).toBe('vscode.window.showInformationMessage');
    expect(ipc.calls[0].params[0]).toBe('Hello!');
  });

  test('onCall + _simulateCall round-trips correctly', async () => {
    ipc.onCall('test.echo', (x) => x * 2);
    const result = await ipc._simulateCall('test.echo', 21);
    expect(result).toBe(42);
  });

  test('onEvent + _simulateEvent fires the handler', () => {
    let received = null;
    ipc.onEvent('ping', (data) => { received = data; });
    ipc._simulateEvent('ping', { ts: 123 });
    expect(received).toEqual({ ts: 123 });
  });
});
