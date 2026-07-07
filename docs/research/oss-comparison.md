# OSS Usage Monitor Comparison

Static source review performed against cloned open-source projects. No third-party project code was executed.

## Repositories Reviewed

| Project | Repo | App Type | Primary Method |
| --- | --- | --- | --- |
| claude-usage | https://github.com/phuryn/claude-usage | Python scanner, dashboard, VS Code integration | Local Claude Code JSONL to SQLite |
| ai-token-monitor | https://github.com/soulduse/ai-token-monitor | Tauri menu bar app | Local JSONL plus optional Anthropic OAuth usage API |
| Claude-Usage-Monitor | https://github.com/theDanButuc/Claude-Usage-Monitor | Native macOS menu bar app | Claude.ai session cookie plus private web usage endpoints |
| Claude-Monitor | https://github.com/RISCfuture/Claude-Monitor | Native macOS menu bar app | Claude Code OAuth token plus Anthropic OAuth usage API |

## Our Current Method

Claude Usage Bar currently stays local-only and reads:

- `~/.claude/projects/**/*.jsonl` for Claude Code token usage.
- `~/Library/Application Support/Claude/local-agent-mode-sessions/**/audit.jsonl` for Claude Desktop/Cowork local agent usage.
- `~/Library/Application Support/Claude/Cache/Cache_Data/*` for cached Claude app usage snapshots around `/usage` and `/v1/code/routines/run-budget`.

This gives a privacy-first, no-login menu bar app. It also covers Desktop/Cowork audit logs, which the reviewed tools generally do not cover. The weak point is that cache snapshots are opportunistic and stale by nature.

## Method Comparison

### Local JSONL Scanners

`phuryn/claude-usage` and `soulduse/ai-token-monitor` both scan Claude Code JSONL logs under Claude config directories.

Useful ideas from `phuryn/claude-usage`:

- Stores scans in SQLite with `sessions`, `turns`, `processed_files`, `agents`, and schema metadata.
- Tracks processed file path, modified time, and line count for incremental rescans.
- Deduplicates streaming JSONL records by `message.id`; the last record wins because it has the final usage tally.
- Reads title records (`custom-title`, `ai-title`) to backfill session topics.
- Detects subagents via `isSidechain`, `agentId`, and `/subagents/` paths.
- Includes Xcode Claude agent logs at `~/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/projects`.

Useful ideas from `soulduse/ai-token-monitor`:

- Detects multiple Claude config dirs, including `CLAUDE_CONFIG_DIR` and `~/.claude-*`.
- Deduplicates parsed entries by message/request identity in an in-memory map.
- Handles newer cache creation usage shape:
  - `usage.cache_creation.ephemeral_5m_input_tokens`
  - `usage.cache_creation.ephemeral_1h_input_tokens`
  - fallback to `usage.cache_creation_input_tokens`
- Parses `usage.server_tool_use.web_search_requests`.
- Builds model, project, tool, shell command, MCP, cost, and daily analytics.

Compared to them, our local parser is simpler and easier to maintain, but it should add deduplication and newer usage-field support to avoid overcounting or undercounting.

### OAuth Usage API

`RISCfuture/Claude-Monitor` and `soulduse/ai-token-monitor` call:

`GET https://api.anthropic.com/api/oauth/usage`

They send:

- `Authorization: Bearer <Claude Code OAuth token>`
- `anthropic-beta: oauth-2025-04-20`

The response exposes live account quota buckets such as `five_hour`, `seven_day`, `seven_day_oauth_apps`, `seven_day_opus`, and `seven_day_sonnet`, each with utilization percent and reset time.

This is the cleanest way to show live quota/reset information like the Claude UI without scraping Claude.ai browser state. It does require network access and access to a Claude Code OAuth token, usually via Keychain or Claude Code credentials.

### Claude.ai Session Cookie API

`theDanButuc/Claude-Usage-Monitor` logs into Claude.ai, captures a `sessionKey`, fetches organization data from `https://claude.ai/api/organizations`, and then calls:

- `https://claude.ai/api/organizations/{orgId}/usage`
- `https://claude.ai/v1/code/routines/run-budget`

This mirrors the Claude web UI closely and exposes useful windows like 5-hour, 7-day, Sonnet, Opus, Design/Omelette, extra usage, and routine budget.

The tradeoff is that it depends on Claude.ai private web endpoints, browser session cookies, and Claude web app behavior. For this app, OAuth usage is a better first live-quota option.

### Cache Snapshot Scraping

Our cache reader is the only reviewed approach that scans Claude native app cache files for usage snapshots instead of authenticating. This is useful as a zero-permission fallback but cannot be treated as authoritative because:

- Cached responses may be stale.
- The cache may not contain the latest usage endpoint response.
- Chromium cache layout and Claude endpoint payloads can change.
- It is hard to distinguish missing data from zero usage.

## Recommended Changes

1. Add JSONL deduplication by `message.id`, and fall back to `requestId` plus timestamp when no message id exists.
2. Support nested cache-creation fields: `usage.cache_creation.ephemeral_5m_input_tokens` and `usage.cache_creation.ephemeral_1h_input_tokens`.
3. Add optional source directories: `CLAUDE_CONFIG_DIR`, `~/.claude-*`, and Xcode's `~/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/projects`.
4. Add optional OAuth live quota support using Claude Code OAuth credentials from Keychain or local Claude config.
5. Keep Claude app cache snapshots as a fallback source, not the primary truth for live quota.
6. Consider a small SQLite store if rescans become slow or if we add historical charts.
7. Add cost estimates only after token parsing is correct and deduped.

## Positioning

The best direction is a hybrid:

- Local JSONL/audit logs for real local token history across Claude Code and Desktop/Cowork.
- OAuth usage API for live quota windows and reset times.
- Cache snapshots as a no-auth fallback.

Avoid making Claude.ai session-cookie scraping the default path. It is powerful, but it is the most brittle and sensitive method among the reviewed approaches.
