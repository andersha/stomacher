import SwiftUI
import UIKit
import UniformTypeIdentifiers
import OSLog

private let logger = Logger(subsystem: "no.abrahamsen.stomacher", category: "FileSystem")

private enum PendingOpenAction {
    case file(URL)
    case importer
}

private struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: PatternStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var shareFile: ShareFile?
    @State private var showingDocumentBrowser = false
    @State private var showingImporter = false
    @State private var showingHelp = false
    @State private var pendingExport: PendingExport?
    @State private var pendingOpenAction: PendingOpenAction?
    @State private var showingNewConfirmation = false
    @State private var replaceSourceID = PaletteSwatch.defaultPalette[0].id
    @State private var replaceTargetID = PaletteSwatch.defaultPalette[1].id

    init(store: PatternStore) {
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            NavigationStack {
                InspectorView(
                    store: store,
                    replaceSourceID: $replaceSourceID,
                    replaceTargetID: $replaceTargetID,
                    exportPDF: exportPDF,
                    startSewing: startSewing,
                    resumeSewing: resumeSewing
                )
                .navigationTitle("Bringeduk")
            }
        } detail: {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    PatternCanvasView(store: store)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    StatusBar(store: store)
                }

                if store.document.isProtected, store.document.sewingProgress != nil {
                    SewingControls(store: store) {
                        store.cancelSewing()
                        columnVisibility = .all
                    }
                    .padding(.bottom, 42)
                    .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PencilDoubleTapView(store: store))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ZoomControls(store: store)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        store.undo()
                    } label: {
                        Label("Angre", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!store.canUndo)
                    .keyboardShortcut("z", modifiers: .command)

                    Button {
                        store.redo()
                    } label: {
                        Label("Gjør om", systemImage: "arrow.uturn.forward")
                    }
                    .disabled(!store.canRedo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])

                    Button {
                        if store.hasUnsavedChanges {
                            showingNewConfirmation = true
                        } else {
                            store.newDocument()
                        }
                    } label: {
                        Label("Ny", systemImage: "doc.badge.plus")
                    }

                    Menu {
                        Button {
                            saveDocument()
                        } label: {
                            Label("Lagre", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            presentExporter()
                        } label: {
                            Label("Lagre som...", systemImage: "folder.badge.plus")
                        }

                        Button {
                            shareDocument()
                        } label: {
                            Label("Send til...", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Label("Lagre", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        showingDocumentBrowser = true
                    } label: {
                        Label("Åpne", systemImage: "folder")
                    }

                    Button {
                        showingHelp = true
                    } label: {
                        Label("Hjelp", systemImage: "questionmark.circle")
                    }
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
        .alert("Ulagrede endringer", isPresented: Binding(
            get: { pendingOpenAction != nil },
            set: { if !$0 { pendingOpenAction = nil } }
        )) {
            Button("Avbryt", role: .cancel) {
                pendingOpenAction = nil
            }
            Button("Lagre og fortsett") {
                saveAndContinueOpening()
            }
            Button("Fortsett uten å lagre", role: .destructive) {
                continueOpeningWithoutSaving()
            }
        } message: {
            Text("Dette mønsteret har ulagrede endringer. Lagre før du åpner en annen fil?")
        }
        .alert("Fylle inn område?", isPresented: Binding(
            get: { store.pendingFillConfirmation != nil },
            set: { if !$0 { store.cancelPendingFill() } }
        )) {
            Button("Avbryt", role: .cancel) {
                store.cancelPendingFill()
            }
            Button("Fyll inn", role: .destructive) {
                store.confirmPendingFill()
            }
        } message: {
            Text("Dette vil endre \(store.pendingFillConfirmation?.count ?? 0) ruter til valgt farge. Er du sikker?")
        }
        .sheet(isPresented: $showingImporter) {
            StomacherDocumentImporter(
                initialDirectory: store.containerDocumentsURL,
                onCompletion: { result in
                    showingImporter = false
                    do {
                        let url = try result.get()
                        requestOpenFile(at: url)
                    } catch {
                        store.statusMessage = "Kunne ikke åpne: \(error.localizedDescription)"
                    }
                },
                onCancellation: { showingImporter = false }
            )
        }
        .sheet(item: $pendingExport, onDismiss: cleanupPendingExport) { export in
            StomacherDocumentExporter(
                exportURL: export.url,
                initialDirectory: export.initialDirectory,
                onCompletion: handleExportResult,
                onCancellation: {
                    pendingExport = nil
                }
            )
        }
        .sheet(isPresented: $showingDocumentBrowser) {
            DocumentListView(store: store, onOpenFile: { url in
                showingDocumentBrowser = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    requestOpenFile(at: url)
                }
            }, onOpenFromOtherLocation: {
                showingDocumentBrowser = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    requestOpenImporter()
                }
            })
        }
        .sheet(item: $shareFile) { file in
            ShareSheet(items: [file.url])
        }
        .fullScreenCover(isPresented: $showingHelp) {
            HelpOverlayView()
                .presentationBackground(.clear)
        }
        .onAppear {
            syncReplaceColors()
            store.startAutosave()
            updateIdleTimer(for: scenePhase)
        }
        .onDisappear {
            store.stopAutosave()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: store.document.palette) {
            syncReplaceColors()
        }
        .onChange(of: store.isAutolockEnabled) {
            updateIdleTimer(for: scenePhase)
        }
        .onChange(of: scenePhase) { _, newPhase in
            updateIdleTimer(for: newPhase)
        }
        .onOpenURL { url in
            requestOpenFile(at: url)
        }
    }

    private func startSewing(from startCorner: SewingStartCorner) {
        store.startSewing(from: startCorner)
        if store.document.sewingProgress != nil {
            columnVisibility = .detailOnly
        }
    }

    private func resumeSewing() {
        store.resumeSewing()
        if store.document.sewingProgress != nil {
            columnVisibility = .detailOnly
        }
    }

    private func updateIdleTimer(for scenePhase: ScenePhase) {
        UIApplication.shared.isIdleTimerDisabled = scenePhase == .active && !store.isAutolockEnabled
    }

    private func requestOpenFile(at url: URL) {
        requestOpen(.file(url))
    }

    private func requestOpenImporter() {
        requestOpen(.importer)
    }

    private func requestOpen(_ action: PendingOpenAction) {
        if store.hasUnsavedChanges {
            pendingOpenAction = action
        } else {
            performOpen(action)
        }
    }

    private func saveAndContinueOpening() {
        guard let action = pendingOpenAction else { return }

        do {
            try store.save()
            pendingOpenAction = nil
            performOpen(action)
        } catch {
            pendingOpenAction = nil
            store.statusMessage = "Kunne ikke lagre: \(error.localizedDescription)"
        }
    }

    private func continueOpeningWithoutSaving() {
        guard let action = pendingOpenAction else { return }
        pendingOpenAction = nil
        performOpen(action)
    }

    private func performOpen(_ action: PendingOpenAction) {
        switch action {
        case .file(let url):
            openFile(at: url)
        case .importer:
            showingImporter = true
        }
    }

    private func openFile(at url: URL) {
        do {
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing { url.stopAccessingSecurityScopedResource() }
            }
            try store.load(url: url)
        } catch {
            store.statusMessage = "Kunne ikke åpne: \(error.localizedDescription)"
        }
    }

    private func exportPDF() {
        do {
            let url = try PatternPDFExporter().export(document: store.document)
            shareFile = ShareFile(url: url)
            store.statusMessage = "PDF klar"
        } catch {
            store.statusMessage = "Kunne ikke lage PDF: \(error.localizedDescription)"
        }
    }

    private func saveDocument() {
        do {
            try store.save()
        } catch {
            store.statusMessage = "Kunne ikke lagre: \(error.localizedDescription)"
        }
    }

    private func presentExporter() {
        do {
            let url = try store.prepareExportCopy(filename: store.document.title.stomFileName)
            logger.info("Lagre som — tempfil: \(url.path, privacy: .public)")
            pendingExport = PendingExport(url: url, initialDirectory: store.containerDocumentsURL)
        } catch {
            store.statusMessage = "Kunne ikke klargjøre lagring: \(error.localizedDescription)"
        }
    }

    private func shareDocument() {
        do {
            let url = try store.prepareExportCopy(filename: store.document.title.stomFileName)
            logger.info("Send til — tempfil: \(url.path, privacy: .public)")
            shareFile = ShareFile(url: url)
        } catch {
            store.statusMessage = "Kunne ikke klargjøre deling: \(error.localizedDescription)"
        }
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            logger.info("Lagre som — valgt destinasjon: \(url.path, privacy: .public)")
            store.markSaved(to: url)
        case .failure(let error):
            logger.error("Lagre som — feil: \(error.localizedDescription, privacy: .public)")
            store.statusMessage = "Kunne ikke lagre: \(error.localizedDescription)"
        }
        pendingExport = nil
    }

    private func cleanupPendingExport() {
        if let pendingExport {
            try? FileManager.default.removeItem(at: pendingExport.url.deletingLastPathComponent())
        }
        pendingExport = nil
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

private struct HelpOverlayView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Label("Hjelp", systemImage: "questionmark.circle")
                        .font(.title2.weight(.semibold))

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.semibold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Lukk hjelp")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HelpSection(title: "Hva appen gjør") {
                            HelpParagraph("Bringeduk er en tegneflate for å bygge bringedukmønstre på et rutenett. Hver utfylte rute får en farge fra paletten og vises som perle, korssting eller plattsøm, avhengig av teknikkvalget. Mønsteret kan lagres som .stom-fil, åpnes igjen senere og eksporteres som en profesjonell PDF med farger, symboler og sideinndelt rutenett.")
                        }

                        HelpSection(title: "Toppknapper") {
                            HelpItem(systemImage: "minus.magnifyingglass", title: "Zoom", text: "Bruk minus, pluss og 100 % for å zoome arbeidsflaten. Du kan også klype på lerretet.")
                            HelpItem(systemImage: "arrow.uturn.backward", title: "Angre og gjør om", text: "Angre de siste mønsterendringene og gjør dem om igjen. Appen husker inntil fem steg; et tegnestrøk, en flytting eller en Fyll inn-handling teller som ett steg.")
                            HelpItem(systemImage: "doc.badge.plus", title: "Ny", text: "Starter et nytt mønster. Hvis gjeldende mønster har ulagrede endringer, blir du bedt om å bekrefte først.")
                            HelpItem(systemImage: "square.and.arrow.down", title: "Lagre", text: "Lagrer til valgt .stom-fil. Menyen inneholder også Lagre som for ny plassering og Send til for deling.")
                            HelpItem(systemImage: "folder", title: "Åpne", text: "Viser lagrede mønstre med forhåndsvisning. Fra annet sted åpner en .stom-fil via filvelgeren.")
                        }

                        HelpSection(title: "Dokument") {
                            HelpItem(systemImage: "textformat", title: "Navn", text: "Endrer mønsternavnet som brukes ved lagring, eksport og visning i dokumentlisten.")
                            HelpItem(systemImage: "text.alignleft", title: "Beskrivelse", text: "Åpner et stort tekstfelt der du kan skrive en detaljert mønsterbeskrivelse. Teksten lagres i .stom-filen sammen med mønsteret.")
                            HelpItem(systemImage: "rectangle.expand.vertical", title: "Bredde og høyde", text: "Endrer antall ruter i arbeidsflaten. Hvis en mindre størrelse fjerner tegnede ruter, får du en advarsel først.")
                            HelpItem(systemImage: "square.grid.3x3", title: "Ruteblokk", text: "Bestemmer avstanden mellom kraftigere hjelpelinjer, for eksempel hver 10. rute.")
                            HelpItem(systemImage: "shield", title: "Beskytt", text: "Låser mønsteret mot redigering. Bruk dette når tegningen er klar for lesing eller sy-modus.")
                        }

                        HelpSection(title: "Verktøy") {
                            HelpItem(systemImage: "applepencil", title: "Apple Pencil", text: "På iPad kan du la Apple Pencil redigere mønsteret mens fingrene brukes til flytting og zoom. Trykk én rute eller dra over flere; første berørte rute tegnes også. Double-tap på Pencil bytter mellom Tegn og Visk.")
                            HelpItem(systemImage: "lock", title: "Autolås", text: "Når autolås er av, holder appen skjermen våken mens den er aktiv. Det er nyttig ved sying fra skjerm.")
                            HelpItem(systemImage: "hand.raised", title: "Flytt", text: "Flytter arbeidsflaten. Velg Ark for vanlig panorering, eller Mønster for å skyve selve innholdet i rutenettet.")
                            HelpItem(systemImage: "paintbrush.pointed", title: "Tegn", text: "Fyller ruter med valgt palettfarge. Tegning utenfor en lukket ytterkant blir stoppet.")
                            HelpItem(systemImage: "square.fill", title: "Fyll inn", text: "Trykk med pennen for å fylle det lukkede området rundt ruten med valgt farge. Ytterkantruter tas med i fyllingen, men stopper fyllingen fra å gå videre. Tom startrute stoppes også av fylte ruter; farget startrute stoppes også av tomme ruter og andre farger. Hvis mer enn 100 ruter endres, ber appen om bekreftelse først.")
                            HelpItem(systemImage: "eraser", title: "Visk", text: "Fjerner farge fra ruter. Hvis du visker på en ytterkant, fjernes også ytterkantruten.")
                            HelpItem(systemImage: "lasso", title: "Ytterkant", text: "Tegner mønsterets aktive grense. Når kanten er lukket, brukes området innenfor som mønsterflate.")
                            HelpItem(systemImage: "selection.pin.in.out", title: "Marker", text: "Markerer ruter for kopiering og transformasjon. Bruk Rektangel for et område, eller Enkeltruter for å bygge markeringen rute for rute.")
                            HelpItem(systemImage: "eyedropper", title: "Pipette", text: "Trykk en utfylt rute for å velge samme farge i paletten og gå tilbake til Tegn.")
                            HelpItem(systemImage: "arrow.triangle.2.circlepath", title: "Bytt farge", text: "Velg Fra- og Til-farge i verktøypanelet, og bytt alle forekomster i hele mønsteret.")
                        }

                        HelpSection(title: "Markering") {
                            HelpItem(systemImage: "doc.on.doc", title: "Kopier", text: "Kopierer markerte, utfylte ruter til intern utklippstavle.")
                            HelpItem(systemImage: "scissors", title: "Klipp ut", text: "Kopierer markeringen og fjerner de markerte rutene fra mønsteret.")
                            HelpItem(systemImage: "doc.on.clipboard", title: "Lim inn", text: "Setter inn kopierte ruter ved siste berørte rute, eller omtrent midt på arbeidsflaten hvis ingen rute er valgt.")
                            HelpItem(systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right", title: "Speil horisontalt", text: "Speiler markeringen fra venstre til høyre innenfor markeringens yttergrenser.")
                            HelpItem(systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down", title: "Speil vertikalt", text: "Speiler markeringen opp og ned innenfor markeringens yttergrenser.")
                            HelpItem(systemImage: "rotate.right", title: "Roter 90°", text: "Roterer de markerte, utfylte rutene 90 grader med klokken.")
                            HelpItem(systemImage: "square.grid.2x2", title: "Lag kvadrat av 1/4", text: "Bruker markert kvart mønster som utgangspunkt og speiler det til et fullt kvadrat.")
                            HelpItem(systemImage: "xmark.circle", title: "Fjern markering", text: "Tømmer markeringen uten å slette rutene i mønsteret.")
                        }

                        HelpSection(title: "Palett og teknikk") {
                            HelpItem(systemImage: "paintpalette", title: "Palett", text: "Velg innebygde eller egne paletter. Trykk en fargebrikke for å velge tegnefarge. Appen går til Tegn, bortsett fra når Fyll inn allerede er valgt.")
                            HelpItem(systemImage: "pencil", title: "Rediger palett", text: "Lag en egendefinert palett fra gjeldende palett. Du kan justere HEX, RGB, HSL, HSV og CMYK, velge nabofarger eller søke i DMC-farger.")
                            HelpItem(systemImage: "trash", title: "Slett egendefinert palett", text: "Fjerner valgt egendefinert palett. Innebygde paletter kan ikke slettes.")
                            HelpItem(systemImage: "circle.grid.cross", title: "Teknikk", text: "Velg om rutene skal tegnes og eksporteres som perler, korssting eller plattsøm. Antall utfylte felt vises under valget.")
                        }

                        HelpSection(title: "Ytterkant, sying og utskrift") {
                            HelpItem(systemImage: "square.dashed", title: "Skjul ubrukt område", text: "Når en lukket ytterkant finnes, kan området utenfor skjules i arbeidsflaten og holdes utenfor PDF-visningen.")
                            HelpItem(systemImage: "xmark.diamond", title: "Fjern ytterkant", text: "Sletter hele den egendefinerte ytterkanten. Da brukes hele rutenettet igjen som aktivt mønsterområde.")
                            HelpItem(systemImage: "scissors", title: "Sy", text: "Når mønsteret er beskyttet kan du starte sying fra et hjørne. Appen markerer nåværende rute, gråer ut passerte ruter og lar deg gå til neste rute eller neste linje.")
                            HelpItem(systemImage: "printer", title: "Eksporter profesjonell PDF", text: "Lager en PDF med forside, fargekart, symbolforklaring, oversikt og sideinndelt mønsterrutenett.")
                        }
                    }
                    .padding(20)
                }
            }
            .frame(maxWidth: 940, maxHeight: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.primary.opacity(0.08))
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
    }
}

