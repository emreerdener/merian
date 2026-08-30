import SwiftUI
import UIKit

struct InsightFirstRenderProbe: UIViewRepresentable {
    let scanId: String?
    let onRendered: @MainActor (String) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = InsightFirstRenderProbeView()
        view.configure(scanId: scanId, onRendered: onRendered)
        return view
    }

    func updateUIView(
        _ uiView: UIView,
        context: Context
    ) {
        guard let probeView = uiView as? InsightFirstRenderProbeView else {
            return
        }
        probeView.configure(scanId: scanId, onRendered: onRendered)
    }
}

private final class InsightFirstRenderProbeView: UIView {
    private var scanId: String?
    private var reportedScanId: String?
    private var onRendered: (@MainActor (String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        scanId: String?,
        onRendered: @escaping @MainActor (String) -> Void
    ) {
        self.onRendered = onRendered
        guard self.scanId != scanId else { return }
        self.scanId = scanId
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard window != nil,
              let scanId,
              reportedScanId != scanId else { return }
        reportedScanId = scanId
        onRendered?(scanId)
    }
}
