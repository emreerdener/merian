import Foundation
@testable import Merian
import Testing

@MainActor @Suite
struct AnalysisRecoveryCheckingModelTests {
    typealias Model = AnalysisRecoveryCheckingModel

    @Test(arguments: [false, true])
    func leavingBeforeTaskStartsKeepsAcceptedCheckWithoutChargingInvisibleTime(background: Bool) async {
        var reads = 0, charges: [Duration] = []
        let model = Model(access: .init(isCurrent: { true }, reserve: {
            .init(allowance: .seconds(30), settle: { charges.append($0) })
        }, check: { reads += 1; #expect(!Task.isCancelled); return true }))
        model.check()
        if background { model.setVisible(false) } else { model.close() }
        while model.isRunning { await Task.yield() }
        #expect(reads == 1 && charges == [.zero])
        #expect(model.state != .recovered && model.state != .checking)
        if background { model.setVisible(true); #expect(reads == 1 && model.state == .recovered) }
    }

    @Test func reservationAcknowledgedAfterCloseOwnsZeroVisibleTime() async {
        var reserve: CheckedContinuation<Model.Interval?, Never>?
        var charges: [Duration] = [], reads = 0
        let model = Model(access: .init(isCurrent: { true }, reserve: {
            await withCheckedContinuation { reserve = $0 }
        }, check: { reads += 1; return true }))
        model.check()
        while reserve == nil { await Task.yield() }
        #expect(model.state == .preparing)
        model.close()
        reserve?.resume(returning: .init(allowance: .seconds(30), settle: { charges.append($0) }))
        while model.isRunning { await Task.yield() }
        #expect(charges == [.zero] && reads == 1 && model.state == .unavailable)
    }

    @Test(arguments: [false, true])
    func closeOrBackgroundPausesClockWithoutCancellingKnownResult(background: Bool) async {
        var instant = ContinuousClock.now, reply: CheckedContinuation<Bool, Never>?
        var charges: [Duration] = [], completed = false, deliveries = 0
        let model = Model(access: .init(isCurrent: { true }, reserve: {
            .init(allowance: .seconds(30), settle: { charges.append($0) })
        }, check: {
            let result = await withCheckedContinuation { reply = $0 }
            #expect(!Task.isCancelled); completed = true
            return result
        }), didFinish: { deliveries += 1 }, now: { instant })
        model.check()
        while reply == nil { await Task.yield() }
        #expect(model.state == .checking)
        instant += .seconds(4)
        if background { model.setVisible(false) } else { model.close() }
        #expect(charges == [.seconds(4)] && model.isRunning)
        instant += .seconds(60)
        reply?.resume(returning: true)
        while model.isRunning { await Task.yield() }
        #expect(completed && charges == [.seconds(4)] && model.state != .recovered && deliveries == 0)
        model.setVisible(true)
        if background {
            #expect(model.state == .recovered && deliveries == 1 && charges == [.seconds(4)])
            model.setVisible(false); model.setVisible(true)
            #expect(deliveries == 1 && model.state == .recovered)
        } else { #expect(model.state == .unavailable && deliveries == 0) }
    }

    @Test func visibleThresholdDoesNotCancelLateResultOrRefundTwice() async {
        var instant = ContinuousClock.now, reply: CheckedContinuation<Bool, Never>?
        var wake: CheckedContinuation<Void, Never>?, charges: [Duration] = []
        let model = Model(access: .init(isCurrent: { true }, reserve: {
            .init(allowance: .seconds(30), settle: { charges.append($0) })
        }, check: {
            let result = await withCheckedContinuation { reply = $0 }
            #expect(!Task.isCancelled); return result
        }), now: { instant }, sleep: { _ in await withCheckedContinuation { wake = $0 } })
        model.check()
        while reply == nil || wake == nil { await Task.yield() }
        instant += .seconds(30); wake?.resume()
        while model.state == .checking { await Task.yield() }
        #expect(model.state == .needsAttention && model.isRunning && charges == [.seconds(30)])
        model.check(); #expect(!model.canCheck)
        reply?.resume(returning: true)
        while model.isRunning { await Task.yield() }
        #expect(model.state == .recovered && charges == [.seconds(30)])
    }

    @Test(arguments: [false, true])
    func exhaustedBudgetAllowsOneExactCheckButFailedReservationDoesNot(failed: Bool) async {
        var reads = 0, reply: CheckedContinuation<Bool, Never>?
        let model = Model(access: .init(isCurrent: { true }, reserve: {
            if failed { throw CocoaError(.fileReadUnknown) }
            return nil
        }, check: { reads += 1; return await withCheckedContinuation { reply = $0 } }))
        model.check()
        while model.state == .preparing { await Task.yield() }
        if failed {
            #expect(reads == 0 && model.state == .unavailable && !model.isRunning)
        } else {
            while reply == nil { await Task.yield() }
            #expect(model.state == .needsAttention && model.isRunning)
            model.check(); #expect(reads == 1)
            reply?.resume(returning: false)
            while model.isRunning { await Task.yield() }
            #expect(model.state == .needsAttention)
        }
    }

    @Test func changedAccountWithholdsLatePrivateDelivery() async {
        var current = true, reply: CheckedContinuation<Bool, Never>?, deliveries = 0
        let model = Model(access: .init(isCurrent: { current }, reserve: { nil }, check: {
            await withCheckedContinuation { reply = $0 }
        }), didFinish: { deliveries += 1 })
        model.check()
        while reply == nil { await Task.yield() }
        current = false; reply?.resume(returning: true)
        while model.isRunning { await Task.yield() }
        #expect(model.isClosed && model.state == .unavailable && deliveries == 0)
    }
}
