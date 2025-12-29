import SwiftUI
import UniformTypeIdentifiers

// MARK: - ContentView

struct ContentView: View {
    enum DropZoneType {
        case source
        case destination
    }

    @Namespace private var focusNamespace
    @State private var sourceURL: URL?
    @State private var destinationURL: URL?
    @State private var linkName: String = ""
    @State private var showSuccess: Bool = false
    @State private var isCreatingLink: Bool = false
    @FocusState private var focusedZone: DropZoneType?

    var body: some View {
        VStack(spacing: 24) {
            // Drop Zones
            HStack(spacing: 16) {
                DropZone(
                    title: "Source",
                    subtitle: "Drag file or folder here",
                    url: self.$sourceURL,
                    systemImage: "doc.on.doc",
                    isFocused: self.focusedZone == .source,
                )
                .focusable()
                .focused(self.$focusedZone, equals: .source)
                .focusEffectDisabled()
                .onKeyPress(.delete) {
                    if self.focusedZone == .source {
                        self.sourceURL = nil
                        self.linkName = ""
                        return .handled
                    }
                    return .ignored
                }

                DropZone(
                    title: "Destination",
                    subtitle: "Drag destination folder here",
                    url: self.$destinationURL,
                    systemImage: "folder",
                    acceptsOnlyFolders: true,
                    isFocused: self.focusedZone == .destination,
                )
                .focusable()
                .focused(self.$focusedZone, equals: .destination)
                .focusEffectDisabled()
                .onKeyPress(.delete) {
                    if self.focusedZone == .destination {
                        self.destinationURL = nil
                        return .handled
                    }
                    return .ignored
                }
            }
            .frame(height: 160)

            // Name Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Link Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Enter name", text: self.$linkName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(self.sourceURL == nil)
            }

            // Buttons
            HStack(spacing: 12) {
                Button(action: self.createSymlink) {
                    HStack {
                        if self.isCreatingLink {
                            ProgressView()
                                .controlSize(.small)
                        } else if self.showSuccess {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .controlSize(.large)
                        } else {
                            Text("Create Symlink")
                        }
                    }
                    .frame(width: 400, height: 36)
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.sourceURL == nil || self.destinationURL == nil || self.linkName.isEmpty || self.isCreatingLink)

                Button(action: self.clearAll) {
                    Text("Clear")
                        .frame(width: 100, height: 36)
                }
                .buttonStyle(.bordered)
                .disabled(self.sourceURL == nil && self.destinationURL == nil && self.linkName.isEmpty && self.focusedZone == nil)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(32)
        .frame(width: 600)
        .focusScope(self.focusNamespace)
        .overlay(alignment: .topLeading) {
            // Prevent macOS from auto-focusing the first focusable child (Source) on launch,
            // which causes a one-frame "blue flash". This invisible view absorbs default focus.
            Color.clear
                .frame(width: 1, height: 1)
                .focusable()
                .focusEffectDisabled()
                .prefersDefaultFocus(in: self.focusNamespace)
                .accessibilityHidden(true)
        }
        .onChange(of: self.sourceURL) { oldValue, newValue in
            if let newValue, linkName.isEmpty || oldValue != nil {
                self.linkName = newValue.lastPathComponent
            }
        }
    }

    private func clearAll() {
        self.sourceURL = nil
        self.destinationURL = nil
        self.linkName = ""
        self.showSuccess = false
        self.focusedZone = nil
    }

    private func createSymlink() {
        guard
            let sourceURL,
            let destinationURL,
            !linkName.isEmpty else { return }

        self.isCreatingLink = true

        Task {
            do {
                let symlinkURL = destinationURL.appendingPathComponent(self.linkName)

                // Create the symbolic link
                try FileManager.default.createSymbolicLink(
                    at: symlinkURL,
                    withDestinationURL: sourceURL,
                )

                await MainActor.run {
                    self.showSuccess = true
                    self.isCreatingLink = false

                    // Reveal in Finder
                    NSWorkspace.shared.activateFileViewerSelecting([symlinkURL])

                    // Reset after a delay
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        await MainActor.run {
                            self.showSuccess = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isCreatingLink = false
                    // Show error alert
                    let alert = NSAlert()
                    alert.messageText = "Failed to Create Symlink"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
}

// MARK: - DropZone

struct DropZone: View {
    let title: String
    let subtitle: String
    @Binding var url: URL?
    let systemImage: String
    var acceptsOnlyFolders: Bool = false
    var isFocused: Bool = false

    @State private var isTargeted: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: self.systemImage)
                .font(.system(size: 32))
                .frame(width: 40, height: 40)
                .foregroundStyle(url != nil ? .primary : .secondary)

            if let url {
                Text(url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(url.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(self.title)
                    .font(.headline)

                Text(self.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(self.isTargeted ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            self.isTargeted || self.isFocused ? Color.accentColor : Color.secondary.opacity(0.3),
                            style: StrokeStyle(lineWidth: 2, dash: [8, 4]),
                        ),
                ),
        )
        .onDrop(of: [.fileURL], isTargeted: self.$isTargeted) { providers in
            guard let provider = providers.first else { return false }

            _ = provider.loadObject(ofClass: URL.self) { droppedURL, _ in
                guard let droppedURL else { return }

                DispatchQueue.main.async {
                    var isDirectory: ObjCBool = false
                    FileManager.default.fileExists(atPath: droppedURL.path(percentEncoded: false), isDirectory: &isDirectory)

                    if self.acceptsOnlyFolders, !isDirectory.boolValue {
                        let alert = NSAlert()
                        alert.messageText = "Invalid Drop"
                        alert.informativeText = "Please drop a folder here."
                        alert.alertStyle = .warning
                        alert.runModal()
                        return
                    }

                    self.url = droppedURL
                }
            }

            return true
        }
    }
}

#Preview {
    ContentView()
}
