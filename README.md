# Halmstad Rush

Arkadracing i öppen värld i ett stiliserat Halmstad. Byggt för Roblox, skrivet i Luau.

## Så testar du (bara webbläsare, inget extra program)

**Varje gång en ny fas är klar**
1. Öppna https://github.com/SUEDESUPERFLY/Halmstad-rush/blob/main/build/HalmstadRush.rbxlx i webbläsaren på datorn (logga in på GitHub).
2. Klicka på nedladdningsikonen (**Download raw file**, pilen uppe till höger ovanför filinnehållet).
3. Öppna Roblox Studio → *File → Open from File…* → välj den nedladdade `HalmstadRush.rbxlx`.
4. Tryck **Play** (F5).

> Ta bort eller skriv över den gamla filen när du laddar ner en ny version, så att du inte öppnar en gammal.
> Spara inte dina egna ändringar i filen. Vill du experimentera: *File → Save As…* med ett annat namn.

**Testa mobil i Studio:** *Test*-fliken → *Device* → välj en telefon (t.ex. iPhone 14) innan du trycker Play.

**Testa på riktig telefon:** publicera spelet från Studio (*File → Publish to Roblox*) och starta det i Roblox-appen. Studio finns bara för Windows och Mac.

## Inför publicering
- **Sparning:** File → Publish to Roblox, sedan Game Settings → Security → *Enable Studio Access to API Services*.
- **Butiken:** skapa game passes och developer products på create.roblox.com (spelet → Monetization) och skicka ID:na, så läggs de in i `ShopConfig`.
- **Motorljud (valfritt):** hitta ett ljud i Toolbox → Audio, kopiera Asset ID och skicka det, så läggs det in i `SoundConfig`.
- **Max 10 spelare:** Game Settings → Places → Max Players.

## För utvecklare
- Källkoden ligger i `src/` (Rojo-struktur, `default.project.json`).
- `python3 tools/build_place.py` bygger placefilen. Med Rojo fungerar även `rojo serve` / `rojo build`.
- Regler, arkitektur och beslut finns i [CLAUDE.md](CLAUDE.md).
