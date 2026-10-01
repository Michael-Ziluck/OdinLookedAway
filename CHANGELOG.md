# Changelog

## 1.0.0 - Unpublished

- Override the current cheat-bypass getter and achievement eligibility gate.
- Suppress audited item, drop, and character cheat-field writes, including damage-based item marking.
- Clean loaded inventories, serialized item/container data, entity markers, and production queues at storage, load, save, and network boundaries.
- Preserve cheat-command execution without repeated confirmation; prevent new cheat-counter increments and clear the character cheat flag.
- Remove the achievement disqualification warning while preserving achievement objectives, statistics, and difficulty requirements.
- Include reproducible builds, offline checks, disabled publication scaffolding, and save-aware deployment/rollback tools.

In-game behavior and actual Steam achievement progress/unlocks are not yet verified.
