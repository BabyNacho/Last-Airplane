--[[
	ShopCatalog
	Every cosmetic in the game. NOTHING here affects survival, health, flight performance,
	disaster difficulty, objectives or landing quality - items only change how things look.

	Item fields:
		Id           stable id (saved in player data - never rename an existing id)
		Name, Description (short and fun)
		Category     FlightGear | Outfits | Emotes | Plane | Effects | Bundles | Premium
		Type         Accessory | Outfit | Badge | Luggage | Title | Emote | Trail | Aura |
		             VictoryEffect | Theme | PlaneSkin | WingEffect | PlaneTrail | Bundle
		Slot         loadout slot for equippables (see ShopCatalog.Slots)
		Price        Flight Credits (nil = not sold for credits)
		Product      MonetizationConfig product key for Robux items
		Pass         game pass key that also grants it
		Unlock       achievement id that grants it
		Default      owned by everyone
		Exclusive    only available inside a bundle / pass (shown as "BUNDLE EXCLUSIVE")
		Rarity       Common | Rare | Epic | Legendary | Ultra (purely visual tier)
		Color        main tint for the card art
		Data         type specific (shape, colours, emote animation...)
]]

local ShopCatalog = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Store tabs in display order. "Featured" and "Loadout" are virtual pages built by the UI.
ShopCatalog.Categories = { "FlightGear", "Outfits", "Emotes", "Plane", "Effects", "Bundles", "Premium" }

ShopCatalog.CategoryInfo = {
	Featured = { Label = "FEATURED", Icon = "🔥", Color = rgb(255, 110, 70) },
	FlightGear = { Label = "FLIGHT GEAR", Icon = "✈️", Color = rgb(70, 160, 255) },
	Outfits = { Label = "OUTFITS", Icon = "😎", Color = rgb(255, 120, 190) },
	Emotes = { Label = "EMOTES", Icon = "🎭", Color = rgb(255, 200, 60) },
	Plane = { Label = "PLANE", Icon = "🛩️", Color = rgb(90, 220, 255) },
	Effects = { Label = "EFFECTS", Icon = "✨", Color = rgb(190, 120, 255) },
	Bundles = { Label = "BUNDLES", Icon = "🎁", Color = rgb(90, 230, 140) },
	Premium = { Label = "PASSES & CREDITS", Icon = "💎", Color = rgb(255, 215, 90) },
	Loadout = { Label = "MY LOADOUT", Icon = "🧳", Color = rgb(160, 175, 200) },
}

-- Loadout slots. Character slots are rebuilt on the server for everyone to see; plane slots
-- are applied on each player's own screen (the aircraft is shared, so everyone flies their
-- own look). None of them change gameplay.
ShopCatalog.Slots = {
	"Outfit", "Hat", "Face", "Body", "Badge", "Luggage", "Title", "Emote",
	"Trail", "Aura", "VictoryEffect", "Theme",
	"PlaneSkin", "WingEffect", "PlaneTrail",
}

ShopCatalog.SlotInfo = {
	Outfit = { Label = "OUTFIT", Icon = "👕", Group = "Character" },
	Hat = { Label = "HAT", Icon = "🧢", Group = "Character" },
	Face = { Label = "FACE", Icon = "🕶️", Group = "Character" },
	Body = { Label = "BACK", Icon = "🎒", Group = "Character" },
	Badge = { Label = "BADGE", Icon = "🎖️", Group = "Character" },
	Luggage = { Label = "LUGGAGE", Icon = "🧳", Group = "Character" },
	Title = { Label = "TITLE", Icon = "🏷️", Group = "Character", Required = true },
	Emote = { Label = "FAVOURITE EMOTE", Icon = "🎭", Group = "Character" },
	Trail = { Label = "TRAIL", Icon = "💨", Group = "Effects" },
	Aura = { Label = "AURA", Icon = "✨", Group = "Effects" },
	VictoryEffect = { Label = "VICTORY EFFECT", Icon = "🎆", Group = "Effects" },
	Theme = { Label = "INTERFACE", Icon = "🎨", Group = "Effects", Required = true },
	PlaneSkin = { Label = "PLANE SKIN", Icon = "🛩️", Group = "Plane", Required = true },
	WingEffect = { Label = "WING EFFECT", Icon = "✈️", Group = "Plane" },
	PlaneTrail = { Label = "PLANE TRAIL", Icon = "☁️", Group = "Plane" },
}

ShopCatalog.RarityOrder = { "Common", "Rare", "Epic", "Legendary", "Ultra" }

ShopCatalog.Rarities = {
	Common = rgb(170, 180, 195),
	Rare = rgb(80, 160, 255),
	Epic = rgb(180, 100, 255),
	Legendary = rgb(255, 190, 60),
	Ultra = rgb(255, 90, 160),
}

-- Ultra cards get an animated rainbow edge; the rest use their rarity colour.
ShopCatalog.UltraGradient = {
	rgb(255, 90, 160),
	rgb(255, 200, 70),
	rgb(90, 230, 255),
	rgb(170, 110, 255),
}

-- Price tiers used to lay every category out from cheapest to most premium.
ShopCatalog.PriceTiers = {
	{ Id = "Starter", Label = "STARTER PICKS", Hint = "Great first buys", MaxCredits = 250, MaxRobux = 25 },
	{ Id = "Mid", Label = "MID-RANGE", Hint = "Stand out on the flight", MaxCredits = 900, MaxRobux = 79 },
	{ Id = "Premium", Label = "PREMIUM", Hint = "Show-stoppers", MaxCredits = math.huge, MaxRobux = math.huge },
}

local items = {}
local function add(item)
	table.insert(items, item)
end

---------------------------------------------------------------------------- FLIGHT GEAR

add({ Id = "BadgeJuniorWings", Name = "Junior Wings", Category = "FlightGear", Type = "Badge", Slot = "Badge", Price = 100, Rarity = "Common",
	Description = "Your very first pilot wings. Shiny!", Color = rgb(200, 205, 215),
	Data = { Shape = "Wings", Primary = rgb(200, 205, 215), Accent = rgb(70, 150, 255) } })
add({ Id = "LuggageCarryOn", Name = "Carry-On Roller", Category = "FlightGear", Type = "Luggage", Slot = "Luggage", Price = 120, Rarity = "Common",
	Description = "Fits in the overhead bin. Mostly.", Color = rgb(60, 120, 200),
	Data = { Shape = "Roller", Primary = rgb(60, 120, 200), Accent = rgb(230, 230, 235) } })
add({ Id = "PilotSunglasses", Name = "Pilot Sunglasses", Category = "FlightGear", Type = "Accessory", Slot = "Face", Price = 150, Rarity = "Common",
	Description = "Instant cool. Works at any altitude.", Color = rgb(40, 40, 45),
	Data = { Shape = "Shades", Primary = rgb(40, 40, 45), Accent = rgb(20, 25, 35) } })
add({ Id = "BoardingPassLanyard", Name = "Boarding Pass Lanyard", Category = "FlightGear", Type = "Badge", Slot = "Badge", Price = 180, Rarity = "Common",
	Description = "Seat 14A. Window seat, obviously.", Color = rgb(90, 200, 255),
	Data = { Shape = "Pass", Primary = rgb(255, 255, 255), Accent = rgb(90, 200, 255) } })
