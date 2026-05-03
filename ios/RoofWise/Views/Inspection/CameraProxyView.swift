import SwiftUI
import AVFoundation

/// Wraps a real AVFoundation camera preview (sharing the session owned by
/// `CameraCaptureService`) when a rear camera exists, otherwise shows a
/// Rork-friendly placeholder for the cloud simulator.
struct CameraProxyView: View {
    var session: AVCaptureSession? = nil
    /// Optional capture service to receive the preview layer for coordinate mapping.
    var onPreviewLayer: ((AVCaptureVideoPreviewLayer) -> Void)? = nil

    var body: some View {
        if Self.hasRearCamera {
            ActualCameraView(session: session ?? AVCaptureSession(),
                             onPreviewLayer: onPreviewLayer)
        } else {
            CameraPlaceholderView()
        }
    }

    static var hasRearCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }
}

// MARK: - Placeholder (cloud simulator)

struct CameraPlaceholderView: View {
    @State private var sweep: CGFloat = 0

    var body: some View {
        ZStack {
            LinearGradient(colors: [
                Color(red: 0.04, green: 0.07, blue: 0.16),
                Color(red: 0.10, green: 0.14, blue: 0.26)
            ], startPoint: .top, endPoint: .bottom)

            Canvas { ctx, size in
                let cols = 14
                let rows = 22
                let dx = size.width / CGFloat(cols)
                let dy = size.height / CGFloat(rows)
                for r in 0...rows {
                    let y = CGFloat(r) * dy + (r.isMultiple(of: 2) ? dx / 2 : 0)
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(path, with: .color(.white.opacity(0.06)), lineWidth: 0.6)
                }
                for c in 0...cols {
                    let x = CGFloat(c) * dx
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(path, with: .color(.white.opacity(0.05)), lineWidth: 0.6)
                }
            }

            GeometryReader { geo in
                LinearGradient(colors: [
                    Theme.ember.opacity(0),
                    Theme.ember.opacity(0.55),
                    Theme.ember.opacity(0)
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .blur(radius: 8)
                .offset(y: sweep * (geo.size.height + 120) - 120)
            }
            .allowsHitTesting(false)

            VStack(spacing: 12) {
                Image(systemName: "camera.metering.center.weighted")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Live camera unavailable in preview")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Install RoofWise on your device via the Rork App\nto run live shingle detection.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
        .onAppear {
            withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
                sweep = 1
            }
        }
    }
}

// MARK: - Real camera (used on physical device)

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
