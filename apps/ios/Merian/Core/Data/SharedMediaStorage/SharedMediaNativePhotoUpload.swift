import Foundation

/// Concrete, single-task file consumption. Construction is deliberately closed
/// in Release until fresh ticket authority and a durable started/unknown
/// transition exist. Historical status is never upload permission.
final class SharedMediaNativePhotoUpload: Sendable {
    struct Readback: Sendable {
        let statusCode: Int
        let inspection: SharedMediaPhotoRetirementInspection
        let completion: SharedMediaNativePairCompletion?
    }
    let allocation: SharedMediaNativePhotoAllocation
    private let request: URLRequest
    private let timeout: TimeInterval
    private let task: PinnedPhotoUploadTask

    private init(allocation: SharedMediaNativePhotoAllocation, request: URLRequest,
                 timeout: TimeInterval, task: PinnedPhotoUploadTask) {
        self.allocation = allocation; self.request = request
        self.timeout = timeout; self.task = task
    }

    /// Only the file owner supplies this URL. Neither a callback nor a response
    /// can publish it. Every started task is joined even on error/cancellation.
    func consume(file: URL) async throws -> Int {
        let response: HTTPURLResponse
        do { response = try await task.response(for: request, fromFile: file, timeout: timeout) } catch {
            await task.waitForLocalTermination()
            throw error
        }
        await task.waitForLocalTermination()
        try Task.checkCancellation()
        return response.statusCode
    }

    #if DEBUG
    /// Unit-test-only construction, using an injected intercepted session and a
    /// reserved invalid hostname. This is not a ticket decoder or app factory.
    static func forTesting(allocation: SharedMediaNativePhotoAllocation,
                           task: PinnedPhotoUploadTask, timeout: TimeInterval = 10) throws -> Self {
        guard TestExecutionCoordinator.isRunningTests,
              let url = URL(string: "https://sealed-role.invalid/photo-upload") else {
            throw SharedMediaStorageFailure.closed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        return Self(allocation: allocation, request: request, timeout: timeout, task: task)
    }
    #endif
}