add({
	Id = "SleepMask", Name = "Sleep Mask", Category = "FlightGear", Type = "Accessory", Slot = "Face", Price = 200, Rarity = "Common",
	Description = "Ignore the alarms in comfort.", Color = rgb(150, 110, 200),
	Data = { Shape = "SleepMask", Primary = rgb(150, 110, 200), Accent = rgb(255, 255, 255) },
})
add({
	Id = "NeckPillow", Name = "Neck Pillow", Category = "FlightGear", Type = "Accessory", Slot = "Body", Price = 250, Rarity = "Common",
	Description = "Long-haul essential.", Color = rgb(90, 170, 220),
	Data = { Shape = "NeckPillow", Primary = rgb(90, 170, 220) },
})
add({ Id = "LuggageStickers", Name = "Sticker Suitcase", Category = "FlightGear", Type = "Luggage", Slot = "Luggage", Price = 280, Rarity = "Common",
	Description = "Covered in stickers from places you've (nearly) landed.", Color = rgb(255, 150, 60),
	Data = { Shape = "Roller", Primary = rgb(255, 150, 60), Accent = rgb(80, 220, 160), Stickers = true } })
add({
	Id = "PilotCap", Name = "Pilot Cap", Category = "FlightGear", Type = "Accessory", Slot = "Hat", Price = 300, Rarity = "Common",
	Description = "A crisp navy cap. Instantly looks like you know what you're doing.", Color = rgb(30, 45, 90),
	Data = { Shape = "Cap", Primary = rgb(30, 45, 90), Accent = rgb(20, 20, 25) },
})
add({
	Id = "AviatorGoggles", Name = "Aviator Goggles", Category = "FlightGear", Type = "Accessory", Slot = "Face", Price = 350, Rarity = "Common",
	Description = "Vintage flight goggles for the modern passenger.", Color = rgb(120, 80, 45),
	Data = { Shape = "Goggles", Primary = rgb(120, 80, 45), Accent = rgb(120, 200, 255) },
})
add({
	Id = "SafetyHelmet", Name = "Safety Helmet", Category = "FlightGear", Type = "Accessory", Slot = "Hat", Price = 400, Rarity = "Common",
	Description = "Ramp crew approved. Purely decorative up here.", Color = rgb(255, 200, 40),
	Data = { Shape = "Helmet", Primary = rgb(255, 200, 40), Accent = rgb(240, 240, 240) },
})
add({ Id = "BackpackEmergency", Name = "Emergency Backpack", Category = "FlightGear", Type = "Accessory", Slot = "Body", Price = 400, Rarity = "Common",
	Description = "Bright red and ready for anything. (Contains snacks.)", Color = rgb(220, 50, 50),
	Data = { Shape = "Backpack", Primary = rgb(220, 50, 50), Accent = rgb(255, 255, 255), Cross = true } })
add({
	Id = "Aviators", Name = "Aviator Shades", Category = "FlightGear", Type = "Accessory", Slot = "Face", Price = 450, Rarity = "Rare",
	Description = "Reflective lenses. Cool under pressure.", Color = rgb(200, 170, 80),
	Data = { Shape = "Shades", Primary = rgb(200, 170, 80), Accent = rgb(30, 30, 35) },
})
add({
	Id = "CrewHeadset", Name = "Crew Headset", Category = "FlightGear", Type = "Accessory", Slot = "Hat", Price = 500, Rarity = "Rare",
	Description = "Noise cancelling, apparently not alarm cancelling.", Color = rgb(45, 45, 50),
	Data = { Shape = "Headset", Primary = rgb(45, 45, 50), Accent = rgb(90, 200, 120) },
})
add({
	Id = "LifeVest", Name = "Life Vest", Category = "FlightGear", Type = "Accessory", Slot = "Body", Price = 600, Rarity = "Rare",
	Description = "Located under your seat. Now located on you.", Color = rgb(255, 170, 20),
	Data = { Shape = "Vest", Primary = rgb(255, 170, 20), Accent = rgb(230, 230, 230) },
})
add({ Id = "AviatorHeadset", Name = "Aviator Headset", Category = "FlightGear", Type = "Accessory", Slot = "Hat", Price = 650, Rarity = "Rare",
	Description = "Leather ear cups and a gold mic. Roger that!", Color = rgb(130, 85, 50),
	Data = { Shape = "Headset", Primary = rgb(130, 85, 50), Accent = rgb(255, 200, 70) } })
add({ Id = "BackpackJet", Name = "Jet Backpack", Category = "FlightGear", Type = "Accessory", Slot = "Body", Price = 700, Rarity = "Rare",
	Description = "Sleek fins, zero thrust. Pure style.", Color = rgb(200, 205, 220),
	Data = { Shape = "JetBackpack", Primary = rgb(200, 205, 220), Accent = rgb(70, 150, 255) } })
add({
	Id = "CaptainHat", Name = "Captain's Hat", Category = "FlightGear", Type = "Accessory", Slot = "Hat", Price = 750, Rarity = "Rare",
	Description = "Gold braid included. Authority not included.", Color = rgb(20, 25, 45),
	Data = { Shape = "Cap", Primary = rgb(20, 25, 45), Accent = rgb(230, 185, 60), Badge = true },
})
add({ Id = "BadgeGoldenPilot", Name = "Golden Pilot Badge", Category = "FlightGear", Type = "Badge", Slot = "Badge", Price = 800, Rarity = "Epic",
	Description = "Polished gold wings for top flyers.", Color = rgb(255, 200, 60),
	Data = { Shape = "Wings", Primary = rgb(255, 200, 60), Accent = rgb(255, 240, 170), Shiny = true } })
add({ Id = "LuggagePremium", Name = "Premium Suitcase", Category = "FlightGear", Type = "Luggage", Slot = "Luggage", Price = 850, Rarity = "Epic",
	Description = "Brushed metal, silent wheels, very important contents.", Color = rgb(170, 175, 190),
	Data = { Shape = "Roller", Primary = rgb(170, 175, 190), Accent = rgb(40, 45, 60), Metal = true } })
add({
	Id = "PropellerBeanie", Name = "Propeller Beanie", Category = "FlightGear", Type = "Accessory", Slot = "Hat", Price = 900, Rarity = "Epic",
	Description = "Generates zero lift. Maximum style.", Color = rgb(220, 60, 60),
	Data = { Shape = "Beanie", Primary = rgb(220, 60, 60), Accent = rgb(60, 120, 230) },
})
add({
	Id = "ParachutePack", Name = "Parachute Pack", Category = "FlightGear", Type = "Accessory", Slot = "Body", Price = 1100, Rarity = "Epic",
	Description = "Sadly decorative. Looks very prepared.", Color = rgb(70, 90, 60),
	Data = { Shape = "Backpack", Primary = rgb(70, 90, 60), Accent = rgb(200, 60, 40) },
})
add({ Id = "BadgeNeonPilot", Name = "Neon Pilot Badge", Category = "FlightGear", Type = "Badge", Slot = "Badge", Product = "NeonPilotBadge", Rarity = "Rare",
	Description = "Glowing cyan wings that light up the cabin.", Color = rgb(60, 230, 255),
	Data = { Shape = "Wings", Primary = rgb(60, 230, 255), Accent = rgb(255, 90, 200), Neon = true } })
