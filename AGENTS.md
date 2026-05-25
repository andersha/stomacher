# AGENTS

- Dette er en SwiftUI-prototype for å tegne bringeduk-mønstre på et rutenett.
- Følg eksisterende SwiftUI-/modellstruktur: visninger i `Stomacher/Views`, dokument- og appstate i `Stomacher/Models`, PDF-eksport i `Stomacher/Export`.
- Appen har en hjelpefunksjon i UI-et. Når funksjoner, verktøy eller arbeidsflyter legges til, endres eller fjernes, skal hjelpeteksten oppdateres samtidig.
- Prosjektet bruker XcodeGen. Regenerer prosjektet med `xcodegen generate` bare når prosjektoppsettet endres.
- Verifiser i Codex/sandbox med generisk iOS-build, ikke CoreSimulator:

```sh
xcodebuild -project Stomacher.xcodeproj -scheme Stomacher -destination generic/platform=iOS -derivedDataPath ./DerivedData CODE_SIGNING_ALLOWED=NO build
```

- Ikke bruk `-sdk iphonesimulator` som standard i Codex; CoreSimulator er ofte utilgjengelig og gir falske feil.
- Bevar `.stom`-formatet bakoverkompatibelt når dokumentmodellen endres.
