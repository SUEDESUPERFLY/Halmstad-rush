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
- **Mängden trafik** (`VehicleConfig.Npc`): `TrafficMax` (25) bilar på en tom server, `TrafficPerPlayer` (1) färre per riktig spelare, aldrig under `TrafficMin`. Fördelas på rutterna efter `RouteShare`. `NpcService` justerar en bil var `TrafficAdjustInterval`:e sekund: nya bilar dyker upp utom synhåll (`MinSpawnDistance`) och inte närmare en annan NPC än `SpawnSpacing`. Bilar tas bara bort när ingen spelare är inom `DespawnDistance` och bilen inte nyss knuffats. Gäller bara trafik, inte race-, kull- eller krocklägesbilar.
- `CrashEffect` skickas till alla när en NPC kvaddas, och visas för spelare inom 600 studs.
- NPC-bilarna har attributet `Obstacle` och ger nära-ögat-boost.

## Race och pengar (fas 4)
- **Banor** (`RaceConfig.Races`) följer de genererade rutterna i `CityRoutes`. Kontrollpunkterna ligger var `CheckpointSpacing`:e ruttpunkt, och mål är startpunkten. Första racet heter "Stora ringen" (1 varv, cirka 8 500 studs, 3 NPC-motståndare).
- **`RaceService` (servern avgör allt):** flödet är Idle, Lobby (`LobbyTime`, andra kan gå med), Countdown (alla flyttas till startgriden, och den som rullar iväg ställs tillbaka), Running och Cooldown.
  - Kontrollpunkter måste tas i ordning. Servern mäter avståndet var 0,1 s, och klienten visar bara portarna.
  - Placering: i mål efter tid, annars efter framsteg (ruttpunkter).
  - Racet slutar när alla spelare gått i mål, `FinishTimeout` efter första målgång, eller vid `MaxRaceTime`.
  - Belöningen (`Rewards` per placering och `TakedownBonus` per takedown) betalas bara ut av servern via `EconomyService`.
- **Deltagarna ligger i kollisionsgruppen `RaceCars`:** de krockar med varandra och trafiken men är spöken för andra spelare (`VehicleService.SetCollisionGroup`). Klientens fjäderstrålar följer `Chassis.CollisionGroup`.
- **Respawn och snabbresa under race:** `RespawnService.SetRespawnOverride` gör att kvaddning, vatten och R två gånger flyttar bilen till senaste kontrollpunkten. `SetTeleportBlocker` spärrar snabbresa under racet.
- **NPC-motståndare** (`NpcService.SpawnRacer`) har egen fart och rubber band mot den ledande spelaren (`RubberBand`). Efter kvaddning kommer de tillbaka strax bakom. Framsteget räknas i `Npc.Passed`.
- **Takedowns i race:**
  - Takedowns på motståndare räknas som vanliga takedowns och ger bonus vid målgång.
  - En kvaddad spelare (ReportWreck) ger takedown till närmaste annan deltagare inom `PlayerTakedownRadius`.
  - Känd svaghet: en klient kan fejka kvaddningar och skänka takedowns till någon i närheten. Det begränsas av cooldown och avstånd och ger bara små belopp.
- **Pengar (`EconomyService`):** leaderstats `Kronor`, sparas i profilen från och med fas 5. `AddMoney` validerar beloppet (`MaxSingleReward`). En takedown i fri körning ger `EconomyConfig.TakedownReward`. Nära ögat, drift och lufttid ger ingen pengar, eftersom de räknas på klienten.
- `src/server/Util/Leaderstats.luau` skapar leaderstats-värden vid behov.
- Startlinjen har en neonring, en banderoll och en BillboardGui. Spelaren kör in i ringen och trycker på knappen eller E. Snabbresan "Race: Stora ringen" går till startlinjen.

