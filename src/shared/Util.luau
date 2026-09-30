--[[
	Util
	Small shared helpers.
]]

local Util = {}

function Util.DeepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value :: any do
		copy[Util.DeepCopy(key)] = Util.DeepCopy(inner)
	end
	return (copy :: any) :: T
end

-- Fills missing keys in `target` from `template` (recursively). Used for data migration.
function Util.Reconcile(target: { [any]: any }, template: { [any]: any })
	for key, value in template do
		if target[key] == nil then
			target[key] = Util.DeepCopy(value)
		elseif type(value) == "table" and type(target[key]) == "table" and next(value) ~= nil and #value == 0 then
			Util.Reconcile(target[key], value)
		end
	end
	return target
end

function Util.FormatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function Util.FormatNumber(n: number): string
	local formatted = tostring(math.floor(n))
	local k
	repeat
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return formatted
end

-- Weighted pick from { key = weight } or { {weight=..}, ...} via accessor.
function Util.WeightedPick(rng: Random, entries: { [any]: number }): any
	local total = 0
	for _, weight in entries do
		total += math.max(0, weight)
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	local last
	for key, weight in entries do
		if weight > 0 then
			last = key
			roll -= weight
			if roll <= 0 then
				return key
			end
		end
	end
	return last
end

function Util.RandomRange(rng: Random, range: number | { number }): number
	if type(range) == "number" then
		return range
	end
	return rng:NextNumber(range[1], range[2])
end

function Util.Shuffle<T>(rng: Random, list: { T }): { T }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = rng:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

function Util.Pick<T>(rng: Random, list: { T }): T?
	if #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

function Util.Count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

function Util.GetRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function Util.GetHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

-- UTC day / week keys used by challenges and daily bonuses.
function Util.DayKey(timestamp: number?): number
	return math.floor((timestamp or os.time()) / 86400)
end

function Util.WeekKey(timestamp: number?): number
	-- weeks start on Monday (unix epoch was a Thursday)
	return math.floor(((timestamp or os.time()) / 86400 + 3) / 7)
end

return Util
