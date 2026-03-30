import AVFoundation
import Combine

class Test {
    var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    var cancellables = Set<AnyCancellable>()
    
    func setup(device: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        self.rotationCoordinator = coordinator
        
        coordinator.publisher(for: \.videoRotationAngleForHorizonLevelCapture)
            .sink { angle in
                print(angle)
            }
            .store(in: &cancellables)
    }
}
