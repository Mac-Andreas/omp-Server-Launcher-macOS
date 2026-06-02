// open.mp-styled dark palette, matching the original Qt app's stylesheet.
import SwiftUI
import AppKit

enum Theme {
    static let bg        = Color(hex: 0x20242C)
    static let card      = Color(hex: 0x171A20)
    static let cardHi    = Color(hex: 0x262B34)
    static let border    = Color(hex: 0x333A45)
    static let accent    = Color(hex: 0x7B5CFF)   // purple
    static let text      = Color(hex: 0xE6E9EE)
    static let textDim   = Color(hex: 0x9AA1AD)
    static let good      = Color(hex: 0x3FB950)   // green
    static let goodDark  = Color(hex: 0x2E8B40)   // darker green (Start button)
    static let bad       = Color(hex: 0xE5534B)   // red
    static let badDark   = Color(hex: 0x8E2820)   // dark red (Delete button)
    static let warn      = Color(hex: 0xE0922F)   // orange
    static let warnDark  = Color(hex: 0x9A6113)   // darker orange (Restart button)
    static let caution   = Color(hex: 0xE3C84A)   // yellow (running with warnings)
    static let disabled  = Color(hex: 0x3A4250)   // grey (inactive button)

    static let corner: CGFloat = 9
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// A rounded card container used across tabs.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .background(Theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
    }
}

// Big colored action tile — explicit fill, greys out when disabled. Used for
// the Start / Stop / Restart row.
struct ActionTileStyle: ButtonStyle {
    var fill: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let bg = isEnabled ? fill : Theme.disabled
        return configuration.label
            .font(.system(size: 13, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .imageScale(.medium)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(bg.opacity(configuration.isPressed ? 0.8 : 1))
            .foregroundStyle(isEnabled ? .white : Theme.textDim)
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
            .contentShape(Rectangle())
            .modifier(EnabledHoverCursor(enabled: isEnabled))
    }
}

// Pointing-hand cursor only when the control is enabled. The cursor comes from
// the AppKit cursor-rect overlay (only mounted while enabled) so it survives the
// re-render a click triggers instead of reverting to the arrow.
private struct EnabledHoverCursor: ViewModifier {
    let enabled: Bool
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .brightness(enabled && hovering ? 0.06 : 0)
            .overlay {
                if enabled { PointerCursorRegion().allowsHitTesting(false) }
            }
            .onHover { hovering = $0 }
    }
}

// VSCode-style full-width flush tab strip: equal-width tabs separated by a
// bottom border, the active one marked by an accent underline. No rounded
// segmented-control chrome.
struct FlushTabBar<T: Hashable>: View {
    let tabs: [(value: T, label: String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.value) { tab in
                FlushTab(label: tab.label,
                         active: tab.value == selection) {
                    selection = tab.value
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }
}

private struct FlushTab: View {
    let label: String
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(label)
                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                    .foregroundStyle(active || hovering ? Theme.text : Theme.textDim)
                Spacer(minLength: 0)
                Rectangle()
                    .fill(active ? Theme.accent : (hovering ? Theme.accent.opacity(0.4) : .clear))
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(active ? Theme.cardHi.opacity(0.5)
                        : (hovering ? Theme.cardHi.opacity(0.28) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        // Pointing-hand cursor on hover + track hover for the highlight.
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// AppKit-backed pointing-hand cursor region. A tracking area with `.cursorUpdate`
// makes AppKit re-assert the pointing-hand on every cursor-update event — across
// SwiftUI re-renders and right after a click — so the cursor never flips back to
// the arrow while the pointer is still over the control. `hitTest` returns nil so
// it never eats clicks meant for the SwiftUI content beneath.
private struct PointerCursorRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { CursorTrackingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class CursorTrackingView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for ta in trackingAreas { removeTrackingArea(ta) }
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.activeInActiveApp, .inVisibleRect, .mouseEnteredAndExited, .cursorUpdate],
                owner: self, userInfo: nil))
        }
        override func mouseEntered(with event: NSEvent) { NSCursor.pointingHand.set() }
        override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
        override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
    }
}

