import SwiftUI

/// Shared by the Discover views for one authenticated session.
@MainActor
final class Sprint4Services {
    let dismissals: any RediscoverDismissing
    let watchLater: any WatchLaterStoring
    let trends: any TrendsLoading
    let creatorsCache = CreatorsCache()
    let insights: any InsightsSnapshotStoring
    private let tracker: BatchingAnalyticsTracker?

    var analytics: any AnalyticsTracking {
        if let tracker { return tracker }
        return NoOpAnalyticsTracking()
    }

    init(
        dismissals: any RediscoverDismissing,
        watchLater: any WatchLaterStoring,
        trends: any TrendsLoading,
        insights: any InsightsSnapshotStoring,
        tracker: BatchingAnalyticsTracker? = nil
    ) {
        self.dismissals = dismissals
        self.watchLater = watchLater
        self.trends = trends
        self.insights = insights
        self.tracker = tracker
    }

    func flushAnalytics() async {
        await tracker?.flush()
    }

    func endSession() -> Task<Void, Never> {
        tracker?.stop()
        dismissals.clear()
        return Task {
            await watchLater.clear()
            await trends.clear()
            await insights.clear()
        }
    }
}

extension EnvironmentValues {
    @Entry var sprint4: Sprint4Services? = nil
}
