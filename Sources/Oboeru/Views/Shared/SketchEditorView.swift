import SwiftUI
import AppKit

// MARK: - Tool

enum SketchTool: String, Codable, CaseIterable {
    case pen, marker, eraser

    var sfSymbol: String {
        switch self {
        case .pen:    return "pencil"
        case .marker: return "paintbrush.pointed"
        case .eraser: return "eraser"
        }
    }
}

// MARK: - Codable stroke storage

struct SketchPoint: Codable {
    var x, y: CGFloat
    init(_ pt: CGPoint) { x = pt.x; y = pt.y }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

struct SketchStroke: Codable, Identifiable {
    var id         = UUID()
    var points:      [SketchPoint]
    var r, g, b, a: CGFloat          // sRGB components
    var lineWidth:   CGFloat
    var tool:        SketchTool

    init(points: [SketchPoint], color: NSColor, lineWidth: CGFloat, tool: SketchTool) {
        self.points    = points
        self.lineWidth = lineWidth
        self.tool      = tool
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        (color.usingColorSpace(.sRGB) ?? color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    var nsColor: NSColor { NSColor(red: r, green: g, blue: b, alpha: a) }
}

struct SketchDocument: Codable {
    var strokes:      [SketchStroke]
    var canvasWidth:  CGFloat
    var canvasHeight: CGFloat
}

// MARK: - Editor state (@Observable)

@Observable
final class SketchEditorState {

    var strokes:     [SketchStroke]        = []
    var tool:        SketchTool            = .pen
    var color:       NSColor               = .black
    var widthPreset: WidthPreset           = .medium
    private(set) var undoStack: [[SketchStroke]] = []

    enum WidthPreset: CaseIterable {
        case thin, medium, thick

        var dotDisplaySize: CGFloat {
            switch self { case .thin: return 5; case .medium: return 9; case .thick: return 14 }
        }

        func strokeWidth(for tool: SketchTool) -> CGFloat {
            switch (self, tool) {
            case (.thin,   .pen):    return 2
            case (.medium, .pen):    return 4
            case (.thick,  .pen):    return 8
            case (.thin,   .marker): return 8
            case (.medium, .marker): return 16
            case (.thick,  .marker): return 28
            case (.thin,   .eraser): return 16
            case (.medium, .eraser): return 32
            case (.thick,  .eraser): return 56
            }
        }
    }

    var effectiveWidth: CGFloat { widthPreset.strokeWidth(for: tool) }

    var effectiveColor: NSColor {
        switch tool {
        case .pen:    return color
        case .marker: return color.withAlphaComponent(0.45)
        case .eraser: return .white
        }
    }

    var canUndo:    Bool { !undoStack.isEmpty }
    var hasContent: Bool { !strokes.isEmpty }

    func pushStroke(_ stroke: SketchStroke) {
        if undoStack.count >= 60 { undoStack.removeFirst() }
        undoStack.append(strokes)
        strokes.append(stroke)
    }

    func undo() {
        guard !undoStack.isEmpty else { return }
        strokes = undoStack.removeLast()
    }

    func clear() {
        guard !strokes.isEmpty else { return }
        undoStack.append(strokes)
        strokes = []
    }

    func encode(canvasSize: CGSize) -> Data? {
        try? JSONEncoder().encode(
            SketchDocument(strokes: strokes,
                           canvasWidth: canvasSize.width,
                           canvasHeight: canvasSize.height)
        )
    }

    func load(from data: Data) {
        guard let doc = try? JSONDecoder().decode(SketchDocument.self, from: data) else { return }
        strokes = doc.strokes
        undoStack = []
    }
}

// MARK: - Canvas NSView

final class SketchCanvasNSView: NSView {

    var state: SketchEditorState!
    private var livePoints: [SketchPoint] = []

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }   // y increases downward (matches mouse coordinates)

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        _ = becomeFirstResponder()
        livePoints = [SketchPoint(convert(event.locationInWindow, from: nil))]
    }

    override func mouseDragged(with event: NSEvent) {
        livePoints.append(SketchPoint(convert(event.locationInWindow, from: nil)))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        livePoints.append(SketchPoint(convert(event.locationInWindow, from: nil)))
        guard !livePoints.isEmpty else { return }
        let stroke = SketchStroke(
            points:    livePoints,
            color:     state.effectiveColor,
            lineWidth: state.effectiveWidth,
            tool:      state.tool
        )
        state.pushStroke(stroke)
        livePoints = []
        needsDisplay = true
    }

