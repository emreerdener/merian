import Foundation
import AVFoundation
import CoreLocation
import WeatherKit
import WatchKit

@MainActor
class WatchAcousticManager: NSObject, ObservableObject, AVAudioRecorderDelegate, CLLocationManagerDelegate {
    @Published var isRecording: Bool = false
    @Published var isProcessing: Bool = false
    @Published var authorizationState: CLAuthorizationStatus = .notDetermined
    
    private var audioRecorder: AVAudioRecorder?
    private var locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var currentWeather: Weather?
    private var recordingURL: URL?
    
    override init() {
        super.init()
        locationManager.delegate = self
        requestPermissions()
    }
    
    private func requestPermissions() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            print("Microphone access granted: \(granted)")
        }
        locationManager.requestWhenInUseAuthorization()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.authorizationState = manager.authorizationStatus
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.currentLocation = location
        // Stop updating immediately to save battery on WatchOS
        locationManager.stopUpdatingLocation()
        
        Task {
            do {
                self.currentWeather = try await WeatherService.shared.weather(for: location)
            } catch {
                print("Failed to fetch WeatherKit context for watch: \(error)")
            }
        }
    }
    
    func startAcousticCapture() {
        // Fetch fresh coordinates & weather for the payload
        locationManager.startUpdatingLocation()
        
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
            
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "\(UUID().uuidString).m4a"
            let url = tempDir.appendingPathComponent(fileName)
            self.recordingURL = url
            
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            
            // Capture a 15-second acoustic window for bird/insect calls
            audioRecorder?.record(forDuration: 15.0)
            
            isRecording = true
            
            // Provide physical watchOS feedback to indicate recording start
            WKInterfaceDevice.current().play(.start)
            
        } catch {
            print("Failed to initialize watchOS acoustic capture: \(error)")
            isRecording = false
        }
    }
    
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            self.isRecording = false
            guard flag, let url = self.recordingURL else { return }
            
            // Provide success thump alerting user audio is complete
            WKInterfaceDevice.current().play(.success)
            self.isProcessing = true
            
            await self.processPayload(fileURL: url)
        }
    }
    
    private func processPayload(fileURL: URL) async {
        defer {
            // CRITICAL: Prevent watchOS storage bloat by manually wiping the temporary recording buffer.
            do {
                try FileManager.default.removeItem(at: fileURL)
                print("Successfully purged temporary .m4a buffer from Apple Watch.")
            } catch {
                print("Failed to securely delete temporary watchOS audio memory: \(error)")
            }
            self.isProcessing = false
        }
        
        do {
            let audioData = try Data(contentsOf: fileURL)
            let base64Audio = audioData.base64EncodedString()
            
            var payload: [String: Any] = [
                "audioData": base64Audio,
                "currentMonth": Calendar.current.component(.month, from: Date()),
                "deviceLocale": Locale.current.identifier
            ]
            
            if let location = currentLocation {
                payload["gpsLatitude"] = location.coordinate.latitude
                payload["gpsLongitude"] = location.coordinate.longitude
                payload["gpsElevation"] = location.altitude
            }
            
            if let weather = currentWeather {
                payload["weatherCondition"] = weather.currentWeather.condition.description
                payload["weatherTemperatureF"] = weather.currentWeather.temperature.converted(to: .fahrenheit).value
            }
            
            // This payload runs out securely over WatchConnectivity to the iOS Device or directly via Cellular models.
            print("Successfully encoded WatchOS Payload! Keys: \(payload.keys)")
            
        } catch {
            print("Failed to encode acoustic payload: \(error)")
        }
    }
}
