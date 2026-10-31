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
    private let signedExpiry: Int64?
    private let validate: (@MainActor @Sendable () throws -> Void)?

    private init(allocation: SharedMediaNativePhotoAllocation, request: URLRequest,
                 timeout: TimeInterval, task: PinnedPhotoUploadTask, signedExpiry: Int64? = nil,
                 validate: (@MainActor @Sendable () throws -> Void)? = nil) {
        self.allocation = allocation; self.request = request
        self.timeout = timeout; self.task = task; self.signedExpiry = signedExpiry; self.validate = validate
    }

    /// Only the file owner supplies this URL. Neither a callback nor a response
    /// can publish it. Every started task is joined even on error/cancellation.
    func consume(file: URL) async throws -> Int {
        let response: HTTPURLResponse
        try await validate?()
        do { response = try await task.response(for: request, fromFile: file, timeout: timeout, expiresAtMilliseconds: signedExpiry) } catch {
            await task.waitForLocalTermination()
            throw error
        }
        await task.waitForLocalTermination()
        try Task.checkCancellation()
        return response.statusCode
    }

    @MainActor static func authorized(_ authority: SharedMediaNativePhotoPutAuthorization,
                                      task: PinnedPhotoUploadTask, nowMilliseconds: Int64) throws -> Self {
        let (request, expiry) = try authority.request(nowMilliseconds: nowMilliseconds)
        return Self(allocation: authority.allocation, request: request, timeout: 300, task: task,
            signedExpiry: expiry, validate: { try authority.validateConsumed() })
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
