import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var store: PatternStore
    @State private var pdfURL: URL?
    @State private var showingShareSheet = false
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var shouldEnableAutosaveAfterExport = false
    @State private var showingNewConfirmation = false
    @State private var replaceSourceID = PaletteSwatch.defaultPalette[0].id
    @State private var replaceTargetID = PaletteSwatch.defaultPalette[1].id
    private let autosaveTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init(store: PatternStore) {
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        NavigationSplitView {
            NavigationStack {
                InspectorView(
                    store: store,
                    replaceSourceID: $replaceSourceID,
                    replaceTargetID: $replaceTargetID,
                    exportPDF: exportPDF
                )
                .navigationTitle("Bringeduk")
            }
        } detail: {
            VStack(spacing: 0) {
                PatternCanvasView(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                StatusBar(store: store)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PencilDoubleTapView(store: store))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ZoomControls(store: store)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        if store.hasUnsavedChanges {
                            showingNewConfirmation = true
                        } else {
                            store.newDocument()
                        }
                    } label: {
                        Label("Ny", systemImage: "doc.badge.plus")
                    }

                    Button {
                        saveDocument()
                    } label: {
                        Label("Lagre", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        showingImporter = true
                    } label: {
                        Label("Åpne", systemImage: "folder")
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .accessibilityHidden(true)

                        Toggle("Autosave", isOn: Binding {
                            store.autosaveEnabled
                        } set: { isEnabled in
                            setAutosave(isEnabled)
                        })
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Autosave")
                }
            }
        }
        .alert("Start nytt mønster?", isPresented: $showingNewConfirmation) {
            Button("Avbryt", role: .cancel) {}
            Button("Forkast endringer", role: .destructive) {
                store.newDocument()
            }
        } message: {
            Text("Ulagrede endringer i dette mønsteret vil gå tapt.")
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.stomPattern]) { result in
            do {
                let url = try result.get()
                let isAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if isAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                try store.load(url: url)
            } catch {
                store.statusMessage = "Kunne ikke åpne: \(error.localizedDescription)"
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: PatternFileDocument(pattern: store.document),
            contentType: .stomPattern,
            defaultFilename: store.document.title.stomFileName
        ) { result in
            switch result {
            case .success(let url):
                store.markSaved(to: url)
                if shouldEnableAutosaveAfterExport {
                    store.autosaveEnabled = true
                    store.statusMessage = "Autosave på"
                    shouldEnableAutosaveAfterExport = false
                }
            case .failure(let error):
                store.statusMessage = "Kunne ikke lagre: \(error.localizedDescription)"
                shouldEnableAutosaveAfterExport = false
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let pdfURL {
                ShareSheet(items: [pdfURL])
            }
        }
        .onAppear {
            syncReplaceColors()
        }
        .onChange(of: store.document.palette) {
            syncReplaceColors()
        }
        .onReceive(autosaveTimer) { _ in
            do {
                try store.autosaveIfNeeded()
            } catch {
                store.statusMessage = "Autosave feilet: \(error.localizedDescription)"
            }
        }
    }

    private func exportPDF() {
        do {
            let url = try PatternPDFExporter().export(document: store.document)
            pdfURL = url
            showingShareSheet = true
            store.statusMessage = "PDF klar"
        } catch {
            store.statusMessage = "Kunne ikke lage PDF: \(error.localizedDescription)"
        }
    }

    private func saveDocument() {
        guard store.canAutosave else {
            showingExporter = true
            return
        }

        do {
            try store.save()
        } catch {
            store.statusMessage = "Kunne ikke lagre: \(error.localizedDescription)"
        }
    }

    private func setAutosave(_ isEnabled: Bool) {
        if isEnabled {
            guard store.canAutosave else {
                shouldEnableAutosaveAfterExport = true
                showingExporter = true
                return
            }

            store.autosaveEnabled = true
            store.statusMessage = "Autosave på"
        } else {
            shouldEnableAutosaveAfterExport = false
            store.autosaveEnabled = false
            store.statusMessage = "Autosave av"
        }
    }

    private func syncReplaceColors() {
        if !store.document.palette.contains(where: { $0.id == replaceSourceID }) {
            replaceSourceID = store.document.palette.first?.id ?? replaceSourceID
        }
        if !store.document.palette.contains(where: { $0.id == replaceTargetID }) {
            replaceTargetID = store.document.palette.dropFirst().first?.id ?? store.document.palette.first?.id ?? replaceTargetID
        }
    }
}

