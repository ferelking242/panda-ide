/**
 * tasks.js — API vscode.tasks — Phase 11.
 *
 * Permet aux extensions d'enregistrer des task providers et d'exécuter des tâches.
 * Les tâches sont exécutées via le terminal flutter_pty de l'IDE.
 *
 * Référence : https://code.visualstudio.com/api/extension-guides/task-provider
 */

'use strict';

const ipc = require('../ipc.js');

let _taskCounter = 0;

// ── Task proxy ────────────────────────────────────────────────────────────────

/**
 * Wraps a task object from an extension.
 * Assigns a stable _taskId for tracking across IPC calls.
 */
function wrapTask(task) {
  if (!task) return null;
  if (!task._taskId) {
    task._taskId = `task_${_taskCounter++}`;
  }
  return task;
}

// ── TaskExecution proxy ───────────────────────────────────────────────────────

function createTaskExecutionProxy(execId, task) {
  return {
    terminate() {
      ipc.callFlutter('vscode.tasks.terminate', [execId]).catch(() => {});
    },
    get task() { return task; },
    _execId: execId,
  };
}

// ── State ─────────────────────────────────────────────────────────────────────

const _taskProviders = new Map(); // type → provider
const _taskExecutions = new Map(); // execId → execution proxy
const _onDidStartTask_emitters = [];
const _onDidEndTask_emitters = [];
const _onDidStartTaskProcess_emitters = [];
const _onDidEndTaskProcess_emitters = [];

function _makeTaskEvent(emitters) {
  return (listener) => {
    emitters.push(listener);
    return { dispose: () => { const i = emitters.indexOf(listener); if (i >= 0) emitters.splice(i, 1); } };
  };
}

function _fireEvent(emitters, data) {
  for (const l of emitters) {
    try { l(data); } catch (e) {}
  }
}

// Listen for task events from Flutter
ipc.onEvent('task.started', ({ execId, taskId }) => {
  const exec = _taskExecutions.get(execId);
  if (exec) _fireEvent(_onDidStartTask_emitters, { execution: exec });
});

ipc.onEvent('task.ended', ({ execId, exitCode }) => {
  const exec = _taskExecutions.get(execId);
  if (exec) {
    _fireEvent(_onDidEndTask_emitters, { execution: exec });
    _taskExecutions.delete(execId);
  }
});

// ── API publique ────────────────────────────────────────────────────────────

const tasks = {
  /**
   * vscode.tasks.registerTaskProvider(type, provider)
   * provider.provideTasks() → Task[]
   * provider.resolveTask(task) → Task
   */
  registerTaskProvider(type, provider) {
    _taskProviders.set(type, provider);

    // Notify Flutter that a provider is registered for this task type
    ipc.callFlutter('vscode.tasks.registerProvider', [type]).catch(() => {});

    // Handle Flutter requesting task list for this type
    ipc.onCall(`tasks.provide.${type}`, async () => {
      try {
        const taskList = await provider.provideTasks() ?? [];
        const wrapped = taskList.map(wrapTask).filter(Boolean);
        // Report to Flutter
        ipc.callFlutter('vscode.tasks.providerResult', [type, wrapped.map(_serializeTask)])
          .catch(() => {});
        return wrapped.map(_serializeTask);
      } catch (e) {
        process.stderr.write(`[vscode.tasks] provideTasks(${type}) error: ${e?.message ?? e}\n`);
        return [];
      }
    });

    // Handle Flutter requesting task resolution
    ipc.onCall(`tasks.resolve.${type}`, async (taskJson) => {
      if (!provider.resolveTask) return taskJson;
      try {
        const resolved = await provider.resolveTask(taskJson);
        return resolved ? _serializeTask(wrapTask(resolved)) : taskJson;
      } catch (e) {
        return taskJson;
      }
    });

    return {
      dispose() {
        _taskProviders.delete(type);
        ipc.callFlutter('vscode.tasks.unregisterProvider', [type]).catch(() => {});
      },
    };
  },

  /**
   * vscode.tasks.fetchTasks(filter?)
   * Returns a list of all tasks from all providers.
   */
  fetchTasks(filter) {
    return ipc.callFlutter('vscode.tasks.fetchAll', [filter ?? null]);
  },

  /**
   * vscode.tasks.executeTask(task)
   * Returns a TaskExecution.
   */
  async executeTask(task) {
    const wrapped = wrapTask(task);
    if (!wrapped) return null;

    const serialized = _serializeTask(wrapped);
    try {
      const execId = await ipc.callFlutter('vscode.tasks.execute', [serialized]);
      if (!execId) return null;
      const execution = createTaskExecutionProxy(execId, wrapped);
      _taskExecutions.set(execId, execution);
      return execution;
    } catch (e) {
      process.stderr.write(`[vscode.tasks] executeTask error: ${e?.message ?? e}\n`);
      return null;
    }
  },

  get taskExecutions() {
    return Array.from(_taskExecutions.values());
  },

  onDidStartTask: _makeTaskEvent(_onDidStartTask_emitters),
  onDidEndTask: _makeTaskEvent(_onDidEndTask_emitters),
  onDidStartTaskProcess: _makeTaskEvent(_onDidStartTaskProcess_emitters),
  onDidEndTaskProcess: _makeTaskEvent(_onDidEndTaskProcess_emitters),
};

// ── Serializer helper ─────────────────────────────────────────────────────────

function _serializeTask(task) {
  if (!task) return null;
  const exec = task.execution ?? {};
  return {
    name: task.name ?? 'Task',
    type: task.definition?.type ?? task.type ?? 'shell',
    detail: task.detail,
    group: task.group ?? null,
    isBackground: task.isBackground ?? false,
    _taskId: task._taskId,
    execution: {
      command: exec.commandLine ?? exec.command ?? null,
      args: exec.args ?? [],
      cwd: exec.options?.cwd ?? null,
      env: exec.options?.env ?? {},
    },
    presentation: task.presentationOptions ?? {},
    problemMatchers: task.problemMatchers ?? [],
  };
}

module.exports = tasks;