// Forces the enclosing NSScrollView to use OVERLAY scrollers, regardless of the
// system "Show scroll bars" setting. A legacy (always-on) scroller reserves a
// ~15pt gutter, which narrows the content only on pages whose content overflows
// — so the layout would shift left when you switch from a short page (no bar) to
// a scrolling one. Overlay scrollers float over the content and reserve nothing,
// so every page keeps the exact same content width.
private struct OverlayScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { apply(from: v) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(from: nsView) }
    }
    // The page's NSScrollView is a SIBLING subtree (this helper is a background),
    // so walk UP to the window's content view, then DOWN to flip every scroll
    // view to overlay — covering whichever ScrollView this page rendered.
    private func apply(from view: NSView) {
        guard let root = view.window?.contentView ?? topAncestor(of: view) else { return }
        flip(root)
    }
    private func topAncestor(of view: NSView) -> NSView? {
        var n = view
        while let s = n.superview { n = s }
        return n
    }
    private func flip(_ view: NSView) {
        if let scroll = view as? NSScrollView {
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
        }
        for sub in view.subviews { flip(sub) }
    }
}

// AppKit-backed I-beam (text-select) cursor region — same approach as the
// pointing-hand region, but asserts the text cursor. Put it BEHIND a text field
// so hovering the field (and its padding) shows the I-beam consistently, matching
// a plain TextField. `hitTest` returns nil so it never eats clicks.
private struct IBeamCursorRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { TextCursorView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class TextCursorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for ta in trackingAreas { removeTrackingArea(ta) }
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.activeInActiveApp, .inVisibleRect, .mouseEnteredAndExited, .cursorUpdate],
                owner: self, userInfo: nil))
        }
        override func mouseEntered(with event: NSEvent) { NSCursor.iBeam.set() }
        override func cursorUpdate(with event: NSEvent) { NSCursor.iBeam.set() }
        override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
    }
}

extension View {
    /// Show the I-beam (text-select) cursor while hovered — for custom text-field
    /// rows where the native field's own cursor region doesn't cover the row.
    func textCursor() -> some View {
        background(IBeamCursorRegion().allowsHitTesting(false))
    }

    /// Force overlay scrollers on the enclosing ScrollView so a visible scrollbar
    /// never reserves layout width (keeps content width identical across pages).
    func overlayScrollers() -> some View {
        background(OverlayScrollers().allowsHitTesting(false))
    }
}

// Pointing-hand cursor on hover for any view (buttons, tabs, rows). The cursor
// itself comes from the AppKit cursor-rect overlay; `onChange` still reports
// hover so callers can drive a highlight.
struct HoverCursor: ViewModifier {
    var onChange: ((Bool) -> Void)? = nil
    func body(content: Content) -> some View {
        content
            .overlay(PointerCursorRegion().allowsHitTesting(false))
            .onHover { onChange?($0) }
    }
}

extension View {
    /// Pointing-hand cursor while hovered.
    func pointerCursor() -> some View { modifier(HoverCursor()) }
    /// Pointing-hand cursor + a brightness bump while hovered (for clickable rows).
    func hoverHighlight() -> some View {
        modifier(HoverHighlight())
    }
}

struct HoverHighlight: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .brightness(hovering ? 0.06 : 0)
            .overlay(PointerCursorRegion().allowsHitTesting(false))
            .onHover { hovering = $0 }
    }
}

/// Compact icon-sized "press and hold to confirm" destructive button. A circular
/// ring fills while held; the action fires only once the hold completes, so a
/// stray click can't delete. Releasing early cancels. Used for per-row trash
/// actions (snapshots, bans) where a full confirm dialog would be heavy.
struct HoldToConfirmIcon: View {
    var seconds: Double = 0.9
    var icon: String = "trash"
    var size: CGFloat = 14
    var help: String = "Press and hold to delete."
    let action: () -> Void

    @State private var progress: Double = 0
    @State private var holding = false
    @State private var hovering = false
    @State private var done = false
    @State private var holdToken = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.bad.opacity(holding ? 0.18 : (hovering ? 0.12 : 0)))
            // Filling ring shows hold progress.
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.bad, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(1.5)
            Image(systemName: done ? "checkmark" : icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Theme.bad)
        }
        .frame(width: size + 14, height: size + 14)
        .contentShape(Circle())
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !holding && !done { startHold() } }
                .onEnded { _ in if !done { cancelHold() } }
        )
        .help(help)
    }

    private func startHold() {
        holding = true
        holdToken += 1
        let token = holdToken
        let remaining = seconds * (1 - progress)
        withAnimation(.linear(duration: remaining)) { progress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
            guard holding, token == holdToken, !done else { return }
            done = true; holding = false
            action()
        }
    }

    private func cancelHold() {
        holding = false
        holdToken += 1
        withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
    }
}