add({
	Id = "JetpackReplica", Name = "Jetpack Replica", Category = "FlightGear", Type = "Accessory", Slot = "Body", Product = "JetpackReplica", Rarity = "Legendary",
	Description = "Glowing exhausts, zero thrust. Robux exclusive cosmetic.", Color = rgb(200, 200, 215),
	Data = { Shape = "Jetpack", Primary = rgb(200, 200, 215), Accent = rgb(255, 120, 30) },
})
add({ Id = "StormVisor", Name = "Storm Rider Visor", Category = "FlightGear", Type = "Accessory", Slot = "Hat", Product = "StormRiderPack", Exclusive = true, Rarity = "Epic",
	Description = "A lightning-striped visor for flying through the worst weather.", Color = rgb(255, 230, 60),
	Data = { Shape = "Visor", Primary = rgb(40, 45, 60), Accent = rgb(255, 230, 60) } })
add({ Id = "BadgeGoldBoardingPass", Name = "Gold Boarding Pass", Category = "FlightGear", Type = "Badge", Slot = "Badge", Product = "FirstClassBundle", Exclusive = true, Rarity = "Legendary",
	Description = "A glittering golden pass. Seat 1A, naturally.", Color = rgb(255, 210, 90),
	Data = { Shape = "Pass", Primary = rgb(255, 210, 90), Accent = rgb(255, 245, 200), Shiny = true, Sparkle = true } })
add({ Id = "LuggageFirstClass", Name = "First-Class Trunk", Category = "FlightGear", Type = "Luggage", Slot = "Luggage", Product = "FirstClassBundle", Exclusive = true, Rarity = "Legendary",
	Description = "Cream leather with gold corners. Travels better than you do.", Color = rgb(240, 225, 190),
	Data = { Shape = "Trunk", Primary = rgb(240, 225, 190), Accent = rgb(230, 185, 70) } })

---------------------------------------------------------------------------- OUTFITS

-- Outfits are procedural overlays (jacket, sleeves, trousers + trims), so they work on any
-- avatar and need no uploaded clothing. Styles: see CosmeticBuilder.Outfit.
add({ Id = "OutfitCasualFlyer", Name = "Casual Flyer", Category = "Outfits", Type = "Outfit", Slot = "Outfit", Price = 150, Rarity = "Common",
	Description = "Comfy hoodie for a comfy flight.", Color = rgb(90, 110, 140),
	Data = { Style = "Casual", Primary = rgb(90, 110, 140), Secondary = rgb(50, 55, 70), Accent = rgb(240, 240, 245) } })
add({ Id = "OutfitAdventurer", Name = "Adventurer", Category = "Outfits", Type = "Outfit", Slot = "Outfit", Price = 300, Rarity = "Common",
	Description = "Ready for the jungle, the desert or seat 32C.", Color = rgb(70, 120, 70),
	Data = { Style = "Explorer", Primary = rgb(70, 120, 70), Secondary = rgb(110, 85, 55), Accent = rgb(150, 100, 50) } })
add({ Id = "OutfitEmergencyCrew", Name = "Emergency Crew", Category = "Outfits", Type = "Outfit", Slot = "Outfit", Price = 350, Rarity = "Common",
	Description = "High-vis orange with reflective stripes.", Color = rgb(255, 120, 30),
	Data = { Style = "HiVis", Primary = rgb(255, 120, 30), Secondary = rgb(40, 45, 60), Accent = rgb(230, 235, 240) } })
add({ Id = "OutfitAirportSecurity", Name = "Airport Security", Category = "Outfits", Type = "Outfit", Slot = "Outfit", Price = 400, Rarity = "Common",
	Description = "Dark blue uniform with a shiny badge. Nothing gets past you.", Color = rgb(35, 50, 90),
	Data = { Style = "Security", Primary = rgb(35, 50, 90), Secondary = rgb(30, 35, 50), Accent = rgb(255, 205, 60) } })
add({ Id = "OutfitSkyExplorer", Name = "Sky Explorer", Category = "Outfits", Type = "Outfit", Slot = "Outfit", Price = 500, Rarity = "Rare",
	Description = "Khaki flight jacket with a cloud-white scarf.", Color = rgb(190, 160, 110),
	Data = { Style = "Explorer", Primary = rgb(190, 160, 110), Secondary = rgb(90, 75, 55), Accent = rgb(250, 250, 255), Scarf = true } })
add({ Id = "OutfitPilot", Name = "Pilot", Category = "Outfits", Type = "Outfit", Slot = "Outfit", Price = 600, Rarity = "Rare",
	Description = "Navy jacket, gold sleeve stripes, total confidence.", Color = rgb(25, 35, 75),
	Data = { Style = "Pilot", Primary = rgb(25, 35, 75), Secondary = rgb(25, 30, 50), Accent = rgb(240, 195, 70) } })
add({ Id = "OutfitSkyTraveler", Name = "Sky Traveler", Category = "Outfits", Type = "Outfit", Slot = "Outfit", Price = 650, Rarity = "Rare",
	Description = "Sky-blue jacket with puffy cloud trims.", Color = rgb(120, 190, 255),
	Data = { Style = "Sky", Primary = rgb(120, 190, 255), Secondary = rgb(60, 90, 150), Accent = rgb(255, 255, 255) } })
add({ Id = "OutfitRetroTraveler", Name = "Retro Traveler", Category = "Outfits", Type = "Outfit", Slot = "Outfit", Price = 800, Rarity = "Rare",
	Description = "Mustard, brown and orange stripes - straight from the golden age of flying.", Color = rgb(215, 160, 50),
	Data = { Style = "Retro", Primary = rgb(215, 160, 50), Secondary = rgb(110, 70, 40), Accent = rgb(240, 110, 40) } })
add({ Id = "OutfitVIPTraveler", Name = "VIP Traveler", Category = "Outfits", Type = "Outfit", Slot = "Outfit", Price = 1200, Rarity = "Epic",
	Description = "A sharp black suit with gold trim. The lounge is this way.", Color = rgb(30, 30, 35),
	Data = { Style = "Suit", Primary = rgb(30, 30, 35), Secondary = rgb(25, 25, 30), Accent = rgb(240, 195, 70) } })
add({ Id = "OutfitNeonTraveler", Name = "Neon Traveler", Category = "Outfits", Type = "Outfit", Slot = "Outfit", Price = 1400, Rarity = "Epic",
	Description = "Midnight black with glowing cyan and pink edges.", Color = rgb(60, 230, 255),
	Data = { Style = "Neon", Primary = rgb(20, 20, 30), Secondary = rgb(15, 15, 22), Accent = rgb(60, 230, 255), Accent2 = rgb(255, 80, 200) } })
add({ Id = "OutfitFirstClass", Name = "First-Class Traveler", Category = "Outfits", Type = "Outfit", Slot = "Outfit", Product = "FirstClassBundle", Exclusive = true, Rarity = "Legendary",
	Description = "Cream blazer, gold buttons and a silk pocket square.", Color = rgb(240, 230, 205),
	Data = { Style = "Suit", Primary = rgb(240, 230, 205), Secondary = rgb(70, 55, 45), Accent = rgb(230, 185, 70) } })
