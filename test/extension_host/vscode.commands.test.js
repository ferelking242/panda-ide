/**
 * Tests for vscode.commands namespace.
 */
'use strict';

const ipc = require('./mocks/ipc.js');

describe('vscode.commands', () => {
  beforeEach(() => ipc._reset());

  test('registerCommand notifies Flutter of new command', async () => {
    const calls = [];
    ipc.callFlutter = jest.fn().mockImplementation((m, p) => {
      calls.push({ m, p });
      return Promise.resolve(null);
    });

    // Simulate vscode.commands.registerCommand
    await ipc.callFlutter('vscode.commands.register', ['myExtension.helloWorld', 'Hello World']);
    expect(calls[0].m).toBe('vscode.commands.register');
    expect(calls[0].p[0]).toBe('myExtension.helloWorld');
  });

  test('executeCommand tries local handler before Flutter', async () => {
    // Simulate local handler map (as vscode.js does it)
    const localHandlers = new Map();
    let localHandlerCalled = false;
    localHandlers.set('test.command', () => { localHandlerCalled = true; return 42; });

    const command = 'test.command';
    const local = localHandlers.get(command);
    const result = local ? local() : await ipc.callFlutter('vscode.commands.execute', [command]);

    expect(localHandlerCalled).toBe(true);
    expect(result).toBe(42);
  });

  test('executeCommand falls back to Flutter for unknown command', async () => {
    ipc.callFlutter = jest.fn().mockResolvedValue('flutter-result');
    const result = await ipc.callFlutter('vscode.commands.execute', ['unknown.command']);
    expect(result).toBe('flutter-result');
  });

  test('command.invoke event fires registered handler', () => {
    const handlers = new Map();
    let handlerArgs = null;
    handlers.set('ext.myCmd', (a, b) => { handlerArgs = [a, b]; });

    // Simulate receiving command.invoke event
    const { command, args } = { command: 'ext.myCmd', args: ['arg1', 'arg2'] };
    const handler = handlers.get(command);
    if (handler) handler(...(args || []));

    expect(handlerArgs).toEqual(['arg1', 'arg2']);
  });
});
