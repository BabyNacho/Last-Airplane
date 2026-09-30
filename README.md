# LAST FLIGHT

*You're trapped inside a plane and something different can go catastrophically wrong every round.*

A multiplayer Roblox disaster-survival game (1–20 players). Every flight starts calm, a hidden
disaster reveals itself through subtle clues, and players have to work out what's going on,
split up to fix systems, make risky group decisions, rescue each other and bring the aircraft
down in one piece. Then they earn Flight Credits, unlock cosmetics and board the next flight.

The whole game — map, systems, UI, economy — is generated from the Luau source in this repo.
There are no binary place files to maintain.

---

## Quick start

**Easiest:** download the ready-made place from GitHub Actions: repository → **Actions** →
**Build Roblox place** → latest run → **Artifacts** → `LastFlight-Roblox-Place`. Unzip it and open
`LastFlight.rbxl` in Roblox Studio.

**Build it yourself:** install [Rojo](https://rojo.space) 7.4+ and [Lune](https://github.com/lune-org/lune), then run:

```bash
tools/build-place.sh        # -> LastFlight.rbxl (complete place, verified)
```

The build has three steps:

1. `rojo build` packages every script (the output has no world yet).
2. `tools/bake-place.luau` runs the game's own map builders and `Net.Setup`, and saves the airplane,
   lobby, spawn point and RemoteEvents into the place so you can see them in Studio's Edit mode.
3. `tools/verify-place.luau` fails the build unless that content is actually inside the file.

A plain `rojo build` on its own gives a place with scripts but an empty Workspace.

When you press **Play**, the server replaces the baked world with a freshly built identical copy.
The HUD, shop and other screens are built by the LocalScripts at play time, so StarterGui is empty
in Edit mode. That's expected. A round begins after the 30s lobby countdown; use **Start** with
2–4 players in the Test tab to try multiplayer.

### Manual steps Roblox requires

| Step | Why |
|---|---|
| **Publish the place**, then *Game Settings → Security → Enable Studio Access to API Services* | Needed for DataStores in Studio. Without it the game still runs on temporary (unsaved) profiles and says so in-game. |
| **Create Game Passes and Developer Products** on the Creator Dashboard, then paste the ids into `src/shared/Config/MonetizationConfig.luau` | Roblox only lets you create products on the website. Until an id is set, that item shows "COMING SOON" and cannot be bought. |
| *Game Settings → Avatar → Avatar type: R15* | The emotes and passenger sit animation are R15 animations. |
| *(Optional)* replace sound ids in `src/shared/Config/SoundConfig.luau` | The defaults use sounds that ship with the Roblox client (`rbxasset://sounds/...`) so the game is never silent. Swap in licensed `rbxassetid://` audio for a production release. |

Products to create (suggested prices are in `MonetizationConfig`):

- Game passes: `VIP` (VIP Boarding Pass), `EmotePass`
- Developer products: `CreditsSmall`, `CreditsMedium`, `CreditsLarge`, `FirstClassBundle`, `PartyPack`, `JetpackReplica`

---

## The round

```
LOBBY (30s) → BOARDING (18s) → FLIGHT (35–55s, clues start) → DISASTER (70–90s)
→ CRISIS (80–110s) → FINAL EVENT (55s, landing prep) → LANDING (14s)
→ [EVACUATION (30s) after rough landings or fires] → RESULTS (16s) → LOBBY
```

A round lasts roughly 5–8 minutes. Every timing lives in `src/shared/Config/GameConfig.luau`.

- **Hidden disaster.** Nothing tells players what the disaster is. They get clues: sounds, smoke,
  flickering lights, a captain's announcement cut off mid-sentence. The disaster's name only appears
  on the results screen.
- **Objectives** appear in the HUD as the situation unfolds, marked *critical* or *optional*, with a
  3D waypoint for the most urgent one.
- **Decisions** are group votes (majority wins, ties go to the safer default) or personal choices
  at a panel. Every option has a different consequence, and the results screen shows what each
  decision led to.
- **Condition:** Healthy → Injured → Critical → Unconscious (revivable for 28s) → Dead. Teammates can
  treat injuries or revive you. In a solo game you can pull yourself back up once per flight.
- **Landing score** combines aircraft stability, landing gear, unresolved critical objectives,
  fires aboard, the manual approach (when someone has to fly) and the results of decisions. It maps
  to Perfect / Successful / Hard / Emergency / Crash. Buckled-in players are far safer at touchdown.
- **Outcomes:** Perfect Survival, Successful Landing, Hard Landing, Emergency Landing, Partial
  Survival, Crash Landing, Complete Disaster.
- **Random modifiers** (Night Flight, Full Flight, Rough Air, Veteran Crew, Low Fuel) and random
  variants inside every disaster keep rounds different.

## Disasters

| Disaster | Clues | Core gameplay | Decisions |
|---|---|---|---|
| **Engine Failure** | vibration, smoke puff from one engine, reassuring captain | diagnose the fault (random cause) at the aft engine panel, start the APU, open the fuel crossfeed | vote: *restart now* (chance of full power; can set the engine on fire) vs *prepare for landing* (safe, no perfect landing) |
| **Severe Turbulence** | seatbelt chime, clouds, light bumps | light→moderate→severe; unbuckled players stumble and get hurt, bins drop luggage, galley carts break loose; reset the yaw damper | vote: *climb above* (ends fast, but the masks drop) vs *descend below* (keeps shaking, gusty landing) |
| **Cabin Fire** | faint haze, chirping smoke detector, flickering lights | spreading fire cells and smoke, extinguishers, doors that contain it, re-ignition until the circuit is cut | personal: *cut all power* vs *isolate one circuit* (work out which circuit feeds the fire's zone); vote: *vent the cabin* (starves the fire, everyone needs masks) |
| **Lightning Strike** | storm, distant flashes, static in announcements | blackout, three electrical buses in different places (split up), sparking wiring hazards | vote: *restart now* (a surge can knock everything out again and start a fire) vs *wait for the storm* |
| **Bird Strike** | a flock visible outside | hidden damage (engine / windshield / cabin window); inspect wings, windows and cockpit to find it; speed tape, standby air data, fuel valves | engine: *shut down vs keep running*; windshield: *divert vs continue*; window: *descend vs stay high* |
| **Cabin Depressurization** | whistle, ears pop, the captain starts slurring | masks, portable oxygen, gradual hypoxia, hypoxic pilots you can revive, a hidden leak source | vote: *rapid dive* (safe air fast, violent) vs *controlled descent* (mask oxygen may run out) |
| **The Empty Cockpit** *(rare)* | announcement cut off, attendant knocking, no answer | three ways in (crash axe / hidden keycard / door code from the captain's logbook), fly by hand, radio ATC, optionally find the pilots | personal: how to get in; vote: *nearest airport* (short runway) vs *major airport* (fly longer) |
| **Hydraulic Failure** | thunk, twitching controls, dripping fluid | find the leaking line by its drip, isolate it | vote: reserve fluid to *flight controls* (then hand-crank the gear as a team) or *landing gear* (heavy aircraft) |
| **Blind Approach** *(rare)* | thickening fog, glitching displays | reboot and re-align navigation; watch the windows for runway lights and report the correct side | vote: *hold for the fog* (clearer, fuel risk) vs *approach now* |

## Features

- **Map:** an airport terminal lobby (departure board, gate, shop / wardrobe / records kiosks,
  leaderboard, VIP lounge, parked airliner) and a full airliner interior: cockpit, galleys,
  first class, economy (106 passenger seats), overwing exits, lavatories, service/avionics bay, crew rest,
  wings and engines outside the windows. Everything is built procedurally and modular per section.
- **Outside world:** clouds stream past, the ground rises during the descent, a runway slides
  underneath at touchdown; storms, fog, birds and runway lights are rendered client-side.
- **NPCs:** pooled, seated passengers that react (nervous / panic / confused / masked), injured
  passengers you can help, flight attendants who make announcements in person, pilots.
- **Interaction:** ProximityPrompts with a custom UI for keyboard `[E]`, gamepad `(X)` and a large tap
  target on touch. Hold-to-use with progress bars. The server re-checks every trigger.
- **Mobile:** UI scales to the screen, respects safe-area insets and enforces a minimum touch target
  size. The cockpit controls and decision cards have on-screen buttons.
- **Camera:** Roblox's default camera, with one owner (`CameraController`) layering shake and, while
  you fly the aircraft, a tilt from its attitude. The layer is removed every frame before the
  Roblox camera runs, so it never builds up. Releasing the controls, or pressing **⟲ RECENTER**
  (`V` / right stick click), glides the view back to an upright, eye-level angle behind you.
- **Economy:** Flight Credits for surviving, objectives, rescues, helping passengers, good
  decisions, bravery, evacuating, plus a first-flight-of-the-day bonus. A typical survived round
  pays 150–300 FC and cosmetics cost 200–1,300 FC.
- **Shop (Duty Free):** hats, face and body accessories (built from parts, no uploads needed),
  titles, trails, emotes, victory effects, UI themes and bundles. Robux items use the official
  MarketplaceService prompts. Nothing sold affects survival.
- **VIP pass:** VIP title and chat tag, VIP lounge access, Golden Wake trail, Gold UI theme and +20% credits.
- **Progression:** 16 tracked stats, 21 achievements (some unlock exclusive titles), disaster
  mastery levels, and daily and weekly challenges.
- **Data:** DataStore profiles written with `UpdateAsync` and a session lock, retries with backoff,
  autosave and `BindToClose`. A failed load gives a temporary profile that is **never** saved over
  real data; progress is merged in once the store recovers. Developer product receipts are
  idempotent and are only acknowledged after the profile saves.
- **Server authority:** the server decides rewards, damage, objectives, decisions, survival and
  round state. Every remote is type-checked and rate-limited.

## Project layout

```
default.project.json            Rojo project (also sets Workspace/Lighting/Players properties)
src/shared/  -> ReplicatedStorage.Shared
  Config/                       all tuning: GameConfig, DisasterConfig, EconomyConfig, ShopCatalog,
                                MonetizationConfig, AchievementConfig, ChallengeConfig, SoundConfig,
                                UIConfig, MapConfig
  Net.luau                      every RemoteEvent/RemoteFunction, created by the server at boot
  Maid, Signal, Util, Enums
src/server/  -> ServerScriptService.Server
  Main.server.luau              boots services in order (Init, then Start)
  Registry.luau                 service lookup (no circular requires)
  RoundContext.luau             per-round state + round-scoped scheduler (auto-cancels on round end)
  Services/                     RoundService (state machine), MapService, FlightService,
                                ConditionService, ObjectiveService, DecisionService, InteractionService,
                                CabinService, EquipmentService, RescueService, NPCService, LandingService,
                                DisasterService, RewardService, DataService, ShopService,
                                MonetizationService, CosmeticService, EmoteService, AchievementService,
                                ChallengeService, LobbyService, EffectsService, DevService (Studio only)
  Systems/                      FireSystem, OxygenSystem, TurbulenceSystem, CockpitSystem
  Disasters/                    DisasterBase + one module per disaster
  Map/                          AirplaneBuilder, LobbyBuilder, BuildUtil
src/client/  -> StarterPlayerScripts.Client
  Main.client.luau, ClientState.luau
  UI/                           UIKit (themeable components, scaling), Sfx
  Controllers/                  HUD, Prompt, Decision, Cockpit, Shop, Profile, Emote, Results,
                                Effects, Lighting, OutsideWorld, Sound, Camera (owner: flight tilt,
                                recenter, spectate),
                                Character, ChatTag
src/character/                  replaces default health regen (health is server-controlled)
tests/sim/                      headless server + client simulation (see Testing)
tools/                          check.sh (build + type-check), test.sh (simulation)
```

## Testing

### Automated checks (no Studio needed)

```bash
tools/check.sh     # rojo build + strict type-check of every script against the Roblox API
tools/test.sh      # builds, then runs the headless simulation with Lune
tools/test.sh fire # run only scenarios whose name matches "fire"
```

`tools/check.sh` needs `rojo` and `luau-lsp`. `tools/test.sh` needs `rojo` and
[`lune`](https://github.com/lune-org/lune). Both scripts also look for binaries in `tools/.cache/bin`.

The simulation (`tests/sim`) loads the built place into Lune, runs the real server and client
scripts in virtual time (a full round takes milliseconds), and uses bot players that sit, wander,
use equipment, trigger prompts, fight fires, vote, fly the approach and evacuate. Scenarios:

- every disaster played solo and with a squad of 4
- 6-player and 8–14 player stress runs over several rounds with cooperative, selfish and idle bots
- the camera: flight tilt while piloting (no drift), smooth recenter on release and from the
  RECENTER button, clean reset on death, respawn and round end
- a player leaving mid-round, a player dying (respawns at the terminal, can spectate), everyone
  dying, a late joiner waiting for the next flight, a disaster module crashing (safe fallback)
- a DataStore outage (temporary profile, never written, merged on recovery)
- idempotent receipt processing and shop validation, including exploit-shaped remote payloads
- the full client UI on desktop, tablet and phones (touch input, small viewports) while a random
  button fuzzer clicks through the HUD, shop, records, decisions and results screens

The simulation already caught real bugs before any Studio run: a shadowed `task` library in Maid,
an ambiguous-syntax call in UIKit, a `UDim`/table `Padding` mix-up that would have broken every
list layout, and a non-existent ParticleEmitter property.

### In Studio

- `GameConfig.StudioForceDisaster = "CabinFire"` always picks that disaster in Studio.
- `GameConfig.StudioTimeScale = 0.3` shortens every phase in Studio.
- Chat commands (Studio only): `/skip` ends the current phase, `/disaster <Id>` or `/disaster off`
  forces the next disaster, `/credits` gives 1,000 FC, `/hurt` deals 40 damage.
- Multiplayer: Test tab → Clients and Servers → start 2–4 players to try rescues, votes and co-op objectives.

## Extending

- **New disaster:** create `src/server/Disasters/MyDisaster.luau` with
  `DisasterBase.extend("MyDisaster")`, implement any of `Setup / Clues / Start / Crisis / Final /
  OnTouchdown / RevealDetail / Cleanup`, then add an entry to `DisasterConfig.Disasters`. The base
  class gives you objectives, prompts, votes, announcements, effects and landing adjustments.
- **New cosmetic:** add an entry to `ShopCatalog` (accessories take a `Shape` from `CosmeticService`).
- **New achievement or challenge:** add a row to `AchievementConfig` / `ChallengeConfig`.
- **New aircraft section:** add a builder function in `AirplaneBuilder` and a range in `MapConfig.Sections`.

## Known limitations

- The aircraft doesn't physically move; flight, descent and landing are shown through the outside
  world, camera and effects. This is the usual approach on Roblox and keeps physics stable.
- The simulation covers server logic and client UI code paths, but not rendering, physics or feel.
  Tune visuals and difficulty with real play sessions in Studio.
- Default sounds are Roblox built-in placeholders; supply licensed audio before release.
- Shop previews are stylised icons and swatches, not 3D renders.
- Robux purchases need the product ids from the manual steps above.