add({ Id = "OutfitGoldenTraveler", Name = "Golden Traveler", Category = "Outfits", Type = "Outfit", Slot = "Outfit", Product = "GoldenTraveler", Rarity = "Ultra",
	Description = "Head-to-toe shimmering gold. Everyone will look.", Color = rgb(255, 205, 70),
	Data = { Style = "Gold", Primary = rgb(255, 205, 70), Secondary = rgb(200, 150, 40), Accent = rgb(255, 255, 255), Material = Enum.Material.Foil } })

-- Titles live with the outfits: they're part of your look.
add({
	Id = "TitlePassenger", Name = "Passenger", Category = "Outfits", Type = "Title", Slot = "Title", Default = true, Rarity = "Common",
	Description = "Everyone starts somewhere.", Color = rgb(190, 190, 200),
})
add({
	Id = "TitleFrequentFlyer", Name = "Frequent Flyer", Category = "Outfits", Type = "Title", Slot = "Title", Price = 250, Rarity = "Common",
	Description = "You've seen things at 35,000 feet.", Color = rgb(120, 200, 255),
})
add({
	Id = "TitleBraceBrace", Name = "Brace! Brace!", Category = "Outfits", Type = "Title", Slot = "Title", Price = 400, Rarity = "Rare",
	Description = "Heads down, stay down.", Color = rgb(255, 120, 80),
})
add({
	Id = "TitleCrashTestDummy", Name = "Crash Test Dummy", Category = "Outfits", Type = "Title", Slot = "Title", Price = 600, Rarity = "Rare",
	Description = "Survival not guaranteed. Style guaranteed.", Color = rgb(255, 220, 60),
})
add({
	Id = "TitleSurvivor", Name = "Survivor", Category = "Outfits", Type = "Title", Slot = "Title", Unlock = "Survivor", Rarity = "Rare",
	Description = "Unlocked by surviving 10 flights.", Color = rgb(120, 230, 140),
})
add({
	Id = "TitleLifesaver", Name = "Lifesaver", Category = "Outfits", Type = "Title", Slot = "Title", Unlock = "Guardian", Rarity = "Epic",
	Description = "Unlocked by reviving 10 players.", Color = rgb(255, 90, 120),
})
add({
	Id = "TitleCaptain", Name = "Captain", Category = "Outfits", Type = "Title", Slot = "Title", Unlock = "AcePilot", Rarity = "Epic",
	Description = "Unlocked by flying 5 perfect manual approaches.", Color = rgb(230, 190, 70),
})
add({
	Id = "TitleLegend", Name = "Legend of the Skies", Category = "Outfits", Type = "Title", Slot = "Title", Unlock = "DisasterMaster", Rarity = "Legendary",
	Description = "Unlocked by surviving every type of disaster.", Color = rgb(255, 170, 40),
})
add({
	Id = "TitleFirstClass", Name = "First Class", Category = "Outfits", Type = "Title", Slot = "Title", Product = "FirstClassBundle", Exclusive = true, Rarity = "Legendary",
	Description = "Included in the First Class Pack.", Color = rgb(255, 215, 120),
})
add({
	Id = "TitleVIP", Name = "VIP", Category = "Outfits", Type = "Title", Slot = "Title", Pass = "VIP", Exclusive = true, Rarity = "Legendary",
	Description = "Included with the VIP game pass.", Color = rgb(255, 200, 50),
})

---------------------------------------------------------------------------- EMOTES

-- Emotes use Roblox's built-in emote animations (Speed changes the feel) plus an emoji bubble
-- above your head that everyone sees. Swap AnimationId for your own uploads at any time.
local ANIM = {
	Wave = "rbxassetid://507770239",
	Point = "rbxassetid://507770453",
	Cheer = "rbxassetid://507770677",
	Laugh = "rbxassetid://507770818",
	Dance1 = "rbxassetid://507771019",
	Dance2 = "rbxassetid://507776043",
	Dance3 = "rbxassetid://507777268",
}
ShopCatalog.Animations = ANIM

add({
	Id = "EmoteWave", Name = "Wave", Category = "Emotes", Type = "Emote", Slot = "Emote", Default = true, Rarity = "Common",
	Description = "Hello from row 14.", Color = rgb(150, 200, 255),
	Data = { AnimationId = ANIM.Wave, Looped = false, Bubble = "👋" },
})
add({
	Id = "EmotePoint", Name = "Point", Category = "Emotes", Type = "Emote", Slot = "Emote", Default = true, Rarity = "Common",
	Description = "The exit is that way.", Color = rgb(150, 200, 255),
	Data = { AnimationId = ANIM.Point, Looped = false, Bubble = "👉" },
})
add({ Id = "EmoteNervous", Name = "Nervous", Category = "Emotes", Type = "Emote", Slot = "Emote", Price = 80, Rarity = "Common",
	Description = "Was that bump normal? That bump was not normal.", Color = rgb(160, 220, 255),
	Data = { AnimationId = ANIM.Laugh, Speed = 0.5, Looped = false, Bubble = "😬" } })
add({ Id = "EmoteFacepalm", Name = "Facepalm", Category = "Emotes", Type = "Emote", Slot = "Emote", Price = 90, Rarity = "Common",
	Description = "When someone opens the wrong door.", Color = rgb(255, 190, 150),
	Data = { AnimationId = ANIM.Point, Speed = 0.35, Looped = false, Bubble = "🤦" } })
add({ Id = "EmoteSleep", Name = "Sleep", Category = "Emotes", Type = "Emote", Slot = "Emote", Price = 100, Rarity = "Common",
	Description = "Zzz... wake me when we land.", Color = rgb(150, 130, 230),
	Data = { AnimationId = ANIM.Cheer, Speed = 0.12, Looped = false, Bubble = "💤", BubbleTime = 4 } })
add({ Id = "EmotePanic", Name = "Panic", Category = "Emotes", Type = "Emote", Slot = "Emote", Price = 120, Rarity = "Common",
	Description = "Arms everywhere. Totally under control.", Color = rgb(255, 110, 90),
	Data = { AnimationId = ANIM.Dance2, Speed = 2.2, Looped = false, Bubble = "😱" } })
add({
	Id = "EmoteCheer", Name = "Cheer", Category = "Emotes", Type = "Emote", Slot = "Emote", Price = 150, Rarity = "Common",
	Description = "We landed! Probably.", Color = rgb(120, 230, 140),
	Data = { AnimationId = ANIM.Cheer, Looped = false, Bubble = "🙌" },
})
add({
	Id = "EmoteLaugh", Name = "Laugh", Category = "Emotes", Type = "Emote", Slot = "Emote", Price = 200, Rarity = "Common",
	Description = "Nervous laughter at 30,000 feet.", Color = rgb(255, 220, 90),
	Data = { AnimationId = ANIM.Laugh, Looped = false, Bubble = "😂" },
})
add({ Id = "EmoteTravelWave", Name = "Bon Voyage", Category = "Emotes", Type = "Emote", Slot = "Emote", Price = 200, Rarity = "Common",
	Description = "A big happy wave for the folks on the ground.", Color = rgb(120, 200, 255),
	Data = { AnimationId = ANIM.Wave, Speed = 1.3, Looped = false, Bubble = "✈️" } })
