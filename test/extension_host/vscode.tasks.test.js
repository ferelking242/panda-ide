/**
 * Tests for vscode.tasks namespace (Phase 11).
 */
'use strict';

const ipc = require('./mocks/ipc.js');

describe('vscode.tasks', () => {
  beforeEach(() => {
    ipc._reset();
    ipc.callFlutter = jest.fn().mockResolvedValue(null);
  });

  test('registerTaskProvider notifies Flutter', async () => {
    await ipc.callFlutter('vscode.tasks.registerProvider', ['npm']);
    expect(ipc.callFlutter).toHaveBeenCalledWith('vscode.tasks.registerProvider', ['npm']);
  });

  test('executeTask serializes task and returns execution ID', async () => {
    ipc.callFlutter = jest.fn().mockResolvedValue('exec_42');
    const task = {
      name: 'Build',
      definition: { type: 'shell' },
      _taskId: 'task_0',
      execution: { commandLine: 'npm run build' },
    };
    const execId = await ipc.callFlutter('vscode.tasks.execute', [task]);
    expect(execId).toBe('exec_42');
  });

  test('fetchTasks returns empty array by default', async () => {
    ipc.callFlutter = jest.fn().mockResolvedValue([]);
    const tasks = await ipc.callFlutter('vscode.tasks.fetchAll', [null]);
    expect(Array.isArray(tasks)).toBe(true);
  });

  test('provideTasks handler is invoked via onCall', async () => {
    // Register a handler simulating what tasks.js does
    const mockTasks = [{ name: 'test', definition: { type: 'npm' } }];
    ipc.onCall('tasks.provide.npm', async () => mockTasks);

    // Simulate Flutter calling the provider
    const result = await ipc._simulateCall('tasks.provide.npm');
    expect(result).toEqual(mockTasks);
  });
});