// A destructive-action confirmation card (designed to live inside a .popover):
// a title + body, a Cancel button, and a confirm control that is GATED — first
// shown greyed with a live countdown (e.g. 10 → 0), and only after the countdown
// reaches zero does it swap to a press-and-hold-to-confirm button. This forces a
// deliberate pause + a sustained press before anything irreversible happens.
struct DangerConfirmPopover: View {
    let title: String
    let message: String
    /// Countdown seconds before the hold-to-confirm unlocks.
    var countdown: Int = 10
    /// Label on the unlocked hold button (e.g. "Hold to delete").
    var holdTitle: String
    var holdIcon: String = "trash"
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var remaining: Int
    @State private var ticking = false
    @State private var timer: Timer?

    init(title: String, message: String, countdown: Int = 10,
         holdTitle: String, holdIcon: String = "trash",
         onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        self.title = title; self.message = message; self.countdown = countdown
        self.holdTitle = holdTitle; self.holdIcon = holdIcon
        self.onCancel = onCancel; self.onConfirm = onConfirm
        _remaining = State(initialValue: countdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 14, weight: .bold))
            Text(message).font(.system(size: 12)).foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Cancel") { stop(); onCancel() }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                    .frame(maxWidth: .infinity)

                Group {
                    if remaining > 0 {
                        // Greyed, inert countdown button.
                        HStack(spacing: 6) {
                            Image(systemName: holdIcon)
                            Text("\(holdTitle) (\(remaining))")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(Theme.disabled)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                    } else {
                        HoldToConfirmButton(
                            seconds: 2.0, title: holdTitle, icon: holdIcon,
                            doneText: "Working…") { stop(); onConfirm() }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16).frame(width: 340)
        .onAppear { start() }
        .onDisappear { stop() }
    }

    private func start() {
        remaining = countdown
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if remaining > 0 { remaining -= 1 } else { stop() }
        }
    }
    private func stop() { timer?.invalidate(); timer = nil }
}

// In-window modal overlay: a dimmed backdrop (click anywhere outside the card
// to dismiss) with the content centered on top. Used instead of .sheet so the
// popup is the app's own and outside-clicks close it.
extension View {
    @ViewBuilder
    func appModal<Modal: View>(isPresented: Binding<Bool>,
                               @ViewBuilder content: () -> Modal) -> some View {
        self.overlay {
            if isPresented.wrappedValue {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { isPresented.wrappedValue = false }
                    content()
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
                        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
                        // Swallow taps on the card so they don't dismiss.
                        .onTapGesture { }
                }
                .transition(.opacity)
            }
        }
    }
}

// App-styled text field box: dark fill, rounded, accent border on focus and an
// orange border when flagged invalid. Wrap a TextField/SecureField inside.
struct InputBox<Content: View>: View {
    var invalid: Bool = false
    var corner: CGFloat = Theme.corner
    @ViewBuilder var content: Content

    var body: some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: corner))
            .overlay(
                RoundedRectangle(cornerRadius: corner)
                    .stroke(invalid ? Theme.warn : Theme.border,
                            lineWidth: invalid ? 1.6 : 1)
            )
    }
}

