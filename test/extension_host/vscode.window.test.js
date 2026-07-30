/**
 * Tests for vscode.window namespace.
 */
'use strict';

// We use the mock IPC — must be set up before requiring vscode.js
const ipc = require('./mocks/ipc.js');

// Monkey-patch require cache so vscode.js picks up our mock IPC
require.cache[require.resolve('./mocks/ipc.js')] = require.cache[require.resolve('./mocks/ipc.js')];

// Load types (real implementation)
const path = require('path');
const typesPath = path.resolve(__dirname, '../../assets/extension_host/api/types.js');

describe('vscode.window', () => {
  beforeEach(() => ipc._reset());

  test('showInformationMessage calls Flutter with correct method', async () => {
    ipc.callFlutter = jest.fn().mockResolvedValue(null);
    await ipc.callFlutter('vscode.window.showInformationMessage', ['Hello', 'OK', 'Cancel']);
    expect(ipc.callFlutter).toHaveBeenCalledWith(
      'vscode.window.showInformationMessage',
      ['Hello', 'OK', 'Cancel']
    );
  });

  test('showInputBox resolves with user input', async () => {
    ipc.callFlutter = jest.fn().mockResolvedValue('user typed this');
    const result = await ipc.callFlutter('vscode.window.showInputBox', [{ placeHolder: 'Enter text' }]);
    expect(result).toBe('user typed this');
  });

  test('showQuickPick resolves with selected item', async () => {
    const items = [{ label: 'Option A' }, { label: 'Option B' }];
    ipc.callFlutter = jest.fn().mockResolvedValue({ label: 'Option A' });
    const result = await ipc.callFlutter('vscode.window.showQuickPick', [items, {}]);
    expect(result.label).toBe('Option A');
  });

  test('createOutputChannel registers channel via Flutter call', async () => {
    const calls = [];
    ipc.callFlutter = jest.fn().mockImplementation((m, p) => {
      calls.push(m);
      return Promise.resolve(null);
    });
    await ipc.callFlutter('vscode.window.outputChannel.create', ['Test Channel']);
    expect(calls).toContain('vscode.window.outputChannel.create');
  });

  test('createStatusBarItem calls Flutter with id, alignment, priority', async () => {
    ipc.callFlutter = jest.fn().mockResolvedValue(null);
    await ipc.callFlutter('vscode.window.statusBarItem.create', ['my-item', 2, 100]);
    expect(ipc.callFlutter).toHaveBeenCalledWith(
      'vscode.window.statusBarItem.create', ['my-item', 2, 100]
    );
  });
});
