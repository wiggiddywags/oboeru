import SwiftUI
import AppKit

// MARK: - Editor state
// Shared between the SwiftUI toolbar and the NSTextView via a weak reference.
// All formatting actions go through this object.

@Observable
final class RichTextEditorState {
    weak var textView: NSTextView?

    // Toolbar display — reflect the formatting at the current cursor position
    var isBold: Bool = false
    var isItalic: Bool = false
    var isUnderline: Bool = false
    var fontSize: CGFloat = 14
    var fontFamilyName: String = "System"

    static let availableFamilies: [String] = [
        "System", "Georgia", "Helvetica Neue",
        "Times New Roman", "Palatino", "Courier New",
    ]
    static let availableSizes: [CGFloat] = [
        10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 32, 36, 48,
    ]

    // MARK: - Actions

    func toggleBold()   { textView?.toggleBoldface(nil) }
    func toggleItalic() { textView?.toggleItalics(nil) }

    func toggleUnderline() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        guard range.length > 0 else { return }
        let cur = storage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
        let next = cur == 0 ? NSUnderlineStyle.single.rawValue : 0
        storage.beginEditing()
        storage.addAttribute(.underlineStyle, value: next, range: range)
        storage.endEditing()
        isUnderline = next != 0
    }

    func applyFontSize(_ size: CGFloat) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = selectedOrAll(tv: tv, storage: storage)
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { val, r, _ in
            let existing = (val as? NSFont) ?? .systemFont(ofSize: size)
            if let f = NSFont(descriptor: existing.fontDescriptor, size: size) {
                storage.addAttribute(.font, value: f, range: r)
            }
        }
        storage.endEditing()
        fontSize = size
    }

    func applyFontFamily(_ familyName: String) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = selectedOrAll(tv: tv, storage: storage)
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { val, r, _ in
            let existing = (val as? NSFont) ?? .systemFont(ofSize: 14)
            let f = makeFont(family: familyName,
                             size: existing.pointSize,
                             traits: existing.fontDescriptor.symbolicTraits) ?? existing
            storage.addAttribute(.font, value: f, range: r)
        }
        storage.endEditing()
        fontFamilyName = familyName
    }

    func applyHeading(_ level: Int) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        // level 0 = Body, 1–3 = H1–H3
        let config: (CGFloat, Bool) = {
            switch level {
            case 1:  return (26, true)
            case 2:  return (20, true)
            case 3:  return (17, true)
            default: return (14, false)
            }
        }()
        let paraRange = (tv.string as NSString).paragraphRange(for: tv.selectedRange())
        let f: NSFont = config.1
            ? .boldSystemFont(ofSize: config.0)
            : .systemFont(ofSize: config.0)
        storage.beginEditing()
        storage.addAttribute(.font, value: f, range: paraRange)
        storage.endEditing()
        updateFormattingState()
    }

    func clearFormatting() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = selectedOrAll(tv: tv, storage: storage)
        storage.beginEditing()
        storage.setAttributes([.font: NSFont.systemFont(ofSize: 14)], range: range)
        storage.endEditing()
        updateFormattingState()
    }

    func updateFormattingState() {
        guard let tv = textView,
              let storage = tv.textStorage,
              storage.length > 0 else { return }
        let sel = tv.selectedRange()
        let loc = min(
            sel.length > 0 ? sel.location : max(0, sel.location - 1),
            storage.length - 1
        )
        let attrs = storage.attributes(at: loc, effectiveRange: nil)
        let f = attrs[.font] as? NSFont ?? .systemFont(ofSize: 14)
        let traits = f.fontDescriptor.symbolicTraits
        isBold      = traits.contains(.bold)
        isItalic    = traits.contains(.italic)
        isUnderline = (attrs[.underlineStyle] as? Int ?? 0) != 0
        fontSize    = f.pointSize
        let family  = f.familyName ?? "System"
        fontFamilyName = RichTextEditorState.availableFamilies.contains(family) ? family : "System"
    }

    // MARK: - Helpers

    private func selectedOrAll(tv: NSTextView, storage: NSTextStorage) -> NSRange {
        let sel = tv.selectedRange()
        return sel.length > 0 ? sel : NSRange(location: 0, length: storage.length)
    }

    private func makeFont(_ familyName: String? = nil,
                          family: String,
                          size: CGFloat,
                          traits: NSFontDescriptor.SymbolicTraits) -> NSFont? {
        if family == "System" {
            let base = NSFont.systemFont(ofSize: size)
            return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: size)
        }
        let desc = NSFontDescriptor(fontAttributes: [.family: family])
            .withSymbolicTraits(traits)
        return NSFont(descriptor: desc, size: size)
    }

    private func makeFont(family: String,
                          size: CGFloat,
                          traits: NSFontDescriptor.SymbolicTraits) -> NSFont? {
        makeFont(nil, family: family, size: size, traits: traits)
    }
}

// MARK: - Editable rich text view

struct RichTextEditor: NSViewRepresentable {
    @Binding var rtfData: Data?
    @Binding var plainText: String
    let state: RichTextEditorState
    var minHeight: CGFloat = 80

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let tv = scrollView.documentView as? NSTextView else { return scrollView }

        tv.isRichText   = true
        tv.allowsUndo   = true
        tv.isEditable   = true
        tv.isSelectable = true
        tv.usesFontPanel = true
        tv.usesRuler     = false
        tv.drawsBackground = false
        tv.font      = .systemFont(ofSize: 14)
        tv.textColor = .labelColor
        tv.delegate  = context.coordinator
        tv.textContainerInset = NSSize(width: 4, height: 6)

