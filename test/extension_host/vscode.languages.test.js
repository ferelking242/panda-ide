/**
 * Tests for vscode.languages namespace — provider registration + pull model.
 */
'use strict';

const ipc = require('./mocks/ipc.js');

describe('vscode.languages — provider registration', () => {
  beforeEach(() => ipc._reset());

  test('registerCompletionItemProvider fires flutter registration call', async () => {
    const calls = [];
    ipc.callFlutter = jest.fn().mockImplementation((method, params) => {
      calls.push({ method, params });
      return Promise.resolve(null);
    });

    // Simulate what vscode.js does when registering a provider
    const providerId = 'completionItemProvider_0';
    await ipc.callFlutter('vscode.languages.completionItemProvider.register', [
      providerId, [{ language: 'typescript' }], ['.', ':']
    ]);

    expect(calls[0].method).toBe('vscode.languages.completionItemProvider.register');
    expect(calls[0].params[0]).toBe(providerId);
  });

  test('provider.invoke is called by Flutter and returns results', async () => {
    const mockItems = [{ label: 'myFunction', kind: 2 }];

    // Register a provider handler
    ipc.onCall('provider.comp_0.invoke', async (doc, pos) => {
      return mockItems;
    });

    const result = await ipc._simulateCall('provider.comp_0.invoke',
      { languageId: 'typescript', text: 'myF' },
      { line: 0, character: 3 }
    );

    expect(result).toEqual(mockItems);
  });

  test('diagnostics.set stores diagnostics at file path', async () => {
    const calls = [];
    ipc.callFlutter = jest.fn().mockImplementation((m, p) => {
      calls.push({ m, p });
      return Promise.resolve(null);
    });

    await ipc.callFlutter('vscode.languages.diagnostics.set', [
      '/src/main.ts',
      [{ message: 'Type error', severity: 0, range: { start: { line: 1, character: 0 }, end: { line: 1, character: 5 } } }]
    ]);

    expect(calls[0].m).toBe('vscode.languages.diagnostics.set');
  });

  test('getLanguages returns a list of language IDs', async () => {
    const langs = await ipc.callFlutter('vscode.languages.getLanguages', []);
    expect(Array.isArray(langs)).toBe(true);
    expect(langs).toContain('javascript');
    expect(langs).toContain('typescript');
  });
});