## Sparad data, garage och bilar (fas 5)
- **`DataService`** (DataStore `DataConfig.StoreName`, nyckel `Player_<UserId>`):
  - Varje anrop görs med retry och exponentiell backoff.
  - Sessionslås `_lock = { JobId, Time }` i posten. Är låset någon annans och färskare än `LockTimeout` väntar servern (`LockWaitAttempts`) och kickar sedan med en förklaring.
  - Autosparning var `AutosaveInterval`. Spelaren sparas och låset släpps vid `PlayerRemoving` och `BindToClose`.
  - Misslyckad laddning ger en icke-sparad profil som aldrig skriver över den riktiga datan.
  - Opublicerat place eller Studio utan API-åtkomst: data sparas bara i minnet, och spelaren får en notis.
- **Schema v1 (nu v2, se fas 7)** (`PlayerData`): `Version`, `Money`, `Takedowns`, `OwnedCars[id] = { Upgrades = { Engine, Grip, Turbo }, Color }`, `SelectedCar`, `Stats = { RacesFinished, RacesWon }`.
  - `sanitize` migrerar och validerar allt som läses in: okända bilar och färger tas bort, nivåer kläms, och startbilen finns alltid.
  - Nya fält kräver ny `SchemaVersion` och en migrering i `sanitize`.
- **All ändring av sparad data** går via `DataService.Update(player, fn)`. Den markerar profilen för sparning och skickar `Changed`, som speglas till leaderstats (`EconomyService`) och till klienten (`GarageService` → `ProfileUpdated`).
- **`EconomyService`:** `AddMoney` (validerat belopp) och `Spend` (bara om saldot räcker). Pengarna lever i profilen.
- **`CarCatalog` (delad):**
  - 5 bilar: Kustpilen (start), Laxen, Galgbergaren, Tylösand GT och Stormvind. De köps bara med kronor, aldrig med Robux.
  - Uppgraderingarna Motor, Grepp och Turbo (3 nivåer var) och 12 lackfärger (`PaintCost`).
  - `ComputeStats` ger multiplikatorer.
- **`GarageService`:** tar emot `GarageAction(action, carId, arg)`.
  - Validerar typ, längd, cooldown, ägande, nivå och saldo.
  - Stängt under race.
  - Köp och byte bygger om bilen där den står (`VehicleService.RebuildCar`). Uppgradering och lackering ändrar bilen på plats (`RefreshCar`).
- **Bilens egenskaper:**
  - Servern sätter dem som attribut på bilmodellen (`TopSpeedMul`, `AccelerationMul`, `HandlingMul`, `BoostMul`, `ChargeMul`, `HillAssistMul`, `CarId`), och klientens fysik läser dem.
  - Serverns fartgräns per bil = `Server.HorizontalSpeedCap × TopSpeed × Boost`.
- **`CarBuilder`:** 5 karosstilar (Cabriolet, Hatch, Coupe, Jeep, Hyper) på samma chassi och samma fysik. Delar med attributet `Paint` lackeras om med `CarBuilder.Paint`.
- **Garagemenyn** (`GarageUI`) öppnas med G eller GARAGE-knappen och visar bara det servern skickat.
- **För riktig sparning i Studio** måste placet vara publicerat (File → Publish to Roblox) och Game Settings → Security → "Enable Studio Access to API Services" vara påslaget.

