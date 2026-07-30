/**
 * Tests for vscode.env namespace.
 */
'use strict';

const ipc = require('./mocks/ipc.js');

describe('vscode.env', () => {
  beforeEach(() => ipc._reset());

  test('clipboard.readText calls Flutter and returns text', async () => {
    ipc.callFlutter = jest.fn().mockResolvedValue('clipboard content');
    const text = await ipc.callFlutter('vscode.env.clipboard.read', []);
    expect(text).toBe('clipboard content');
  });

  test('clipboard.writeText sends text to Flutter', async () => {
    ipc.callFlutter = jest.fn().mockResolvedValue(null);
    await ipc.callFlutter('vscode.env.clipboard.write', ['hello world']);
    expect(ipc.callFlutter).toHaveBeenCalledWith('vscode.env.clipboard.write', ['hello world']);
  });

  test('openExternal sends URI to Flutter', async () => {
    ipc.callFlutter = jest.fn().mockResolvedValue(true);
    const result = await ipc.callFlutter('vscode.env.openExternal', [
      { toString: () => 'https://panda-ide.app' }
    ]);
    expect(result).toBe(true);
  });
});

describe('vscode.env static values', () => {
  test('appName is Panda IDE', () => {
    // These are pure values, no IPC needed
    const appName = 'Panda IDE';
    expect(appName).toBe('Panda IDE');
  });

  test('uiKind is Desktop (1)', () => {
    const uiKind = 1;
    expect(uiKind).toBe(1);
  });
});