    // MARK: Keyboard (⌘Z = undo)

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "z" {
            state.undo()
            needsDisplay = true
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        // White canvas background
        NSColor.white.setFill()
        NSBezierPath.fill(bounds)

        for stroke in state.strokes { drawStroke(stroke) }

        if !livePoints.isEmpty {
            let live = SketchStroke(points: livePoints,
                                    color: state.effectiveColor,
                                    lineWidth: state.effectiveWidth,
                                    tool: state.tool)
            drawStroke(live)
        }
    }

    private func drawStroke(_ stroke: SketchStroke) {
        let pts = stroke.points.map(\.cgPoint)
        guard !pts.isEmpty else { return }

        stroke.nsColor.setStroke()
        stroke.nsColor.setFill()

        if pts.count == 1 {
            // Dot for a tap
            let r = stroke.lineWidth / 2
            NSBezierPath(ovalIn: CGRect(x: pts[0].x - r, y: pts[0].y - r,
                                        width: r * 2, height: r * 2)).fill()
            return
        }

        let path: NSBezierPath = stroke.tool == .pen
            ? smoothPath(pts)
            : straightPath(pts)

        path.lineWidth     = stroke.lineWidth
        path.lineCapStyle  = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    // Catmull-Rom spline for smooth pen strokes
    private func smoothPath(_ pts: [CGPoint]) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: pts[0])
        guard pts.count >= 3 else { p.line(to: pts.last!); return p }
        for i in 1..<pts.count - 1 {
            let p0 = pts[max(0, i - 1)], p1 = pts[i]
            let p2 = pts[i + 1],          p3 = pts[min(pts.count - 1, i + 2)]
            let cp1 = NSPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let cp2 = NSPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            p.curve(to: p2, controlPoint1: cp1, controlPoint2: cp2)
        }
        return p
    }

    private func straightPath(_ pts: [CGPoint]) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: pts[0])
        pts.dropFirst().forEach { p.line(to: $0) }
        return p
    }
}

// MARK: - NSViewRepresentable

struct SketchCanvasView: NSViewRepresentable {
    let state: SketchEditorState

    func makeNSView(context: Context) -> SketchCanvasNSView {
        let v = SketchCanvasNSView()
        v.state = state
        return v
    }

    func updateNSView(_ nsView: SketchCanvasNSView, context: Context) {
        // Called whenever SwiftUI observes a state change — redraw to stay in sync.
        nsView.needsDisplay = true
    }
}

// MARK: - Off-screen renderer (used by display views and exports)

enum SketchRenderer {

    /// Decode `data` and render to an NSImage scaled to `width` (height proportional).
    static func render(from data: Data, width: CGFloat = 600) -> NSImage? {
        guard let doc  = try? JSONDecoder().decode(SketchDocument.self, from: data),
              doc.canvasWidth > 0, doc.canvasHeight > 0 else { return nil }
        let aspect = doc.canvasHeight / doc.canvasWidth
        let target = CGSize(width: width, height: width * aspect)
        let orig   = CGSize(width: doc.canvasWidth, height: doc.canvasHeight)
        return render(strokes: doc.strokes, originalSize: orig, targetSize: target)
    }