## Aktiviteter (fas 6)
- **`PlayerMode`** (`src/server/Util`) håller koll på om en spelare är i ett läge: `Race`, `Activity` eller `Tag`. Bara ett läge åt gången, och garaget är stängt under alla lägen.
- **`RespawnService`:** `AddRespawnOverride` och `AddTeleportBlocker` kan nu ha flera lägen samtidigt (race, aktivitet, kull). `RandomPointNear` slumpar gatupunkter, till exempel för budjobb.
- **`ActivityService`** hanterar aktiviteter för en spelare åt gången. Modulerna ligger i `src/server/Activities/` och har `Start`, `Update` och vid behov `OnWreck`, `RespawnCFrame`, `Stop` och `OnNpcEvent`.
  - Markörerna (`ActivityConfig.Activities`) snäpps till närmaste gata, utom när `SnapMarker = false`.
  - Inbjudan (`ActivityInvite`) går ut när bilen är i ringen. Klienten skickar `RequestActivity(id)`, och servern kontrollerar avstånd och läge.
  - Modulerna får bara använda `api` (bland annat `SetState`, `Finish`, `MoveCar` och `RandomRoadPoint`).
  - `Finish` betalar ut via `EconomyService` och skickar `ActivityResult`. Klienten får bara visningsdata (`ActivityState`: Title, Role, Objective, EndsAt, CountdownTo, Score, Target, TargetLabel).
- **Aktiviteterna:**
  - **Delivery** (Pizzabud, Taxi): 3 slumpade mål på riktiga gator. Klockan räknas från avståndet. Betalningen är bas plus tidsbonus, och varje kvaddning kostar `WreckPenalty`. Man måste stanna (`ArriveMaxSpeed`) vid målet.
  - **StuntJump** (Strandhoppet, Tylösandshoppet): ramperna ligger på stränderna. Servern mäter uppskjut (bilen högt över marken nära rampens topp) och landning, och avståndet ger brons, silver eller guld. Tre försök, och bilen ställs tillbaka på startsträckan mellan dem.
  - **Drift** (Driftkungen): servern räknar poäng från bilens fart i sidled (replikerad, begränsad av fartkontrollen) i 45 s. En krock kostar poäng.
  - **CrashMode** (Krockläget): en avskild industrikorsning vid `CrashMode.Origin` (x 6000, z −2200), som bokas av en spelare åt gången.
    - Korsande trafik (NPC-typen `Arena`) och en nedräkning med låst bil.
    - Skadevärdet räknas från `NpcService.OnEvent` ("Impact" och "Wrecked"), med kedjebonus.
    - Belöningen är skadevärdet / `ScorePerKrona`, högst `MaxReward`. Efteråt flyttas bilen tillbaka till markören.
- **`TagService`** (Kull med bilar): lobby (`LobbyTime`), sedan en runda på `RoundTime`.
  - Den som är "den" tar över rollen genom att komma inom `TagDistance` (och kan inte tas tillbaka direkt, `TagImmunity`).
  - Kortast tid som "den" vinner, och `Rewards` delas ut efter placering.
  - NPC-bilar (typen `Chaser`) fyller ut till `MinParticipants`. Som "den" jagar de med `Npc.Target` och enkel hinderundvikning, annars kör de runt på ringen.
  - Deltagarna ligger i kollisionsgruppen `TagCars`.
- **`NpcService`** har nu `SpawnOnRoute`, `Npc.Target` (styr mot en punkt), `Npc.RespawnAt` och `OnEvent`.
- **Klient:** `ActivityController` sköter remotes, ett ljus vid målet med avstånd och "håll still" vid `CountdownTo`. `ActivityUI` har startknappen (E), panelen (avbryt), nedräkningen och resultatet.

## Butik och daglig belöning (fas 7)
- **`ShopConfig`:** game passes VIP-lack (6 extra färger), Neonunderrede och Snabbresa+ (1 s cooldown), samt developer products Konfettiregn och Stöd utvecklaren.
  - **Inget säljs som ger fartfördel, kronor, bilar eller slump.**
  - `Id = 0` betyder att köpet inte är skapat på roblox.com än. Då visas "Inte i butiken än", och i Studio finns knappen "Testa (Studio)" (servern kontrollerar `RunService:IsStudio()`).
