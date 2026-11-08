import SwiftUI
import AVFoundation

struct MirrorTabView: View {
    @State private var authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var denied = AVCaptureDevice.authorizationStatus(for: .video) == .denied

    var body: some View {
        if authorized {
            CameraPreview()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Text("Nothing is recorded").font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)).padding(8)
                }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "web.camera").font(.system(size: 22)).foregroundStyle(.secondary)
                Text(denied ? "Camera access was declined" : "Quick mirror check before a call").font(.system(size: 12, weight: .semibold))
                if denied {
                    Button("Open Privacy Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!) }
                } else {
                    Button("Allow Camera") {
                        AVCaptureDevice.requestAccess(for: .video) { ok in DispatchQueue.main.async { authorized = ok; denied = !ok } }
                    }
                }
            }
            .buttonStyle(.loftProminent()).controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraView { CameraView() }
    func updateNSView(_ nsView: CameraView, context: Context) {}
    static func dismantleNSView(_ nsView: CameraView, coordinator: ()) { nsView.stop() }
}

final class CameraView: NSView {
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        configure()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func configure() {
        session.sessionPreset = .medium
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device) else { return }
        if session.canAddInput(input) { session.addInput(input) }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.connection?.automaticallyAdjustsVideoMirroring = false
        layer.connection?.isVideoMirrored = true
        self.layer?.addSublayer(layer)
        previewLayer = layer
        DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
    }

    override func layout() { super.layout(); previewLayer?.frame = bounds }

    func stop() { DispatchQueue.global(qos: .userInitiated).async { [session] in session.stopRunning() } }
}
