import SwiftUI
import UIKit

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

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = true
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        context.coordinator.panGesture = pan
        context.coordinator.tapGesture = tap
        context.coordinator.update(store: store, cellSize: cellSize, isEnabled: isEnabled, usesApplePencilOnly: usesApplePencilOnly)
        return view
    }

    func updateUIView(_ uiView: DrawingTouchView, context: Context) {
        context.coordinator.update(store: store, cellSize: cellSize, isEnabled: isEnabled, usesApplePencilOnly: usesApplePencilOnly)
        uiView.isUserInteractionEnabled = isEnabled
    }

    final class DrawingTouchView: UIView {}

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var store: PatternStore
        private var cellSize: CGFloat = 1
        private var isEnabled = true
        private var usesApplePencilOnly = false

        weak var panGesture: UIPanGestureRecognizer?
        weak var tapGesture: UITapGestureRecognizer?

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
                    NSNumber(value: UITouch.TouchType.pencil.rawValue)
                ]

            panGesture?.isEnabled = isEnabled
            tapGesture?.isEnabled = isEnabled
            panGesture?.allowedTouchTypes = allowedTouchTypes
            tapGesture?.allowedTouchTypes = allowedTouchTypes
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard isEnabled else { return }

            switch recognizer.state {
            case .began:
                begin(location: recognizer.location(in: recognizer.view))
            case .changed:
                update(location: recognizer.location(in: recognizer.view))
            case .ended, .cancelled, .failed:
                store.endInteraction()
            default:
                break
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard isEnabled, recognizer.state == .ended else { return }
            begin(location: recognizer.location(in: recognizer.view))
            store.endInteraction()
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
