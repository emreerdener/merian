extension CaptureWorkspaceViewModel {
    func triggerZoomOpticalStopFeedback() {
        dependencies.scan.feedback.zoomOpticalStop()
    }

    func triggerZoomTickFeedback() {
        dependencies.scan.feedback.zoomTick()
    }
}
