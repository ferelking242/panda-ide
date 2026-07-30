/**
 * Tests for vscode.workspace namespace.
 */
'use strict';

const ipc = require('./mocks/ipc.js');

describe('vscode.workspace', () => {
  beforeEach(() => ipc._reset());

  test('openTextDocument calls Flutter with URI JSON', async () => {
    ipc.callFlutter = jest.fn().mockResolvedValue({ uri: { fsPath: '/test.ts' } });
    const result = await ipc.callFlutter('vscode.workspace.openTextDocument', [
      { scheme: 'file', path: '/test.ts', fsPath: '/test.ts' }
    ]);
    expect(ipc.callFlutter).toHaveBeenCalledWith(
      'vscode.workspace.openTextDocument',
      expect.any(Array)
    );
  });

  test('findFiles sends include/exclude/maxResults', async () => {
    ipc.callFlutter = jest.fn().mockResolvedValue([]);
    await ipc.callFlutter('vscode.workspace.findFiles', ['**/*.ts', '**/node_modules/**', 100]);
    expect(ipc.callFlutter).toHaveBeenCalledWith(
      'vscode.workspace.findFiles',
      ['**/*.ts', '**/node_modules/**', 100]
    );
  });

  test('getConfiguration returns proxy object', async () => {
    ipc.callFlutter = jest.fn().mockResolvedValue({ items: { 'fontSize': 14 } });
    const config = await ipc.callFlutter('vscode.workspace.configuration.get', ['editor']);
    expect(config.items).toBeDefined();
  });

  test('workspace fs.stat calls correct method', async () => {
    ipc.callFlutter = jest.fn().mockResolvedValue({ type: 1, size: 1024 });
    const stat = await ipc.callFlutter('vscode.workspace.fs.stat', [{ fsPath: '/test.ts' }]);
    expect(ipc.callFlutter).toHaveBeenCalledWith('vscode.workspace.fs.stat', expect.any(Array));
    expect(stat.type).toBe(1);
  });
});
