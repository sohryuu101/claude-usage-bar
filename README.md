# Claude Usage Bar

Native macOS menu bar app for local Claude usage monitoring.

Run from source:

```bash
swift run ClaudeUsageBar
```

The app reads local Claude files only:

- `~/.claude/projects/**/*.jsonl`
- `~/Library/Application Support/Claude/local-agent-mode-sessions/**/audit.jsonl`
- `~/Library/Application Support/Claude/Cache/Cache_Data/*`