- **`ShopService`:**
  - Ägda pass blir spelarattribut `Pass_<Key>`. De läses av `GarageService` (VIP-färger), `VehicleService` (underrede) och `RespawnService` (snabbresa).
  - **`ProcessReceipt`:** köpet delas ut, köp-ID:t sparas i profilen (`Receipts`, senaste 50) och sparas direkt (`DataService.SaveNow`). Först därefter returneras `PurchaseGranted`. Ett köp-ID som redan finns returneras som Granted utan att delas ut igen.
  - **Daglig belöning:** UTC-dag (`os.time() // 86400`) och streak i profilen (`Daily`). Belöningen räknas av `ShopConfig.DailyReward`.
- **Schema v2:** `Receipts` och `Daily` har lagts till. `sanitize` fyller på standardvärden för äldre profiler.
- **Klient:** `ShopUI` öppnas med B eller SHOP-knappen. Dagens belöning visas som en notis vid start. Konfetti visas via `Celebrate` och `EffectsController.Confetti`.
- **Inställningar i Roblox** (publicering, API-åtkomst, max spelare, frågeformulär, pass) står som checklista i `README.md`.
- **När du vill sälja på riktigt:** skapa passen och produkterna på create.roblox.com (spelet → Monetization) och skriv in ID:na i `ShopConfig`.

## Polering: ljud, minikarta och mobil (fas 8)
- **`SoundController`** (lokalt) använder Robloxs inbyggda ljud (`rbxasset://sounds/...`) och kräver inga uppladdningar:
  - fartvind som stiger med farten
  - duns vid krock
  - plask vid "SPLASH!"
  - pling vid pengar, kontrollpunkter, takedowns och nära ögat.

- **Motor och musik (egna ljud):** `tools/audio/make_audio.py` syntetiserar `assets/audio/engine_loop.ogg` (2 s, sömlös) och `assets/audio/music_loop.ogg` (cirka 69 s, 112 BPM, a-moll, sömlös). Inga licensfrågor. Användaren laddar upp filerna på create.roblox.com och ID:na skrivs in i `SoundConfig.EngineId` och `SoundConfig.MusicIds`. Tomt ID = inget ljud.
  - Egen bil: varvtal med låtsasväxlar (`EngineGears`), stiger med gas, frivarv i luften, extra varv vid boost. Tonhöjd `EnginePitch`.
  - Andra bilar (taggen `HalmstadCar`, sätts i `CarBuilder.Build`): 3D-motorljud för de `OtherEngineLimit` närmaste inom `OtherEngineMaxDistance`.
  - Musiken spelas i tur och ordning och börjar om. U eller ♪-knappen (visas bara om det finns musik) slår av och på.
- **Minikartan (`MinimapUI`)** har norr uppåt och visas uppe till vänster. N döljer och visar den.
  - Data: `src/shared/Map/MinimapData.luau`, genererad av `tools/map/build_minimap.py` från `CityGrid`. Den består av rektanglar (gata, huvudgata, vatten) på 24 studs, cirka 2 200 GUI-rutor.
  - Havet och Tylösandsvägen ritas från `MapData`. Prickar visar aktiviteter, kull, racestart, andra spelare och aktuellt mål.
  - Bara kartans position uppdateras varje bildruta (`ClipsDescendants`).
- **Övrigt i fas 8:** `SpinnerController` snurrar modeller med taggen `Spinner` (vindkraftverkens rotorer, attributet `SpinSpeed`) lokalt inom 1 500 studs. Minikartan visar nästa kontrollpunkt under race (`RaceController.NextCheckpoint`). `HelpUI` (H eller ?-knappen) visar kontrollerna och öppnas en gång vid start.
- **Mobil och prestanda:**
  - `Workspace.StreamingEnabled` (min-radie 256, målradie 1024) sätts i `default.project.json` (`$properties`, som byggskriptet stöder för bool, int, float och sträng).
  - `VehicleService` anropar `RequestStreamAroundAsync` före långa flyttar (över 300 studs), så att marken hinner laddas.
  - Dekordelar kastar inga skuggor, och plåtdelarna är färre på pekskärm.