// Fully app-rendered dropdown — NO native Picker/menu anywhere. The closed field
// is our InputBox chrome with the selected label + a chevron; tapping it opens a
// custom overlay list (own rows, hover + selected highlight) anchored under the
// field. Clicking a row selects it; clicking outside or re-tapping closes it.
struct AppDropdown<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, label: String)]
    /// Open the list upward instead of downward — for fields near a container's
    /// bottom edge (e.g. the last field in a modal) where a downward menu would
    /// be clipped.
    var dropUp: Bool = false
    /// Flush style: a borderless, full-bleed field + edge-to-edge menu (no card
    /// outline / rounded corners), matching the Config/Bans server picker so the
    /// Logs scope selector reads identically. Always drops down.
    var flush: Bool = false
    /// Optional right-aligned accessory per menu row (e.g. a status dot + version
    /// pill), keyed by the option's value. Return nil to show nothing for that row.
    var accessory: ((T) -> AnyView?)? = nil

    @State private var open = false
    @State private var hovering = false

    private var selectedLabel: String {
        options.first { $0.value == selection }?.label ?? ""
    }

    // Approx closed-field height, used to drop the menu just beyond it. The flush
    // height matches the Config tab's header strip (40pt field + 12pt padding ×2).
    private var fieldHeight: CGFloat { flush ? 64 : 38 }

    var body: some View {
        if flush { flushBody } else { boxedBody }
    }

    // MARK: Boxed (default) — rounded, outlined field + menu.
    private var boxedBody: some View {
        fieldContent
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner)
                    .stroke(open ? Theme.accent : Theme.border, lineWidth: open ? 1.6 : 1)
            )
            .contentShape(Rectangle())
            .pointerCursor()
            .onTapGesture { open.toggle() }
            // The open list drops straight down INLINE (no popover/OS window): an
            // overlay anchored to the field's bottom edge, offset just below it. It
            // renders above following content (zIndex) and isn't clipped here.
            .overlay(alignment: dropUp ? .bottomLeading : .topLeading) {
                if open {
                    menu.offset(y: dropUp ? -fieldHeight : fieldHeight)
                        .zIndex(100).transition(.opacity)
                }
            }
            .zIndex(open ? 100 : 0)
            .animation(.easeOut(duration: 0.12), value: open)
    }

    // MARK: Flush — borderless full-bleed strip + edge-to-edge menu.
    private var flushBody: some View {
        fieldContent
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: fieldHeight)
            .background(open ? Theme.accent.opacity(0.10)
                        : (hovering ? Theme.cardHi.opacity(0.28) : .clear))
            .contentShape(Rectangle())
            .pointerCursor()
            .onHover { hovering = $0 }
            .onTapGesture { open.toggle() }
            .overlay(alignment: .topLeading) {
                if open { menu.offset(y: fieldHeight).zIndex(100).transition(.opacity) }
            }
            .zIndex(open ? 100 : 0)
            .animation(.easeOut(duration: 0.12), value: open)
    }

    private var fieldContent: some View {
        HStack(spacing: 8) {
            Text(selectedLabel.isEmpty ? "—" : selectedLabel)
                .font(.system(size: 13))
                .foregroundStyle(selectedLabel.isEmpty ? Theme.textDim : Theme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textDim)
                .rotationEffect(.degrees(open ? 180 : 0))
        }
    }

    private var menu: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(options, id: \.value) { opt in
                    DropdownRow(
                        label: opt.label,
                        selected: opt.value == selection,
                        accessory: accessory?(opt.value)
                    ) {
                        selection = opt.value
                        open = false
                    }
                }
            }
            .padding(flush ? 0 : 4)   // flush: rows go edge-to-edge, side to side
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: min(CGFloat(options.count) * 38 + 8, 280))
        // Opaque base (the window bg) UNDER the panel fill, so the menu fully
        // hides same-coloured cards beneath it — otherwise a card's border can
        // bleed through the translucent overlap (the Snapshots dropdown glitch).
        .background(Theme.bg)
        .background(flush ? Theme.card : Theme.cardHi)
        .clipShape(RoundedRectangle(cornerRadius: flush ? 0 : Theme.corner))
        .overlay(alignment: .top) { if flush { Divider().overlay(Theme.border) } }
        .overlay(alignment: .bottom) { if flush { Divider().overlay(Theme.border) } }
        .overlay {
            if !flush {
                RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.border, lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(flush ? 0.25 : 0.4), radius: flush ? 8 : 14, y: 6)
        .padding(flush ? [] : (dropUp ? .bottom : .top), flush ? 0 : 6)
    }
}

private struct DropdownRow: View {
    let label: String
    let selected: Bool
    var accessory: AnyView? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .opacity(selected ? 1 : 0)
                Text(label).font(.system(size: 13))
                    .foregroundStyle(Theme.text).lineLimit(1)
                Spacer(minLength: 8)
                if let accessory { accessory }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Theme.accent.opacity(0.18)
                        : (selected ? Theme.cardHi.opacity(0.6) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).focusable(false)
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// A "(?)" help button: pointing-hand cursor, hover/press highlight, and an
// accent tint while its popover is open (selected). The popover content is
// supplied by the caller.
struct HelpButton<HelpView: View>: View {
    @Binding var isPresented: Bool
    let helpView: HelpView
    @State private var hovering = false

