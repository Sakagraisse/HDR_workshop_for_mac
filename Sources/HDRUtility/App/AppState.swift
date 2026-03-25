import Foundation

@MainActor
@Observable
public final class AppState {
    var recentJobs: [ConversionJob] = []
    var lastErrorMessage: String?

    public init() {}

    func record(job: ConversionJob) {
        recentJobs.insert(job, at: 0)
        if recentJobs.count > 20 {
            recentJobs.removeLast(recentJobs.count - 20)
        }
    }
}
