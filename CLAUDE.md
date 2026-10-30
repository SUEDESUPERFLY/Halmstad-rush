# Halmstad Rush – projektregler och arkitektur

Roblox-spel (Luau) som blandar GTA-frihet med Burnout-körning, i ett stiliserat Halmstad.
Detta dokument är källan till sanning för regler och beslut. Uppdatera det efter varje fas.

## Arbetssätt
- Arbeta i faser (se nedan). Bygg aldrig nästa fas förrän användaren bekräftat att föregående fungerar i Studio.
- Efter varje fas: beskriv kort vad som ska testas i Studio och vad som ska hända.
- Användaren kör **inte** Rojo. Leverans sker som placefil:
  1. Kod skrivs i `src/` (Rojo-struktur, `default.project.json` hålls giltig ifall Rojo används senare).
  2. `python3 tools/build_place.py` bygger `build/HalmstadRush.rbxlx`.
  3. Commit + push till `main`. Användaren laddar ner filen via GitHub i webbläsaren (Download raw file) och öppnar den i Studio. Inget GitHub Desktop.
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
- Backhjälp (`HillAssist`): i uppförsbacke tas en del av tyngdkraften bort när man gasar, så att man kan köra upp på Galgberget.
- Fjädringens raycasts använder kollisionsgruppen `Cars`, så de ignorerar andra bilar (spökläge).

## Kartan (fas 2): det riktiga Halmstad
- **Mål: korrekt Halmstad, som GTA V återger Los Angeles.** Rätt gatunät och rätt platser, komprimerat. Inget påhittat "kaliforniskt": inga palmer, ingen Hollywood-skylt och inget pariserhjul.
- **Källa:** turistkartan "Halmstad City 2023" (Destination Halmstad, PDF från användaren). `tools/map/build_city.py` färgklassar kartbilden (vita/gula gator, orange kvarter, grönt, vatten, grå ytor, mörkröda större byggnader) och skriver `src/server/Map/Generated/`:
  - `CityGrid.luau`: markmaterial per 4x4-studs-ruta (RLE). Koder: A/Y gata, B kvarter, P park, W vatten, D brodäck, G grå yta, F fält, S idrottsplats, R större byggnad, N sand.
  - `CityBuildings.luau`: husfotavtryck (stenstad med gårdar i centrum, flerfamiljshus i mellanzonen, villor längre ut, tegelbyggnader för de mörkröda ytorna).
  - `CityRoadPoints.luau`: respawnpunkter mitt på gatorna med riktning.
  - Köra om: `pdftoppm -r 194 -png karta.pdf city` och sedan `python3 tools/map/build_city.py city-1.png --preview preview.png`. Kartbilden committas inte, bara den genererade datan.
- **Skala:** 1 kartpixel = 2 studs (≈ 1:3,6). Origo (0, 0) = Stora torg. X = öster, Z = söder. Marken ligger på Y = 0, vattenytan på Y = -4.
- **Terrain** för all mark: gator är asfalt i Terrain, broar är asfaltsdäck med vatten under (`D`). Galgberget är en kulle (`MapData.Hills`), och gator och hus i backen följer den via `MapData.GroundHeightAt`.
- **Utanför stadskartan** (byggs i `CityBuilder` och `MapService`): en kustremsa med Strandvägen och Östra stranden söder om kartan, havet (Laholmsbukten), Tylösandsvägen västerut till Tylösand (komprimerad), samt pir och fyr vid Nissans mynning.
- **Handplacerade landmärken** (`MapData.Landmarks`, byggs i `Landmarks.luau`): fontänen "Europa och tjuren" på Stora torg, S:t Nikolai kyrka, Halmstads slott, Norre port, Stadsbiblioteket över Nissan, Utsiktstornet, Hallandsgården, strandhotellet (generiskt namn), badbryggan, vindkraftverk och svenska flaggor. `RESERVED` i byggskriptet håller husgeneratorn borta från dem.
- Riktiga gatu- och platsnamn är okej. Företag får generiska namn.
- Stadsdelsnamnet visas efter närmaste etikett från kartan (`MapData.Districts`), med `SpecialAreas` som undantag (Stora torg, Tylösand och liknande).
- Byggnader och andra hinder har attributet `Obstacle` och ger nära-ögat-boost.
- Testbanan från fas 1 ligger kvar vid `MapData.TestTrackOrigin` (x = 6000).
- Grenen `wip/detaljerad-karta` innehåller ett avbrutet kaliforniskt spår. Använd det inte.

## Respawn (fas 2)
- `RespawnService` äger remotes för `ResetVehicle` och `TeleportToLocation` och skickar meddelanden till klienten via `Notify`.
- R / ↻: ställer bilen på hjulen där den står. Ett andra tryck inom `Respawn.DoubleResetWindow` (4 s) flyttar bilen till närmaste väg.
- Automatiskt till närmaste väg om chassit hamnar under vattenytan + 1, eller utanför `MapData.Bounds`.
- Respawnpunkter: genererade mitt på stadens gator (`CityRoadPoints`), plus punkter var 50:e stud längs `MapData.ExtraRoads` och testbanan.
- Snabbresa med `SnapToRoad` flyttar bilen till närmaste gatupunkt från platsens läge.
- Snabbresa: klienten skickar bara ett plats-id. Servern kontrollerar typ, längd, att platsen finns och en cooldown på 5 s.
- Alla serverflyttar går via `VehicleService.MoveCar` / `UprightCar`, som tar över nätverksägarskapet en kort stund och pausar teleportkontrollen.

