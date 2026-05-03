import Foundation
import SwiftUI
import ARKit
import RealityKit
import ModelIO
import Metal
import MetalKit
import simd
import UIKit

/// LiDAR-aware roof analysis utilities. All public surface is
/// `nonisolated`/`static` so callers don't need to think about actor hops.
///
/// The `meshWithClassification` scene reconstruction gives us:
///   - real roof surface area (replaces our gyroscope/visual square estimate)
///   - real roof pitch from the surface normal (replaces motion-based pitch)
///   - geometry we can export to USDZ for AR QuickLook.
enum LiDARRoofService {

    // MARK: - Capability

    /// `true` on iPhones / iPads with LiDAR (iPhone 12 Pro and later, iPad Pro 2020+).
    /// Read via `ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)`
    /// per Apple's recommended availability check.
    static var hasLiDAR: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
    }

    // MARK: - Roof surface area (square feet)

    /// Sum of triangle areas across all mesh faces whose normal points
    /// "roof-like" upward (between 5° and 70° from horizontal — excludes the
    /// ground and walls). Result is converted from m² to ft².
    static func roofSurfaceAreaSquareFeet(meshAnchors: [ARMeshAnchor]) -> Double {
        var totalAreaM2: Double = 0
        for anchor in meshAnchors {
            totalAreaM2 += roofAreaM2(for: anchor)
        }
        return totalAreaM2 * 10.7639  // m² → ft²
    }

    /// Average pitch (degrees from horizontal) across the roof-like faces.
    /// Returns `nil` if no roof faces were found.
    static func roofPitchDegrees(meshAnchors: [ARMeshAnchor]) -> Double? {
        var sumNormal = SIMD3<Double>(repeating: 0)
        var weight: Double = 0
        for anchor in meshAnchors {
            let (n, w) = weightedRoofNormal(for: anchor)
            sumNormal += n
            weight += w
        }
        guard weight > 0 else { return nil }
        let avg = simd_normalize(sumNormal / weight)
        let up = SIMD3<Double>(0, 1, 0)
        let cosAngle = max(-1.0, min(1.0, abs(simd_dot(avg, up))))
        let angleRad = acos(cosAngle)
        return angleRad * 180.0 / .pi
    }

    // MARK: - Triangle iteration helpers

    /// Iterates faces of an ARMeshAnchor, calling the closure with each
    /// triangle's three world-space vertices.
    private static func forEachTriangle(in anchor: ARMeshAnchor,
                                        _ body: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) -> Void) {
        let geometry = anchor.geometry
        let faces = geometry.faces
        let vertices = geometry.vertices
        let transform = anchor.transform

        let vBuffer = vertices.buffer.contents()
        let fBuffer = faces.buffer.contents()
        let stride = vertices.stride
        let bytesPerIndex = faces.bytesPerIndex
        let indicesPerFace = faces.indexCountPerPrimitive

        guard indicesPerFace == 3 else { return }

        for f in 0..<faces.count {
            let i0 = faceIndex(buffer: fBuffer, face: f, slot: 0,
                               bytesPerIndex: bytesPerIndex, indicesPerFace: indicesPerFace)
            let i1 = faceIndex(buffer: fBuffer, face: f, slot: 1,
                               bytesPerIndex: bytesPerIndex, indicesPerFace: indicesPerFace)
            let i2 = faceIndex(buffer: fBuffer, face: f, slot: 2,
                               bytesPerIndex: bytesPerIndex, indicesPerFace: indicesPerFace)

            let v0 = readVertex(buffer: vBuffer, index: i0, stride: stride)
            let v1 = readVertex(buffer: vBuffer, index: i1, stride: stride)
            let v2 = readVertex(buffer: vBuffer, index: i2, stride: stride)

            let w0 = applyTransform(transform, v0)
            let w1 = applyTransform(transform, v1)
            let w2 = applyTransform(transform, v2)
            body(w0, w1, w2)
        }
    }

    private static func faceIndex(buffer: UnsafeMutableRawPointer,
                                  face: Int, slot: Int,
                                  bytesPerIndex: Int, indicesPerFace: Int) -> Int {
        let offset = (face * indicesPerFace + slot) * bytesPerIndex
        if bytesPerIndex == 4 {
            return Int(buffer.load(fromByteOffset: offset, as: UInt32.self))
        } else {
            return Int(buffer.load(fromByteOffset: offset, as: UInt16.self))
        }
    }

    private static func readVertex(buffer: UnsafeMutableRawPointer,
                                   index: Int, stride: Int) -> SIMD3<Float> {
        let p = buffer.advanced(by: index * stride).assumingMemoryBound(to: Float.self)
        return SIMD3<Float>(p[0], p[1], p[2])
    }

    private static func applyTransform(_ t: simd_float4x4, _ v: SIMD3<Float>) -> SIMD3<Float> {
        let h = t * SIMD4<Float>(v.x, v.y, v.z, 1.0)
        return SIMD3<Float>(h.x, h.y, h.z)
    }

    private static func roofAreaM2(for anchor: ARMeshAnchor) -> Double {
        var total: Double = 0
        forEachTriangle(in: anchor) { a, b, c in
            let n = simd_cross(b - a, c - a)
            let area = 0.5 * Double(simd_length(n))
            let normal = simd_normalize(n)
            // up-component: 1 = horizontal (floor/ceiling), 0 = vertical (wall)
            let up = abs(Double(normal.y))
            // Roof slopes: between cos(70°) ≈ 0.34 and cos(5°) ≈ 0.996
            if up > 0.34 && up < 0.996 {
                total += area
            }
        }
        return total
    }

    private static func weightedRoofNormal(for anchor: ARMeshAnchor) -> (SIMD3<Double>, Double) {
        var sum = SIMD3<Double>(repeating: 0)
        var weight: Double = 0
        forEachTriangle(in: anchor) { a, b, c in
            let n = simd_cross(b - a, c - a)
            let area = 0.5 * Double(simd_length(n))
            guard area > 1e-6 else { return }
            let normal = simd_normalize(n)
            let upComp = abs(Double(normal.y))
            guard upComp > 0.34 && upComp < 0.996 else { return }
            // Force normal to point upward so they don't cancel.
            let oriented = SIMD3<Double>(Double(normal.x),
                                         Double(abs(normal.y)),
                                         Double(normal.z))
            sum += oriented * area
            weight += area
        }
        return (sum, weight)
    }

    // MARK: - USDZ export

    /// Build a USDZ file containing the LiDAR roof mesh + a colored sphere at
    /// every damage marker, written to a temp URL the caller can present in
    /// QuickLook (`QLPreviewController`).
    static func exportUSDZ(meshAnchors: [ARMeshAnchor],
                           markers: [ARDamageMarker]) throws -> URL {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "LiDARRoofService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Metal device unavailable"])
        }
        let allocator = MTKMeshBufferAllocator(device: device)
        let asset = MDLAsset(bufferAllocator: allocator)

        // Roof mesh nodes (one per anchor)
        for (i, anchor) in meshAnchors.enumerated() {
            if let mdl = makeMDLMesh(from: anchor, allocator: allocator) {
                let object = MDLObject()
                object.name = "RoofMesh_\(i)"
                object.addChild(mdl)
                asset.add(object)
            }
        }

        // Damage marker spheres
        for (i, marker) in markers.enumerated() {
            let sphere = MDLMesh.newEllipsoid(
                withRadii: SIMD3<Float>(repeating: 0.04),
                radialSegments: 24,
                verticalSegments: 16,
                geometryType: .triangles,
                inwardNormals: false,
                hemisphere: false,
                allocator: allocator)
            sphere.name = "Damage_\(marker.type.rawValue)_\(i)"

            // Color
            let scatter = MDLScatteringFunction()
            let material = MDLMaterial(name: "DamageMat_\(i)", scatteringFunction: scatter)
            let uiColor = UIColor(marker.type.color)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
            uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            let color = SIMD3<Float>(Float(r), Float(g), Float(b))
            material.setProperty(MDLMaterialProperty(
                name: "baseColor", semantic: .baseColor,
                float3: color))
            material.setProperty(MDLMaterialProperty(
                name: "emission", semantic: .emission,
                float3: color * 0.6))
            for sub in (sphere.submeshes ?? []) {
                if let s = sub as? MDLSubmesh { s.material = material }
            }

            // Position
            let transform = MDLTransform()
            transform.translation = marker.position
            sphere.transform = transform

            let parent = MDLObject()
            parent.name = sphere.name
            parent.addChild(sphere)
            asset.add(parent)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roofwise_3d_report_\(Int(Date().timeIntervalSince1970)).usdz")
        try asset.export(to: url)
        return url
    }

    private static func makeMDLMesh(from anchor: ARMeshAnchor,
                                    allocator: MDLMeshBufferAllocator) -> MDLMesh? {
        let geom = anchor.geometry
        let verts = geom.vertices
        let faces = geom.faces
        guard faces.indexCountPerPrimitive == 3 else { return nil }

        // Bake anchor.transform into the vertex positions so we don't have to
        // wrestle MDLTransform on a parent hierarchy.
        let vCount = verts.count
        var packed = [Float](repeating: 0, count: vCount * 3)
        let raw = verts.buffer.contents()
        let stride = verts.stride
        let t = anchor.transform
        for i in 0..<vCount {
            let p = raw.advanced(by: i * stride).assumingMemoryBound(to: Float.self)
            let v4 = t * SIMD4<Float>(p[0], p[1], p[2], 1.0)
            packed[i * 3 + 0] = v4.x
            packed[i * 3 + 1] = v4.y
            packed[i * 3 + 2] = v4.z
        }
        let vData = packed.withUnsafeBufferPointer { Data(buffer: $0) }
        let vBuffer = allocator.newBuffer(with: vData, type: .vertex)

        let fBytes = faces.buffer.length
        let fData = Data(bytes: faces.buffer.contents(), count: fBytes)
        let iBuffer = allocator.newBuffer(with: fData, type: .index)
        let indexCount = faces.count * 3
        let bitDepth: MDLIndexBitDepth = (faces.bytesPerIndex == 4) ? .uInt32 : .uInt16

        let submesh = MDLSubmesh(indexBuffer: iBuffer,
                                 indexCount: indexCount,
                                 indexType: bitDepth,
                                 geometryType: .triangles,
                                 material: nil)

        let descriptor = MDLVertexDescriptor()
        descriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3, offset: 0, bufferIndex: 0)
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 3)

        let mesh = MDLMesh(vertexBuffer: vBuffer,
                           vertexCount: vCount,
                           descriptor: descriptor,
                           submeshes: [submesh])

        // Subtle gray material so the roof reads in QuickLook.
        let scatter = MDLScatteringFunction()
        let material = MDLMaterial(name: "RoofMat", scatteringFunction: scatter)
        material.setProperty(MDLMaterialProperty(
            name: "baseColor", semantic: .baseColor,
            float3: SIMD3<Float>(0.62, 0.62, 0.65)))
        for sub in (mesh.submeshes ?? []) {
            if let s = sub as? MDLSubmesh { s.material = material }
        }
        return mesh
    }
}

// Apple's plane classification doesn't include `.roof`, but the values we
// want to honor as "valid roof surfaces" map most closely to ceiling
// (overhead), wall (gable end), and floor (steeply tilted attic floor or
// outdoor surface). This helper centralizes that policy.
extension ARPlaneAnchor.Classification {
    var isValidRoofSurface: Bool {
        switch self {
        case .ceiling, .wall, .floor: return true
        default: return false
        }
    }
}
