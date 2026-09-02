import SwiftUI
import AVFoundation
import UIKit

/// Finds a usable video camera, including the cloud simulator's injected `.external` webcam.
enum CameraHardware {
    static var hasCamera: Bool { videoDevice() != nil }

    static func videoDevice() -> AVCaptureDevice? {
        var types: [AVCaptureDevice.DeviceType] = [
            .builtInLiDARDepthCamera,
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
        ]
        if #available(iOS 17.0, *) {
            types.append(.external)
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .unspecified
        )
        if let back = discovery.devices.first(where: { $0.position == .back }) {
            return back
        }
        if #available(iOS 17.0, *) {
            if let external = discovery.devices.first(where: { $0.deviceType == .external }) {
                return external
            }
        }
        return discovery.devices.first
    }
}

/// Real AVFoundation preview for a running capture session.
struct CameraProxyView: View {
    var session: AVCaptureSession
    var onPreviewLayer: ((AVCaptureVideoPreviewLayer) -> Void)? = nil

    var body: some View {
        ActualCameraView(session: session, onPreviewLayer: onPreviewLayer)
    }

    static var hasRearCamera: Bool { CameraHardware.hasCamera }
}

// MARK: - Permission denied (distinct from no-device)

struct CameraPermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
            Text("Camera access is off")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(.white)
            Text("Turn on camera access in Settings to inspect roofs live.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 22)
                    .background(Theme.ember, in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

// MARK: - No camera device

struct CameraUnavailableView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.metering.center.weighted")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
            Text("No camera found")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(.white)
            Text("Connect a camera or try again on a device.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

// MARK: - Real camera preview

struct ActualCameraView: UIViewRepresentable {
    let session: AVCaptureSession
    var onPreviewLayer: ((AVCaptureVideoPreviewLayer) -> Void)? = nil

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        onPreviewLayer?(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        onPreviewLayer?(uiView.previewLayer)
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