private struct HelpSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HelpParagraph: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct HelpItem: View {
    var systemImage: String
    var title: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DescriptionEditorOverlayView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    var onSave: (String) -> Void

    init(description: String, onSave: @escaping (String) -> Void) {
        _draft = State(initialValue: description)
        self.onSave = onSave
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Label("Beskrivelse", systemImage: "text.alignleft")
                        .font(.title2.weight(.semibold))

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider()

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $draft)
                        .font(.body)
                        .padding(12)
                        .scrollContentBackground(.hidden)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    if draft.isEmpty {
                        Text("Skriv en detaljert beskrivelse av mønsteret.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)

                Divider()

                HStack {
                    Spacer()

                    Button("Avbryt", role: .cancel) {
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button("Lagre") {
                        onSave(draft)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .frame(maxWidth: 940, maxHeight: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.primary.opacity(0.08))
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
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
    @State private var showingDescriptionEditor = false
    @State private var showingSewingStartDialog = false
    var exportPDF: () -> Void
    var startSewing: (SewingStartCorner) -> Void
    var resumeSewing: () -> Void

    private var toolDetailBackground: Color {
        Color(uiColor: .secondarySystemFill)
    }
    private var supportsApplePencilEditing: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        Form {
            Section("Dokument") {
                Group {
                    TextField("Navn", text: Binding {
                        store.document.title
                    } set: { newValue in
                        store.updateTitle(newValue)
                    })

                    Button {
                        showingDescriptionEditor = true
                    } label: {
                        Label("Beskrivelse", systemImage: "text.alignleft")
                    }

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
                .disabled(store.document.isProtected)

                Toggle(isOn: Binding {
                    store.document.isProtected
                } set: { newValue in
                    store.updateProtected(newValue)
                }) {
                    Label("Beskytt", systemImage: store.document.isProtected ? "shield.fill" : "shield")
                }
            }

            Section("Verktøy") {
                if supportsApplePencilEditing {
                    Toggle(isOn: $store.usesApplePencilForEditing) {
                        Label("Apple Pencil", systemImage: "applepencil")
                    }
                }

                Toggle(isOn: $store.isAutolockEnabled) {
                    Label("Autolås", systemImage: "lock")
                }

                if !store.document.isProtected {
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

                        if store.tool == tool, tool == .hand {
                            Picker("Flytt", selection: $store.moveMode) {
                                ForEach(MoveMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .listRowBackground(toolDetailBackground)
                        }

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

                                Toggle(isOn: Binding {
                                    store.document.hideUnusedArea
                                } set: { newValue in
                                    store.updateHideUnusedArea(newValue)
                                }) {
                                    Label("Skjul ubrukt område", systemImage: "square.dashed")
                                }

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
            }

            if !store.document.isProtected {
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
                                if store.tool != .fill {
                                    store.tool = .paint
                                }
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
            }

            if store.document.isProtected {
                Section("Sy") {
                    if store.document.sewingProgress == nil {
                        Button {
                            showingSewingStartDialog = true
                        } label: {
                            Label("Start", systemImage: "scissors")
                        }
                    } else {
                        Button {
                            resumeSewing()
                        } label: {
                            Label("Fortsett", systemImage: "scissors")
                        }
                    }
                }
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
        .fullScreenCover(isPresented: $showingDescriptionEditor) {
            DescriptionEditorOverlayView(description: store.document.patternDescription) { description in
                store.updateDescription(description)
            }
            .presentationBackground(.clear)
        }
        .confirmationDialog("Start sying fra", isPresented: $showingSewingStartDialog, titleVisibility: .visible) {
            ForEach(SewingStartCorner.allCases) { corner in
                Button(corner.title) {
                    startSewing(corner)
                }
            }
            Button("Avbryt", role: .cancel) {}
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

private struct SewingControls: View {
    @ObservedObject var store: PatternStore
    var cancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                store.advanceSewingCell()
            } label: {
                Label("Neste rute", systemImage: "arrow.right")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!store.canAdvanceSewingCell)

            Button {
                store.advanceSewingLine()
            } label: {
                Label("Neste linje", systemImage: "arrow.down")
            }
            .buttonStyle(.bordered)
            .disabled(!store.canAdvanceSewingLine)

            Button(role: .destructive, action: cancel) {
                Label("Avbryt", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }
}

private struct PaletteEditorView: View {
    @ObservedObject var store: PatternStore
    @Environment(\.dismiss) private var dismiss
    @State private var paletteName: String
    @State private var draftSwatches: [PaletteSwatch]
    @State private var selectedSwatchID: UUID
    @State private var workingColor: PaletteColor
    @State private var hexInput: String
    @State private var selectedMode: PaletteColorMode = .hsl
    @State private var dmcSearch = ""
    @State private var dmcFamily = "Alle"
    @State private var savedFlash = false
    @FocusState private var isHexFocused: Bool
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
        _workingColor = State(initialValue: initialColor)
        _hexInput = State(initialValue: String(initialColor.hex.dropFirst()))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                paletteMetadataCard

                PaletteSlotPicker(
                    swatches: draftSwatches,
                    selectedID: selectedSwatchID,
                    workingColor: workingColor,
                    isDirty: isDirty,
                    onSelect: selectSwatch
                )

                if let selectedSwatch {
                    PaletteEditorSectionLabel("Redigerer farge \(selectedSwatch.symbol)")

                    PaletteColorHero(
                        swatch: selectedSwatch,
                        color: workingColor,
                        hexInput: $hexInput,
                        isHexFocused: $isHexFocused,
                        matchedDMC: matchedDMC,
                        isDirty: isDirty,
                        savedFlash: savedFlash,
                        onHexInput: updateColorFromHexInput,
                        onSave: applyWorkingColorToSlot
                    )

                    Picker("Fargemodell", selection: $selectedMode) {
                        ForEach(PaletteColorMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if selectedMode == .dmc {
                        DMCColorPicker(
                            search: $dmcSearch,
                            family: $dmcFamily,
                            selectedHex: workingColor.hex,
                            onPick: setWorkingColor
                        )
                    } else {
                        PaletteEditorCard {
                            VStack(spacing: 12) {
                                ForEach(channels, id: \.id) { channel in
                                    ColorChannelRow(channel: channel)
                                }
                            }
                        }

                        PaletteEditorSectionLabel("Naboer · finjustering")

                        PaletteEditorCard {
                            NeighborColorGrid(colors: neighborColors, selectedHex: workingColor.hex) { color in
                                setWorkingColor(color)
                            }
                        }
                    }
                }

                if store.canDeleteSelectedPalette {
                    Button(role: .destructive) {
                        store.deleteCustomPalette(id: sourcePaletteID)
                        dismiss()
                    } label: {
                        Label("Slett egendefinert palett", systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(18)
        }
        .background(Color(uiColor: .systemGroupedBackground))
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
        .onChange(of: workingColor) {
            guard !isHexFocused else { return }
            hexInput = String(workingColor.hex.dropFirst())
        }
    }

    private var paletteMetadataCard: some View {
        PaletteEditorCard {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Utgangspunkt", value: store.document.paletteName)
                TextField("Nytt palettnavn", text: $paletteName)
                    .textInputAutocapitalization(.words)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var selectedSwatch: PaletteSwatch? {
        draftSwatches.first { $0.id == selectedSwatchID }
    }

    private var isDirty: Bool {
        selectedSwatch?.hex.uppercased() != workingColor.hex.uppercased()
    }

    private var matchedDMC: DMCThreadColor? {
        DMCThreadColor.colors.first { $0.hex.uppercased() == workingColor.hex.uppercased() }
    }

    private var channels: [PaletteColorChannel] {
        PaletteColorChannel.channels(for: selectedMode, color: workingColor, setColor: setWorkingColor)
    }

    private var neighborColors: [NeighborColor] {
        let hsl = workingColor.hsl
        return [
            NeighborColor(title: "−Tone", color: PaletteColor(hue: shiftedHue(hsl.hue, by: -20), saturation: hsl.saturation, lightness: hsl.lightness)),
            NeighborColor(title: "−Lyshet", color: PaletteColor(hue: hsl.hue, saturation: hsl.saturation, lightness: max(0, hsl.lightness - 0.12))),
            NeighborColor(title: "Nå", color: workingColor),
            NeighborColor(title: "+Lyshet", color: PaletteColor(hue: hsl.hue, saturation: hsl.saturation, lightness: min(1, hsl.lightness + 0.12))),
            NeighborColor(title: "+Tone", color: PaletteColor(hue: shiftedHue(hsl.hue, by: 20), saturation: hsl.saturation, lightness: hsl.lightness))
        ]
    }

    private func selectSwatch(_ swatch: PaletteSwatch) {
        selectedSwatchID = swatch.id
        savedFlash = false
        if let color = PaletteColor(hex: swatch.hex) {
            setWorkingColor(color)
        }
    }

    private func setWorkingColor(_ color: PaletteColor) {
        workingColor = color
        if !isHexFocused {
            hexInput = String(color.hex.dropFirst())
        }
    }

    private func updateColorFromHexInput(_ value: String) {
        let filtered = String(value.uppercased().filter(\.isHexadecimalDigit).prefix(6))
        if filtered != value {
            hexInput = filtered
        }
        guard filtered.count == 6, let color = PaletteColor(hex: filtered) else { return }
        workingColor = color
    }

    private func applyWorkingColorToSlot() {
        guard let index = draftSwatches.firstIndex(where: { $0.id == selectedSwatchID }) else { return }
        draftSwatches[index].hex = workingColor.hex
        savedFlash = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            savedFlash = false
        }
    }

    private func shiftedHue(_ hue: Double, by degrees: Double) -> Double {
        let shifted = hue + degrees / 360
        if shifted < 0 { return shifted + 1 }
        if shifted > 1 { return shifted - 1 }
        return shifted
    }
}

private enum PaletteColorMode: String, CaseIterable, Identifiable {
    case rgb = "RGB"
    case hsl = "HSL"
    case hsv = "HSV"
    case cmyk = "CMYK"
    case dmc = "DMC"

    var id: String { rawValue }
}

private struct PaletteEditorCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct PaletteEditorSectionLabel: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline.weight(.regular))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.top, 6)
    }
}

private struct PaletteSlotPicker: View {
    var swatches: [PaletteSwatch]
    var selectedID: UUID
    var workingColor: PaletteColor
    var isDirty: Bool
    var onSelect: (PaletteSwatch) -> Void

    var body: some View {
        PaletteEditorCard {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Palettfarger")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Trykk for å redigere")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .fixedSize(horizontal: true, vertical: false)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(swatches) { swatch in
                            let isSelected = swatch.id == selectedID

                            Button {
                                onSelect(swatch)
                            } label: {
                                VStack(spacing: 4) {
                                    ZStack(alignment: .bottomTrailing) {
                                        Circle()
                                            .fill(swatch.color)
                                            .overlay(
                                                Circle()
                                                    .stroke(.white, lineWidth: isSelected ? 2 : 0)
                                            )
                                            .overlay(
                                                Circle()
                                                    .stroke(isSelected ? Color.accentColor : .primary.opacity(0.12), lineWidth: isSelected ? 2.5 : 1)
                                            )
                                            .frame(width: 30, height: 30)

                                        if isSelected && isDirty {
                                            Circle()
                                                .fill(workingColor.color)
                                                .overlay(Circle().stroke(.white, lineWidth: 2))
                                                .overlay(Circle().stroke(.black.opacity(0.16), lineWidth: 1))
                                                .frame(width: 13, height: 13)
                                                .offset(x: 3, y: 3)
                                        }
                                    }

                                    Text(swatch.symbol)
                                        .font(.caption2.weight(isSelected ? .bold : .medium))
                                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                }
                                .frame(width: 38)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Rediger farge \(swatch.symbol)")
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }
}

private struct PaletteColorHero: View {
    var swatch: PaletteSwatch
    var color: PaletteColor
    @Binding var hexInput: String
    var isHexFocused: FocusState<Bool>.Binding
    var matchedDMC: DMCThreadColor?
    var isDirty: Bool
    var savedFlash: Bool
    var onHexInput: (String) -> Void
    var onSave: () -> Void

    private var heroForeground: Color {
        color.prefersDarkForeground ? .black : .white
    }

    private var chipBackground: Color {
        color.prefersDarkForeground ? .black.opacity(0.10) : .white.opacity(0.22)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text("Farge \(swatch.symbol)")
                            .font(.caption2.weight(.bold))
                            .textCase(.uppercase)
                            .tracking(1.2)
                            .foregroundStyle(heroForeground.opacity(0.62))

                        if let matchedDMC {
                            heroChip("DMC \(matchedDMC.num) · \(matchedDMC.name)")
                        }

                        if isDirty {
                            heroChip("Ulagrede endringer")
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("#")
                            .opacity(0.5)

                        TextField("HEX", text: $hexInput)
                            .focused(isHexFocused)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .onChange(of: hexInput) { _, newValue in
                                onHexInput(newValue)
                            }
                            .submitLabel(.done)
                            .frame(width: 172, alignment: .leading)
                    }
                    .font(.system(size: 42, weight: .bold, design: .monospaced))
                    .foregroundStyle(heroForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 8)

                Button(action: onSave) {
                    Label(savedFlash ? "Lagret i \(swatch.symbol)" : "Lagre i \(swatch.symbol)", systemImage: savedFlash ? "checkmark" : "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .foregroundStyle(saveForeground)
                        .background(saveBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .opacity(isDirty || savedFlash ? 1 : 0.55)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 9) {
                colorMetric("RGB", "\(color.rgb255.red)·\(color.rgb255.green)·\(color.rgb255.blue)")
                divider
                colorMetric("HSL", "\(rounded(color.hsl.hue * 360))°·\(rounded(color.hsl.saturation * 100))·\(rounded(color.hsl.lightness * 100))")
                divider
                colorMetric("HSV", "\(rounded(color.hsv.hue * 360))°·\(rounded(color.hsv.saturation * 100))·\(rounded(color.hsv.brightness * 100))")
                divider
                colorMetric("CMYK", "\(rounded(color.cmyk.cyan * 100))·\(rounded(color.cmyk.magenta * 100))·\(rounded(color.cmyk.yellow * 100))·\(rounded(color.cmyk.black * 100))")
            }
            .font(.caption2.monospaced())
            .foregroundStyle(heroForeground.opacity(0.72))
            .lineLimit(1)
            .minimumScaleFactor(0.62)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .background(color.color, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.black.opacity(0.06)))
    }

    private var saveBackground: Color {
        if savedFlash { return .green }
        return color.prefersDarkForeground ? .black : .white
    }

    private var saveForeground: Color {
        if savedFlash { return .white }
        return color.prefersDarkForeground ? .white : .black
    }

    private var divider: some View {
        Text("|")
            .opacity(0.35)
    }

    private func heroChip(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .tracking(0.2)
            .foregroundStyle(heroForeground.opacity(0.86))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(chipBackground, in: Capsule())
    }

    private func colorMetric(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .fontWeight(.bold)
                .opacity(0.58)
            Text(value)
        }
    }

    private func rounded(_ value: Double) -> Int {
        Int(value.rounded())
    }
}

private struct PaletteColorChannel {
    let id: String
    let key: String
    let title: String
    let value: Int
    let maxValue: Int
    let unit: String
    let gradient: [Color]
    let setValue: (Int) -> Void

    static func channels(for mode: PaletteColorMode, color: PaletteColor, setColor: @escaping (PaletteColor) -> Void) -> [PaletteColorChannel] {
        let rgb = color.rgb255
        let hsl = color.hsl
        let hsv = color.hsv
        let cmyk = color.cmyk

        func gradient(_ build: (Double) -> PaletteColor) -> [Color] {
            (0...6).map { step in
                build(Double(step) / 6).color
            }
        }

        switch mode {
        case .rgb:
            return [
                PaletteColorChannel(id: "rgb-r", key: "R", title: "Rød", value: rgb.red, maxValue: 255, unit: "", gradient: gradient { PaletteColor(red: $0, green: color.green, blue: color.blue) }, setValue: { setColor(PaletteColor(red: Double($0) / 255, green: color.green, blue: color.blue)) }),
                PaletteColorChannel(id: "rgb-g", key: "G", title: "Grønn", value: rgb.green, maxValue: 255, unit: "", gradient: gradient { PaletteColor(red: color.red, green: $0, blue: color.blue) }, setValue: { setColor(PaletteColor(red: color.red, green: Double($0) / 255, blue: color.blue)) }),
                PaletteColorChannel(id: "rgb-b", key: "B", title: "Blå", value: rgb.blue, maxValue: 255, unit: "", gradient: gradient { PaletteColor(red: color.red, green: color.green, blue: $0) }, setValue: { setColor(PaletteColor(red: color.red, green: color.green, blue: Double($0) / 255)) })
            ]
        case .hsl:
            return [
                PaletteColorChannel(id: "hsl-h", key: "H", title: "Tone", value: Int((hsl.hue * 360).rounded()), maxValue: 360, unit: "°", gradient: gradient { PaletteColor(hue: $0, saturation: hsl.saturation, lightness: hsl.lightness) }, setValue: { setColor(PaletteColor(hue: Double($0) / 360, saturation: hsl.saturation, lightness: hsl.lightness)) }),
                PaletteColorChannel(id: "hsl-s", key: "S", title: "Metning", value: Int((hsl.saturation * 100).rounded()), maxValue: 100, unit: "%", gradient: gradient { PaletteColor(hue: hsl.hue, saturation: $0, lightness: hsl.lightness) }, setValue: { setColor(PaletteColor(hue: hsl.hue, saturation: Double($0) / 100, lightness: hsl.lightness)) }),
                PaletteColorChannel(id: "hsl-l", key: "L", title: "Lyshet", value: Int((hsl.lightness * 100).rounded()), maxValue: 100, unit: "%", gradient: gradient { PaletteColor(hue: hsl.hue, saturation: hsl.saturation, lightness: $0) }, setValue: { setColor(PaletteColor(hue: hsl.hue, saturation: hsl.saturation, lightness: Double($0) / 100)) })
            ]
        case .hsv:
            return [
                PaletteColorChannel(id: "hsv-h", key: "H", title: "Tone", value: Int((hsv.hue * 360).rounded()), maxValue: 360, unit: "°", gradient: gradient { PaletteColor(hue: $0, saturation: hsv.saturation, brightness: hsv.brightness) }, setValue: { setColor(PaletteColor(hue: Double($0) / 360, saturation: hsv.saturation, brightness: hsv.brightness)) }),
                PaletteColorChannel(id: "hsv-s", key: "S", title: "Metning", value: Int((hsv.saturation * 100).rounded()), maxValue: 100, unit: "%", gradient: gradient { PaletteColor(hue: hsv.hue, saturation: $0, brightness: hsv.brightness) }, setValue: { setColor(PaletteColor(hue: hsv.hue, saturation: Double($0) / 100, brightness: hsv.brightness)) }),
                PaletteColorChannel(id: "hsv-v", key: "V", title: "Lysverdi", value: Int((hsv.brightness * 100).rounded()), maxValue: 100, unit: "%", gradient: gradient { PaletteColor(hue: hsv.hue, saturation: hsv.saturation, brightness: $0) }, setValue: { setColor(PaletteColor(hue: hsv.hue, saturation: hsv.saturation, brightness: Double($0) / 100)) })
            ]
        case .cmyk:
            return [
                PaletteColorChannel(id: "cmyk-c", key: "C", title: "Cyan", value: Int((cmyk.cyan * 100).rounded()), maxValue: 100, unit: "%", gradient: gradient { PaletteColor(cyan: $0, magenta: cmyk.magenta, yellow: cmyk.yellow, black: cmyk.black) }, setValue: { setColor(PaletteColor(cyan: Double($0) / 100, magenta: cmyk.magenta, yellow: cmyk.yellow, black: cmyk.black)) }),
                PaletteColorChannel(id: "cmyk-m", key: "M", title: "Magenta", value: Int((cmyk.magenta * 100).rounded()), maxValue: 100, unit: "%", gradient: gradient { PaletteColor(cyan: cmyk.cyan, magenta: $0, yellow: cmyk.yellow, black: cmyk.black) }, setValue: { setColor(PaletteColor(cyan: cmyk.cyan, magenta: Double($0) / 100, yellow: cmyk.yellow, black: cmyk.black)) }),
                PaletteColorChannel(id: "cmyk-y", key: "Y", title: "Gul", value: Int((cmyk.yellow * 100).rounded()), maxValue: 100, unit: "%", gradient: gradient { PaletteColor(cyan: cmyk.cyan, magenta: cmyk.magenta, yellow: $0, black: cmyk.black) }, setValue: { setColor(PaletteColor(cyan: cmyk.cyan, magenta: cmyk.magenta, yellow: Double($0) / 100, black: cmyk.black)) }),
                PaletteColorChannel(id: "cmyk-k", key: "K", title: "Sort", value: Int((cmyk.black * 100).rounded()), maxValue: 100, unit: "%", gradient: gradient { PaletteColor(cyan: cmyk.cyan, magenta: cmyk.magenta, yellow: cmyk.yellow, black: $0) }, setValue: { setColor(PaletteColor(cyan: cmyk.cyan, magenta: cmyk.magenta, yellow: cmyk.yellow, black: Double($0) / 100)) })
            ]
        case .dmc:
            return []
        }
    }
}

private struct ColorChannelRow: View {
    var channel: PaletteColorChannel

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(channel.key)
                    .font(.caption2.weight(.bold))
                    .tracking(0.4)
                    .foregroundStyle(.tertiary)
                Text(channel.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 76, alignment: .leading)

            GradientChannelSlider(channel: channel)

            ChannelNumberStepper(channel: channel)
        }
    }
}

private struct GradientChannelSlider: View {
    var channel: PaletteColorChannel

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                LinearGradient(colors: channel.gradient, startPoint: .leading, endPoint: .trailing)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.black.opacity(0.06)))

                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                    .overlay(Circle().stroke(.black.opacity(0.06), lineWidth: 0.5))
                    .frame(width: 26, height: 30)
                    .offset(x: knobX(width: proxy.size.width))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let percentage = (value.location.x / max(proxy.size.width, 1)).clamped(to: 0...1)
                        channel.setValue(Int((Double(percentage) * Double(channel.maxValue)).rounded()))
                    }
            )
        }
        .frame(height: 30)
    }

    private func knobX(width: CGFloat) -> CGFloat {
        let percentage = CGFloat(channel.value) / CGFloat(max(channel.maxValue, 1))
        return (percentage * width - 13).clamped(to: -2...(width - 24))
    }
}

private struct ChannelNumberStepper: View {
    var channel: PaletteColorChannel
    @State private var text = ""

    var body: some View {
        HStack(spacing: 0) {
            Button {
                channel.setValue(max(0, channel.value - 1))
            } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 32)
            }

            TextField("", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .frame(width: 40)
                .onChange(of: text) { _, newValue in
                    let filtered = String(newValue.filter(\.isNumber).prefix(3))
                    if filtered != newValue {
                        text = filtered
                    }
                    guard let value = Int(filtered) else { return }
                    channel.setValue(value.clamped(to: 0...channel.maxValue))
                }

            Text(channel.unit)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 12, alignment: .leading)

            Button {
                channel.setValue(min(channel.maxValue, channel.value + 1))
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 32)
            }
        }
        .foregroundStyle(Color.accentColor)
        .frame(width: 116, height: 36)
        .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onAppear {
            text = "\(channel.value)"
        }
        .onChange(of: channel.value) {
            text = "\(channel.value)"
        }
    }
}

private struct NeighborColor: Identifiable {
    let id = UUID()
    var title: String
    var color: PaletteColor
}

private struct NeighborColorGrid: View {
    var colors: [NeighborColor]
    var selectedHex: String
    var onPick: (PaletteColor) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(colors) { item in
                let isSelected = item.color.hex.uppercased() == selectedHex.uppercased()

                Button {
                    onPick(item.color)
                } label: {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(item.color.color)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.black.opacity(0.08)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
                            )

                        Text(item.title)
                            .font(.caption2.weight(isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Text(String(item.color.hex.dropFirst()))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct DMCColorPicker: View {
    @Binding var search: String
    @Binding var family: String
    var selectedHex: String
    var onPick: (PaletteColor) -> Void

    private var filteredColors: [DMCThreadColor] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return DMCThreadColor.colors.filter { color in
            guard family == "Alle" || color.family == family else { return false }
            guard !query.isEmpty else { return true }
            return color.num.lowercased().contains(query)
                || color.name.lowercased().contains(query)
                || color.family.lowercased().contains(query)
        }
    }

    private var groupedColors: [(family: String, colors: [DMCThreadColor])] {
        DMCThreadColor.families.compactMap { familyName in
            guard familyName != "Alle" else { return nil }
            let colors = filteredColors.filter { $0.family == familyName }
            return colors.isEmpty ? nil : (familyName, colors)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Søk etter DMC-nummer eller navn", text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(DMCThreadColor.families, id: \.self) { familyName in
                        let isSelected = familyName == family

                        Button {
                            family = familyName
                        } label: {
                            HStack(spacing: 6) {
                                if let dot = DMCThreadColor.familyDot(familyName) {
                                    Circle()
                                        .fill(dot)
                                        .overlay(Circle().stroke(.black.opacity(0.08)))
                                        .frame(width: 10, height: 10)
                                }

                                Text(familyName)
                                    .font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(isSelected ? Color.white : Color.secondary)
                            .background(isSelected ? Color.primary : Color(uiColor: .secondarySystemFill), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Text("\(filteredColors.count) av \(DMCThreadColor.colors.count) farger")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                if !search.isEmpty || family != "Alle" {
                    Button("Nullstill") {
                        search = ""
                        family = "Alle"
                    }
                    .font(.caption)
                }
            }
            .padding(.horizontal, 4)

            PaletteEditorCard {
                if groupedColors.isEmpty {
                    Text("Ingen farger matcher søket.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 90)
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(groupedColors, id: \.family) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                if family == "Alle" {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(DMCThreadColor.familyDot(group.family) ?? .gray)
                                            .overlay(Circle().stroke(.black.opacity(0.08)))
                                            .frame(width: 8, height: 8)
                                        Text("\(group.family) · \(group.colors.count)")
                                            .font(.caption2.weight(.bold))
                                            .textCase(.uppercase)
                                            .tracking(0.6)
                                            .foregroundStyle(.tertiary)
                                    }
                                }

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 10) {
                                    ForEach(group.colors) { threadColor in
                                        DMCSwatchButton(
                                            threadColor: threadColor,
                                            isSelected: threadColor.hex.uppercased() == selectedHex.uppercased(),
                                            onPick: onPick
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 2)
    }
}

private struct DMCSwatchButton: View {
    var threadColor: DMCThreadColor
    var isSelected: Bool
    var onPick: (PaletteColor) -> Void

    var body: some View {
        Button {
            if let color = PaletteColor(hex: threadColor.hex) {
                onPick(color)
            }
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(threadColor.color)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.black.opacity(0.08)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
                    )
                    .overlay {
                        if isSelected {
                            Circle()
                                .fill(.white)
                                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                                .overlay(Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(Color.accentColor))
                                .frame(width: 22, height: 22)
                        }
                    }

                Text(threadColor.num)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("DMC \(threadColor.num), \(threadColor.name)")
    }
}

private struct DMCThreadColor: Identifiable, Equatable {
    var num: String
    var name: String
    var hex: String
    var family: String

    var id: String { num }
    var color: Color { PaletteColor(hex: hex)?.color ?? .black }

    static let families = ["Alle", "Hvit", "Rød", "Rosa", "Oransje", "Gul", "Grønn", "Blå", "Lilla", "Brun", "Grå"]

    static func familyDot(_ family: String) -> Color? {
        switch family {
        case "Hvit": .white
        case "Rød": Color(hex: "#C8102E")
        case "Rosa": Color(hex: "#EBA1B5")
        case "Oransje": Color(hex: "#F58227")
        case "Gul": Color(hex: "#FFCB58")
        case "Grønn": Color(hex: "#1E8B4E")
        case "Blå": Color(hex: "#2A66AC")
        case "Lilla": Color(hex: "#75517B")
        case "Brun": Color(hex: "#80532A")
        case "Grå": Color(hex: "#6E7172")
        default: nil
        }
    }

    static let colors: [DMCThreadColor] = [
        DMCThreadColor(num: "Blanc", name: "Hvit", hex: "#FFFFFF", family: "Hvit"),
        DMCThreadColor(num: "B5200", name: "Snøhvit", hex: "#FAFAFA", family: "Hvit"),
        DMCThreadColor(num: "Ecru", name: "Ecru", hex: "#F0EAD6", family: "Hvit"),
        DMCThreadColor(num: "712", name: "Krem", hex: "#F4ECC2", family: "Hvit"),
        DMCThreadColor(num: "739", name: "Tan ultralys", hex: "#EBD3A5", family: "Hvit"),
        DMCThreadColor(num: "3865", name: "Vinterhvit", hex: "#F1ECDD", family: "Hvit"),
        DMCThreadColor(num: "666", name: "Julerød lys", hex: "#E2231A", family: "Rød"),
        DMCThreadColor(num: "321", name: "Rød", hex: "#C8102E", family: "Rød"),
        DMCThreadColor(num: "304", name: "Rød medium", hex: "#B5172E", family: "Rød"),
        DMCThreadColor(num: "498", name: "Rød mørk", hex: "#A4111B", family: "Rød"),
        DMCThreadColor(num: "816", name: "Granat", hex: "#931625", family: "Rød"),
        DMCThreadColor(num: "815", name: "Granat medium", hex: "#851021", family: "Rød"),
        DMCThreadColor(num: "814", name: "Granat mørk", hex: "#6E1525", family: "Rød"),
        DMCThreadColor(num: "347", name: "Laks veldig mørk", hex: "#B22222", family: "Rød"),
        DMCThreadColor(num: "349", name: "Korall mørk", hex: "#C3413D", family: "Rød"),
        DMCThreadColor(num: "817", name: "Korallrød", hex: "#B12A2E", family: "Rød"),
        DMCThreadColor(num: "818", name: "Babyrosa", hex: "#FAD3DA", family: "Rosa"),
        DMCThreadColor(num: "963", name: "Rosa ultralys", hex: "#F8C8C8", family: "Rosa"),
        DMCThreadColor(num: "776", name: "Rosa medium", hex: "#ECA3BB", family: "Rosa"),
        DMCThreadColor(num: "894", name: "Nellik veldig lys", hex: "#F1AAB6", family: "Rosa"),
        DMCThreadColor(num: "957", name: "Geranium blek", hex: "#F0A5B8", family: "Rosa"),
        DMCThreadColor(num: "760", name: "Laks", hex: "#D78E92", family: "Rosa"),
        DMCThreadColor(num: "3326", name: "Rose lys", hex: "#F5A8B7", family: "Rosa"),
        DMCThreadColor(num: "335", name: "Rose", hex: "#DC7491", family: "Rosa"),
        DMCThreadColor(num: "602", name: "Tranebær medium", hex: "#D7588E", family: "Rosa"),
        DMCThreadColor(num: "603", name: "Tranebær", hex: "#DD7BA5", family: "Rosa"),
        DMCThreadColor(num: "604", name: "Tranebær lys", hex: "#E5A3BC", family: "Rosa"),
        DMCThreadColor(num: "718", name: "Plomme", hex: "#82235D", family: "Rosa"),
        DMCThreadColor(num: "3803", name: "Mauve mørk", hex: "#9E486B", family: "Rosa"),
        DMCThreadColor(num: "722", name: "Krydder lys", hex: "#EE9E5E", family: "Oransje"),
        DMCThreadColor(num: "721", name: "Krydder medium", hex: "#E07A24", family: "Oransje"),
        DMCThreadColor(num: "720", name: "Krydder mørk", hex: "#C75B12", family: "Oransje"),
        DMCThreadColor(num: "742", name: "Tangerin lys", hex: "#FFB853", family: "Oransje"),
        DMCThreadColor(num: "741", name: "Tangerin medium", hex: "#FF9F40", family: "Oransje"),
        DMCThreadColor(num: "740", name: "Tangerin", hex: "#F58227", family: "Oransje"),
        DMCThreadColor(num: "970", name: "Gresskar lys", hex: "#F18233", family: "Oransje"),
        DMCThreadColor(num: "947", name: "Brent oransje", hex: "#E54E12", family: "Oransje"),
        DMCThreadColor(num: "946", name: "Brent oransje medium", hex: "#D34416", family: "Oransje"),
        DMCThreadColor(num: "745", name: "Gul blek lys", hex: "#FCDFA5", family: "Gul"),
        DMCThreadColor(num: "744", name: "Gul blek", hex: "#FCD771", family: "Gul"),
        DMCThreadColor(num: "743", name: "Gul medium", hex: "#FFCB58", family: "Gul"),
        DMCThreadColor(num: "727", name: "Topas veldig lys", hex: "#FCEAA1", family: "Gul"),
        DMCThreadColor(num: "726", name: "Topas lys", hex: "#FFCF44", family: "Gul"),
        DMCThreadColor(num: "725", name: "Topas medium", hex: "#FFC831", family: "Gul"),
        DMCThreadColor(num: "307", name: "Sitron", hex: "#FFE338", family: "Gul"),
        DMCThreadColor(num: "445", name: "Sitron lys", hex: "#FAEC9A", family: "Gul"),
        DMCThreadColor(num: "444", name: "Sitron mørk", hex: "#FFC91F", family: "Gul"),
        DMCThreadColor(num: "973", name: "Kanari klar", hex: "#FFD11A", family: "Gul"),
        DMCThreadColor(num: "972", name: "Kanari dyp", hex: "#FFAB0F", family: "Gul"),
        DMCThreadColor(num: "472", name: "Avokado ultralys", hex: "#D2D78A", family: "Grønn"),
        DMCThreadColor(num: "471", name: "Avokado lys", hex: "#B5BD63", family: "Grønn"),
        DMCThreadColor(num: "470", name: "Avokado", hex: "#98A442", family: "Grønn"),
        DMCThreadColor(num: "704", name: "Chartreuse klar", hex: "#99CD43", family: "Grønn"),
        DMCThreadColor(num: "703", name: "Chartreuse", hex: "#6DC04A", family: "Grønn"),
        DMCThreadColor(num: "702", name: "Kelly grønn", hex: "#1AA34A", family: "Grønn"),
        DMCThreadColor(num: "701", name: "Julegrønn lys", hex: "#008F4C", family: "Grønn"),
        DMCThreadColor(num: "700", name: "Julegrønn klar", hex: "#007D43", family: "Grønn"),
        DMCThreadColor(num: "699", name: "Grønn", hex: "#006B3C", family: "Grønn"),
        DMCThreadColor(num: "912", name: "Smaragd lys", hex: "#2EAB5E", family: "Grønn"),
        DMCThreadColor(num: "911", name: "Smaragd medium", hex: "#1E8B4E", family: "Grønn"),
        DMCThreadColor(num: "910", name: "Smaragd mørk", hex: "#1B7843", family: "Grønn"),
        DMCThreadColor(num: "909", name: "Smaragd veldig mørk", hex: "#156842", family: "Grønn"),
        DMCThreadColor(num: "563", name: "Jade lys", hex: "#6FC495", family: "Grønn"),
        DMCThreadColor(num: "562", name: "Jade medium", hex: "#428F60", family: "Grønn"),
        DMCThreadColor(num: "561", name: "Jade veldig mørk", hex: "#2F6048", family: "Grønn"),
        DMCThreadColor(num: "369", name: "Pistasj veldig lys", hex: "#C7D5B3", family: "Grønn"),
        DMCThreadColor(num: "368", name: "Pistasj lys", hex: "#A0BE99", family: "Grønn"),
        DMCThreadColor(num: "367", name: "Pistasj mørk", hex: "#647057", family: "Grønn"),
        DMCThreadColor(num: "989", name: "Skogsgrønn", hex: "#93AD6B", family: "Grønn"),
        DMCThreadColor(num: "988", name: "Skogsgrønn medium", hex: "#688D52", family: "Grønn"),
        DMCThreadColor(num: "827", name: "Blå veldig lys", hex: "#B6D6E7", family: "Blå"),
        DMCThreadColor(num: "3325", name: "Babyblå lys", hex: "#ACC4D6", family: "Blå"),
        DMCThreadColor(num: "3755", name: "Babyblå", hex: "#7DA5C9", family: "Blå"),
        DMCThreadColor(num: "334", name: "Babyblå medium", hex: "#6A93C0", family: "Blå"),
        DMCThreadColor(num: "322", name: "Babyblå mørk", hex: "#607FB4", family: "Blå"),
        DMCThreadColor(num: "813", name: "Blå lys", hex: "#87ABCC", family: "Blå"),
        DMCThreadColor(num: "826", name: "Blå medium", hex: "#4090C0", family: "Blå"),
        DMCThreadColor(num: "824", name: "Blå veldig mørk", hex: "#1F4F86", family: "Blå"),
        DMCThreadColor(num: "798", name: "Delft mørk", hex: "#2A66AC", family: "Blå"),
        DMCThreadColor(num: "799", name: "Delft medium", hex: "#5384BE", family: "Blå"),
        DMCThreadColor(num: "800", name: "Delft blek", hex: "#97B5D5", family: "Blå"),
        DMCThreadColor(num: "312", name: "Marineblå lys", hex: "#2B5E92", family: "Blå"),
        DMCThreadColor(num: "311", name: "Marineblå medium", hex: "#1C436A", family: "Blå"),
        DMCThreadColor(num: "336", name: "Marineblå", hex: "#1F3650", family: "Blå"),
        DMCThreadColor(num: "939", name: "Marineblå mørk", hex: "#1A2A47", family: "Blå"),
        DMCThreadColor(num: "820", name: "Kongeblå mørk", hex: "#1F4280", family: "Blå"),
        DMCThreadColor(num: "597", name: "Turkis", hex: "#00859A", family: "Blå"),
        DMCThreadColor(num: "996", name: "Elektrisk blå", hex: "#14A2C2", family: "Blå"),
        DMCThreadColor(num: "554", name: "Fiolett lys", hex: "#C19DBE", family: "Lilla"),
        DMCThreadColor(num: "553", name: "Fiolett", hex: "#92608A", family: "Lilla"),
        DMCThreadColor(num: "552", name: "Fiolett medium", hex: "#75517B", family: "Lilla"),
        DMCThreadColor(num: "327", name: "Fiolett mørk", hex: "#682760", family: "Lilla"),
        DMCThreadColor(num: "340", name: "Blålilla medium", hex: "#8E84BB", family: "Lilla"),
        DMCThreadColor(num: "333", name: "Blålilla veldig mørk", hex: "#533E84", family: "Lilla"),
        DMCThreadColor(num: "794", name: "Kornblomst lys", hex: "#A2AECE", family: "Lilla"),
        DMCThreadColor(num: "793", name: "Kornblomst medium", hex: "#7E89B7", family: "Lilla"),
        DMCThreadColor(num: "792", name: "Kornblomst mørk", hex: "#56649E", family: "Lilla"),
        DMCThreadColor(num: "791", name: "Kornblomst veldig mørk", hex: "#3F4E8E", family: "Lilla"),
        DMCThreadColor(num: "437", name: "Tan lys", hex: "#D6AB77", family: "Brun"),
        DMCThreadColor(num: "436", name: "Tan", hex: "#C29161", family: "Brun"),
        DMCThreadColor(num: "435", name: "Brun veldig lys", hex: "#B07A45", family: "Brun"),
        DMCThreadColor(num: "434", name: "Brun lys", hex: "#93582C", family: "Brun"),
        DMCThreadColor(num: "433", name: "Brun medium", hex: "#794022", family: "Brun"),
        DMCThreadColor(num: "400", name: "Mahogni mørk", hex: "#80532A", family: "Brun"),
        DMCThreadColor(num: "300", name: "Mahogni veldig mørk", hex: "#6D3F1E", family: "Brun"),
        DMCThreadColor(num: "301", name: "Mahogni medium", hex: "#936946", family: "Brun"),
        DMCThreadColor(num: "738", name: "Tan veldig lys", hex: "#DEC089", family: "Brun"),
        DMCThreadColor(num: "758", name: "Terrakotta veldig lys", hex: "#DB9A8B", family: "Brun"),
        DMCThreadColor(num: "898", name: "Kaffebrun veldig mørk", hex: "#553527", family: "Brun"),
        DMCThreadColor(num: "938", name: "Kaffebrun ultramørk", hex: "#422518", family: "Brun"),
        DMCThreadColor(num: "762", name: "Perlegrå veldig lys", hex: "#DAD9D8", family: "Grå"),
        DMCThreadColor(num: "415", name: "Perlegrå", hex: "#B7B9B9", family: "Grå"),
        DMCThreadColor(num: "318", name: "Stålgrå lys", hex: "#A4A4A4", family: "Grå"),
        DMCThreadColor(num: "414", name: "Stålgrå mørk", hex: "#777879", family: "Grå"),
        DMCThreadColor(num: "317", name: "Tinngrå", hex: "#6E7172", family: "Grå"),
        DMCThreadColor(num: "3799", name: "Tinngrå veldig mørk", hex: "#45494B", family: "Grå"),
        DMCThreadColor(num: "844", name: "Bevergrå ultramørk", hex: "#444140", family: "Grå"),
        DMCThreadColor(num: "310", name: "Sort", hex: "#000000", family: "Grå")
    ]
}

private struct PendingExport: Identifiable {
    let id = UUID()
    let url: URL
    let initialDirectory: URL?
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
    private var supportsApplePencilEditing: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

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
            if supportsApplePencilEditing && store.usesApplePencilForEditing {
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

private struct PatternThumbnailCanvas: View {
    let document: PatternDocument

    private let thumbnailSize = CGSize(width: 90, height: 60)

    var body: some View {
        Canvas { context, size in
            let bounds = document.printableBounds
            guard bounds.width > 0, bounds.height > 0 else { return }

            let scaleX = size.width / CGFloat(bounds.width)
            let scaleY = size.height / CGFloat(bounds.height)
            let cellSize = min(scaleX, scaleY)
            let offsetX = (size.width - cellSize * CGFloat(bounds.width)) / 2
            let offsetY = (size.height - cellSize * CGFloat(bounds.height)) / 2

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))

            let patternArea = document.activePatternArea()

            for (coordinate, swatchID) in document.cells {
                guard let swatch = document.swatch(for: swatchID) else { continue }
                guard patternArea?.contains(coordinate) ?? true else { continue }

                let x = CGFloat(coordinate.x - bounds.minX) * cellSize + offsetX
                let y = CGFloat(coordinate.y - bounds.minY) * cellSize + offsetY
                let cellRect = CGRect(x: x, y: y, width: cellSize, height: cellSize)

                switch document.technique {
                case .beads:
                    let beadRect = cellRect.insetBy(dx: cellSize * 0.07, dy: cellSize * 0.07)
                    context.fill(PatternCellSymbol.beadPath(in: beadRect), with: .color(swatch.color))
                case .crossStitches:
                    let rect = cellRect.insetBy(dx: cellSize * 0.1, dy: cellSize * 0.1)
                    var stitch = Path()
                    stitch.move(to: CGPoint(x: rect.minX, y: rect.minY))
                    stitch.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                    stitch.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                    stitch.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                    context.stroke(stitch, with: .color(swatch.color), lineWidth: max(0.8, cellSize * 0.18))
                case .satinStitch:
                    context.fill(Path(cellRect), with: .color(swatch.color))
                }
            }
        }
        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
    }
}

private struct PatternThumbnail: View {
    let url: URL

    @State private var document: PatternDocument?
    @State private var failed = false

    var body: some View {
        Group {
            if let document {
                PatternThumbnailCanvas(document: document)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(.black.opacity(0.08)))
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .overlay {
                        if !failed {
                            ProgressView().scaleEffect(0.7)
                        }
                    }
            }
        }
        .frame(width: 90, height: 60)
        .task(id: url) { await load() }
    }

    private func load() async {
        let decoded: PatternDocument? = await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(PatternDocument.self, from: data)
        }.value
        if let decoded {
            document = decoded
        } else {
            failed = true
        }
    }
}

private struct DocumentListItem: Identifiable {
    let id = UUID()
    let url: URL
    let modifiedAt: Date

    var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }
}

private struct DocumentListView: View {
    @ObservedObject var store: PatternStore
    var onOpenFile: (URL) -> Void
    var onOpenFromOtherLocation: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var files: [DocumentListItem] = []
    @State private var pendingDelete: DocumentListItem?
    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Group {
                if files.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Text("Ingen lagrede mønstre")
                            .font(.headline)
                        Text("Lagrede mønstre vises her.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(files) { file in
                            Button {
                                openFile(file)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(file.displayName)
                                            .foregroundStyle(.primary)
                                        Text(file.modifiedAt, style: .relative)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    PatternThumbnail(url: file.url)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDelete = file
                                } label: {
                                    Label("Slett", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bringeduk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Lukk") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fra annet sted…") {
                        onOpenFromOtherLocation()
                    }
                }
            }
        }
        .onAppear(perform: loadFiles)
        .onReceive(refreshTimer) { _ in
            loadFiles()
        }
        .alert("Slett mønster?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Avbryt", role: .cancel) { pendingDelete = nil }
            Button("Slett", role: .destructive) {
                if let file = pendingDelete { deleteFile(file) }
                pendingDelete = nil
            }
        } message: {
            Text("«\(pendingDelete?.displayName ?? "")» slettes permanent og kan ikke gjenopprettes.")
        }
    }

    private func openFile(_ file: DocumentListItem) {
        onOpenFile(file.url)
    }

    private func deleteFile(_ file: DocumentListItem) {
        do {
            try FileManager.default.removeItem(at: file.url)
            files.removeAll { $0.id == file.id }
        } catch {
            store.statusMessage = "Kunne ikke slette: \(error.localizedDescription)"
        }
    }

    private func loadFiles() {
        guard let dir = store.containerDocumentsURL else { files = []; return }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        )) ?? []
        files = urls
            .filter { $0.pathExtension == "stom" }
            .map { url in
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return DocumentListItem(url: url, modifiedAt: modified)
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }
}

private struct StomacherDocumentImporter: UIViewControllerRepresentable {
    var initialDirectory: URL?
    var onCompletion: (Result<URL, Error>) -> Void
    var onCancellation: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion, onCancellation: onCancellation)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.stomPattern])
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        picker.directoryURL = initialDirectory
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onCompletion: (Result<URL, Error>) -> Void
        var onCancellation: () -> Void

        init(onCompletion: @escaping (Result<URL, Error>) -> Void, onCancellation: @escaping () -> Void) {
            self.onCompletion = onCompletion
            self.onCancellation = onCancellation
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onCompletion(.failure(CocoaError(.fileReadUnknown)))
                return
            }
            onCompletion(.success(url))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancellation()
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct StomacherDocumentExporter: UIViewControllerRepresentable {
    var exportURL: URL
    var initialDirectory: URL?
    var onCompletion: (Result<URL, Error>) -> Void
    var onCancellation: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion, onCancellation: onCancellation)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [exportURL], asCopy: false)
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        picker.directoryURL = initialDirectory
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onCompletion: (Result<URL, Error>) -> Void
        var onCancellation: () -> Void

        init(
            onCompletion: @escaping (Result<URL, Error>) -> Void,
            onCancellation: @escaping () -> Void
        ) {
            self.onCompletion = onCompletion
            self.onCancellation = onCancellation
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onCompletion(.failure(CocoaError(.fileWriteUnknown)))
                return
            }

            onCompletion(.success(url))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancellation()
        }
    }
}

private extension PaletteColor {
    var prefersDarkForeground: Bool {
        (0.299 * red + 0.587 * green + 0.114 * blue) > 0.55
    }
}

private extension Character {
    var isHexadecimalDigit: Bool {
        isNumber || ("A"..."F").contains(String(self)) || ("a"..."f").contains(String(self))
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
