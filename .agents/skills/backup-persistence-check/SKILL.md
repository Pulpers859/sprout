---
name: backup-persistence-check
description: Check local persistence, backup import/export, and schema-default safety when work touches saved budget data.
when_to_use: Use for changes involving JSONEncoder/Decoder, UserDefaults, localStorage, Firebase merge logic, backup import/export, or snapshot schema changes.
---

The goal is to prevent silent data loss and fragile restores.

Steps:

1. Identify the storage path involved:
   - iOS local JSON file
   - iOS backup document import/export
   - web local cache
   - web Firebase sync
2. Verify these safety properties:
   - missing fields decode to safe defaults
   - import paths normalize categories and other derived state
   - corrupted or missing data does not silently overwrite good data unless that tradeoff is explicit
   - save operations update timestamps or freshness markers consistently
   - restore/import flows do not leave stale UI selection state behind
3. For web sync logic, check local-vs-cloud freshness comparison and merge direction.
4. For iOS backup logic, check file access flow and user-facing failure reporting.
5. Report any place where a failed load falls back to empty state without enough visibility.

Do not recommend a database or large storage refactor unless the current bug clearly requires it.
