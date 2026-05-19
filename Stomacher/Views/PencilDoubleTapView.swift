import SwiftUI
import UIKit

struct PencilDoubleTapView: UIViewRepresentable {
    var store: PatternStore

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false

        let interaction = UIPencilInteraction()
        interaction.delegate = context.coordinator
        view.addInteraction(interaction)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.store = store
    }

    @MainActor
    final class Coordinator: NSObject, UIPencilInteractionDelegate {
        var store: PatternStore

        init(store: PatternStore) {
            self.store = store
        }

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            store.togglePaintAndEraseFromPencilDoubleTap()
        }
    }
}

