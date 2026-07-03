# Claude Usage Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar app for local Claude usage monitoring.

**Architecture:** A Swift package with `ClaudeUsageCore` for parsing and aggregation, plus `ClaudeUsageBar` as a SwiftUI `MenuBarExtra` executable. The app reads local files only and never calls external APIs.

**Tech Stack:** Swift 6, Swift Package Manager, SwiftUI, Foundation, XCTest.

---

### Task 1: Scaffolding

**Files:**
- Create: `Package.swift`
- Create: `Sources/ClaudeUsageCore/*.swift`
- Create: `Sources/ClaudeUsageBar/*.swift`
- Create: `Tests/ClaudeUsageCoreTests/*.swift`

- [x] Create package manifest and directories.
- [ ] Add parser tests for transcript, audit, cache, and aggregation behavior.
- [ ] Implement parser and aggregation code.
- [ ] Implement menu bar UI.
- [ ] Run `swift test`.
- [ ] Run `swift build`.

### Task 2: Verification

- [ ] Confirm tests cover positive parsing and malformed-line tolerance.
- [ ] Confirm build produces the executable.
- [ ] Document how to run: `swift run ClaudeUsageBar`.
