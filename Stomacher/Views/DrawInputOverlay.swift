import SwiftUI
import UIKit

enum EditingInputSupport {
    static var isRunningOnMac: Bool {
        if ProcessInfo.processInfo.isiOSAppOnMac {
            return true
        }

        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    @MainActor
    static var supportsApplePencilEditing: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && !isRunningOnMac
    }
}

struct DrawInputOverlay: UIViewRepresentable {
    var store: PatternStore
    var cellSize: CGFloat
    var isEnabled: Bool
    var usesApplePencilOnly: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeUIView(context: Context) -> DrawingTouchView {
        let view = DrawingTouchView()
        view.backgroundColor = .clear
        view.isOpaque = false

        let draw = DrawingGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDraw(_:)))
        draw.cancelsTouchesInView = true
        draw.delegate = context.coordinator
        view.addGestureRecognizer(draw)

        context.coordinator.drawGesture = draw
        context.coordinator.update(store: store, cellSize: cellSize, isEnabled: isEnabled, usesApplePencilOnly: usesApplePencilOnly)
        return view
    }

    func updateUIView(_ uiView: DrawingTouchView, context: Context) {
        context.coordinator.update(store: store, cellSize: cellSize, isEnabled: isEnabled, usesApplePencilOnly: usesApplePencilOnly)
        uiView.isUserInteractionEnabled = isEnabled
    }

    final class DrawingTouchView: UIView {}

    final class DrawingGestureRecognizer: UIGestureRecognizer {
        private var activeTouch: UITouch?
        private(set) var currentLocation: CGPoint = .zero

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            guard state == .possible, activeTouch == nil, touches.count == 1, let touch = touches.first, let view else {
                state = .failed
                return
            }

            activeTouch = touch
            currentLocation = touch.location(in: view)
            state = .began
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let touch = trackedTouch(in: touches), let view else { return }
            currentLocation = touch.location(in: view)
            state = .changed
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            guard trackedTouch(in: touches) != nil else { return }
            state = .ended
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            guard trackedTouch(in: touches) != nil else { return }
            state = .cancelled
        }

        override func reset() {
            activeTouch = nil
            currentLocation = .zero
        }

        private func trackedTouch(in touches: Set<UITouch>) -> UITouch? {
            guard let activeTouch else { return nil }
            return touches.first { $0 === activeTouch }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var store: PatternStore
        private var cellSize: CGFloat = 1
        private var isEnabled = true
        private var usesApplePencilOnly = false

        weak var drawGesture: DrawingGestureRecognizer?

        init(store: PatternStore) {
            self.store = store
        }

        func update(store: PatternStore, cellSize: CGFloat, isEnabled: Bool, usesApplePencilOnly: Bool) {
            self.store = store
            self.cellSize = max(1, cellSize)
            self.isEnabled = isEnabled
            self.usesApplePencilOnly = usesApplePencilOnly

            let allowedTouchTypes = usesApplePencilOnly
                ? [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
                : [
                    NSNumber(value: UITouch.TouchType.direct.rawValue),
                    NSNumber(value: UITouch.TouchType.pencil.rawValue),
                    NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)
                ]

            drawGesture?.isEnabled = isEnabled
            drawGesture?.allowedTouchTypes = allowedTouchTypes
        }

        @objc func handleDraw(_ recognizer: DrawingGestureRecognizer) {
            guard isEnabled else { return }

            switch recognizer.state {
            case .began:
                begin(location: recognizer.currentLocation)
            case .changed:
                update(location: recognizer.currentLocation)
            case .ended, .cancelled, .failed:
                store.endInteraction()
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard isEnabled else { return false }
            return !usesApplePencilOnly || touch.type == .pencil
        }

        private func begin(location: CGPoint) {
            store.beginInteraction(at: coordinate(at: location))
        }

        private func update(location: CGPoint) {
            store.updateInteraction(at: coordinate(at: location))
        }

        private func coordinate(at location: CGPoint) -> GridCoordinate {
            let coordinate = GridCoordinate(
                x: Int((location.x / cellSize).rounded(.down)),
                y: Int((location.y / cellSize).rounded(.down))
            )
            return coordinate
        }
    }
}
