import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    private let viewModel = ShareImportViewModel()

    override func viewDidLoad() {
        super.viewDidLoad()

        let rootView = ShareImportView(viewModel: viewModel)
        let hostingController = UIHostingController(rootView: rootView)
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)

        viewModel.configure(
            extensionContext: extensionContext,
            complete: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            },
            cancel: { [weak self] error in
                self?.extensionContext?.cancelRequest(withError: error)
            }
        )
    }
}
