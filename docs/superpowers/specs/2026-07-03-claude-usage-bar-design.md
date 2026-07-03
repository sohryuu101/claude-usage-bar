# Claude Usage Bar Design

## Goal

Build a native macOS menu bar app that monitors Claude usage from local Claude app and Claude Code data.

## Data Sources

- Claude Code transcripts: `~/.claude/projects/**/*.jsonl`.
- Claude Desktop/Cowork audit logs: `~/Library/Application Support/Claude/local-agent-mode-sessions/**/audit.jsonl`.
- Claude app cache snapshots: `~/Library/Application Support/Claude/Cache/Cache_Data/*`, including cached `usage`, `subscription_status`, `is_pure_usage_based`, and `v1/code/routines/run-budget` responses when present.

## Behavior

The menu bar title shows the freshest account snapshot percentage when available, otherwise today's local token total. The popover shows:

- Account snapshot, marked with cache freshness.
- Today and week local totals.
- Breakdown by Claude Code and Desktop/Cowork.
- Last refresh time and refresh/quit controls.

All values are local reads. The app does not authenticate, call Claude APIs, or send data anywhere.

## Architecture

`ClaudeUsageCore` contains file discovery, JSONL parsing, Chromium cache scanning, and aggregation. `ClaudeUsageBar` contains the SwiftUI `MenuBarExtra` UI and periodically refreshes a `UsageMonitor`.

## Testing

Unit tests cover parsing of Claude JSONL usage records, Cowork audit logs, run-budget cache payloads, and aggregation by source/date.
