import Foundation
import ClaudeUsageCore

let store = UsageStore()
let aggregate = store.load()

func formatTokens(_ value: Int) -> String {
    if value >= 1_000_000 {
        return String(format: "%.1fM tokens", Double(value) / 1_000_000)
    }
    if value >= 1_000 {
        return String(format: "%.1fK tokens", Double(value) / 1_000)
    }
    return "\(value) tokens"
}

func formatNumber(_ value: Double) -> String {
    if value.rounded() == value {
        return String(format: "%.0f", value)
    }
    return String(format: "%.2f", value)
}

print("== Claude Usage ==")
print("")

if let snapshot = aggregate.accountSnapshot {
    print("Account Snapshot (\(snapshot.kind.rawValue)):")
    print("  Used:  $\(formatNumber(snapshot.used))")
    print("  Limit: $\(formatNumber(snapshot.limit))")
    print("  (\(snapshot.percentUsed)% used)")
    if let date = snapshot.capturedAt {
        print("  Cached: \(date)")
    }
    print("")
} else {
    print("Account Snapshot: Unavailable")
    print("")
}

if let design = aggregate.designSnapshot {
    print("Claude Design Included Allowance:")
    print("  Used: \(Int(design.used))%")
    if let date = design.capturedAt {
        print("  Cached: \(date)")
    }
    print("")
}

print("Local Activity:")
print("  Today:      \(formatTokens(aggregate.today.tokens.total)) (\(aggregate.today.messages) messages)")
print("  This Month: \(formatTokens(aggregate.month.tokens.total)) (\(aggregate.month.messages) messages)")
print("")
print("By Source:")
for source in UsageSource.allCases {
    let bucket = aggregate.bySource[source] ?? UsageBucket()
    print("  \(source.rawValue):")
    print("    \(formatTokens(bucket.tokens.total)) (\(bucket.messages) messages)")
}