add({ Id = "EmoteCelebrate", Name = "Celebrate", Category = "Emotes", Type = "Emote", Slot = "Emote", Price = 250, Rarity = "Common",
	Description = "Party time in the aisle!", Color = rgb(255, 130, 200),
	Data = { AnimationId = ANIM.Cheer, Speed = 1.6, Looped = false, Bubble = "🎉" } })
add({ Id = "EmotePilotSalute", Name = "Pilot Salute", Category = "Emotes", Type = "Emote", Slot = "Emote", Price = 300, Rarity = "Rare",
	Description = "A crisp salute from the flight deck.", Color = rgb(70, 120, 220),
	Data = { AnimationId = ANIM.Point, Speed = 0.7, Looped = false, Bubble = "🎖️" } })
add({
	Id = "EmoteDance", Name = "Aisle Dance", Category = "Emotes", Type = "Emote", Slot = "Emote", Price = 450, Pass = "EmotePass", Rarity = "Rare",
	Description = "Seatbelt sign is off. Probably.", Color = rgb(200, 120, 255),
	Data = { AnimationId = ANIM.Dance1, Looped = true, Bubble = "💃" },
})
add({ Id = "EmoteVictory", Name = "Victory Dance", Category = "Emotes", Type = "Emote", Slot = "Emote", Price = 500, Rarity = "Rare",
	Description = "You survived. Time to show off.", Color = rgb(255, 200, 60),
	Data = { AnimationId = ANIM.Cheer, Speed = 1.25, Looped = false, Bubble = "🏆" } })
add({
	Id = "EmoteDance2", Name = "Turbulence Groove", Category = "Emotes", Type = "Emote", Slot = "Emote", Price = 650, Pass = "EmotePass", Rarity = "Epic",
	Description = "Move with the bumps.", Color = rgb(255, 100, 180),
	Data = { AnimationId = ANIM.Dance2, Looped = true, Bubble = "🕺" },
})
add({ Id = "EmoteWeSurvived", Name = "We Survived!", Category = "Emotes", Type = "Emote", Slot = "Emote", Price = 750, Rarity = "Epic",
	Description = "The loudest celebration on the runway.", Color = rgb(90, 230, 140),
	Data = { AnimationId = ANIM.Cheer, Speed = 1.1, Looped = false, Bubble = "🙌", BubbleText = "WE SURVIVED!" } })
add({
	Id = "EmoteDance3", Name = "Victory Shuffle", Category = "Emotes", Type = "Emote", Slot = "Emote", Pass = "EmotePass", Product = "PartyPack", Exclusive = true, Rarity = "Epic",
	Description = "Emote Pass / Party Pack exclusive.", Color = rgb(90, 220, 255),
	Data = { AnimationId = ANIM.Dance3, Looped = true, Bubble = "💫" },
})
add({ Id = "EmoteStormDance", Name = "Lightning Strut", Category = "Emotes", Type = "Emote", Slot = "Emote", Product = "StormRiderPack", Exclusive = true, Rarity = "Epic",
	Description = "Strut through the storm like you own it.", Color = rgb(255, 230, 60),
	Data = { AnimationId = ANIM.Dance2, Speed = 1.4, Looped = true, Bubble = "⚡" } })
add({ Id = "EmoteFirstClassToast", Name = "First-Class Toast", Category = "Emotes", Type = "Emote", Slot = "Emote", Product = "FirstClassBundle", Exclusive = true, Rarity = "Legendary",
	Description = "Raise a glass of sparkling juice to a safe landing.", Color = rgb(255, 215, 120),
	Data = { AnimationId = ANIM.Wave, Speed = 0.8, Looped = false, Bubble = "🥂" } })

---------------------------------------------------------------------------- PLANE COSMETICS

-- Visual only: recolours the aircraft exterior on YOUR screen. Flight, disasters, health and
-- landing are untouched (the parts are non-colliding decoration).
add({ Id = "PlaneClassic", Name = "Classic Airliner", Category = "Plane", Type = "PlaneSkin", Slot = "PlaneSkin", Default = true, Rarity = "Common",
	Description = "Clean white with a blue stripe.", Color = rgb(235, 238, 242),
	Data = { Hull = rgb(235, 238, 242), Engine = rgb(200, 204, 210), Stripe = rgb(70, 150, 255) } })
add({ Id = "PlaneSkyBlue", Name = "Sky Blue", Category = "Plane", Type = "PlaneSkin", Slot = "PlaneSkin", Price = 150, Rarity = "Common",
	Description = "A happy blue paint job.", Color = rgb(110, 180, 255),
	Data = { Hull = rgb(110, 180, 255), Engine = rgb(235, 240, 250), Stripe = rgb(255, 255, 255) } })
add({ Id = "PlaneSunset", Name = "Sunset Orange", Category = "Plane", Type = "PlaneSkin", Slot = "PlaneSkin", Price = 200, Rarity = "Common",
	Description = "Warm orange with a sunny yellow stripe.", Color = rgb(255, 140, 60),
	Data = { Hull = rgb(255, 140, 60), Engine = rgb(255, 230, 200), Stripe = rgb(255, 215, 60) } })
add({ Id = "PlaneMint", Name = "Mint Green", Category = "Plane", Type = "PlaneSkin", Slot = "PlaneSkin", Price = 200, Rarity = "Common",
	Description = "Fresh, cool and minty.", Color = rgb(120, 230, 180),
	Data = { Hull = rgb(120, 230, 180), Engine = rgb(240, 250, 245), Stripe = rgb(40, 140, 110) } })
add({ Id = "PlaneCloud", Name = "Cloud Plane", Category = "Plane", Type = "PlaneSkin", Slot = "PlaneSkin", Price = 650, Rarity = "Rare",
	Description = "Soft white and baby blue, like flying inside a cloud.", Color = rgb(225, 240, 255),
	Data = { Hull = rgb(245, 250, 255), Engine = rgb(200, 225, 255), Stripe = rgb(150, 200, 255), Material = Enum.Material.SmoothPlastic } })
add({ Id = "PlaneMidnight", Name = "Midnight Plane", Category = "Plane", Type = "PlaneSkin", Slot = "PlaneSkin", Price = 700, Rarity = "Rare",
	Description = "Deep navy with silver trim. Stealthy.", Color = rgb(25, 30, 60),
	Data = { Hull = rgb(25, 30, 60), Engine = rgb(170, 175, 190), Stripe = rgb(190, 200, 220) } })
add({ Id = "PlaneRetro", Name = "Retro Plane", Category = "Plane", Type = "PlaneSkin", Slot = "PlaneSkin", Price = 800, Rarity = "Rare",
	Description = "Cream paint with classic orange and brown stripes.", Color = rgb(240, 225, 190),
	Data = { Hull = rgb(240, 225, 190), Engine = rgb(110, 70, 40), Stripe = rgb(240, 110, 40), Stripe2 = rgb(110, 70, 40) } })
add({ Id = "PlaneCandy", Name = "Candy Plane", Category = "Plane", Type = "PlaneSkin", Slot = "PlaneSkin", Price = 900, Rarity = "Epic",
	Description = "Pink and white swirls. Sweet!", Color = rgb(255, 150, 200),
	Data = { Hull = rgb(255, 170, 210), Engine = rgb(255, 255, 255), Stripe = rgb(255, 255, 255), Stripe2 = rgb(170, 120, 255) } })