    var body: some View {
        Button { isPresented = true } label: {
            Image(systemName: "questionmark.circle\(isPresented ? ".fill" : "")")
                .font(.system(size: 12))
                .foregroundStyle(isPresented ? Theme.accent
                                 : (hovering ? Theme.text : Theme.textDim))
                .padding(2)
                .background((hovering || isPresented) ? Theme.accent.opacity(0.14) : .clear)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain).focusable(false)
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .popover(isPresented: $isPresented) { helpView }
    }
}

// iOS-style pill switch: green track when on, red when off, with a white knob
// that slides side to side. Fully app-rendered so it looks identical on every
// macOS version. Shared by Settings and the Config filterscript/plugin toggles.
struct IOSToggle: View {
    @Binding var isOn: Bool
    /// Fired only on user taps (not programmatic changes), with the new value.
    var onUserToggle: ((Bool) -> Void)? = nil
    var body: some View {
        Button {
            let new = !isOn
            withAnimation(.easeInOut(duration: 0.15)) { isOn = new }
            onUserToggle?(new)
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Theme.good : Theme.bad)
                    .frame(width: 46, height: 28)
                Circle().fill(.white).frame(width: 22, height: 22).padding(3)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .pointerCursor()
    }
}

// Pill-shaped update-status badge shown next to a server's version pill. Green
// "✓ up to date" when the installed version matches the latest available, or an
// amber "↑ update available — v<latest>" otherwise. Tappable when an update
// exists (the action typically opens the install flow / release page).
struct UpdatePill: View {
    let installed: String?     // installed version (no "v")
    let latest: String?        // latest available version (no "v")
    var big: Bool = false
    var onUpdate: (() -> Void)? = nil
    @State private var hovering = false

    private var upToDate: Bool {
        guard let installed, let latest else { return true }   // unknown ⇒ don't nag
        return installed == latest
    }

    var body: some View {
        let color: Color = upToDate ? Theme.good : Theme.warn
        let label: String = upToDate ? "up to date" : "update — v\(latest ?? "?")"
        let icon = upToDate ? "checkmark.circle.fill" : "arrow.up.circle.fill"

        let content = HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: big ? 11 : 9, weight: .bold))
            Text(label).font(.system(size: big ? 11 : 9, weight: .bold))
                .lineLimit(1).fixedSize()
        }
        .padding(.horizontal, big ? 10 : 7).padding(.vertical, big ? 5 : 3)
        .background(color.opacity(hovering && !upToDate ? 0.3 : 0.18))
        .foregroundStyle(color)
        .clipShape(Capsule())

        if upToDate || onUpdate == nil {
            content
        } else {
            Button { onUpdate?() } label: { content }
                .buttonStyle(.plain).focusable(false)
                .onHover { h in
                    hovering = h
                    if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .help("A newer server build (v\(latest ?? "?")) is available.")
        }
    }
}

// Small status pill (e.g. "Installed", "Beta"). `big` bumps it up for use as a
// version badge next to a server name.
struct Pill: View {
    let text: String
    var color: Color = Theme.good
    var big: Bool = false
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: big ? 11 : 9, weight: .bold))
            .lineLimit(1).fixedSize()
            .padding(.horizontal, big ? 10 : 7).padding(.vertical, big ? 5 : 3)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// A pill with a leading SF Symbol + label (e.g. "🔒 Locked", "Port 7777").
// Same big-pill sizing as the version badge.
struct LabeledPill: View {
    let icon: String
    let text: String
    var color: Color = Theme.accent
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(text).font(.system(size: 11, weight: .bold)).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(color.opacity(0.18))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}

