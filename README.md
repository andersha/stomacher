# Bringeduk

SwiftUI-prototype for å tegne bringeduk-mønstre på et vanlig rutenett.

## Funksjoner

- Stor scroll- og zoom-bar arbeidsflate på 180 x 120 ruter.
- Teknikkvalg for perler og masker.
- Fargepalett med symboler for utskrift.
- Flytt, tegn, visk, marker og pipette.
- Egen ytterkant for mønsteret; uten ytterkant brukes hele rutenettet.
- Marker med rektangel som standard, eller bytt til enkeltruter.
- Apple Pencil-modus der bare pennen redigerer mønsteret, mens finger brukes til flytting og klyp-zoom.
- Apple Pencil double-tap bytter mellom tegn og visk.
- Kopier/lim inn markerte strukturer.
- Speil horisontalt/vertikalt, roter 90 grader og bygg et fullt kvadrat fra markert 1/4.
- Bytt én farge med en annen i hele mønsteret.
- Synlig lagring og åpning av `.stom`-filer.
- Autosave hvert minutt når dokumentet har et valgt lagringssted.
- PDF-eksport med forside, fargekart, symbolforklaring, oversikt og sideinndelt mønsterrutenett.

## Bygg

Prosjektet bruker XcodeGen for å generere Xcode-prosjektet.

```sh
xcodegen generate
xcodebuild -project Stomacher.xcodeproj -scheme Stomacher -sdk iphonesimulator -derivedDataPath ./DerivedData build
```

Åpne `Stomacher.xcodeproj` i Xcode for å kjøre appen på iPad eller simulator.
