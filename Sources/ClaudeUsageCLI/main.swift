import ClaudeUsageCore
import Foundation

let enableOAuthLiveQuota = UserDefaults.standard.bool(forKey: UsageSettings.enableOAuthLiveQuotaKey)
let store = UsageStore(enableOAuthLiveQuota: enableOAuthLiveQuota)
let aggregate = await store.loadAsync()

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

if let liveQuota = aggregate.liveQuota {
    print("Live Quota:")
    printQuota("5-hour", liveQuota.fiveHour)
    printQuota("7-day", liveQuota.sevenDay)
    printQuota("OAuth apps", liveQuota.sevenDayOAuthApps)
    printQuota("Opus", liveQuota.sevenDayOpus)
    printQuota("Sonnet", liveQuota.sevenDaySonnet)
    print("  Fetched: \(liveQuota.fetchedAt)")
    print("")
} else if enableOAuthLiveQuota {
    print("Live Quota: \(oauthStatusText(aggregate.liveQuotaStatus))")
    print("")
}

if let snapshot = aggregate.accountSnapshot {
    print("Account Cache Fallback (\(snapshot.kind.rawValue)):")
    print("  Used:  $\(formatNumber(snapshot.used))")
    print("  Limit: $\(formatNumber(snapshot.limit))")
    print("  (\(snapshot.percentUsed)% used)")
    if let date = snapshot.capturedAt {
        print("  Stale fallback: \(date)")
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
        print("  Stale fallback: \(date)")
    }
    print("")
}

let showSub = aggregate.subscriptionSnapshot != nil || aggregate.last5Hours.messages > 0
if showSub {
    let planName = aggregate.subscriptionSnapshot?.plan?.capitalized ?? "Pro"
    let messagesUsed = aggregate.last5Hours.messages
    
    let limit: Int
    switch aggregate.subscriptionSnapshot?.plan?.lowercased() {
    case "free": limit = 15
    case "pro": limit = 45
    case "max": limit = 100
    default: limit = 45
    }
    
    let percent = limit > 0 ? Int((Double(messagesUsed) / Double(limit) * 100).rounded()) : 0
    print("Subscription Status (\(planName)):")
    print("  Messages sent (last 5h): \(messagesUsed) of \(limit)")
    print("  (\(percent)% used)")
    if let date = aggregate.subscriptionSnapshot?.capturedAt {
        print("  Stale fallback: \(date)")
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

func printQuota(_ title: String, _ bucket: OAuthQuotaBucket?) {
    guard let bucket else {
        print("  \(title): unavailable")
        return
    }
    let resetText = bucket.resetsAt.map { ", resets \($0)" } ?? ""
    print("  \(title): \(Int(bucket.utilization.rounded()))%\(resetText)")
}

func oauthStatusText(_ status: OAuthLiveQuotaStatus) -> String {
    switch status {
    case .enabled:
        return "Enabled"
    case .unauthorized:
        return "Unauthorized"
    case .rateLimited:
        return "Rate limited"
    case .unavailable:
        return "Unavailable"
    }
}