// Small solid-fill button (compact Start/Stop/Restart in a server row). Kept
// deliberately short with small text + icon.
struct MiniButtonStyle: ButtonStyle {
    var fill: Color
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        let bg = isEnabled ? fill : Theme.disabled
        return configuration.label
            .font(.system(size: 12, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .imageScale(.small)
            .foregroundStyle(isEnabled ? .white : Theme.textDim)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(bg.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .modifier(EnabledHoverCursor(enabled: isEnabled))
    }
}

// Equal-width sheet action button (Cancel / Install). Solid colored fill with a
// leading icon. When `enabled` is false it greys out but STAYS clickable so the
// caller can react (e.g. flag an invalid field). When `working`, an animated
// spinner replaces the icon on the left.
struct SheetActionButton: View {
    let title: String
    let icon: String
    let fill: Color
    var enabled: Bool = true
    var working: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if working {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                }
                Text(title).font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(enabled ? .white : Theme.textDim)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(enabled ? fill : Theme.disabled)
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .pointerCursor()
        .disabled(working)
    }
}

// Primary / secondary pill buttons.
struct PillButtonStyle: ButtonStyle {
    var kind: Kind = .secondary
    enum Kind { case primary, secondary, danger, success }

    func makeBody(configuration: Configuration) -> some View {
        let (bg, fg): (Color, Color) = {
            switch kind {
            case .primary: return (Theme.accent, .white)
            case .secondary: return (Theme.card, Theme.text)
            case .danger: return (Theme.badDark, .white)
            case .success: return (Theme.goodDark, .white)
            }
        }()
        return configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(bg.opacity(configuration.isPressed ? 0.8 : 1))
            .foregroundStyle(fg)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner)
                    .stroke(kind == .secondary ? Theme.border : .clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
            .contentShape(Rectangle())
            .hoverHighlight()
    }
}

// MARK: - Page scaffold (global header / scope / footer bands)

// The single block every page lays itself out with. Each band is an opt-in flag:
// pass the band's content to turn it ON, omit it (nil) to turn it OFF. The
// scaffold owns all the shared chrome — header height, the dividers under the
// header and above the footer, and the fixed footer band — so every page lines
// up edge-to-edge no matter which bands it uses.
//
//   PageScaffold(                       // a page with all three bands:
//       header: { FlushTabBar(...) },   // top tab strip (omit ⇒ no header)
//       scope:  { somePicker },         // scope/filter band under the tabs
//       footer: { PageFooterBar(...) }  // bottom action band (omit ⇒ no footer)
//   ) { pageBody }
//
// `scopeFloating` raises the scope band above the content below it, so an open
// dropdown in the scope band isn't drawn behind the page content.
struct PageScaffold<Header: View, Scope: View, Footer: View, Content: View>: View {
    @ViewBuilder var header: () -> Header
    @ViewBuilder var scope: () -> Scope
    @ViewBuilder var footer: () -> Footer
    @ViewBuilder var content: () -> Content
    /// When true, the scope band floats above the content (for open dropdowns).
    var scopeFloating: Bool = false

    init(scopeFloating: Bool = false,
         @ViewBuilder header: @escaping () -> Header = { EmptyView() },
         @ViewBuilder scope: @escaping () -> Scope = { EmptyView() },
         @ViewBuilder footer: @escaping () -> Footer = { EmptyView() },
         @ViewBuilder content: @escaping () -> Content) {
        self.scopeFloating = scopeFloating
        self.header = header
        self.scope = scope
        self.footer = footer
        self.content = content
    }

    private var hasHeader: Bool { Header.self != EmptyView.self }
    private var hasScope: Bool  { Scope.self  != EmptyView.self }
    private var hasFooter: Bool { Footer.self != EmptyView.self }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasHeader {
                header()
            }
            if hasScope {
                scope()
                    .zIndex(scopeFloating ? 100 : 0)
                Divider().overlay(Theme.border)
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlayScrollers()
            if hasFooter {
                VStack(spacing: 0) {
                    Divider().overlay(Theme.border)
                    footer()
                }
            }
        }
    }
}

// A bottom action band rendering one or more buttons as a single full-width tile,
// each cell equal-width and separated by a divider — the global footer look
// shared by every page (Server's Install/Import, Config's Finder/Refresh/Save,
// Bans' Reload, Snapshots' Delete-all). Pages just hand it the list of actions.
struct PageFooterBar: View {
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        var tint: Color = Theme.accent
        var enabled: Bool = true
        let action: () -> Void
    }
    let items: [Item]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                if idx > 0 {
                    Divider().overlay(Theme.border).frame(height: 28)
                }
                FlushBarButton(title: item.title, icon: item.icon, tint: item.tint,
                               action: item.action)
                    .disabled(!item.enabled)
                    .opacity(item.enabled ? 1 : 0.45)
            }
        }
    }
}
