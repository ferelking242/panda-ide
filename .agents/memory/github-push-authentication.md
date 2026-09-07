---
name: GitHub push authentication
description: Reliable authenticated pushes to the Panda IDE GitHub repository from this workspace.
---

When publishing to GitHub from this workspace, the secure `GITHUB_PAT` secret may be present in the shell while Git's `http.extraheader` authentication still returns `invalid credentials`. The working form is an ephemeral Git URL rewrite using the token as the `x-access-token` password:

`git -c url."https://x-access-token:${GITHUB_PAT}@github.com/".insteadOf="https://github.com/" push origin HEAD:main`

**Why:** The header-based attempt was rejected even though the PAT was present and the same token succeeded through the URL rewrite.

**How to apply:** Keep the token out of remotes, command output, commits, and chat. Use the secure secret flow first, then apply the rewrite only to the single push command.