private struct InspectorView: View {
    @ObservedObject var store: PatternStore
    @Binding var replaceSourceID: UUID
    @Binding var replaceTargetID: UUID
    @State private var pendingResize: GridResizeRequest?
    @State private var showingResizeWarning = false
    @State private var showingOutlineDeleteConfirmation = false
    var exportPDF: () -> Void

    private var toolDetailBackground: Color {
        Color(uiColor: .secondarySystemFill)
    }

    var body: some View {
        Form {
            Section("Dokument") {
                TextField("Navn", text: Binding {
                    store.document.title
                } set: { newValue in
                    store.updateTitle(newValue)
                })

                Stepper("Bredde: \(store.document.width)", value: Binding {
                    store.document.width
                } set: { newValue in
                    requestResize(width: newValue, height: store.document.height)
                }, in: 40...260, step: 10)

                Stepper("Høyde: \(store.document.height)", value: Binding {
                    store.document.height
                } set: { newValue in
                    requestResize(width: store.document.width, height: newValue)
                }, in: 40...200, step: 10)

                Stepper("Ruteblokk: \(store.document.gridBlockSize)", value: Binding {
                    store.document.gridBlockSize
                } set: { newValue in
                    store.updateGridBlockSize(newValue)
                }, in: 2...20, step: 1)
            }

            Section("Verktøy") {
                Toggle(isOn: $store.usesApplePencilForEditing) {
                    Label("Apple Pencil", systemImage: "applepencil")
                }

                ForEach(CanvasTool.allCases) { tool in
                    Button {
                        store.tool = tool
                    } label: {
                        HStack {
                            Label(tool.title, systemImage: tool.systemImage)
                            Spacer()
                            if store.tool == tool {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(store.tool == tool ? .isSelected : [])

                    if store.tool == tool, tool == .select {
                        Group {
                            Picker("Markering", selection: $store.selectionMode) {
                                ForEach(SelectionMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.inline)

                            ToolDetailButton(title: "Kopier", systemImage: "doc.on.doc") {
                                store.copySelection()
                            }
                            .disabled(store.selection.isEmpty)

                            ToolDetailButton(title: "Klipp ut", systemImage: "scissors") {
                                store.cutSelection()
                            }
                            .disabled(store.selection.isEmpty)

                            ToolDetailButton(title: "Lim inn", systemImage: "doc.on.clipboard") {
                                store.pasteClipboard()
                            }
                            .disabled(store.clipboard.isEmpty)

                            ToolDetailButton(title: "Speil horisontalt", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                                store.mirrorSelectionHorizontally()
                            }
                            .disabled(store.selection.isEmpty)

                            ToolDetailButton(title: "Speil vertikalt", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down") {
                                store.mirrorSelectionVertically()
                            }
                            .disabled(store.selection.isEmpty)

                            ToolDetailButton(title: "Roter 90°", systemImage: "rotate.right") {
                                store.rotateSelectionClockwise()
                            }
                            .disabled(store.selection.isEmpty)

                            ToolDetailButton(title: "Lag kvadrat av 1/4", systemImage: "square.grid.2x2") {
                                store.completeQuarterAsSquare()
                            }
                            .disabled(store.selection.isEmpty)

                            ToolDetailButton(title: "Fjern markering", systemImage: "xmark.circle", isDestructive: true) {
                                store.clearSelection()
                            }
                            .disabled(store.selection.isEmpty)
                        }
                        .listRowBackground(toolDetailBackground)
                    }

                    if store.tool == tool, tool == .replaceColor {
                        Group {
                            Picker("Fra", selection: $replaceSourceID) {
                                ForEach(store.document.palette) { swatch in
                                    Text("\(swatch.symbol) \(swatch.name)").tag(swatch.id)
                                }
                            }

                            Picker("Til", selection: $replaceTargetID) {
                                ForEach(store.document.palette) { swatch in
                                    Text("\(swatch.symbol) \(swatch.name)").tag(swatch.id)
                                }
                            }

                            ToolDetailButton(title: "Bytt i hele mønsteret", systemImage: "arrow.triangle.2.circlepath") {
                                store.replaceColor(from: replaceSourceID, to: replaceTargetID)
                            }
                        }
                        .listRowBackground(toolDetailBackground)
                    }

                    if store.tool == tool, tool == .outline {
                        Group {
                            LabeledContent("Ruter", value: "\(store.document.outlineCells.count)")

                            if store.document.hasCustomOutline {
                                Text(store.document.activePatternArea() == nil ? "Ytterkanten er ikke lukket ennå. Når den lukkes brukes den som mønstergrense." : "Ytterkanten brukes som aktiv mønstergrense.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                ToolDetailButton(title: "Fjern ytterkant", systemImage: "xmark.diamond", isDestructive: true) {
                                    showingOutlineDeleteConfirmation = true
                                }
                            } else {
                                Text("Uten egen ytterkant brukes hele rutenettet som mønstergrense.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .listRowBackground(toolDetailBackground)
                    }
                }
            }

            Section("Palett") {
                Picker("Palett", selection: Binding {
                    store.document.paletteID
                } set: { paletteID in
                    store.applyPalette(id: paletteID)
                }) {
                    ForEach(store.palettes) { palette in
                        Text(palette.name).tag(palette.id)
                    }
                }

                NavigationLink {
                    PaletteEditorView(store: store)
                } label: {
                    Label("Rediger palett", systemImage: "pencil")
                }

                if store.canDeleteSelectedPalette {
                    Button(role: .destructive) {
                        store.deleteCustomPalette(id: store.document.paletteID)
                    } label: {
                        Label("Slett egendefinert palett", systemImage: "trash")
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 8)], spacing: 8) {
                    ForEach(store.document.palette) { swatch in
                        Button {
                            store.selectedSwatchID = swatch.id
                            store.tool = .paint
                        } label: {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(swatch.color)
                                    .overlay(Circle().stroke(.primary.opacity(store.selectedSwatchID == swatch.id ? 0.9 : 0.18), lineWidth: store.selectedSwatchID == swatch.id ? 3 : 1))
                                    .frame(width: 32, height: 32)
                                Text(swatch.symbol)
                                    .font(.caption.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(swatch.name)
                    }
                }
            }

            Section("Teknikk") {
                Picker("Teknikk", selection: Binding {
                    store.document.technique
                } set: { newValue in
                    store.updateTechnique(newValue)
                }) {
                    ForEach(PatternTechnique.allCases) { technique in
                        Text(technique.title).tag(technique)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Utfylte felt", value: "\(store.document.cells.count)")
            }

            Section("Utskrift") {
                Button(action: exportPDF) {
                    Label("Eksporter profesjonell PDF", systemImage: "printer")
                }
            }
        }
        .alert("Endre størrelse?", isPresented: $showingResizeWarning) {
            Button("Avbryt", role: .cancel) {}
            Button("Endre størrelse", role: .destructive) {
                guard let pendingResize else { return }
                store.resize(width: pendingResize.width, height: pendingResize.height)
            }
        } message: {
            Text("Den nye størrelsen vil fjerne \(pendingResize?.croppedCellCount ?? 0) utfylte ruter utenfor rutenettet.")
        }
        .alert("Ønsker du å slette ytterkanten?", isPresented: $showingOutlineDeleteConfirmation) {
            Button("Nei", role: .cancel) {}
            Button("Ja", role: .destructive) {
                store.clearOutline()
            }
        }
    }

    private func requestResize(width: Int, height: Int) {
        let croppedCellCount = store.croppedPaintedCellCount(width: width, height: height)
        guard croppedCellCount > 0 else {
            store.resize(width: width, height: height)
            return
        }

        pendingResize = GridResizeRequest(width: width, height: height, croppedCellCount: croppedCellCount)
        showingResizeWarning = true
    }
}

private struct ToolDetailButton: View {
    var title: String
    var systemImage: String
    var isDestructive = false
    var action: () -> Void

    var body: some View {
        Button(role: isDestructive ? .destructive : nil, action: action) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(isDestructive ? Color.red : Color.accentColor)
                    .frame(width: 22)
                Text(title)
                    .foregroundStyle(isDestructive ? Color.red : Color.primary)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PaletteEditorView: View {
    @ObservedObject var store: PatternStore
    @Environment(\.dismiss) private var dismiss
    @State private var paletteName: String
    @State private var draftSwatches: [PaletteSwatch]
    @State private var selectedSwatchID: UUID
    @State private var spectrumBrightness: Double
    private let sourcePaletteID: UUID

    init(store: PatternStore) {
        self.store = store
        self.sourcePaletteID = store.document.paletteID
        let swatches = store.document.palette
        let initialName = store.canDeleteSelectedPalette ? store.document.paletteName : ""
        let initialColor = PaletteColor(hex: swatches.first?.hex ?? "") ?? PaletteColor(red: 1, green: 1, blue: 1)

        _paletteName = State(initialValue: initialName)
        _draftSwatches = State(initialValue: swatches)
        _selectedSwatchID = State(initialValue: swatches.first?.id ?? UUID())
        _spectrumBrightness = State(initialValue: initialColor.hsv.brightness)
    }

    var body: some View {
        Form {
            Section("Valgt palett") {
                LabeledContent("Utgangspunkt", value: store.document.paletteName)
                TextField("Nytt palettnavn", text: $paletteName)
                    .textInputAutocapitalization(.words)
            }

            Section("Fargekart") {
                ColorSpectrumPicker(
                    brightness: $spectrumBrightness,
                    selectedColor: selectedColor,
                    onSelect: setSelectedColor
                )
            }

            Section("Palettfarger") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 8)], spacing: 8) {
                    ForEach(draftSwatches) { swatch in
                        Button {
                            selectedSwatchID = swatch.id
                            if let color = PaletteColor(hex: swatch.hex) {
                                spectrumBrightness = color.hsv.brightness
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(swatch.color)
                                    .overlay(
                                        Circle()
                                            .stroke(.primary.opacity(selectedSwatchID == swatch.id ? 0.9 : 0.18), lineWidth: selectedSwatchID == swatch.id ? 3 : 1)
                                    )
                                    .frame(width: 34, height: 34)

                                Text(swatch.symbol)
                                    .font(.caption.weight(.semibold))

                                Text(swatch.hex)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let colorBinding = selectedColorBinding {
                Section("Valgt farge") {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colorBinding.wrappedValue.color)
                            .frame(width: 54, height: 54)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.primary.opacity(0.16)))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedSwatch?.symbol ?? "")
                                .font(.headline.monospaced())
                            Text(colorBinding.wrappedValue.hex)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }

                    ColorCodeFields(color: colorBinding)
                }
            }

            if store.canDeleteSelectedPalette {
                Section {
                    Button(role: .destructive) {
                        store.deleteCustomPalette(id: sourcePaletteID)
                        dismiss()
                    } label: {
                        Label("Slett egendefinert palett", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Rediger palett")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Avbryt", role: .cancel) {
                    dismiss()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Lagre") {
                    store.saveCustomPalette(name: paletteName, swatches: draftSwatches, replacing: sourcePaletteID)
                    dismiss()
                }
                .disabled(paletteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var selectedSwatch: PaletteSwatch? {
        draftSwatches.first { $0.id == selectedSwatchID }
    }

    private var selectedColor: PaletteColor? {
        guard let selectedSwatch else { return nil }
        return PaletteColor(hex: selectedSwatch.hex)
    }

    private var selectedColorBinding: Binding<PaletteColor>? {
        guard draftSwatches.contains(where: { $0.id == selectedSwatchID }) else { return nil }

        return Binding {
            selectedColor ?? PaletteColor(red: 0, green: 0, blue: 0)
        } set: { color in
            setSelectedColor(color)
        }
    }

    private func setSelectedColor(_ color: PaletteColor) {
        guard let index = draftSwatches.firstIndex(where: { $0.id == selectedSwatchID }) else { return }
        draftSwatches[index].hex = color.hex
    }
}

private struct ColorSpectrumPicker: View {
    @Binding var brightness: Double
    var selectedColor: PaletteColor?
    var onSelect: (PaletteColor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    Canvas { context, size in
                        let columns = 48
                        let rows = 24
                        let cellWidth = size.width / CGFloat(columns)
                        let cellHeight = size.height / CGFloat(rows)

                        for row in 0..<rows {
                            for column in 0..<columns {
                                let hue = Double(column) / Double(columns - 1)
                                let saturation = 1 - Double(row) / Double(rows - 1)
                                let color = PaletteColor(hue: hue, saturation: saturation, brightness: brightness).color
                                let rect = CGRect(
                                    x: CGFloat(column) * cellWidth,
                                    y: CGFloat(row) * cellHeight,
                                    width: cellWidth + 0.5,
                                    height: cellHeight + 0.5
                                )
                                context.fill(Path(rect), with: .color(color))
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.12)))

                    if let selectedColor {
                        let hsv = selectedColor.hsv
                        Circle()
                            .stroke(.white, lineWidth: 3)
                            .overlay(Circle().stroke(.black.opacity(0.62), lineWidth: 1))
                            .frame(width: 18, height: 18)
                            .offset(
                                x: max(0, min(proxy.size.width - 18, CGFloat(hsv.hue) * proxy.size.width - 9)),
                                y: max(0, min(proxy.size.height - 18, CGFloat(1 - hsv.saturation) * proxy.size.height - 9))
                            )
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            selectColor(at: value.location, size: proxy.size)
                        }
                )
            }
            .frame(height: 220)

            LabeledContent {
                Slider(value: $brightness, in: 0...1)
            } label: {
                Text("Lysstyrke")
            }
        }
        .onChange(of: brightness) {
            guard let selectedColor else { return }
            let hsv = selectedColor.hsv
            onSelect(PaletteColor(hue: hsv.hue, saturation: hsv.saturation, brightness: brightness))
        }
    }

    private func selectColor(at location: CGPoint, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let hue = Double((location.x / size.width).clamped(to: 0...1))
        let saturation = Double((1 - location.y / size.height).clamped(to: 0...1))
        onSelect(PaletteColor(hue: hue, saturation: saturation, brightness: brightness))
    }
}

private struct ColorCodeFields: View {
    @Binding var color: PaletteColor
    @State private var rgbRed = ""
    @State private var rgbGreen = ""
    @State private var rgbBlue = ""
    @State private var hslHue = ""
    @State private var hslSaturation = ""
    @State private var hslLightness = ""
    @State private var cmykCyan = ""
    @State private var cmykMagenta = ""
    @State private var cmykYellow = ""
    @State private var cmykBlack = ""
    @State private var hsvHue = ""
    @State private var hsvSaturation = ""
    @State private var hsvBrightness = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            colorRow(title: "RGB", values: [
                ("R", $rgbRed),
                ("G", $rgbGreen),
                ("B", $rgbBlue)
            ], action: applyRGB)

            colorRow(title: "HSL", values: [
                ("H", $hslHue),
                ("S", $hslSaturation),
                ("L", $hslLightness)
            ], suffix: "%", action: applyHSL)

            colorRow(title: "CMYK", values: [
                ("C", $cmykCyan),
                ("M", $cmykMagenta),
                ("Y", $cmykYellow),
                ("K", $cmykBlack)
            ], suffix: "%", action: applyCMYK)

            colorRow(title: "HSV", values: [
                ("H", $hsvHue),
                ("S", $hsvSaturation),
                ("V", $hsvBrightness)
            ], suffix: "%", action: applyHSV)
        }
        .onAppear(perform: syncFields)
        .onChange(of: color) {
            syncFields()
        }
    }

    private func colorRow(
        title: String,
        values: [(String, Binding<String>)],
        suffix: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(values, id: \.0) { label, value in
                    HStack(spacing: 3) {
                        Text(label)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        TextField(label, text: value)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 48, maxWidth: 64)
                            .onSubmit(action)
                        if let suffix {
                            Text(suffix)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button("Bruk", action: action)
                    .buttonStyle(.bordered)
            }
        }
    }

    private func applyRGB() {
        guard
            let red = parse(rgbRed),
            let green = parse(rgbGreen),
            let blue = parse(rgbBlue)
        else { return }

        color = PaletteColor(red: red / 255, green: green / 255, blue: blue / 255)
        syncFields()
    }

    private func applyHSL() {
        guard
            let hue = parse(hslHue),
            let saturation = parse(hslSaturation),
            let lightness = parse(hslLightness)
        else { return }

        color = PaletteColor(hue: hue / 360, saturation: saturation / 100, lightness: lightness / 100)
        syncFields()
    }

    private func applyCMYK() {
        guard
            let cyan = parse(cmykCyan),
            let magenta = parse(cmykMagenta),
            let yellow = parse(cmykYellow),
            let black = parse(cmykBlack)
        else { return }

        color = PaletteColor(cyan: cyan / 100, magenta: magenta / 100, yellow: yellow / 100, black: black / 100)
        syncFields()
    }

    private func applyHSV() {
        guard
            let hue = parse(hsvHue),
            let saturation = parse(hsvSaturation),
            let brightness = parse(hsvBrightness)
        else { return }

        color = PaletteColor(hue: hue / 360, saturation: saturation / 100, brightness: brightness / 100)
        syncFields()
    }

    private func syncFields() {
        let rgb = color.rgb255
        rgbRed = "\(rgb.red)"
        rgbGreen = "\(rgb.green)"
        rgbBlue = "\(rgb.blue)"

        let hsl = color.hsl
        hslHue = "\(Int((hsl.hue * 360).rounded()))"
        hslSaturation = "\(Int((hsl.saturation * 100).rounded()))"
        hslLightness = "\(Int((hsl.lightness * 100).rounded()))"

        let cmyk = color.cmyk
        cmykCyan = "\(Int((cmyk.cyan * 100).rounded()))"
        cmykMagenta = "\(Int((cmyk.magenta * 100).rounded()))"
        cmykYellow = "\(Int((cmyk.yellow * 100).rounded()))"
        cmykBlack = "\(Int((cmyk.black * 100).rounded()))"

        let hsv = color.hsv
        hsvHue = "\(Int((hsv.hue * 360).rounded()))"
        hsvSaturation = "\(Int((hsv.saturation * 100).rounded()))"
        hsvBrightness = "\(Int((hsv.brightness * 100).rounded()))"
    }

    private func parse(_ value: String) -> Double? {
        Double(value.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private struct GridResizeRequest: Identifiable {
    let id = UUID()
    var width: Int
    var height: Int
    var croppedCellCount: Int
}

private struct ZoomControls: View {
    @ObservedObject var store: PatternStore

    var body: some View {
        HStack(spacing: 8) {
            Button {
                store.zoom = max(0.45, store.zoom - 0.15)
            } label: {
                Label("Zoom ut", systemImage: "minus.magnifyingglass")
            }
            .labelStyle(.iconOnly)

            Slider(value: $store.zoom, in: 0.45...2.4)
                .frame(width: 170)

            Button {
                store.zoom = min(2.4, store.zoom + 0.15)
            } label: {
                Label("Zoom inn", systemImage: "plus.magnifyingglass")
            }
            .labelStyle(.iconOnly)
        }
    }
}

private struct StatusBar: View {
    @ObservedObject var store: PatternStore

    var body: some View {
        HStack {
            Text(store.statusMessage)
            Spacer()
            if !store.selection.isEmpty {
                Text("\(store.selection.count) markert")
            }
            if let coordinate = store.lastTouchedCoordinate {
                Text("x \(coordinate.x), y \(coordinate.y)")
                    .monospacedDigit()
            }
            if store.autosaveEnabled {
                Text("Autosave")
            }
            if store.usesApplePencilForEditing {
                Text("Pencil")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private extension String {
    var stomFileName: String {
        let illegalCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = components(separatedBy: illegalCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let baseName = cleaned.isEmpty ? "bringeduk" : cleaned
        return baseName.hasSuffix(".stom") ? baseName : "\(baseName).stom"
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
