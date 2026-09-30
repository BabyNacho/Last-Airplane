--[[
	NPCService
	Passengers, flight attendants and pilots.
	  * Rigs are created once into a pool and reused every round (no per-round rig creation cost).
	  * Seated passengers are welded to anchored seats, so they cost almost nothing to simulate.
	  * Reactions: speech bubbles + head movement per mood (calm, nervous, panic, confused, masked).
	  * Injured passengers can be helped by players ([E] HELP PASSENGER) for credits/objectives.
	  * Flight attendants deliver announcements in person and can walk to places.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Util = require(ReplicatedStorage.Shared.Util)
local Registry = require(script.Parent.Parent.Registry)

local NPCService = {}

local SIT_ANIMATION = "rbxassetid://2506281703"
local POOL_SIZE = GameConfig.NPC.Passengers + GameConfig.NPC.FullFlightBonus + GameConfig.NPC.FlightAttendants + 2

local SKIN_TONES = {
	Color3.fromRGB(255, 220, 190),
	Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(198, 140, 100),
	Color3.fromRGB(150, 100, 70),
	Color3.fromRGB(105, 70, 50),
}

local LINES = {
	Calm = { "Is the movie any good?", "I love a window seat.", "Could I get some water?", "Finally, some sleep...", "First time flying!", "Wake me up when we land." },
	Nervous = { "Did you feel that?", "That noise isn't normal...", "Why are they whispering?", "Something's wrong.", "Is it supposed to shake like that?", "My ears just popped." },
	Panic = { "WE'RE GOING DOWN!", "Somebody do something!", "Help! Please!", "I don't want to die!", "Where are the exits?!", "Oh no oh no oh no" },
	Confused = { "Where's the pilot?", "Why won't they answer?", "Who's flying this thing?", "The cockpit door is locked...", "Is this a drill?" },
	Masked = { "*breathing heavily*", "Put your own mask on first!", "Pull it down hard!", "*muffled* Is everyone OK?" },
	Relief = { "We made it!", "Thank you, thank you!", "I'm never flying again.", "Everyone OK?", "Best landing ever." },
	Injured = { "My leg... I can't move!", "Help me, please!", "I hit my head...", "It hurts..." },
}

type NPC = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Head: BasePart?,
	Role: string, -- "Passenger" | "Attendant" | "Pilot"
	Seat: Seat?,
	SitTrack: AnimationTrack?,
	Mask: BasePart?,
	Injured: boolean,
	Helped: boolean,
	HelpHandle: any?,
	Bubble: BillboardGui?,
	BubbleToken: number,
}

local pool: { Model } = {}
local storage: Folder
local active: { NPC } = {}
local npcFolder: Folder
local poolReady = false
local ctxRef: any = nil

---------------------------------------------------------------- rigs

local function makeRig(index: number): Model?
	local ok, rig = pcall(function()
		local description = Instance.new("HumanoidDescription")
		local rng = Random.new(index * 7919)
		local skin = SKIN_TONES[rng:NextInteger(1, #SKIN_TONES)]
		local shirt = Color3.fromHSV(rng:NextNumber(), rng:NextNumber(0.2, 0.7), rng:NextNumber(0.35, 0.9))
		local pants = Color3.fromHSV(rng:NextNumber(), rng:NextNumber(0, 0.4), rng:NextNumber(0.15, 0.5))
		description.HeadColor = skin
		description.TorsoColor = shirt
		description.LeftArmColor = shirt
		description.RightArmColor = shirt
		description.LeftLegColor = pants
		description.RightLegColor = pants
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not rig then
		warn("[NPCService] rig creation failed:", rig)
		return nil
	end
	rig.Name = "NPC"
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
		for _, state in { Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Swimming, Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Dead } do
			humanoid:SetStateEnabled(state, false)
		end
	end
	for _, part in rig:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanQuery = true
			part.CanTouch = false
		end
	end
	return rig
end

local function buildPool()
	for i = 1, POOL_SIZE do
		local rig = makeRig(i)
		if rig then
			rig.Parent = storage
			table.insert(pool, rig)
		end
		task.wait()
	end
	poolReady = true
	print(string.format("[NPCService] %d NPC rigs pooled", #pool))
end

---------------------------------------------------------------- helpers

local function bubble(npc: NPC, text: string, duration: number?)
	if not npc.Head then
		return
	end
	npc.BubbleToken += 1
	local token = npc.BubbleToken
	local gui = npc.Bubble
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "SpeechBubble"
		gui.Size = UDim2.fromOffset(200, 50)
		gui.StudsOffset = Vector3.new(0, 2.4, 0)
		gui.MaxDistance = 45
		gui.AlwaysOnTop = false
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(250, 250, 252)
		label.BackgroundTransparency = 0.05
		label.TextColor3 = Color3.fromRGB(20, 24, 32)
		label.Font = Enum.Font.GothamMedium
		label.TextScaled = true
		label.TextWrapped = true
		label.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = label
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 8)
		padding.PaddingRight = UDim.new(0, 8)
		padding.PaddingTop = UDim.new(0, 4)
		padding.PaddingBottom = UDim.new(0, 4)
		padding.Parent = label
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MaxTextSize = 18
		constraint.Parent = label
		npc.Bubble = gui
	end
	(gui:FindFirstChild("Text") :: TextLabel).Text = text
	gui.Adornee = npc.Head
	gui.Parent = npc.Head
	task.delay(duration or 4, function()
		if npc.BubbleToken == token and gui then
			gui.Parent = nil
		end
	end)
end

local function lookAround(npc: NPC, intensity: number)
	local head = npc.Head
	local neck = head and head:FindFirstChild("Neck")
	if not neck or not neck:IsA("Motor6D") then
		return
	end
	local base = neck:GetAttribute("BaseC0") or neck.C0
	neck:SetAttribute("BaseC0", base)
	local angle = math.rad(math.random(-35, 35) * intensity)
	local tween = TweenService:Create(neck, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 1, true), { C0 = base * CFrame.Angles(0, angle, 0) })
	tween:Play()
end

local function playSit(npc: NPC)
	local animator = npc.Humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = npc.Humanoid
	local animation = Instance.new("Animation")
	animation.AnimationId = SIT_ANIMATION
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok and track then
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Core
		track:Play(0)
		npc.SitTrack = track
	end
end

local function seatNPC(npc: NPC, seat: Seat)
	npc.Model:PivotTo(seat.CFrame * CFrame.new(0, 2.5, 0))
	npc.Model.Parent = npcFolder
	npc.Root:SetNetworkOwner(nil)
	seat:Sit(npc.Humanoid)
	npc.Seat = seat
	playSit(npc)
end

local function standNPC(npc: NPC, cframe: CFrame)
	npc.Model:PivotTo(cframe)
	npc.Model.Parent = npcFolder
	npc.Root:SetNetworkOwner(nil)
	npc.Humanoid.WalkSpeed = 10
end

local function take(role: string): NPC?
	local rig = table.remove(pool)
	if not rig then
		return nil
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	local npc: NPC = {
		Model = rig,
		Humanoid = humanoid,
		Root = root,
		Head = rig:FindFirstChild("Head") :: BasePart?,
		Role = role,
		Seat = nil,
		SitTrack = nil,
		Mask = nil,
		Injured = false,
		Helped = false,
		HelpHandle = nil,
		Bubble = nil,
		BubbleToken = 0,
	}
	rig:SetAttribute("Role", role)
	table.insert(active, npc)
	return npc
end

local function release(npc: NPC)
	if npc.HelpHandle then
		npc.HelpHandle:Destroy()
		npc.HelpHandle = nil
	end
	if npc.SitTrack then
		npc.SitTrack:Stop(0)
		npc.SitTrack = nil
	end
	if npc.Mask then
		npc.Mask:Destroy()
		npc.Mask = nil
	end
	if npc.Bubble then
		npc.Bubble:Destroy()
		npc.Bubble = nil
	end
	npc.Humanoid.Sit = false
	if npc.Seat then
		local weld = npc.Seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
	for _, extra in npc.Model:GetChildren() do
		if extra:GetAttribute("NPCExtra") then
			extra:Destroy()
		end
	end
	local head = npc.Head
	local neck = head and head:FindFirstChild("Neck")
	if neck and neck:IsA("Motor6D") and neck:GetAttribute("BaseC0") then
		neck.C0 = neck:GetAttribute("BaseC0")
	end
	npc.Model:SetAttribute("Injured", nil)
	npc.Model:SetAttribute("Role", nil)
	npc.Model.Parent = storage
	table.insert(pool, npc.Model)
end

local function addHat(npc: NPC, color: Color3)
	if not npc.Head then
		return
	end
	local hat = Instance.new("Part")
	hat.Name = "CrewHat"
	hat.Size = Vector3.new(1.3, 0.35, 1.3)
	hat.Color = color
	hat.Material = Enum.Material.Fabric
	hat.CanCollide = false
	hat.Massless = true
	hat.CFrame = npc.Head.CFrame * CFrame.new(0, 0.62, 0)
	hat:SetAttribute("NPCExtra", true)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hat
	weld.Part1 = npc.Head
	weld.Parent = hat
	hat.Parent = npc.Model
end

---------------------------------------------------------------- public API

function NPCService:Passengers(): { any }
	local list = {}
	for _, npc in active do
		if npc.Role == "Passenger" then
			table.insert(list, npc)
		end
	end
	return list
end

function NPCService:Attendants(): { any }
	local list = {}
	for _, npc in active do
		if npc.Role == "Attendant" then
			table.insert(list, npc)
		end
	end
	return list
end

function NPCService:Pilots(): { any }
	local list = {}
	for _, npc in active do
		if npc.Role == "Pilot" then
			table.insert(list, npc)
		end
	end
	return list
end

-- A random subset of passengers react with a line from `mood`.
function NPCService:React(mood: string, fraction: number?)
	local lines = LINES[mood] or LINES.Nervous
	local passengers = self:Passengers()
	local rng = ctxRef and ctxRef.Rng or Random.new()
	for _, npc in Util.Shuffle(rng, passengers) do
		if rng:NextNumber() < (fraction or 0.35) and not npc.Injured then
			task.delay(rng:NextNumber(0, 1.5), function()
				if npc.Model.Parent then
					bubble(npc, lines[rng:NextInteger(1, #lines)], 3.5)
					lookAround(npc, if mood == "Panic" then 1.4 else 0.8)
				end
			end)
		end
	end
end

-- A flight attendant says something in person and over the intercom.
function NPCService:CrewSay(text: string, speaker: string?)
	local attendants = self:Attendants()
	local npc = attendants[1]
	if npc then
		bubble(npc, text, 5)
	end
	Registry.EffectsService:Announce(speaker or "Flight Attendant", text)
end

function NPCService:AttendantWalkTo(position: Vector3, index: number?)
	local npc = self:Attendants()[index or 1]
	if npc then
		npc.Humanoid:MoveTo(position)
	end
end

function NPCService:SetMasks(on: boolean)
	for _, npc in self:Passengers() do
		if on and not npc.Mask and npc.Head then
			local mask = Instance.new("Part")
			mask.Name = "OxygenMask"
			mask.Size = Vector3.new(0.6, 0.5, 0.35)
			mask.Color = Color3.fromRGB(255, 220, 40)
			mask.CanCollide = false
			mask.Massless = true
			mask.CFrame = npc.Head.CFrame * CFrame.new(0, -0.2, -0.6)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = mask
			weld.Part1 = npc.Head
			weld.Parent = mask
			mask.Parent = npc.Model
			npc.Mask = mask
		elseif not on and npc.Mask then
			npc.Mask:Destroy()
			npc.Mask = nil
		end
	end
end

-- Marks `count` random passengers as injured, adding a help prompt. Returns the list.
function NPCService:InjurePassengers(ctx, count: number, reason: string?): { any }
	local candidates = {}
	for _, npc in self:Passengers() do
		if not npc.Injured then
			table.insert(candidates, npc)
		end
	end
	local injured = {}
	for _, npc in Util.Shuffle(ctx.Rng, candidates) do
		if #injured >= count then
			break
		end
		npc.Injured = true
		npc.Helped = false
		npc.Model:SetAttribute("Injured", true)
		table.insert(injured, npc)
		bubble(npc, LINES.Injured[ctx.Rng:NextInteger(1, #LINES.Injured)], 5)
		npc.HelpHandle = Registry.InteractionService:Add(npc.Root, {
			Action = "HELP PASSENGER",
			Object = reason or "Injured passenger",
			Hold = GameConfig.NPC.HelpHoldTime,
			Range = 8,
			Kind = "rescue",
			Round = ctx,
			OnTrigger = function(player)
				if npc.Helped then
					return
				end
				npc.Helped = true
				npc.Injured = false
				npc.Model:SetAttribute("Injured", nil)
				if npc.HelpHandle then
					npc.HelpHandle:Destroy()
					npc.HelpHandle = nil
				end
				ctx:Add(player, "PassengersHelped")
				bubble(npc, "Thank you so much!", 3)
				Registry.EffectsService:Notify("Passenger helped", "good", player)
				Registry.RewardService:Popup(player, "PASSENGER HELPED", "PassengerHelped")
				if Registry.ObjectiveService:IsActive("HelpPassengers") then
					Registry.ObjectiveService:Progress("HelpPassengers", 1, player)
				end
			end,
		})
	end
	return injured
end

function NPCService:UnhelpedCount(): number
	local n = 0
	for _, npc in self:Passengers() do
		if npc.Injured and not npc.Helped then
			n += 1
		end
	end
	return n
end

-- Pilots: seated in the cockpit unless the disaster removes them.
function NPCService:SetPilotsPresent(present: boolean)
	for _, npc in self:Pilots() do
		release(npc)
		local index = table.find(active, npc)
		if index then
			table.remove(active, index)
		end
	end
	if not present then
		return
	end
	local points = Registry.MapService.Points
	for _, seat in { points.PilotSeat, points.CopilotSeat } do
		local npc = take("Pilot")
		if npc then
			seatNPC(npc, seat)
			addHat(npc, Color3.fromRGB(20, 25, 45))
		end
	end
end

-- Moves pilots out of their seats and lays them in the crew rest (incapacitated / missing).
function NPCService:MovePilotsToCrewRest()
	local bunks = Registry.MapService.Points.CrewRestBunks
	for i, npc in self:Pilots() do
		if npc.SitTrack then
			npc.SitTrack:Stop(0)
			npc.SitTrack = nil
		end
		npc.Humanoid.Sit = false
		if npc.Seat then
			local weld = npc.Seat:FindFirstChild("SeatWeld")
			if weld then
				weld:Destroy()
			end
			npc.Seat = nil
		end
		task.wait()
		local bunk = bunks[i] or bunks[1]
		npc.Model:PivotTo(bunk * CFrame.Angles(0, 0, math.rad(90)) * CFrame.new(0, 0.5, 0))
		npc.Root.Anchored = true
	end
end

function NPCService:PilotAt(index: number)
	return self:Pilots()[index]
end

function NPCService:SayAs(npc, text: string, duration: number?)
	if npc then
		bubble(npc, text, duration)
	end
end

---------------------------------------------------------------- lifecycle

function NPCService:Init()
	storage = Instance.new("Folder")
	storage.Name = "NPCPool"
	storage.Parent = ServerStorage
	npcFolder = Instance.new("Folder")
	npcFolder.Name = "NPCs"
	npcFolder.Parent = workspace
end

function NPCService:Start()
	task.spawn(buildPool)
end

function NPCService:OnRoundStart(ctx)
	ctxRef = ctx
	-- wait briefly for the pool on the very first round
	local waited = 0
	while not poolReady and waited < 6 do
		task.wait(0.25)
		waited += 0.25
	end
	local reserved = ctx.Flags.ReservedSeats or {}
	local seats = {}
	for _, seat in Registry.MapService.Points.Seats do
		if not reserved[seat] then
			table.insert(seats, seat)
		end
	end
	seats = Util.Shuffle(ctx.Rng, seats)
	local count = GameConfig.NPC.Passengers + (if ctx.Modifier == "FullFlight" then GameConfig.NPC.FullFlightBonus else 0)
	-- leave seats for players (boarding assigns later, so keep plenty free)
	count = math.min(count, #seats - 24)
	for i = 1, count do
		local npc = take("Passenger")
		if not npc then
			break
		end
		seatNPC(npc, seats[i])
	end
	local faSpots = Registry.MapService.Points.FASpots
	for i = 1, GameConfig.NPC.FlightAttendants do
		local npc = take("Attendant")
		local spot = faSpots[i]
		if npc and spot then
			standNPC(npc, spot.CFrame)
			addHat(npc, Color3.fromRGB(30, 50, 110))
		end
	end
	self:SetPilotsPresent(true)
	-- idle chatter
	ctx:Every({ 12, 22 }, function()
		if ctx.Phase == "Flight" or ctx.Phase == "Boarding" then
			self:React("Calm", 0.12)
		end
		return true
	end)
end

function NPCService:OnPhase(_ctx, phase: string)
	if phase == "Results" then
		self:React("Relief", 0.4)
	end
end

function NPCService:OnRoundEnd()
	for i = #active, 1, -1 do
		local npc = active[i]
		if npc.Root then
			npc.Root.Anchored = false
		end
		release(npc)
		active[i] = nil
	end
	ctxRef = nil
end

return NPCService
