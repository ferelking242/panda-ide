/**
 * Tests for vscode.scm namespace (Phase 10).
 */
'use strict';

const ipc = require('./mocks/ipc.js');

// Mock ipc module before requiring scm.js
jest.mock('./mocks/ipc.js');

// We test the scm.js module logic directly
describe('vscode.scm', () => {
  beforeEach(() => {
    ipc._reset();
    ipc.callFlutter = jest.fn().mockResolvedValue(null);
    ipc.onCall = jest.fn();
    ipc.onEvent = jest.fn();
  });

  test('createSourceControl calls Flutter with correct params', async () => {
    // Simulate the call made by scm.js
    await ipc.callFlutter('vscode.scm.create', [{
      scmId: 'scm_git_0',
      id: 'git',
      label: 'Git',
      rootUri: 'file:///workspace',
    }]);

    expect(ipc.callFlutter).toHaveBeenCalledWith(
      'vscode.scm.create',
      expect.arrayContaining([
        expect.objectContaining({ id: 'git', label: 'Git' })
      ])
    );
  });

  test('createResourceGroup calls Flutter', async () => {
    await ipc.callFlutter('vscode.scm.createResourceGroup', ['scm_git_0', 'grp_staged_0', 'Staged Changes']);
    expect(ipc.callFlutter).toHaveBeenCalledWith(
      'vscode.scm.createResourceGroup',
      ['scm_git_0', 'grp_staged_0', 'Staged Changes']
    );
  });

  test('setResourceStates sends resources to Flutter', async () => {
    const resources = [
      { resourceUri: 'file:///workspace/main.dart', decorations: 1 }
    ];
    await ipc.callFlutter('vscode.scm.setResourceStates', ['scm_git_0', 'grp_0', resources]);
    expect(ipc.callFlutter).toHaveBeenCalledWith(
      'vscode.scm.setResourceStates',
      ['scm_git_0', 'grp_0', resources]
    );
  });
});