- **ScreenGui-ordning (`DisplayOrder`):** fönster (garage och butik) 10, snabbresemenyn 5, övrigt 0.

## Snyggare stad (fas 9)
- Inspiration: stadsspel som Greenville, Brookhaven och Driving Empire. Det som gör deras städer snygga är sammanhållna färger, tak, fönster, trottoarer, träd, gatlyktor, vägmarkeringar och mjukt ljus med skuggor. Ingen betafunktion används.
- **`CityDetails`** (`src/server/Map/`):
  - Sadeltak (två `WedgePart`) med nocken längs långsidan på stenstaden, flerfamiljshusen och villorna. Tegel (`ClayRoofTiles`), takpapp (`RoofShingles`) eller plåt. Offentliga tegelbyggnader har platt tak med ljus takfot.
  - Ett fönsterband per våning (var 7:e stud från 3,5 över marken). Bandet sticker ut på långsidorna men inte på gavlarna. Fönster är dekor.
  - Streckad mittlinje (6 + 8 studs) och gatlyktor (`Props.StreetLamp`, ungefär var 60:e stud, varannan sida, minst 40 studs mellan lyktor) längs rutterna i `CityRoutes`. Lyktan står vid första ruta som inte är gata.
  - Lövträd i parkerna (kod P, rutnät 26 studs, 45 %), tallar på Galgberget. Inga träd inom 8 studs från gata, vatten eller större byggnad, och inte vid landmärkena (`keepOut` i `MapService`). Trädkronorna går att köra igenom.
  - De nya materialen hämtas med `CityDetails.Material(name, fallback)`, så att bygget inte kraschar om ett material saknas.
- **Trottoarer och gårdar:** `CityBuilder.SurfaceCodeAt` delar kvarteren (B) i trottoar (K, `Pavement`) närmast gatan, gårdar (C, `Cobblestone`) i stenstaden (under 750 studs från Stora torg) och gräs (L) längre ut. Husväggar mot gata flyttas in 3 studs (`pullBackFromRoads`), så att trottoaren syns.
- **Ljus:** `Lighting.Technology = ShadowMap` sätts i `default.project.json` (byggskriptet stöder enum som `{"Enum": n}`). `ShadowSoftness`, miljöljus för de nya materialen, varm ton och svaga solstrålar sätts i `MapService`.
- Cirka 23 000 extra delar på husen plus träd, lyktor och linjer. StreamingEnabled gör att mobilen bara laddar det närmaste.

## Språk
- **All text i koden skrivs på engelska.** Svenska översättningar ligger i `src/shared/Localization/Swedish.luau`, med den engelska källtexten som nyckel. Saknas en översättning visas engelskan.
- **`Locale`** (`src/shared/Localization/Locale.luau`) väljer svenska på klienten om `LocalizationService.RobloxLocaleId` börjar på `sv`. Alla andra språk får engelska.
  - Klienten: `Locale.T(text, ...)` översätter och formaterar (`%d`/`%s`). `Locale.Resolve(msg)` gör om en sträng eller `Locale.Msg` till text.
  - Servern översätter aldrig. Den skickar engelska strängar eller `Locale.Msg(format, ...)` i `Notify`, `ActivityState`, `ActivityResult`, inbjudningar och `AddMoney(reason)`. Argument som är `Msg` översätts också, vanliga strängar (spelarnamn) lämnas orörda.
  - Kick-meddelanden: `Locale.ForPlayer(player, text)` (läser `player.LocaleId` på servern).
  - Skyltar som servern bygger märks med `Geometry.Localize` (taggen `Localize`) och översätts av `LocaleController` på klienten.