add({ Id = "PlaneNeon", Name = "Neon Plane", Category = "Plane", Type = "PlaneSkin", Slot = "PlaneSkin", Price = 1500, Rarity = "Legendary",
	Description = "Jet black with glowing cyan lines. Lights up the night sky.", Color = rgb(60, 230, 255),
	Data = { Hull = rgb(20, 22, 30), Engine = rgb(35, 38, 50), Stripe = rgb(60, 230, 255), Stripe2 = rgb(255, 80, 200), Neon = true } })
add({ Id = "PlaneCyber", Name = "Cyber Plane", Category = "Plane", Type = "PlaneSkin", Slot = "PlaneSkin", Product = "CyberPlane", Rarity = "Epic",
	Description = "Carbon black with electric magenta circuitry.", Color = rgb(255, 60, 200),
	Data = { Hull = rgb(30, 30, 38), Engine = rgb(60, 60, 75), Stripe = rgb(255, 60, 200), Stripe2 = rgb(90, 255, 160), Neon = true } })
add({ Id = "PlaneLuxury", Name = "Luxury Plane", Category = "Plane", Type = "PlaneSkin", Slot = "PlaneSkin", Product = "LuxuryPlane", Rarity = "Ultra",
	Description = "Pearl white with real-looking gold trim. Very fancy.", Color = rgb(255, 215, 110),
	Data = { Hull = rgb(250, 248, 240), Engine = rgb(255, 205, 80), Stripe = rgb(255, 200, 70), Stripe2 = rgb(255, 235, 160), Gold = true } })
add({ Id = "PlaneStorm", Name = "Storm Plane", Category = "Plane", Type = "PlaneSkin", Slot = "PlaneSkin", Product = "StormRiderPack", Exclusive = true, Rarity = "Epic",
	Description = "Thundercloud grey with a bolt down the side.", Color = rgb(90, 95, 115),
	Data = { Hull = rgb(90, 95, 115), Engine = rgb(50, 52, 65), Stripe = rgb(255, 230, 60), Neon = true } })

add({ Id = "WingColorTips", Name = "Color Tips", Category = "Plane", Type = "WingEffect", Slot = "WingEffect", Price = 120, Rarity = "Common",
	Description = "Bright purple wingtip lights.", Color = rgb(190, 110, 255),
	Data = { Tip = rgb(190, 110, 255) } })
add({ Id = "WingNeon", Name = "Neon Wings", Category = "Plane", Type = "WingEffect", Slot = "WingEffect", Price = 600, Rarity = "Rare",
	Description = "Glowing cyan strips along both wings.", Color = rgb(60, 230, 255),
	Data = { Strip = rgb(60, 230, 255), Tip = rgb(60, 230, 255) } })
add({ Id = "WingGolden", Name = "Golden Wings", Category = "Plane", Type = "WingEffect", Slot = "WingEffect", Price = 1300, Rarity = "Legendary",
	Description = "Gold-trimmed wings with a gentle sparkle.", Color = rgb(255, 200, 60),
	Data = { Strip = rgb(255, 200, 60), Tip = rgb(255, 230, 140), Sparkle = rgb(255, 220, 120) } })
add({ Id = "WingLightning", Name = "Storm Wings", Category = "Plane", Type = "WingEffect", Slot = "WingEffect", Product = "StormRiderPack", Exclusive = true, Rarity = "Epic",
	Description = "Electric yellow wing edges that crackle.", Color = rgb(255, 230, 60),
	Data = { Strip = rgb(255, 230, 60), Tip = rgb(255, 255, 200), Sparkle = rgb(255, 240, 120) } })

add({ Id = "PlaneTrailContrail", Name = "Double Contrail", Category = "Plane", Type = "PlaneTrail", Slot = "PlaneTrail", Price = 250, Rarity = "Common",
	Description = "Two long white vapour trails behind the engines.", Color = rgb(240, 245, 255),
	Data = { Colors = { rgb(255, 255, 255), rgb(210, 225, 255) }, Texture = "Smoke" } })
add({ Id = "PlaneTrailCandy", Name = "Candy Puffs", Category = "Plane", Type = "PlaneTrail", Slot = "PlaneTrail", Price = 500, Rarity = "Rare",
	Description = "Pink and purple puffs behind the engines.", Color = rgb(255, 150, 210),
	Data = { Colors = { rgb(255, 150, 210), rgb(180, 130, 255) }, Texture = "Smoke" } })
add({ Id = "PlaneTrailSparks", Name = "Spark Stream", Category = "Plane", Type = "PlaneTrail", Slot = "PlaneTrail", Price = 700, Rarity = "Rare",
	Description = "A glittering stream of golden sparks.", Color = rgb(255, 200, 80),
	Data = { Colors = { rgb(255, 230, 120), rgb(255, 150, 40) }, Texture = "Sparkle" } })
add({ Id = "PlaneTrailRainbow", Name = "Rainbow Exhaust", Category = "Plane", Type = "PlaneTrail", Slot = "PlaneTrail", Price = 950, Rarity = "Epic",
	Description = "Every colour, all the way to the horizon.", Color = rgb(255, 120, 200),
	Data = { Colors = { rgb(255, 70, 70), rgb(255, 200, 40), rgb(60, 220, 100), rgb(60, 140, 255), rgb(200, 80, 255) }, Texture = "Smoke" } })

---------------------------------------------------------------------------- EFFECTS

add({ Id = "TrailSkyStreak", Name = "Sky Streak", Category = "Effects", Type = "Trail", Slot = "Trail", Price = 100, Rarity = "Common",
	Description = "A simple bright blue streak.", Color = rgb(90, 170, 255),
	Data = { Colors = { rgb(120, 200, 255), rgb(60, 120, 255) }, Lifetime = 0.5 } })
add({ Id = "TrailSparkle", Name = "Sparkle Trail", Category = "Effects", Type = "Trail", Slot = "Trail", Price = 220, Rarity = "Common",
	Description = "Leave a little glitter wherever you go.", Color = rgb(255, 240, 160),
	Data = { Colors = { rgb(255, 250, 200), rgb(255, 200, 255) }, Lifetime = 0.6, LightEmission = 0.8, Texture = "Sparkle" } })
add({
	Id = "TrailContrail", Name = "Contrail", Category = "Effects", Type = "Trail", Slot = "Trail", Price = 350, Rarity = "Common",
	Description = "A soft white vapor trail.", Color = rgb(240, 245, 255),
	Data = { Colors = { rgb(255, 255, 255), rgb(200, 220, 255) }, Lifetime = 0.6 },
})
add({ Id = "TrailCloud", Name = "Cloud Trail", Category = "Effects", Type = "Trail", Slot = "Trail", Price = 500, Rarity = "Rare",
	Description = "Fluffy little clouds follow you around.", Color = rgb(235, 245, 255),
	Data = { Colors = { rgb(255, 255, 255), rgb(190, 220, 255) }, Lifetime = 0.9, Texture = "Smoke", Width = 1.6 } })