## Krockar, takedowns och NPC-bilar (fas 3)
- **Delad fjädring:** `src/shared/Vehicle/Suspension.luau` används av spelarbilar (klienten) och NPC-bilar (servern).
- **Krockdetektering (klient, egen bil):** hastigheten vi satte förra bildrutan jämförs med vad fysiken gjort av den (bara horisontellt). `Crash.LightImpact` ger gnistor och skak. `Crash.WreckImpact` vid minst `WreckMinSpeed`, där bilen tappat fart, ger WRECKED!: ingen styrning, fjädringen släpps, krockkamera i `WreckDuration`, och sedan `ReportWreck`, så att servern kör `RespawnOnRoad`. Teleporter, respawn och återställning pausar detekteringen (`IgnoreCrashes`).
- **NPC-bilar (`NpcService`, servern äger fysiken):** de följer rutter (`Generated/CityRoutes.luau`, A* på gatunätet längs huvudgatorna, högertrafik) och saktar ner i kurvor. Smällar mäts likadant som för spelarbilar. Respawn sker långt från spelare vid kvaddning (efter `WreckDuration`), om de fastnar, hamnar i vattnet eller utanför kartan. Kollisionsgruppen `NPCCars` krockar med spelarbilar och med varandra.
- **Takedowns avgörs bara på servern:** en NPC-smäll med en spelarbil inom `HitRadius` sparar spelaren som "senaste knuffare". Kvaddas NPC-bilen inom `TakedownWindow` räknas det som en takedown: `CrashService.AwardTakedown` ökar `leaderstats.Takedowns` och skickar `Takedown` till spelaren, som får popup, boost och en kort krockkamera med låst styrning. Klienten kan aldrig rapportera en takedown.
- **Effekter (`EffectsController`, bara lokalt):**
  - Gnistor och rök använder Robloxs inbyggda texturer (`rbxasset://`).
  - Plåtdelarna ligger i kollisionsgruppen `Debris` och krockar inte med bilar. Motverkad gravitation gör att de svävar sakta.
  - Oskärpa och avmättade färger ger slow motion-känsla. Fysiken saktas aldrig ner.
- `CrashEffect` skickas till alla när en NPC kvaddas, och visas för spelare inom 600 studs.
- NPC-bilarna har attributet `Obstacle` och ger nära-ögat-boost.

## Kontroller
| | Tangentbord | Handkontroll | Touch |
|---|---|---|---|
| Gas | W / ↑ | RT | GAS |
| Broms/back | S / ↓ | LT | BRAKE |
| Styr | A/D / ←→ | vänster spak | ◀ ▶ |
| Drift | Space | X | DRIFT |
| Boost | Shift | A | BOOST |
| Återställ (2 tryck = till väg) | R | Y | ↻ |
| Snabbresa | M | Select | MAP-knappen |

## Beslut
| Beslut | Val |
|---|---|
| Leverans | Placefil (`build/HalmstadRush.rbxlx`) som laddas ner från GitHub på webben. Ingen Rojo och inget GitHub Desktop hos användaren |
| Kartan | Genereras från turistkartan över Halmstad (färgklassning till Terrain + hus). Korrekt gatunät, komprimerat ≈ 1:3,6 |
| Spelarkrockar | Spöken mot varandra i fri roam (kollisionsgruppen `Cars`, inte kolliderbar med sig själv, införd i fas 2). Krockar bara i race och jaktläge. NPC-bilar går alltid att krocka med |
| Språk | Engelska som bas i UI, svensk översättning via Robloxs Localization. Platsnamn alltid på svenska |
| Krockläge | Avskild korsning i industrizonen som bokas av en spelare åt gången |
| Slow motion | Fejkas på klienten (krockkamera, lokala vrakdelar). Fysiken på servern saktas aldrig ner |
| Max spelare | 10. Ställs in i Game Settings → Places på roblox.com (går inte att sätta i placefilen) |

## Faser
- [x] Fas 0: plan och frågor
- [x] Fas 1: Struktur + körbar bil med arkadfysik, drift och boost på en testplatta. Touch-kontroller.
- [x] Fas 2: Halmstad från riktiga stadskartan + respawn-system
- [ ] Fas 3: Krockar, takedowns, krockkamera, enkla NPC-bilar *(byggd, väntar på test)*
- [ ] Fas 4: Första racet + poäng/pengar (i minnet)
- [ ] Fas 5: DataStore (retry, sessionslås, versionerat schema), garage, bilköp, uppgraderingar, lackering
- [ ] Fas 6: Stunts, budjobb, kull-jaktläge, krockläge
- [ ] Fas 7: Butik, game passes, developer products, daglig belöning
- [ ] Fas 8: Ljud, UI, minikarta, mobiloptimering

## Kända begränsningar / att göra
- Ingen Luau-linter körs i molnmiljön. Fel syns först i Studios Output-fönster.
- Andra spelare ser inte hjulens fjädring och rotation (fixas vid behov i fas 8).
- Kartan har inte StreamingEnabled-optimering ännu (fas 8). Cirka 5 600 hus som Parts plus Terrain.
- Krockdetekteringen kan ge falska WRECKED! vid hårda landningar i backar. Justera `Crash.WreckImpact` vid behov.
- Gatorna saknar vägmarkeringar. Husen är enkla block utan tak och fönster (polering senare).