- Platsnamn, bilnamn och racenamn översätts inte. Gatuskyltar i världen är på svenska, som i riktiga Halmstad.
- Ny text: skriv den på engelska och lägg till en rad i `Swedish.luau`.
- Testa i Studio: Test → Player Emulator → Locale (t.ex. `sv-se` eller `en-us`).

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
| Starta/gå med i race (vid startlinjen) | E | B | knappen START RACE |
| Garage | G | – | GARAGE-knappen |
| Starta aktivitet (vid markören) | E | B | knappen STARTA |
| Butik | B | – | SHOP-knappen |
| Minikarta av/på | N | – | – |
| Musik av/på | U | – | ♪-knappen |
| Hjälp (kontroller) | H | – | ?-knappen |

## Beslut
| Beslut | Val |
|---|---|
| Leverans | Placefil (`build/HalmstadRush.rbxlx`) som laddas ner från GitHub på webben. Ingen Rojo och inget GitHub Desktop hos användaren |
| Kartan | Genereras från turistkartan över Halmstad (färgklassning till Terrain + hus). Korrekt gatunät, komprimerat ≈ 1:3,6 |
| Spelarkrockar | Spöken mot varandra i fri roam (kollisionsgruppen `Cars`, inte kolliderbar med sig själv, införd i fas 2). Krockar bara i race och jaktläge. NPC-bilar går alltid att krocka med |
| Språk | Engelska som bas i UI, svensk översättning för spelare med svenska som Roblox-språk (egen ordlista, se "Språk"). Platsnamn och bilnamn alltid på svenska |
| Krockläge | Avskild industrikorsning (egen plats utanför stan, x 6000 / z −2200) som bokas av en spelare åt gången. Markören står i hamnens industriområde |
| Slow motion | Fejkas på klienten (krockkamera, lokala vrakdelar). Fysiken på servern saktas aldrig ner |
| Max spelare | 10. Ställs in i Game Settings → Places på roblox.com (går inte att sätta i placefilen) |

## Faser
- [x] Fas 0: plan och frågor
- [x] Fas 1: Struktur + körbar bil med arkadfysik, drift och boost på en testplatta. Touch-kontroller.
- [x] Fas 2: Halmstad från riktiga stadskartan + respawn-system
- [x] Fas 3: Krockar, takedowns, krockkamera, enkla NPC-bilar
- [x] Fas 4: Första racet + poäng/pengar (i minnet)
- [x] Fas 5: DataStore (retry, sessionslås, versionerat schema), garage, bilköp, uppgraderingar, lackering
- [x] Fas 6: Stunts, budjobb, kull-jaktläge, krockläge
- [x] Fas 7: Butik, game passes, developer products, daglig belöning
- [x] Fas 8: Ljud, UI, minikarta, mobiloptimering
- [x] Fas 9: Snyggare stad: tak, fönster, trottoarer, träd, gatlyktor, vägmarkeringar, skuggor

## Kända begränsningar / att göra
- Lint i molnmiljön: `stylua --syntax luau --check` (syntax) och `selene src` (`selene.toml`, egen std `roblox_min.yml` där Roblox-globaler bara deklareras). Ingen typkontroll (luau-lsp saknas), så typfel syns först i Studios Output-fönster. Verktygen installeras med `cargo install stylua selene` om de saknas.
- Andra spelare ser inte hjulens fjädring och rotation.
- Cirka 5 600 hus som Parts plus Terrain, med StreamingEnabled (fas 8). Testa på en riktig mobil innan publicering.
- Inget motorljud eller musik förrän ljuden laddats upp och ID:na lagts in i `SoundConfig` (`EngineId`, `MusicIds`).
- Alla game pass- och produkt-ID:n är inlagda i `ShopConfig`. Passen måste vara "Item for Sale" på roblox.com för att gå att köpa.
- Krockdetekteringen kan ge falska WRECKED! vid hårda landningar i backar. Justera `Crash.WreckImpact` vid behov.
- Vägmarkeringar finns bara längs huvudgatorna (rutterna). Mittlinjen följer ruttens linje, som kan ligga lite vid sidan av gatans mitt på breda gator.
- Husen har inga dörrar eller enskilda fönster, bara fönsterband.
