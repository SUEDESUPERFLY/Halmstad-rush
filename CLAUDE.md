# Halmstad Rush – projektregler och arkitektur

Roblox-spel (Luau) som blandar GTA-frihet med Burnout-körning, i ett stiliserat Halmstad.
Detta dokument är källan till sanning för regler och beslut. Uppdatera det efter varje fas.

## Arbetssätt
- Arbeta i faser (se nedan). Bygg aldrig nästa fas förrän användaren bekräftat att föregående fungerar i Studio.
- Efter varje fas: beskriv kort vad som ska testas i Studio och vad som ska hända.
- Användaren kör **inte** Rojo. Leverans sker som placefil:
  1. Kod skrivs i `src/` (Rojo-struktur, `default.project.json` hålls giltig ifall Rojo används senare).
  2. `python3 tools/build_place.py` bygger `build/HalmstadRush.rbxlx`.
  3. Commit + push till `main`. Användaren hämtar med GitHub Desktop och öppnar filen i Studio.
- Kör alltid byggskriptet och committa den byggda filen tillsammans med källkoden.
- Användaren ändrar inte i placefilen i Studio. Allt innehåll (även kartan) genereras av kod eller ligger som `.rbxm` i `assets/`.

## Innehållsregler (barnvänligt, Robloxs "mild")
- Inga vapen, inget skjutande, inget blod. Ingen brottslighet som tema (ingen stöld, ingen polisjakt).
- Krockar är tecknade: studs, plåtdelar, gnistor, rök. Ingen skadas, förare respawnar direkt.
- Inga fotgängare som går att köra på. Om fotgängare läggs till: bara på upphöjda trottoarer som bilar inte når.
- "Jaktläge" = kull med bilar, inte polis.
- Inga verkliga varumärken eller bilmärken. Egna fantasibilar (första: "Kustpilen", en cabriolet).
- Text som andra spelare ser ska filtreras med TextService, annars ska funktionen inte finnas.
- Monetisering: inget pay-to-win i race. Betalning ger kosmetik eller bekvämlighet. Inga slumpade betalda föremål (loot boxes).

## Arkitektur
```
src/shared  -> ReplicatedStorage.Shared       (config, typer, remotes, utils)
src/server  -> ServerScriptService.Server     (init.server.luau laddar Services/*)
src/client  -> StarterPlayerScripts.Client    (init.client.luau startar Controllers/* och UI/*)
tools/      -> byggskript (rbxlx utan Rojo)
build/      -> byggd placefil (committas)
```
- **Server-services** (`src/server/Services/*.luau`): moduler med `Init()` och `Start()`. Loadern kör Init på alla, sedan Start på alla. Hjälpmoduler som inte är services ligger i andra mappar (t.ex. `src/server/Vehicle/`).
- **Klient-controllers** startas i fast ordning i `init.client.luau`. Därefter anropas `VehicleController.Begin()` när alla lyssnare är uppkopplade.
- **Config**: alla justerbara siffror i `src/shared/Config/`. Ingen magisk siffra i logikkoden om den påverkar spelkänslan.
- **Remotes**: alla namn i `src/shared/Remotes.luau`. Bara servern skapar dem. Varje server-handler validerar argument (typ, intervall), ägarskap och takt (rate limit).
- **Typannoteringar**: `--!strict` i nya moduler där det är rimligt.

## Säkerhetsprinciper (server-auktoritativt)
- Pengar, poäng, race-resultat, köp och uppgraderingar räknas **bara** på servern. Klienten skickar avsikter ("jag vill köpa X"), aldrig resultat ("jag har 500 kr").
- Fordonsfysiken simuleras av föraren (nätverksägare) för responsiv styrning. Servern kontrollerar horisontell hastighet mot `VehicleConfig.Server.HorizontalSpeedCap` och stoppar teleportering (`VehicleService.validateCar`).
- Boost-mätaren ligger på klienten (fas 1). Den påverkar bara farten, och farten är begränsad av servern. **Om boost börjar ge poäng eller pengar måste laddningen valideras på servern.**

## Fordonsfysik (fas 1)
- Chassit (`Chassis`) är den enda delen med massa. Kaross, hjul och säte är Massless. Förarens kroppsdelar sätts till Massless när hen sätts i bilen.
- Fyra raycast-fjädrar med VectorForce per hjul (`Mount_FL/FR/RL/RR`). Jämviktskompression = Gravity / SpringStrength.
- På marken (minst 2 hjul): framåtfart, sidledsfart (grepp/drift) och girhastighet sätts direkt på assemblyn. I luften: girkontroll, självrätning och extra gravitation.
- Drift: handbroms över `DriftMinSpeed` ger lågt grepp och snabbare svängning. Driften fortsätter så länge man styr och glider i sidled.
- Boost laddas av drift, lufttid och nära-ögat (raycast i sidled mot parts med attributet `Obstacle = true`).
- Hjulens grafik flyttas med `Motor6D.Transform` lokalt. Andra spelare ser hjulen i viloläge.
- Bilen återställs: R / Y / ↻-knappen (servern flyttar, med cooldown), automatiskt om den ligger på taket i 2,5 s, och till startplatsen om den faller under Y = -40.

## Kontroller
| | Tangentbord | Handkontroll | Touch |
|---|---|---|---|
| Gas | W / ↑ | RT | GAS |
| Broms/back | S / ↓ | LT | BRAKE |
| Styr | A/D / ←→ | vänster spak | ◀ ▶ |
| Drift | Space | X | DRIFT |
| Boost | Shift | A | BOOST |
| Återställ | R | Y | ↻ |

## Beslut
| Beslut | Val |
|---|---|
| Leverans | Placefil (`build/HalmstadRush.rbxlx`) via GitHub, ingen Rojo hos användaren |
| Kartan | Block-out genereras av kod från en datamodul. Detaljer senare som `.rbxm` i `assets/` |
| Spelarkrockar | Spöken mot varandra i fri roam. Krockar bara i race och jaktläge. NPC-bilar går alltid att krocka med |
| Språk | Engelska som bas i UI, svensk översättning via Robloxs Localization. Platsnamn alltid på svenska |
| Krockläge | Avskild korsning i industrizonen som bokas av en spelare åt gången |
| Slow motion | Fejkas på klienten (krockkamera, lokala vrakdelar). Fysiken på servern saktas aldrig ner |
| Max spelare | 10. Ställs in i Game Settings → Places på roblox.com (går inte att sätta i placefilen) |

## Faser
- [x] Fas 0: plan och frågor
- [ ] Fas 1: Struktur + körbar bil med arkadfysik, drift och boost på en testplatta. Touch-kontroller. *(byggd, väntar på test)*
- [ ] Fas 2: Block-out av Halmstad (Centrum/Stora torg/Storgatan, Nissan med broar, slottet, Tylösand, Östra stranden, Galgberget, hamn/industri, landsväg) + respawn-system
- [ ] Fas 3: Krockar, takedowns, krockkamera, enkla NPC-bilar
- [ ] Fas 4: Första racet + poäng/pengar (i minnet)
- [ ] Fas 5: DataStore (retry, sessionslås, versionerat schema), garage, bilköp, uppgraderingar, lackering
- [ ] Fas 6: Stunts, budjobb, kull-jaktläge, krockläge
- [ ] Fas 7: Butik, game passes, developer products, daglig belöning
- [ ] Fas 8: Ljud, UI, minikarta, mobiloptimering

## Kända begränsningar / att göra
- Ingen Luau-linter körs i molnmiljön. Fel syns först i Studios Output-fönster.
- Andra spelare ser inte hjulens fjädring och rotation (fixas vid behov i fas 8).