        // Load initial content
        if let data = rtfData,
           let attrStr = NSAttributedString(rtf: data, documentAttributes: nil) {
            tv.textStorage?.setAttributedString(attrStr)
            context.coordinator.lastSyncedRTF = data
        } else if !plainText.isEmpty {
            tv.string = plainText
        }

        state.textView = tv

        scrollView.hasVerticalScroller   = true
        scrollView.autohidesScrollers    = true
        scrollView.drawsBackground       = false

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        // Re-link state if the view was recreated
        if state.textView !== tv { state.textView = tv }
        // Apply only external changes (not changes from user typing)
        if let data = rtfData, data != context.coordinator.lastSyncedRTF,
           let attrStr = NSAttributedString(rtf: data, documentAttributes: nil) {
            tv.textStorage?.setAttributedString(attrStr)
            context.coordinator.lastSyncedRTF = data
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        var lastSyncedRTF: Data?

        init(_ parent: RichTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView,
                  let storage = tv.textStorage else { return }
            parent.plainText = tv.string
            let data = storage.rtf(
                from: NSRange(location: 0, length: storage.length),
                documentAttributes: [:]
            )
            parent.rtfData   = data
            lastSyncedRTF    = data
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            parent.state.updateFormattingState()
        }
    }
}

// MARK: - Read-only display view (for review screens)

struct RichTextDisplayView: NSViewRepresentable {
    let rtfData: Data
    var centered: Bool = true

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let tv = scrollView.documentView as? NSTextView else { return scrollView }
        tv.isEditable   = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainer?.widthTracksTextView = true
        scrollView.drawsBackground        = false
        scrollView.hasVerticalScroller    = false
        scrollView.hasHorizontalScroller  = false
        apply(to: tv)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        apply(to: tv)
    }

    private func apply(to tv: NSTextView) {
        guard let raw = NSMutableAttributedString(rtf: rtfData, documentAttributes: nil)
        else { return }
        if centered {
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            raw.addAttribute(.paragraphStyle, value: para,
                             range: NSRange(location: 0, length: raw.length))
        }
        raw.addAttribute(.foregroundColor, value: NSColor.labelColor,
                         range: NSRange(location: 0, length: raw.length))
        tv.textStorage?.setAttributedString(raw)
    }
}

// MARK: - Toolbar

struct RichTextToolbar: View {
    let state: RichTextEditorState

    @State private var pickerSize:   CGFloat = 14
    @State private var pickerFamily: String  = "System"

    var body: some View {
        HStack(spacing: 2) {

            // ── Paragraph style ──
            Menu {
                Button("Heading 1") { state.applyHeading(1) }
                Button("Heading 2") { state.applyHeading(2) }
                Button("Heading 3") { state.applyHeading(3) }
                Divider()
                Button("Body")      { state.applyHeading(0) }
            } label: {
                Image(systemName: "textformat")
                    .frame(width: 26, height: 22)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26)
            .help("Paragraph style")

            sep

            // ── Font family ──
            Picker("Font", selection: $pickerFamily) {
                ForEach(RichTextEditorState.availableFamilies, id: \.self) { name in
                    Text(name == "System" ? "SF Pro" : name).tag(name)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 114)
            .onChange(of: pickerFamily) { _, new in state.applyFontFamily(new) }
            .onChange(of: state.fontFamilyName) { _, new in
                if new != pickerFamily { pickerFamily = new }
            }

            // ── Font size ──
            Picker("Size", selection: $pickerSize) {
                ForEach(RichTextEditorState.availableSizes, id: \.self) { s in
                    Text("\(Int(s))").tag(s)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 56)
            .onChange(of: pickerSize) { _, new in state.applyFontSize(new) }
            .onChange(of: state.fontSize) { _, new in
                if abs(new - pickerSize) > 0.1 { pickerSize = new }
            }

            sep

            // ── Bold ──
            formatButton("bold", active: state.isBold) { state.toggleBold() }

            // ── Italic ──
            formatButton("italic", active: state.isItalic) { state.toggleItalic() }

            // ── Underline ──
            formatButton("underline", active: state.isUnderline) { state.toggleUnderline() }

            sep

            // ── Clear formatting ──
            Button { state.clearFormatting() } label: {
                Image(systemName: "eraser")
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.secondary)
            .help("Clear formatting")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
        .onAppear {
            pickerSize   = state.fontSize
            pickerFamily = state.fontFamilyName
        }
    }

    private var sep: some View {
        Divider().frame(height: 18).padding(.horizontal, 3)
    }

    private func formatButton(_ icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? Color.accentColor : Color.secondary)
        .background(
            active ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 4)
        )
    }
}

// MARK: - Combined editor + toolbar (drop-in replacement for TextEditor)

struct RichTextEditorWithToolbar: View {
    @Binding var rtfData: Data?
    @Binding var plainText: String
    var minHeight: CGFloat = 80

    @State private var state = RichTextEditorState()

    var body: some View {
        VStack(spacing: 0) {
            RichTextToolbar(state: state)
            Divider()
            RichTextEditor(
                rtfData: $rtfData,
                plainText: $plainText,
                state: state,
                minHeight: minHeight
            )
            .frame(minHeight: minHeight)
        }
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
