import Foundation
import AVFoundation
import CoreLocation
import WeatherKit
import WatchKit
import WatchConnectivity

@MainActor
class WatchAcousticManager: NSObject, ObservableObject, AVAudioRecorderDelegate, CLLocationManagerDelegate, WCSessionDelegate {
    @Published var isRecording: Bool = false
    @Published var isProcessing: Bool = false
    @Published var authorizationState: CLAuthorizationStatus = .notDetermined
    
    private var audioRecorder: AVAudioRecorder?
    private var locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var currentWeather: Weather?
    private var recordingURL: URL?
    private var session: WCSession?
    
    override init() {
        super.init()
        locationManager.delegate = self
        setupWatchConnectivity()
        requestPermissions()
    }
    
    private func setupWatchConnectivity() {
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("WCSession globally active: \(activationState.rawValue)")
    }
    
    private func requestPermissions() {
        AVAudioApplication.requestRecordPermission { granted in
            print("Microphone access granted: \(granted)")
        }
        locationManager.requestWhenInUseAuthorization()
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationState = manager.authorizationStatus
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        Task { @MainActor in
            self.currentLocation = location
            // Stop updating immediately to save battery on WatchOS
            self.locationManager.stopUpdatingLocation()
            
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
            
            print("Successfully encoded WatchOS Payload! Keys: \(payload.keys)")
            
            // Dispatch completely over WatchConnectivity explicitly bridging to the iPhone OfflineQueueManager
            if let session = self.session, session.isReachable {
                session.sendMessage(payload, replyHandler: nil) { error in
                    print("Foreground WCSession Error. Transitioning to background transport: \(error)")
                    self.session?.transferUserInfo(payload)
                }
            } else {
                session?.transferUserInfo(payload)
            }
            
        } catch {
            print("Failed to encode acoustic payload: \(error)")
        }
    }
}