    static func render(strokes: [SketchStroke],
                       originalSize: CGSize,
                       targetSize: CGSize) -> NSImage? {
        let scale: CGFloat = 2            // Retina
        let pw = Int(targetSize.width * scale)
        let ph = Int(targetSize.height * scale)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: pw, height: ph,
            bitsPerComponent: 8, bytesPerRow: pw * 4,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let sx = targetSize.width  / originalSize.width
        let sy = targetSize.height / originalSize.height
        ctx.scaleBy(x: scale * sx, y: scale * sy)

        // White background
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: originalSize))

        // Strokes recorded in flipped (y-down) view coords; CGContext is y-up → flip.
        ctx.translateBy(x: 0, y: originalSize.height)
        ctx.scaleBy(x: 1, y: -1)

        for stroke in strokes { renderStroke(stroke, in: ctx) }

        guard let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: targetSize)
    }

    private static func renderStroke(_ stroke: SketchStroke, in ctx: CGContext) {
        let pts = stroke.points.map(\.cgPoint)
        guard !pts.isEmpty else { return }

        ctx.saveGState()
        ctx.setStrokeColor(stroke.nsColor.cgColor)
        ctx.setFillColor(stroke.nsColor.cgColor)
        ctx.setLineWidth(stroke.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        if pts.count == 1 {
            let r = stroke.lineWidth / 2
            ctx.fillEllipse(in: CGRect(x: pts[0].x - r, y: pts[0].y - r, width: r*2, height: r*2))
        } else if stroke.tool == .pen {
            ctx.addPath(catmullRom(pts))
            ctx.strokePath()
        } else {
            ctx.move(to: pts[0])
            pts.dropFirst().forEach { ctx.addLine(to: $0) }
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private static func catmullRom(_ pts: [CGPoint]) -> CGPath {
        let p = CGMutablePath()
        p.move(to: pts[0])
        guard pts.count >= 3 else { if pts.count == 2 { p.addLine(to: pts[1]) }; return p }
        for i in 1..<pts.count - 1 {
            let p0 = pts[max(0, i-1)], p1 = pts[i]
            let p2 = pts[i+1],          p3 = pts[min(pts.count-1, i+2)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            p.addCurve(to: p2, control1: c1, control2: c2)
        }
        return p
    }
}

// MARK: - Display view (read-only, for review screens)

struct SketchDisplayView: View {
    let data: Data
    var maxHeight: CGFloat = 280

    private var image: NSImage? { SketchRenderer.render(from: data) }

    var body: some View {
        if let img = image {
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: maxHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5))
        }
    }
}

// MARK: - Color palette

extension SketchToolbar {
    /// Paired (SwiftUI Color, NSColor) so the toolbar renders correctly and state uses NSColor.
    static let palette: [(Color, NSColor)] = [
        (.black,                                           .black),
        (Color(white: 0.30),                               NSColor(white: 0.30, alpha: 1)),
        (Color(white: 0.60),                               NSColor(white: 0.60, alpha: 1)),
        (.red,                                             NSColor(red: 0.88, green: 0.15, blue: 0.15, alpha: 1)),
        (.orange,                                          NSColor(red: 0.93, green: 0.52, blue: 0.10, alpha: 1)),
        (Color(red: 0.95, green: 0.80, blue: 0.10),       NSColor(red: 0.95, green: 0.80, blue: 0.10, alpha: 1)),
        (Color(red: 0.15, green: 0.72, blue: 0.30),       NSColor(red: 0.15, green: 0.72, blue: 0.30, alpha: 1)),
        (Color(red: 0.10, green: 0.68, blue: 0.72),       NSColor(red: 0.10, green: 0.68, blue: 0.72, alpha: 1)),
        (.blue,                                            NSColor(red: 0.18, green: 0.42, blue: 0.90, alpha: 1)),
        (.purple,                                          NSColor(red: 0.56, green: 0.18, blue: 0.90, alpha: 1)),
        (Color(red: 0.90, green: 0.35, blue: 0.65),       NSColor(red: 0.90, green: 0.35, blue: 0.65, alpha: 1)),
        (Color(red: 0.55, green: 0.35, blue: 0.15),       NSColor(red: 0.55, green: 0.35, blue: 0.15, alpha: 1)),
    ]
}

// MARK: - Toolbar

struct SketchToolbar: View {
    let state: SketchEditorState

    var body: some View {
        HStack(spacing: 4) {

            // ── Tools ──
            ForEach(SketchTool.allCases, id: \.self) { t in
                toolButton(t)
            }

            sep

            // ── Color swatches (hidden while eraser active) ──
            if state.tool != .eraser {
                ForEach(0..<Self.palette.count, id: \.self) { i in
                    colorSwatch(index: i)
                }
                sep
            }

            // ── Stroke widths ──
            ForEach(SketchEditorState.WidthPreset.allCases, id: \.self) { preset in
                widthDot(preset)
            }

            sep

            // ── Undo ──
            Button { state.undo() } label: {
                Image(systemName: "arrow.uturn.backward").frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(!state.canUndo)
            .help("Undo  ⌘Z")

            // ── Clear ──
            Button { state.clear() } label: {
                Image(systemName: "trash").frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(!state.hasContent)
            .foregroundStyle(state.hasContent ? Color.red : Color.secondary)
            .help("Clear canvas")

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: Sub-views

    private func toolButton(_ t: SketchTool) -> some View {
        Button { state.tool = t } label: {
            Image(systemName: t.sfSymbol)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .background(
            state.tool == t ? Color.accentColor.opacity(0.15) : Color.clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
        .foregroundStyle(state.tool == t ? Color.accentColor : Color.primary)
        .help(t.rawValue.capitalized)
    }

    private func colorSwatch(index i: Int) -> some View {
        let (swColor, nsColor) = Self.palette[i]
        let selected = colorsMatch(state.color, nsColor)
        return Circle()
            .fill(swColor)
            .frame(width: selected ? 20 : 16, height: selected ? 20 : 16)
            .overlay(Circle().strokeBorder(.white, lineWidth: selected ? 2.5 : 0))
            .shadow(color: .black.opacity(0.28), radius: 1.5)
            .frame(width: 24, height: 24)
            .animation(.easeInOut(duration: 0.1), value: selected)
            .onTapGesture { state.color = nsColor }
    }

    private func widthDot(_ preset: SketchEditorState.WidthPreset) -> some View {
        let selected = state.widthPreset == preset
        return ZStack {
            if selected {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: preset.dotDisplaySize + 6, height: preset.dotDisplaySize + 6)
            }
            Circle()
                .fill(Color.primary)
                .frame(width: preset.dotDisplaySize, height: preset.dotDisplaySize)
        }
        .frame(width: 30, height: 30)
        .animation(.easeInOut(duration: 0.1), value: selected)
        .onTapGesture { state.widthPreset = preset }
    }

    private var sep: some View {
        Divider().frame(height: 22).padding(.horizontal, 4)
    }

    private func colorsMatch(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let ac = a.usingColorSpace(.sRGB),
              let bc = b.usingColorSpace(.sRGB) else { return false }
        return abs(ac.redComponent   - bc.redComponent)   < 0.02 &&
               abs(ac.greenComponent - bc.greenComponent) < 0.02 &&
               abs(ac.blueComponent  - bc.blueComponent)  < 0.02
    }
}

// MARK: - Full editor sheet

struct SketchEditorSheet: View {

    let existingData: Data?
    let onSave:   (Data) -> Void
    let onCancel: () -> Void

    @State private var editorState = SketchEditorState()
    @State private var canvasSize  = CGSize(width: 660, height: 390)

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ──
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Text("Sketch").font(.headline)
                Spacer()
                Button("Done") {
                    if let data = editorState.encode(canvasSize: canvasSize) {
                        onSave(data)
                    } else {
                        onCancel()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // ── Canvas ──
            GeometryReader { geo in
                SketchCanvasView(state: editorState)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.separator, lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.07), radius: 8, y: 2)
                    .onAppear   { canvasSize = geo.size }
                    .onChange(of: geo.size) { _, s in canvasSize = s }
            }
            .padding(20)

            Divider()

            // ── Drawing toolbar ──
            SketchToolbar(state: editorState)
        }
        .frame(width: 740, height: 560)
        .onAppear {
            if let d = existingData { editorState.load(from: d) }
        }
    }
}

// MARK: - Picker widget (used inside CardEditorSheet)

struct CardSketchPicker: View {

    @Binding var sketchData: Data?
    @State private var isShowingEditor = false

    var body: some View {
        Group {
            if let data = sketchData {
                // Preview thumbnail with Edit + Remove
                ZStack(alignment: .topTrailing) {
                    SketchDisplayView(data: data, maxHeight: 110)
                        .frame(maxWidth: .infinity)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.separator, lineWidth: 0.5)
                        )

                    HStack(spacing: 6) {
                        Button { isShowingEditor = true } label: {
                            Image(systemName: "pencil.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .help("Edit sketch")

                        Button { sketchData = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.black.opacity(0.6))
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .help("Remove sketch")
                    }
                    .padding(6)
                }
            } else {
                Button { isShowingEditor = true } label: {
                    Label("Add Sketch", systemImage: "scribble.variable")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.bordered)
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            SketchEditorSheet(
                existingData: sketchData,
                onSave:   { data in sketchData = data; isShowingEditor = false },
                onCancel: { isShowingEditor = false }
            )
        }
    }
}
