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

## Det här gör du själv i Roblox (checklista)

Allt i koden är klart. Följande går bara att göra inloggad i Studio eller på create.roblox.com.

### 1. Publicera spelet (krävs för sparning)
1. Öppna `HalmstadRush.rbxlx` i Studio.
2. *File → Publish to Roblox* → **Create new experience**. Namn: `Halmstad Rush`. Genre: *Racing* (eller *Adventure*). Enheter: kryssa i **Computer, Phone, Tablet** (inte Console). Klicka **Create**.
3. Spara därefter alltid med *File → Publish to Roblox* (inte *Save to File*), annars hamnar ändringar bara lokalt.

> När en ny version kommer härifrån: öppna den nya `.rbxlx`-filen och välj *File → Publish to Roblox As…* → välj det befintliga spelet *Halmstad Rush*. Då skrivs det publicerade spelet över med den nya versionen.

### 2. Game Settings i Studio (*Home → Game Settings*)
| Flik | Inställning | Värde |
|---|---|---|
| Security | Enable Studio Access to API Services | **På** (annars sparas inget i Studio-test) |
| Security | Allow HTTP Requests | Av (behövs inte) |
| Places | Max Players (*Server Fill*) | **10** |
| Avatar | Avatar type | R15 (standard går bra) |
| Permissions | Playability | **Private** tills du testat, sedan **Public** |
Klicka **Save** efter varje flik.

### 3. Frågeformulär (create.roblox.com → ditt spel → *Audience → Maturity & Compliance*)
Svara så här, så hamnar spelet på **Minimal/Mild**:
- Violence: **Mild/cartoon** (krockar med studs och plåtdelar, ingen skadas). Blood: Nej. Weapons: Nej.
- Crude humor, fear, romance, alcohol, gambling: Nej.
- Free-form user creation / chat: endast Robloxs vanliga chatt.
- Paid random items (loot boxes): **Nej**.
Utan formuläret får spelet inte visas för alla åldrar.

### 4. Butik (valfritt, när du vill sälja)
create.roblox.com → ditt spel → *Monetization*:
1. **Passes → Create a pass**, tre stycken (bild: valfri 512×512, t.ex. en skärmdump):
   - `VIP-lack` – 6 extra lackfärger. Förslag: 99 R$.
   - `Neonunderrede` – neonljus under bilen. Förslag: 149 R$.
   - `Snabbresa+` – snabbresa utan väntetid. Förslag: 79 R$.
   Slå på *Item for Sale* och sätt priset för varje pass.
2. **Developer Products → Create a developer product**, två stycken:
   - `Konfettiregn` – förslag 15 R$.
   - `Stöd utvecklaren` – förslag 25 R$.
3. Kopiera **ID-numret** för varje pass och produkt (siffrorna i adressfältet eller via ⋯ → *Copy Asset ID*) och skicka dem till mig. Då läggs de in i `ShopConfig` och knapparna blir riktiga köp.
Fram till dess visar butiken "Inte i butiken än", och i Studio finns "Testa (Studio)" för att prova effekterna gratis.

### 5. Motorljud (valfritt)
I Studio: *View → Toolbox → Audio*, sök t.ex. `car engine loop`. Välj ett ljud som går att använda fritt (*Roblox*-skapat är säkrast), högerklicka → *Copy Asset ID* och skicka siffrorna till mig.

### 6. Testa innan du släpper
- **Flera spelare:** *Test → Clients and Servers* → 2–3 spelare → *Start*. Prova race, kull och att spelarna är spöken mot varandra i fri körning.
- **Mobil i Studio:** *Test → Device* → välj en telefon.
- **Riktig telefon:** efter publicering, starta spelet i Roblox-appen (Playability måste vara *Private* med dig som ägare, eller *Public*).
- **Sparning:** starta, tjäna lite kronor, avsluta och starta igen. Pengarna ska vara kvar (bara efter steg 1 och 2).

### 7. Innan spelet blir publikt
- Kartan bygger på turistkartan *Halmstad City 2023* (Destination Halmstad). Gatunätet återges förenklat och ingen kartbild finns i spelet, men fråga gärna Destination Halmstad om det är okej att spelet bygger på deras karta.
- Lägg till en ikon (512×512) och tumnaglar (1920×1080, skärmdumpar) under *Places → Basic Info* på create.roblox.com.

## För utvecklare
- Källkoden ligger i `src/` (Rojo-struktur, `default.project.json`).
- Kontroll: `stylua --syntax luau --check src` (syntax) och `selene src` (lint, inställningar i `selene.toml` och `roblox_min.yml`).
- `python3 tools/build_place.py` bygger placefilen. Med Rojo fungerar även `rojo serve` / `rojo build`.
- Regler, arkitektur och beslut finns i [CLAUDE.md](CLAUDE.md).
