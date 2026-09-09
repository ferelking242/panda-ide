---
name: GitHub AI providers
description: Durable distinction between GitHub Models and GitHub Copilot for Panda Agent integrations.
---

GitHub Models and GitHub Copilot are separate products. GitHub Models was retired on July 30, 2026, so it must not be presented as a current free provider. GitHub Copilot remains account- and plan-dependent; Panda should resolve its short-lived Copilot token and live model catalog at request time rather than persisting a token or inventing a static model list.

**Why:** A provider label that says “GitHub” is ambiguous and can create a broken integration or imply access that the user’s GitHub Free account does not have.

**How to apply:** Keep repository authentication separate from AI provider authentication, use the existing Copilot token exchange for Panda Agent, and surface GitHub/Copilot access or quota errors explicitly.