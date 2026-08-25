import SwiftUI
import UIKit

/// Captures hardware keyboard input — arrow keys, Return, and Space — on
/// iPad and forwards it as a simple command. SwiftUI cannot observe arrow
/// keys before iOS 17, so a tiny zero-sized UIView hosts UIKeyCommands
/// instead. It stays transparent to touches and VoiceOver.
struct KeyboardCommandCapture: UIViewRepresentable {
    /// The commands the calling screen understands.
    enum Command {
        case up, down, left, right, confirm
    }

    let onCommand: (Command) -> Void

    func makeUIView(context: Context) -> CommandCaptureView {
        let view = CommandCaptureView()
        view.onCommand = onCommand
        return view
    }

    func updateUIView(_ uiView: CommandCaptureView, context: Context) {
        uiView.onCommand = onCommand
        if !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }
}

/// A transparent view that becomes first responder and serves key commands.
final class CommandCaptureView: UIView {
    var onCommand: ((KeyboardCommandCapture.Command) -> Void)?

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            return
        }
        becomeFirstResponder()
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(
                input: UIKeyCommand.inputUpArrow,
                modifierFlags: [],
                action: #selector(handleUp)
            ),
            UIKeyCommand(
                input: UIKeyCommand.inputDownArrow,
                modifierFlags: [],
                action: #selector(handleDown)
            ),
            UIKeyCommand(
                input: UIKeyCommand.inputLeftArrow,
                modifierFlags: [],
                action: #selector(handleLeft)
            ),
            UIKeyCommand(
                input: UIKeyCommand.inputRightArrow,
                modifierFlags: [],
                action: #selector(handleRight)
            ),
            UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(handleConfirm)),
            UIKeyCommand(input: " ", modifierFlags: [], action: #selector(handleConfirm)),
        ]
    }

    @objc private func handleUp() {
        onCommand?(.up)
    }

    @objc private func handleDown() {
        onCommand?(.down)
    }

    @objc private func handleLeft() {
        onCommand?(.left)
    }

    @objc private func handleRight() {
        onCommand?(.right)
    }

    @objc private func handleConfirm() {
        onCommand?(.confirm)
    }
}
