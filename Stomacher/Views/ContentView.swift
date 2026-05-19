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
            InspectorView(
                store: store,
                replaceSourceID: $replaceSourceID,
                replaceTargetID: $replaceTargetID,
                exportPDF: exportPDF
            )
            .navigationTitle("Bringeduk")
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
            if !store.document.palette.contains(where: { $0.id == replaceSourceID }) {
                replaceSourceID = store.document.palette.first?.id ?? replaceSourceID
            }
            if !store.document.palette.contains(where: { $0.id == replaceTargetID }) {
                replaceTargetID = store.document.palette.dropFirst().first?.id ?? store.document.palette.first?.id ?? replaceTargetID
            }
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
}

private struct InspectorView: View {
    @ObservedObject var store: PatternStore
    @Binding var replaceSourceID: UUID
    @Binding var replaceTargetID: UUID
    @State private var pendingResize: GridResizeRequest?
    @State private var showingResizeWarning = false
    var exportPDF: () -> Void

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

            Section("Verktøy") {
                Picker("Verktøy", selection: $store.tool) {
                    ForEach(CanvasTool.allCases) { tool in
                        Label(tool.title, systemImage: tool.systemImage).tag(tool)
                    }
                }
                .pickerStyle(.inline)

                if store.tool == .select {
                    Picker("Markering", selection: $store.selectionMode) {
                        ForEach(SelectionMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }

            Section("Ytterkant") {
                LabeledContent("Ruter", value: "\(store.document.outlineCells.count)")

                if store.document.hasCustomOutline {
                    Text(store.document.activePatternArea() == nil ? "Ytterkanten er ikke lukket ennå. Når den lukkes brukes den som mønstergrense." : "Ytterkanten brukes som aktiv mønstergrense.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        store.clearOutline()
                    } label: {
                        Label("Fjern ytterkant", systemImage: "xmark.diamond")
                    }
                } else {
                    Text("Uten egen ytterkant brukes hele rutenettet som mønstergrense.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Inndata") {
                Toggle(isOn: $store.usesApplePencilForEditing) {
                    Label("Apple Pencil tegner", systemImage: "applepencil")
                }

                Text(store.usesApplePencilForEditing ? "I mønsteret redigerer bare pennen. Finger flytter, og klyp zoomer." : "Finger og penn kan redigere i mønsteret.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Palett") {
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

            Section("Bytt farge") {
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

                Button {
                    store.replaceColor(from: replaceSourceID, to: replaceTargetID)
                } label: {
                    Label("Bytt i hele mønsteret", systemImage: "arrow.triangle.2.circlepath")
                }
            }

            Section("Markering") {
                Button {
                    store.copySelection()
                } label: {
                    Label("Kopier", systemImage: "doc.on.doc")
                }
                .disabled(store.selection.isEmpty)

                Button {
                    store.pasteClipboard()
                } label: {
                    Label("Lim inn", systemImage: "doc.on.clipboard")
                }
                .disabled(store.clipboard.isEmpty)

                Button {
                    store.mirrorSelectionHorizontally()
                } label: {
                    Label("Speil horisontalt", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                }
                .disabled(store.selection.isEmpty)

                Button {
                    store.mirrorSelectionVertically()
                } label: {
                    Label("Speil vertikalt", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down")
                }
                .disabled(store.selection.isEmpty)

                Button {
                    store.rotateSelectionClockwise()
                } label: {
                    Label("Roter 90°", systemImage: "rotate.right")
                }
                .disabled(store.selection.isEmpty)

                Button {
                    store.completeQuarterAsSquare()
                } label: {
                    Label("Lag kvadrat av 1/4", systemImage: "square.grid.2x2")
                }
                .disabled(store.selection.isEmpty)

                Button(role: .destructive) {
                    store.clearSelection()
                } label: {
                    Label("Fjern markering", systemImage: "xmark.circle")
                }
                .disabled(store.selection.isEmpty)
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
