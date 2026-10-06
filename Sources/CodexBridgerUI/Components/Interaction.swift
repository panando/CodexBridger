import Foundation

// MARK: - Interaction state
//
// Hover/press/focus/disabled used to be implicit in each view, which is exactly why
// the states were inconsistent between components. The transitions live here as a
// pure function so they can be tested without rendering anything.

public enum ControlEvent: Equatable, Sendable {
    case hoverEnter
    case hoverExit
    case pressDown
    case pressUp
    case focusGain
    case focusLoss
    case enable
    case disable
}

/// The visual phase a control should render in.
public enum ControlPhase: Equatable, Sendable {
    case disabled
    case pressed
    case focusedHovered
    case focused
    case hovered
    case normal
}

public struct ControlInteractionState: Equatable, Sendable {
    public private(set) var isHovered = false
    public private(set) var isPressed = false
    public private(set) var isFocused = false
    public private(set) var isEnabled = true

    /// Optional label used for accessibility; stored so components can assert on it.
    public private(set) var activationCount = 0

    public init() {}

    public var phase: ControlPhase {
        if !isEnabled { return .disabled }
        if isPressed { return .pressed }
        if isFocused && isHovered { return .focusedHovered }
        if isFocused { return .focused }
        if isHovered { return .hovered }
        return .normal
    }

    /// Whether the control should respond to pointer or keyboard activation.
    public var isInteractive: Bool { isEnabled }

    /// Applies an event and reports whether it counted as an activation.
    ///
    /// Activation requires a press that ends while the pointer is still inside and the
    /// control is enabled. That is what prevents the double-fire and drag-out
    /// mis-triggers that made the icon buttons feel unreliable.
    @discardableResult
    public mutating func send(_ event: ControlEvent) -> Bool {
        switch event {
        case .hoverEnter:
            isHovered = true
            return false
        case .hoverExit:
            isHovered = false
            // Leaving cancels a held press so a drag-out never activates.
            isPressed = false
            return false
        case .pressDown:
            guard isEnabled else { return false }
            isPressed = true
            return false
        case .pressUp:
            guard isEnabled, isPressed else {
                isPressed = false
                return false
            }
            isPressed = false
            guard isHovered else { return false }
            activationCount += 1
            return true
        case .focusGain:
            isFocused = true
            return false
        case .focusLoss:
            isFocused = false
            isPressed = false
            return false
        case .enable:
            isEnabled = true
            return false
        case .disable:
            isEnabled = false
            isHovered = false
            isPressed = false
            return false
        }
    }
}

/// Keyboard navigation over a list of options.
///
/// Used by the dropdown so arrow keys, Home/End and type-to-select all behave the same
/// way regardless of where the option list is rendered.
public struct SelectionCursor: Equatable, Sendable {
    public private(set) var index: Int?

    public init(index: Int? = nil) {
        self.index = index
    }

    public mutating func move(by offset: Int, count: Int) {
        guard count > 0 else { index = nil; return }
        guard let current = index else {
            index = offset >= 0 ? 0 : count - 1
            return
        }
        index = min(max(current + offset, 0), count - 1)
    }

    public mutating func moveToStart() { if index != nil { index = 0 } }

    public mutating func moveToEnd(count: Int) {
        guard count > 0, index != nil else { return }
        index = count - 1
    }

    /// Clamps the cursor after the option list changes size.
    public mutating func clamp(count: Int) {
        guard let current = index else { return }
        if count == 0 { index = nil; return }
        index = min(max(current, 0), count - 1)
    }

    public mutating func select(_ newIndex: Int?, count: Int) {
        guard let newIndex, count > 0 else { index = nil; return }
        index = min(max(newIndex, 0), count - 1)
    }
}
