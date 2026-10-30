# Halmstad Rush

Arkadracing i öppen värld i ett stiliserat Halmstad. Byggt för Roblox, skrivet i Luau.

## Så testar du (utan Rojo)

**Första gången**
1. Installera [GitHub Desktop](https://desktop.github.com) och logga in.
2. *File → Clone repository* och välj `halmstad-rush`. Välj en mapp, t.ex. `Dokument\GitHub\halmstad-rush`.

**Varje gång en ny fas är klar**
1. Klicka på *Fetch origin* och sedan *Pull origin* i GitHub Desktop.
2. Öppna Roblox Studio → *File → Open from File…* → `build\HalmstadRush.rbxlx` i repomappen.
3. Tryck **Play** (F5).

> Spara inte ändringar i `HalmstadRush.rbxlx`. Den skrivs över vid nästa uppdatering.
> Vill du experimentera i Studio: *File → Save As…* till en annan mapp.

**Testa mobil:** *Test*-fliken → *Device* → välj en telefon (t.ex. iPhone 14) innan du trycker Play.

## För utvecklare
- Källkoden ligger i `src/` (Rojo-struktur, `default.project.json`).
- `python3 tools/build_place.py` bygger placefilen. Med Rojo fungerar även `rojo serve` / `rojo build`.
- Regler, arkitektur och beslut finns i [CLAUDE.md](CLAUDE.md).
