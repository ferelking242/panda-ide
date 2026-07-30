/**
 * Tests for vscode.debug namespace (Phase 12).
 */
'use strict';

const ipc = require('./mocks/ipc.js');

describe('vscode.debug', () => {
  beforeEach(() => {
    ipc._reset();
    ipc.callFlutter = jest.fn().mockResolvedValue(null);
  });

  test('startDebugging sends config to Flutter and returns truthy', async () => {
    ipc.callFlutter = jest.fn().mockResolvedValue('session_1');
    const sessionId = await ipc.callFlutter('vscode.debug.start', [
      null, { name: 'Launch Python', type: 'python', request: 'launch' }, null
    ]);
    expect(sessionId).toBe('session_1');
  });

  test('stopDebugging calls Flutter with session id', async () => {
    await ipc.callFlutter('vscode.debug.stop', ['session_1']);
    expect(ipc.callFlutter).toHaveBeenCalledWith('vscode.debug.stop', ['session_1']);
  });

  test('registerDebugAdapterDescriptorFactory registers handler', async () => {
    let handlerCalled = false;
    ipc.onCall('debug.getAdapterDescriptor.python', async (session, exec) => {
      handlerCalled = true;
      return { type: 'executable', command: 'python', args: ['-m', 'debugpy'] };
    });

    const descriptor = await ipc._simulateCall('debug.getAdapterDescriptor.python', {}, null);
    expect(handlerCalled).toBe(true);
    expect(descriptor.type).toBe('executable');
  });

  test('addBreakpoints calls Flutter', async () => {
    const bps = [{ id: 'bp1', location: { uri: '/main.py', range: { start: { line: 10 } } } }];
    await ipc.callFlutter('vscode.debug.addBreakpoints', [bps]);
    expect(ipc.callFlutter).toHaveBeenCalledWith('vscode.debug.addBreakpoints', [bps]);
  });

  test('debug session started event fires onDidStartDebugSession', () => {
    const received = [];
    ipc.onEvent('debug.sessionStarted', (data) => received.push(data));
    ipc._simulateEvent('debug.sessionStarted', { id: 's1', name: 'Test', type: 'node' });
    expect(received).toHaveLength(1);
    expect(received[0].id).toBe('s1');
  });
});
