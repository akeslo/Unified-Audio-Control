import SwiftUI

/// Alert view shown when an update is available
struct UpdateAlertView: View {
    let release: GitHubRelease
    let currentVersion: String
    let onDownload: () -> Void
    let onSkip: () -> Void
    let onRemindLater: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .resizable()
                    .frame(width: 48, height: 48)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Update Available")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Version \(release.version) is now available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            // Version info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Version")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(currentVersion)
                        .font(.headline)
                }
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("New Version")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(release.version)
                        .font(.headline)
                        .foregroundColor(.accentColor)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            
            // Release notes
            if let body = release.body, !body.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What's New")
                        .font(.headline)
                    
                    ScrollView {
                        Text(body)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 150)
                    .padding(12)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Skip This Version") {
                    onSkip()
                    dismiss()
                }
                .buttonStyle(.borderless)
                
                Button("Remind Me Later") {
                    onRemindLater()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.secondary)
                
                Button("Download Update") {
                    onDownload()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(24)
        .frame(width: 500)
    }
}

/// Settings view for update preferences
struct UpdateSettingsView: View {
    @ObservedObject var updateManager = UpdateManager.shared
    @State private var showingUpdateAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 50)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Updates")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Current Version: \(updateManager.currentVersion)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 10)
            
            Divider()
            
            Form {
                // Auto-check toggle
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Check for updates on app startup", isOn: $updateManager.autoCheckEnabled)
                        .toggleStyle(.checkbox)
                    
                    Text("When enabled, the app will check for new versions each time it launches")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }
                
                // Last check info
                if let lastCheck = updateManager.lastCheckDate {
                    HStack {
                        Text("Last checked:")
                        Spacer()
                        Text(lastCheck, style: .relative)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Latest version info
                if let latest = updateManager.latestRelease {
                    HStack {
                        Text("Latest version:")
                        Spacer()
                        Text(latest.version)
                            .foregroundColor(updateManager.updateAvailable ? .accentColor : .secondary)
                            .fontWeight(updateManager.updateAvailable ? .semibold : .regular)
                    }
                }
                
                // Update status
                if updateManager.updateAvailable {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("An update is available!")
                            .foregroundColor(.green)
                            .fontWeight(.medium)
                    }
                    .padding(.vertical, 4)
                } else if updateManager.latestRelease != nil {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("You're up to date!")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                // Error message
                if let error = updateManager.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            
            Divider()
            
            // Manual check button
            HStack {
                Spacer()
                
                if updateManager.updateAvailable {
                    Button("Download Update") {
                        updateManager.downloadUpdate()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Button(action: {
                    Task {
                        await updateManager.checkForUpdates(silent: false)
                        
                        // Show alert if update is available
                        if updateManager.updateAvailable {
                            showingUpdateAlert = true
                        }
                    }
                }) {
                    HStack {
                        if updateManager.isChecking {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(updateManager.isChecking ? "Checking..." : "Check for Updates")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(updateManager.isChecking)
            }
            
            Spacer()
        }
        .padding()
        .sheet(isPresented: $showingUpdateAlert) {
            if let release = updateManager.latestRelease {
                UpdateAlertView(
                    release: release,
                    currentVersion: updateManager.currentVersion,
                    onDownload: {
                        updateManager.downloadUpdate()
                    },
                    onSkip: {
                        // Save skipped version
                        UserDefaults.standard.set(release.version, forKey: "skippedVersion")
                    },
                    onRemindLater: {
                        // Do nothing, will check again on next scheduled time
                    }
                )
            }
        }
    }
}

#Preview {
    UpdateSettingsView()
        .frame(width: 600, height: 450)
}