add({
	Id = "TrailSunset", Name = "Sunset Glide", Category = "Effects", Type = "Trail", Slot = "Trail", Price = 700, Rarity = "Rare",
	Description = "Golden hour, every hour.", Color = rgb(255, 140, 60),
	Data = { Colors = { rgb(255, 200, 80), rgb(255, 80, 120) }, Lifetime = 0.7 },
})
add({
	Id = "TrailEmergency", Name = "Emergency Lights", Category = "Effects", Type = "Trail", Slot = "Trail", Price = 950, Rarity = "Epic",
	Description = "Follow the lights to the exit.", Color = rgb(255, 60, 60),
	Data = { Colors = { rgb(255, 40, 40), rgb(255, 200, 40) }, Lifetime = 0.8, LightEmission = 1 },
})
add({
	Id = "TrailRainbow", Name = "Rainbow Jetstream", Category = "Effects", Type = "Trail", Slot = "Trail", Product = "FirstClassBundle", Exclusive = true, Rarity = "Legendary",
	Description = "Included in the First Class Pack.", Color = rgb(255, 120, 200),
	Data = {
		Colors = { rgb(255, 60, 60), rgb(255, 200, 40), rgb(60, 220, 100), rgb(60, 140, 255), rgb(200, 80, 255) },
		Lifetime = 0.9,
		LightEmission = 0.6,
	},
})
add({
	Id = "TrailGolden", Name = "Golden Wake", Category = "Effects", Type = "Trail", Slot = "Trail", Pass = "VIP", Exclusive = true, Rarity = "Legendary",
	Description = "Included with the VIP game pass.", Color = rgb(255, 200, 60),
	Data = { Colors = { rgb(255, 230, 120), rgb(255, 170, 30) }, Lifetime = 0.8, LightEmission = 0.8 },
})

-- Auras: a few gentle particles around your character (low particle counts).
add({ Id = "AuraSmoke", Name = "Smoke Puff", Category = "Effects", Type = "Aura", Slot = "Aura", Price = 150, Rarity = "Common",
	Description = "A mysterious little cloud of smoke.", Color = rgb(150, 155, 165),
	Data = { Style = "Smoke", Colors = { rgb(200, 205, 215), rgb(120, 125, 135) } } })
add({ Id = "AuraConfetti", Name = "Confetti", Category = "Effects", Type = "Aura", Slot = "Aura", Price = 300, Rarity = "Common",
	Description = "Every step is a party.", Color = rgb(255, 120, 200),
	Data = { Style = "Confetti", Colors = { rgb(255, 90, 120), rgb(255, 210, 60), rgb(90, 200, 255), rgb(120, 230, 140) } } })
add({ Id = "AuraStars", Name = "Star Particles", Category = "Effects", Type = "Aura", Slot = "Aura", Price = 450, Rarity = "Rare",
	Description = "Tiny stars twinkle around you.", Color = rgb(255, 240, 150),
	Data = { Style = "Stars", Colors = { rgb(255, 255, 220), rgb(255, 220, 120) } } })
add({ Id = "AuraNeon", Name = "Neon Particles", Category = "Effects", Type = "Aura", Slot = "Aura", Price = 800, Rarity = "Rare",
	Description = "Glowing pink and cyan sparks.", Color = rgb(255, 80, 220),
	Data = { Style = "Neon", Colors = { rgb(60, 230, 255), rgb(255, 80, 220) } } })
add({ Id = "AuraGolden", Name = "Golden Particles", Category = "Effects", Type = "Aura", Slot = "Aura", Price = 1200, Rarity = "Epic",
	Description = "A soft shimmer of gold dust.", Color = rgb(255, 200, 60),
	Data = { Style = "Golden", Colors = { rgb(255, 235, 150), rgb(255, 180, 40) } } })
add({ Id = "AuraLightning", Name = "Lightning Aura", Category = "Effects", Type = "Aura", Slot = "Aura", Price = 1400, Rarity = "Legendary",
	Description = "Crackling electric sparks. Storm-proof style.", Color = rgb(255, 235, 80),
	Data = { Style = "Lightning", Colors = { rgb(255, 255, 220), rgb(120, 200, 255) } } })

add({
	Id = "VictoryConfetti", Name = "Confetti Landing", Category = "Effects", Type = "VictoryEffect", Slot = "VictoryEffect", Price = 400, Rarity = "Common",
	Description = "Celebrate every survival with confetti.", Color = rgb(255, 120, 200),
	Data = { Style = "Confetti" },
})
add({
	Id = "VictoryPaperPlanes", Name = "Paper Planes", Category = "Effects", Type = "VictoryEffect", Slot = "VictoryEffect", Price = 800, Rarity = "Rare",
	Description = "A swirl of paper planes when you survive.", Color = rgb(240, 240, 240),
	Data = { Style = "PaperPlanes" },
})
add({
	Id = "VictoryFireworks", Name = "Fireworks", Category = "Effects", Type = "VictoryEffect", Slot = "VictoryEffect", Price = 1200, Rarity = "Epic",
	Description = "Light up the results screen.", Color = rgb(255, 180, 60),
	Data = { Style = "Fireworks" },
})
add({
	Id = "VictoryGoldenWings", Name = "Golden Wings Finale", Category = "Effects", Type = "VictoryEffect", Slot = "VictoryEffect", Product = "FirstClassBundle", Exclusive = true, Rarity = "Legendary",
	Description = "Golden feathers rise when you survive. Included in the First Class Pack.", Color = rgb(255, 210, 90),
	Data = { Style = "GoldenWings" },
})

add({
	Id = "ThemeClassic", Name = "Classic Blue", Category = "Effects", Type = "Theme", Slot = "Theme", Default = true, Rarity = "Common",
	Description = "The default cockpit-blue interface.", Color = rgb(70, 150, 255),
	Data = { Accent = rgb(70, 150, 255) },
})
add({
	Id = "ThemeSunset", Name = "Sunset Interface", Category = "Effects", Type = "Theme", Slot = "Theme", Price = 300, Rarity = "Common",
	Description = "Warm orange HUD accents.", Color = rgb(255, 140, 60),
	Data = { Accent = rgb(255, 140, 60) },
})
add({
	Id = "ThemeEmerald", Name = "Emerald Interface", Category = "Effects", Type = "Theme", Slot = "Theme", Price = 300, Rarity = "Common",
	Description = "Calm green HUD accents.", Color = rgb(60, 210, 140),
	Data = { Accent = rgb(60, 210, 140) },
})
add({
	Id = "ThemeMidnight", Name = "Midnight Interface", Category = "Effects", Type = "Theme", Slot = "Theme", Price = 500, Rarity = "Rare",
	Description = "Deep purple HUD accents.", Color = rgb(160, 110, 255),
	Data = { Accent = rgb(160, 110, 255) },
})
add({
	Id = "ThemeGold", Name = "Gold Interface", Category = "Effects", Type = "Theme", Slot = "Theme", Pass = "VIP", Exclusive = true, Rarity = "Legendary",
	Description = "Included with the VIP game pass.", Color = rgb(255, 200, 60),
	Data = { Accent = rgb(255, 200, 60) },
})

---------------------------------------------------------------------------- BUNDLES

