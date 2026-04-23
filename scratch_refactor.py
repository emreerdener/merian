import re

with open("merian/Features/Profile/Components/Settings/Preferences.swift", "r") as f:
    content = f.read()

body_replacement = """    var body: some View {
        @Bindable var hwOrchestrator = hardwareOrchestrator
        
        Section {
            // MARK: - Sections
            Button { captureModeOrderSettingsActive = true } label: {
                SettingsNavigationRow(
                    title: "Sections",
                    description: "Reorder capture sections and choose your default launch mode.",
                    icon: "rectangle.split.3x1.fill",
                    iconColor: .yellow
                )
            }

            // MARK: - Camera
            Button { cameraSettingsActive = true } label: {
                SettingsNavigationRow(
                    title: "Camera",
                    description: "Zoom controls, viewfinder hints, and capture preferences.",
                    icon: "camera.fill",
                    iconColor: .gray
                )
            }
            
            // MARK: - Audio Recording
            Button { audioRecordingSettingsActive = true } label: {
                SettingsNavigationRow(
                    title: "Audio recording",
                    description: "Microphone hints and tuning preferences.",
                    icon: "mic.fill",
                    iconColor: .purple
                )
            }
        } header: {
            Text("Capture setup")
        }
        
        Section {
            // MARK: - Multi-Capture Scans
            SettingsToggleRow(
                title: "Multi-capture mode",
                description: "Attach up to 2 items (photos or audio clips) before submitting. By default, a single capture is sent to AI immediately.",
                isOn: $isMultiCaptureEnabled,
                icon: "square.stack.fill",
                iconColor: .blue
            )
            
            // MARK: - Confirm Submissions
            SettingsToggleRow(
                title: "Confirm scan submission",
                description: "Present the 'Identify' button after capturing to physically confirm the scan. When disabled, single captures are sent to AI immediately.",
                isOn: $requiresScanConfirmation,
                icon: "hand.tap.fill",
                iconColor: .purple
            )

            // MARK: - Expedition Mode
            SettingsToggleRow(
                title: "Expedition mode",
                description: "Maximizes battery life off-grid by capping camera frame rates, disabling heavy visual effects, and suppressing haptics.",
                isOn: $hwOrchestrator.isExpeditionModeActive,
                icon: "map.fill",
                iconColor: .green
            )
            .onChange(of: hwOrchestrator.isExpeditionModeActive) { _, newValue in
                // Write to UserDefaults before evaluateConstraints() — that method reads
                // this key directly and would otherwise snap the toggle back to its prior state.
                UserDefaults.standard.set(newValue, forKey: "isExpeditionModeActive")
                hardwareOrchestrator.evaluateConstraints()
            }

            // MARK: - System Haptics
            SettingsToggleRow(
                title: "System haptics",
                description: "Tactile feedback on zoom ticks, captures, and key interactions.",
                isOn: $isHapticsEnabled,
                icon: "waveform",
                iconColor: .pink
            )
        } header: {
            Text("Capture behavior")
        }

        Section {
            // MARK: - Upgrades
            Button { managePlanActive = true } label: {
                SettingsNavigationRow(
                    title: "Upgrade",
                    description: "Upgrade or manage your active subscription tier.",
                    icon: "bag.fill",
                    iconColor: .orange
                )
            }

            // MARK: - Theme
            VStack(alignment: .leading, spacing: 8) {                   
                Picker("Theme", selection: $themeMode) {
                    ForEach(ThemeMode.allCases) { mode in
                        Text(mode.rawValue)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)
           
            // MARK: - Push Notifications
            Button { notificationSettingsActive = true } label: {
                SettingsNavigationRow(
                    title: "Notifications",
                    description: "Configure alerts for new discoveries and achievement milestones.",
                    icon: "bell.fill",
                    iconColor: .red
                )
            }

            // MARK: - Geoprivacy
            NavigationLink {
                GeoprivacyPickerView(defaultGeoprivacy: $defaultGeoprivacy)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.blue)
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 24)
                        Text("Geoprivacy")
                            .foregroundColor(.primary)
                        Spacer()
                        Text(defaultGeoprivacy.capitalized)
                            .foregroundColor(.secondary)
                    }
                    Text("Control how precisely your location is recorded on each scan.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 36)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Account & app")
        }"""

# Replace the body of Preferences struct
pattern = re.compile(r'    var body: some View \{[\s\S]*?\} header: \{\n            Text\("Preferences"\)\n        \}', re.MULTILINE)
content = pattern.sub(body_replacement, content)

with open("merian/Features/Profile/Components/Settings/Preferences.swift", "w") as f:
    f.write(content)
