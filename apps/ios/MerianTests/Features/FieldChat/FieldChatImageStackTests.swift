import Testing
import UIKit

@testable import Merian

@MainActor
struct FieldChatImageStackTests {
    @Test func shortAndVerticalGesturesNeverCommitPageChanges() {
        #expect(FieldChatImageNavigation.swipeOffset(horizontal: 20, vertical: 0, isRightToLeft: false) == nil)
        #expect(FieldChatImageNavigation.swipeOffset(horizontal: 40, vertical: 60, isRightToLeft: false) == nil)
        #expect(FieldChatImageNavigation.swipeOffset(horizontal: -50, vertical: 2, isRightToLeft: false) == 1)
        #expect(FieldChatImageNavigation.swipeOffset(horizontal: -50, vertical: 2, isRightToLeft: true) == -1)
    }

    @Test func liveImagePreparationHonorsThumbnailCapAndRejectsInvalidBytes() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800), format: format).jpegData(
            withCompressionQuality: 0.8
        ) { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        }
        let image = try #require(await FieldChatImageDependencies.live.load(.liveImage(data), 600))
        #expect(max(image.size.width * image.scale, image.size.height * image.scale) <= 600)
        #expect(await FieldChatImageDependencies.live.load(.liveImage(Data([1, 2, 3])), 600) == nil)
    }

    @Test func committedNavigationEmitsOneSelectionEffectAndWrapsBothEnds() async {
        var effects: [FieldChatFeedbackEffect] = []
        let chat = InsightChatViewModel(dependencies: FieldChatTestSupport.dependencies(
            endpoint: FieldChatTestSupport.endpoint(),
            feedback: { effects.append($0) }
        ))
        let model = makeModel(count: 2)
        let selection = { chat.performFeedback(.selection) }
        await model.loadWindow(isOnline: true)
        #expect(effects.isEmpty)
        model.move(by: 0, onSelection: selection)
        #expect(effects.isEmpty)
        model.move(by: -1, onSelection: selection)
        #expect(model.selectedIndex == 1)
        #expect(effects == [.selection])
        model.move(by: 1, onSelection: selection)
        #expect(model.selectedIndex == 0)
        #expect(effects == [.selection, .selection])
        model.move(by: 1, onSelection: selection)
        model.move(by: 1, onSelection: selection)
        #expect(model.selectedIndex == 0)
        #expect(effects.count == 4)
    }

    @Test func failedImagesAreSkippedWithoutSelectionFeedback() async {
        let media = images(count: 3)
        let model = FieldChatImageStackModel(media: media, dependencies: .init { source, size in
            #expect(size == 600)
            return source == media[1].source ? UIImage() : nil
        })
        await model.loadWindow(isOnline: true)
        #expect(model.selectedID == media[1].id)
        #expect(model.availableMedia.map(\.id) == [media[1].id])
        #expect(model.images.count == 1)
        var feedbackCount = 0
        model.move(by: 1) { feedbackCount += 1 }
        #expect(feedbackCount == 0)
    }

    @Test func unloadedUserSelectionOnlyEmitsFeedbackAfterSuccessfulDecode() async {
        var feedbackCount = 0
        let model = makeModel(count: 3)
        model.move(by: 1) { feedbackCount += 1 }
        #expect(feedbackCount == 0)
        await model.loadWindow(isOnline: true)
        #expect(feedbackCount == 1)
        await model.loadWindow(isOnline: true)
        #expect(feedbackCount == 1)
    }

    @Test func swipeToFailingImageDoesNotEmitFeedbackForAutomaticReplacement() async {
        var feedbackCount = 0
        let model = FieldChatImageStackModel(media: images(count: 3), dependencies: .init { source, _ in
            source == .path("image-1.jpg") ? nil : UIImage()
        })
        model.move(by: 1) { feedbackCount += 1 }
        await model.loadWindow(isOnline: true)
        #expect(model.selectedID == "image-2.jpg")
        #expect(feedbackCount == 0)
    }

    @Test func totalFailureAndEmptyInputUseFallback() async {
        let failed = FieldChatImageStackModel(media: images(count: 3), dependencies: .init { _, _ in nil })
        await failed.loadWindow(isOnline: true)
        #expect(failed.selectedMedia == nil)
        #expect(failed.images.isEmpty)
        let empty = makeModel(count: 0)
        await empty.loadWindow(isOnline: true)
        #expect(empty.selectedMedia == nil)
    }

    @Test func visibleThreeCardWindowIsLoadedAndRetainedAcrossWraparound() async {
        var requestedSizes: [Int] = []
        let model = FieldChatImageStackModel(media: images(count: 8), dependencies: .init { _, size in
            requestedSizes.append(size)
            return UIImage()
        })
        await model.loadWindow(isOnline: true)
        #expect(model.images.count == 3)
        #expect(model.stackMedia.map(\.id) == ["image-0.jpg", "image-1.jpg", "image-2.jpg"])
        for index in 1...8 {
            model.move(by: 1) {}
            await model.loadWindow(isOnline: true)
            #expect(model.images.count == 3)
            #expect(model.selectedIndex == index % 8)
            #expect(Set(model.images.keys) == Set(model.stackMedia.map(\.id)))
            #expect(model.stackMedia.map(\.id) == (0..<3).map { "image-\((index + $0) % 8).jpg" })
        }
        #expect(requestedSizes.allSatisfy { $0 == 600 })
    }

    @Test func failedRearImagesAreReplacedUntilAllVisibleSlotsAreLoaded() async {
        let model = FieldChatImageStackModel(media: images(count: 5), dependencies: .init { source, _ in
            source == .path("image-1.jpg") || source == .path("image-2.jpg") ? nil : UIImage()
        })
        await model.loadWindow(isOnline: true)
        #expect(model.stackMedia.map(\.id) == ["image-0.jpg", "image-3.jpg", "image-4.jpg"])
        #expect(Set(model.images.keys) == Set(model.stackMedia.map(\.id)))
        model.move(by: -1) {}
        await model.loadWindow(isOnline: true)
        #expect(model.selectedID == "image-4.jpg")
        model.move(by: 1) {}
        #expect(model.selectedID == "image-0.jpg")
    }

    @Test func singleImageCannotLoopOrEmitSelectionFeedback() async {
        let model = makeModel(count: 1)
        await model.loadWindow(isOnline: true)
        var feedback = 0
        model.move(by: 1) { feedback += 1 }
        model.move(by: -1) { feedback += 1 }
        #expect(model.selectedIndex == 0)
        #expect(model.stackMedia.count == 1)
        #expect(feedback == 0)
    }

    @Test func reconnectionRetriesFailedImagesWithoutResettingValidSelection() async {
        var succeeds = false
        let model = FieldChatImageStackModel(media: images(count: 2), dependencies: .init { _, _ in
            succeeds ? UIImage() : nil
        })
        await model.loadWindow(isOnline: false)
        #expect(model.selectedMedia == nil)
        succeeds = true
        await model.loadWindow(isOnline: true)
        #expect(model.selectedIndex == 0)
        #expect(model.images.count == 2)
        model.move(by: 1) {}
        await model.loadWindow(isOnline: false)
        await model.loadWindow(isOnline: true)
        #expect(model.selectedIndex == 1)
    }

    @Test func reverseWrapLoadsUncachedLastCardAndEmitsFeedbackOnce() async {
        let model = makeModel(count: 5)
        await model.loadWindow(isOnline: true)
        var feedback = 0
        model.move(by: -1) { feedback += 1 }
        #expect(model.selectedIndex == 4)
        #expect(model.stackMedia.map(\.id) == ["image-4.jpg", "image-0.jpg", "image-1.jpg"])
        #expect(feedback == 0)
        await model.loadWindow(isOnline: true)
        #expect(feedback == 1)
        #expect(Set(model.images.keys) == Set(model.stackMedia.map(\.id)))
        await model.loadWindow(isOnline: true)
        #expect(feedback == 1)
    }

    @Test func cancelledLoadDoesNotPublishIntoDismissedOrReplacementStack() async {
        var continuation: CheckedContinuation<UIImage?, Never>?
        let old = FieldChatImageStackModel(media: images(count: 1), dependencies: .init { _, _ in
            await withCheckedContinuation { continuation = $0 }
        })
        let task = Task { await old.loadWindow(isOnline: true) }
        while continuation == nil { await Task.yield() }
        task.cancel()
        let replacement = makeModel(count: 2)
        await replacement.loadWindow(isOnline: true)
        continuation?.resume(returning: UIImage())
        await task.value
        #expect(old.images.isEmpty)
        #expect(old.failedIDs.isEmpty)
        #expect(replacement.images.count == 2)
        #expect(replacement.selectedIndex == 0)
    }

    @Test func userNavigationInvalidatesAnOlderLoadBeforeNextTaskStarts() async {
        var continuation: CheckedContinuation<UIImage?, Never>?
        let model = FieldChatImageStackModel(media: images(count: 3), dependencies: .init { _, _ in
            await withCheckedContinuation { continuation = $0 }
        })
        let task = Task { await model.loadWindow(isOnline: true) }
        while continuation == nil { await Task.yield() }
        model.move(by: 1) {}
        continuation?.resume(returning: UIImage())
        await task.value
        #expect(model.images.isEmpty)
        #expect(model.selectedIndex == 1)
    }

    @Test func reverseWrapRejectsLateThirdCardFromPreviousWindow() async {
        var continuation: CheckedContinuation<UIImage?, Never>?
        let model = FieldChatImageStackModel(media: images(count: 5), dependencies: .init { source, _ in
            if source == .path("image-2.jpg") {
                return await withCheckedContinuation { continuation = $0 }
            }
            return UIImage()
        })
        let loading = Task { await model.loadWindow(isOnline: true) }
        while continuation == nil { await Task.yield() }
        #expect(model.images.count == 2)
        var feedback = 0
        model.move(by: -1) { feedback += 1 }
        continuation?.resume(returning: UIImage())
        await loading.value
        #expect(model.images["image-2.jpg"] == nil)
        #expect(feedback == 0)
        await model.loadWindow(isOnline: true)
        #expect(model.selectedIndex == 4)
        #expect(feedback == 1)
        #expect(Set(model.images.keys) == Set(model.stackMedia.map(\.id)))
    }

    private func images(count: Int) -> [FieldChatMedia] {
        (0..<count).compactMap { .image(path: "image-\($0).jpg") }
    }

    private func makeModel(count: Int) -> FieldChatImageStackModel {
        FieldChatImageStackModel(media: images(count: count), dependencies: .init { _, _ in UIImage() })
    }
}
