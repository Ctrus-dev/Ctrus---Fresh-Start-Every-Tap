import SceneKit
import simd
import SwiftUI
import UIKit

/// Interactive USDZ model: drag to rotate freely around its own center,
/// and recolors its accent material to match the app's active theme color.
struct RotatingModel3DView: View {
  var themeColor: Color
  var size: CGFloat = 380

  var body: some View {
    RotatingModel3DRepresentable(themeColor: themeColor)
      .frame(width: size, height: size)
  }
}

private struct RotatingModel3DRepresentable: UIViewRepresentable {
  var themeColor: Color

  func makeUIView(context: Context) -> SCNView {
    let scnView = SCNView()
    scnView.backgroundColor = .clear
    scnView.antialiasingMode = .multisampling4X
    scnView.autoenablesDefaultLighting = true
    scnView.isUserInteractionEnabled = true

    let scene = SCNScene()
    scnView.scene = scene

    let cameraNode = SCNNode()
    cameraNode.camera = SCNCamera()
    cameraNode.position = SCNVector3(0, 0, 3.4)
    scene.rootNode.addChildNode(cameraNode)

    let pivotNode = SCNNode()
    scene.rootNode.addChildNode(pivotNode)

    if let modelURL = Bundle.main.url(forResource: "Ctrus_3D", withExtension: "usdz"),
      let modelScene = try? SCNScene(url: modelURL, options: nil)
    {
      let modelNode = SCNNode()
      for child in modelScene.rootNode.childNodes {
        modelNode.addChildNode(child)
      }
      centerAndScale(modelNode)
      pivotNode.addChildNode(modelNode)
      context.coordinator.modelNode = modelNode
      context.coordinator.applyThemeColor(themeColor, animated: false)
    }

    context.coordinator.pivotNode = pivotNode

    let panGesture = UIPanGestureRecognizer(
      target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
    scnView.addGestureRecognizer(panGesture)

    return scnView
  }

  func updateUIView(_ scnView: SCNView, context: Context) {
    context.coordinator.applyThemeColor(themeColor, animated: true)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  private func centerAndScale(_ node: SCNNode) {
    let (minBox, maxBox) = node.boundingBox
    let center = SCNVector3(
      (minBox.x + maxBox.x) / 2,
      (minBox.y + maxBox.y) / 2,
      (minBox.z + maxBox.z) / 2
    )

    let extent = SCNVector3(
      maxBox.x - minBox.x, maxBox.y - minBox.y, maxBox.z - minBox.z)
    let largestDimension = max(extent.x, max(extent.y, extent.z))
    guard largestDimension > 0 else { return }

    let scale = Float(2.9) / largestDimension
    node.scale = SCNVector3(scale, scale, scale)
    // Position is applied after scale in the node's transform, so the
    // center offset must be scaled too or the pivot won't land on the
    // model's true visual center.
    node.position = SCNVector3(-center.x * scale, -center.y * scale, -center.z * scale)
  }

  final class Coordinator: NSObject {
    var pivotNode: SCNNode?
    var modelNode: SCNNode?

    private var accentMaterials: [SCNMaterial] = []
    private var lastPanTranslation: CGPoint = .zero
    private var yaw: Float = 0
    private var pitch: Float = 0

    private static let dragRotationSpeed: Float = 0.01
    private static let maxTiltRadians: Float = .pi / 2.4

    func applyThemeColor(_ color: Color, animated: Bool) {
      guard let modelNode else { return }
      if accentMaterials.isEmpty {
        accentMaterials = collectAccentMaterials(from: modelNode)
      }

      let uiColor = UIColor(color)
      SCNTransaction.begin()
      SCNTransaction.animationDuration = animated ? 0.35 : 0
      for material in accentMaterials {
        material.diffuse.contents = uiColor
      }
      SCNTransaction.commit()
    }

    // The bundled model's "Verde" (green) material is the accent piece;
    // its other material ("Branco"/steel) stays neutral across themes.
    private func collectAccentMaterials(from node: SCNNode) -> [SCNMaterial] {
      var result: [SCNMaterial] = []
      if let geometry = node.geometry {
        result.append(
          contentsOf: geometry.materials.filter { $0.name?.contains("Verde") == true })
      }
      for child in node.childNodes {
        result.append(contentsOf: collectAccentMaterials(from: child))
      }
      return result
    }

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
      guard let pivotNode else { return }

      switch gesture.state {
      case .began:
        lastPanTranslation = .zero
      case .changed:
        let translation = gesture.translation(in: gesture.view)
        let deltaX = Float(translation.x - lastPanTranslation.x)
        let deltaY = Float(translation.y - lastPanTranslation.y)
        lastPanTranslation = translation

        yaw += deltaX * Self.dragRotationSpeed
        pitch += deltaY * Self.dragRotationSpeed
        pitch = max(-Self.maxTiltRadians, min(Self.maxTiltRadians, pitch))

        // Compose pitch/yaw as separate rotations about fixed world axes
        // (not SCNNode's default Euler order, which nests X inside the
        // already-yawed local space) so a vertical drag always tilts the
        // same way on screen, even after the model has been turned to
        // face away from the camera.
        let yawRotation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        let pitchRotation = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
        pivotNode.simdOrientation = pitchRotation * yawRotation
      default:
        break
      }
    }
  }
}

#Preview {
  RotatingModel3DView(themeColor: ThemeManager.shared.themeColor)
}
