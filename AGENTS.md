## Imported Claude Cowork project instructions

## Backpass-derived reliability guidance

- Do not mark an unresolved reliability case solved or remove it from its checklist until a focused reproduction or test verifies the exact failure mode and its recovery behavior.
- Inspect the current survey model and setup flow before basing an implementation recommendation on existing user inputs.
- For reliability issues involving persisted state and external system state, implement and test reconciliation across fresh install, restore, reinstall, and account-switch scenarios before marking the issue fixed.
- Before recommending behavior for a reliability issue, trace every relevant scheduler caller and state transition, then state one consistent policy tied to the verified execution paths.