-- The UI shows each bundle's contents and, where every item is also sold on its own, the real
-- combined price of buying them separately. No invented "was" prices.
add({ Id = "BundleFirstFlight", Name = "First Flight Pack", Category = "Bundles", Type = "Bundle", Price = 450, Rarity = "Rare",
	Description = "Everything a new flyer needs: cap, salute and a carry-on.", Color = rgb(70, 150, 255), Icon = "✈️",
	Data = { Items = { "PilotCap", "EmotePilotSalute", "LuggageCarryOn" } } })
add({
	Id = "BundleLongHaul", Name = "Long Haul Bundle", Category = "Bundles", Type = "Bundle", Price = 650, Rarity = "Rare",
	Description = "Neck Pillow, Sleep Mask and the Frequent Flyer title.", Color = rgb(90, 170, 220), Icon = "😴",
	Data = { Items = { "NeckPillow", "SleepMask", "TitleFrequentFlyer" } },
})
add({ Id = "BundleSkyTraveler", Name = "Sky Traveler Pack", Category = "Bundles", Type = "Bundle", Price = 900, Rarity = "Epic",
	Description = "The cloud-trimmed outfit, a boarding pass and a big Bon Voyage wave.", Color = rgb(120, 190, 255), Icon = "😎",
	Data = { Items = { "OutfitSkyTraveler", "BoardingPassLanyard", "EmoteTravelWave" } } })
add({
	Id = "BundleFlightCrew", Name = "Flight Crew Bundle", Category = "Bundles", Type = "Bundle", Price = 1300, Rarity = "Epic",
	Description = "Captain's Hat, Crew Headset and the Brace! Brace! title.", Color = rgb(40, 60, 120), Icon = "🧢",
	Data = { Items = { "CaptainHat", "CrewHeadset", "TitleBraceBrace" } },
})
add({ Id = "BundleStormRider", Name = "Storm Rider Pack", Category = "Bundles", Type = "Bundle", Product = "StormRiderPack", Rarity = "Epic",
	Description = "Ride the lightning: visor, storm plane, storm wings, Lightning Aura and an exclusive strut.", Color = rgb(255, 225, 60), Icon = "⚡",
	Data = { Items = { "StormVisor", "PlaneStorm", "WingLightning", "AuraLightning", "EmoteStormDance" } } })
add({
	Id = "BundleParty", Name = "Party Pack", Category = "Bundles", Type = "Bundle", Product = "PartyPack", Rarity = "Epic",
	Description = "All three dance emotes including the exclusive Victory Shuffle.", Color = rgb(200, 100, 255), Icon = "💫",
	Data = { Items = { "EmoteDance", "EmoteDance2", "EmoteDance3" } },
})
add({
	Id = "BundleFirstClass", Name = "First Class Pack", Category = "Bundles", Type = "Bundle", Product = "FirstClassBundle", Rarity = "Legendary",
	Description = "Luxury outfit, first-class trunk, gold boarding pass, an exclusive toast emote, Rainbow Jetstream, Golden Wings Finale and the First Class title.",
	Color = rgb(255, 200, 90), Icon = "👑",
	Data = { Items = { "OutfitFirstClass", "LuggageFirstClass", "BadgeGoldBoardingPass", "EmoteFirstClassToast", "TrailRainbow", "VictoryGoldenWings", "TitleFirstClass" } },
})

---------------------------------------------------------------------------- FEATURED

-- Always-on highlights at the top of the store...
ShopCatalog.Featured = { "OutfitGoldenTraveler", "PlaneNeon", "EmoteVictory", "OutfitVIPTraveler", "TrailCloud" }

-- ...plus a few "today's picks" chosen from this pool by the UTC date. Every item stays for
-- sale in its own category all the time - the rotation only keeps the front page fresh.
ShopCatalog.DailyPool = {
	"PlaneCandy", "WingNeon", "AuraStars", "OutfitRetroTraveler", "EmoteCelebrate", "LuggagePremium",
	"BadgeGoldenPilot", "PlaneCloud", "TrailSparkle", "OutfitNeonTraveler", "PlaneTrailRainbow",
	"AviatorHeadset", "AuraNeon", "OutfitSkyExplorer", "PlaneRetro", "EmoteWeSurvived", "BackpackJet",
}
ShopCatalog.DailyCount = 3

---------------------------------------------------------------------------- index & helpers

ShopCatalog.Items = items
ShopCatalog.ById = {}
for index, item in items do
	item.Order = index
	ShopCatalog.ById[item.Id] = item
end

function ShopCatalog.Get(id: string)
	return ShopCatalog.ById[id]
end

-- Items everyone owns from the start.
function ShopCatalog.DefaultOwned(): { string }
	local owned = {}
	for _, item in items do
		if item.Default then
			table.insert(owned, item.Id)
		end
	end
	return owned
end

ShopCatalog.DefaultEquipped = {
	Title = "TitlePassenger",
	Theme = "ThemeClassic",
	PlaneSkin = "PlaneClassic",
}

-- Bundles a given item is part of (ownership of a bundle implies its contents).
ShopCatalog.BundlesContaining = {} :: { [string]: { string } }
for _, item in items do
	if item.Type == "Bundle" and item.Data then
		for _, inner in item.Data.Items do
			ShopCatalog.BundlesContaining[inner] = ShopCatalog.BundlesContaining[inner] or {}
			table.insert(ShopCatalog.BundlesContaining[inner], item.Id)
		end
	end
end

function ShopCatalog.RarityRank(rarity: string?): number
	return table.find(ShopCatalog.RarityOrder, rarity or "Common") or 1
end

-- "Starter" | "Mid" | "Premium" for items with a price, "Unlock" for achievement rewards,
-- "Exclusive" for bundle/pass-only items, nil for default items.
function ShopCatalog.TierOf(item, robuxPrice: number?): string?
	if item.Default then
		return nil
	end
	if item.Price then
		for _, tier in ShopCatalog.PriceTiers do
			if item.Price <= tier.MaxCredits then
				return tier.Id
			end
		end
	end
	if item.Exclusive then
		return "Exclusive"
	end
	if item.Product and robuxPrice then
		for _, tier in ShopCatalog.PriceTiers do
			if robuxPrice <= tier.MaxRobux then
				return tier.Id
			end
		end
	end
	if item.Unlock then
		return "Unlock"
	end
	return "Exclusive"
end

-- Total Flight Credit price of a bundle's contents bought one by one, or nil if any item in it
-- isn't sold separately for credits (then no comparison is shown).
function ShopCatalog.BundleValue(bundle): number?
	if bundle.Type ~= "Bundle" or not bundle.Data then
		return nil
	end
	local total = 0
	for _, id in bundle.Data.Items do
		local inner = ShopCatalog.ById[id]
		if not inner or not inner.Price then
			return nil
		end
		total += inner.Price
	end
	return total
end

-- Deterministic daily picks for a UTC day number (same on every server and client).
function ShopCatalog.DailyPicks(day: number): { string }
	local pool = table.clone(ShopCatalog.DailyPool)
	local seed = day
	local picks = {}
	for _ = 1, math.min(ShopCatalog.DailyCount, #pool) do
		seed = (seed * 1103515245 + 12345) % 2147483648
		local index = (seed % #pool) + 1
		table.insert(picks, table.remove(pool, index))
	end
	return picks
end

return ShopCatalog
