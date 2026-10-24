import SwiftUI
import UniformTypeIdentifiers

/// Hardware intake: the Control Center's signature door. A new user points
/// the app at a photo or scan of what they own — a board, a flight
/// controller, a label, a QR code — and the app figures out the setup.
/// v0.1 ships the intake itself; the recognition engine (QR/serial first,
/// photo match second, always confirm-before-configure) plugs in behind it.
struct HardwareView: View {
    @State private var pickedImage: NSImage? = nil
    @State private var pickedName: String = ""
    @State private var isImporterPresented = false
    @State private var fleet: [RobotDevice] = RobotDevice.samples
    @State private var newName: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hardware")
                        .font(.largeTitle.bold())
                    Text("Show the app what you've got. It works out what it needs.")
                        .foregroundStyle(.secondary)
                }

                dropZone

                if let image = pickedImage {
                    intakeCard(image: image)
                }

                fleetList
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .navigationTitle("Hardware")
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                let scoped = url.startAccessingSecurityScopedResource()
                if let img = NSImage(contentsOf: url) {
                    pickedImage = img
                    pickedName = url.deletingPathExtension().lastPathComponent
                }
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            for provider in providers {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data, let img = NSImage(data: data) {
                        DispatchQueue.main.async { pickedImage = img }
                    }
                }
            }
            return true
        }
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Drop a photo of your hardware here")
                .font(.title3.weight(.medium))
            Text("A flight controller, a dev board, a product label, a QR code — any of them is enough to start.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose a photo…") { isImporterPresented = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(36)
        .background(RoundedRectangle(cornerRadius: 16).strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])))
    }

    private func intakeCard(image: NSImage) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 180, height: 135)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 8) {
                Text("Intake received")
                    .font(.headline)
                Text("The recognition engine — QR and serial decoding first, photo matching second, always asking you to confirm before it configures anything — plugs in here. For now, name it and add it to your fleet:")
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("e.g. Pixhawk 6C", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                    Button("Add to fleet") {
                        let name = newName.isEmpty ? (pickedName.isEmpty ? "Unnamed hardware" : pickedName) : newName
                        fleet.append(RobotDevice(name: name, kind: "Added by photo intake", connection: "Not connected", status: "Awaiting identification"))
                        newName = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(.quaternary.opacity(0.55)))
    }

    private var fleetList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your fleet")
                .font(.title2.bold())
            ForEach(fleet) { device in
                HStack(spacing: 12) {
                    Image(systemName: "airplane.circle")
                        .font(.title2).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name).font(.headline)
                        Text(device.kind).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(device.status).font(.callout.weight(.medium))
                        Text(device.connection).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
    }
}
