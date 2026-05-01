import SwiftUI
import AVFoundation

/// Wraps a real AVFoundation camera preview when a rear camera exists,
/// otherwise shows a Rork-friendly placeholder for the cloud simulator.
struct CameraProxyView: View {
    var body: some View {
        if Self.hasRearCamera {
            ActualCameraView()
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
            // Dark gradient stand-in for a viewfinder
            LinearGradient(colors: [
                Color(red: 0.04, green: 0.07, blue: 0.16),
                Color(red: 0.10, green: 0.14, blue: 0.26)
            ], startPoint: .top, endPoint: .bottom)

            // Faux roof grid
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

            // Sweeping LiDAR line
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
                Text("LiDAR camera unavailable in preview")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Install RoofWise on your device via the Rork App\nto capture live roof scans.")
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
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.startSession()
        return view
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        private let session = AVCaptureSession()
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        func startSession() {
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.session = session
            session.beginConfiguration()
            if let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
            DispatchQueue.global(qos: .userInitiated).async { [session] in
                session.startRunning()
            }
        }
    }
}
