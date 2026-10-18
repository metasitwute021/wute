--[[
	Cosmic Map — แมพ Obby อวกาศ + ลานบอส Cosmic Hydra (Roblox)

	วิธีใช้
	  1) เปิด Roblox Studio (Baseplate) > ServerScriptService > คลิก + > Script
	  2) ลบโค้ดเดิม แล้ววางโค้ดทั้งไฟล์นี้
	  3) กด Play — แมพจะถูกสร้างใน Workspace ชื่อ "CosmicMap"

	ในแมพมี
	  จุดเกิด > ด่าน 1 หินคริสตัลลอยฟ้า > ด่าน 2 แพลตฟอร์มเลื่อน > ด่าน 3 คานพลาสมาหมุน
	  > ด่าน 4 พื้นแตกหาย > ประตูมิติ > ลานบอส (วงกลม รัศมี 60 stud มีเสาเรืองแสง)
	  ทุกด่านมี checkpoint ตกแมพแล้วจะเกิดใหม่ที่ checkpoint ล่าสุด และมี leaderstats "Stage"

	ใช้คู่กับ CosmicHydra.server.lua
	  วางสคริปต์มังกรไว้ใน ServerScriptService ด้วย มังกรเกิดที่ CFrame.new(0, 0, -40)
	  ซึ่งตรงกับกลางลานบอส (ArenaCenter) อยู่แล้ว ถ้าย้ายลานให้แก้ SpawnCFrame ของมังกรตาม
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CONFIG = {
	ArenaCenter = Vector3.new(0, 0, -40),       -- กลางลานบอส (ผิวพื้นอยู่ที่ Y นี้)
	ArenaRadius = 60,
	StartZ = 330,                               -- จุดเริ่มของ obby (วิ่งไปทาง -Z เข้าหาลาน)
	SetupLighting = true,                       -- ปรับแสงเป็นกลางคืนอวกาศ (ฟ้าม่วง ดาวเยอะ เรืองแสง)
	RemoveBaseplate = true,                     -- ลบ Baseplate และปิด SpawnLocation เดิมของเทมเพลต
	FallHeight = -80,                           -- ตกต่ำกว่านี้ = ตาย แล้วเกิดที่ checkpoint
	Asteroids = 70,                             -- อุกกาบาตลอยรอบแมพ (ถ้าแลคให้ลด)
	MainColor = Color3.fromRGB(120, 85, 255),
	DarkColor = Color3.fromRGB(35, 25, 70),
	GlowColor = Color3.fromRGB(170, 245, 255),
	GoldColor = Color3.fromRGB(255, 205, 110),
	DangerColor = Color3.fromRGB(255, 60, 140),
	Seed = 7,
}

local A = CFrame.Angles
local rad = math.rad
local rng = Random.new(CONFIG.Seed)

local old = workspace:FindFirstChild("CosmicMap")
if old then
	old:Destroy()
end

local map = Instance.new("Model")
map.Name = "CosmicMap"

---------------------------------------------------------------------------
-- ตัวช่วยสร้างชิ้นส่วน
---------------------------------------------------------------------------

local function newPart(name, size, cf, opts)
	opts = opts or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = opts.shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = cf
	p.Material = opts.material or Enum.Material.Glass
	p.Color = opts.color or CONFIG.MainColor
	p.Transparency = opts.transparency or 0
	p.Anchored = true
	p.CanCollide = opts.collide ~= false
	p.CastShadow = opts.shadow == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = opts.parent or map
	return p
end

local function folder(name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = map
	return f
end

local function glow(part, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color or CONFIG.GlowColor
	l.Range = range or 12
	l.Brightness = brightness or 1.5
	l.Parent = part
	return l
end

-- แผ่นกลม (Cylinder ของ Roblox วางแกนตาม X จึงต้องหมุน 90 องศาให้นอนราบ)
local function disk(name, radius, thickness, topPos, opts)
	local cf = CFrame.new(topPos - Vector3.new(0, thickness / 2, 0)) * A(0, 0, rad(90))
	opts = opts or {}
	opts.shape = Enum.PartType.Cylinder
	return newPart(name, Vector3.new(thickness, radius * 2, radius * 2), cf, opts)
end

-- ขอบเรืองแสงรอบแผ่นกลม ต่อจากชิ้นเล็กหลายชิ้น
local function ringAround(parent, center, radius, segments, w, color, tilt)
	tilt = tilt or CFrame.new()
	local seg = 2 * math.pi * radius / segments
	for i = 1, segments do
		local ang = (i / segments) * math.pi * 2
		local cf = CFrame.new(center) * tilt * A(0, ang, 0) * CFrame.new(0, 0, -radius)
		newPart("Ring", Vector3.new(seg * 1.05, w, w), cf, {
			parent = parent, material = Enum.Material.Neon, color = color, collide = false,
		})
	end
end

-- กลุ่มคริสตัลแหลม (บล็อกเอียงหลายแท่ง)
-- down = true ห้อยลงใต้ชิ้นที่ลอยอยู่
local function crystal(parent, base, height, color, down)
	local flip = down and A(math.pi, 0, 0) or CFrame.new()
	for i = 1, rng:NextInteger(3, 5) do
		local h = height * rng:NextNumber(0.5, 1)
		local w = height * rng:NextNumber(0.12, 0.22)
		local tilt = A(rad(rng:NextNumber(-25, 25)), rad(i * 72 + rng:NextNumber(-20, 20)), rad(rng:NextNumber(-25, 25)))
		local cf = CFrame.new(base) * flip * tilt * CFrame.new(0, h / 2, 0) * A(0, rad(45), 0)
		newPart("Crystal", Vector3.new(w, h, w), cf, {
			parent = parent, material = Enum.Material.Neon, color = color or CONFIG.GlowColor,
			transparency = 0.15, collide = false,
		})
	end
end

local function label(part, text, color, offsetY)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(220, 50)
	bb.StudsOffset = Vector3.new(0, offsetY or 6, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 140
	bb.Parent = part
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.Text = text
	t.TextColor3 = color or Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.3
	t.Parent = bb
end

local function humanoidFrom(hit)
	local char = hit and hit.Parent
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		return hum, char
	end
end

local function makeKiller(part)
	part:SetAttribute("Kill", true)
	part.Touched:Connect(function(hit)
		local hum = humanoidFrom(hit)
		if hum then
			hum.Health = 0
		end
	end)
end

---------------------------------------------------------------------------
-- ระบบ checkpoint
---------------------------------------------------------------------------

local checkpoints = {}  -- [ลำดับ] = Part
local progress = {}     -- [Player] = ลำดับ checkpoint ล่าสุด

local function setProgress(player, index)
	if (progress[player] or 0) >= index then
		return false
	end
	progress[player] = index
	local stats = player:FindFirstChild("leaderstats")
	if stats and stats:FindFirstChild("Stage") then
		stats.Stage.Value = index
	end
	return true
end

local function addCheckpoint(index, pos, radius, text)
	local cp = disk("Checkpoint" .. index, radius, 1.2, pos, {
		parent = map, material = Enum.Material.Glass, color = CONFIG.DarkColor,
	})
	ringAround(cp, pos + Vector3.new(0, 0.1, 0), radius, 24, 0.5, CONFIG.GoldColor)
	local pad = disk("Pad", 3, 0.3, pos + Vector3.new(0, 0.3, 0), {
		parent = cp, material = Enum.Material.Neon, color = CONFIG.GoldColor, collide = false,
	})
	glow(pad, CONFIG.GoldColor, 14, 2)
	label(pad, text or ("STAGE " .. index), CONFIG.GoldColor, 5)
	checkpoints[index] = cp
	cp.Touched:Connect(function(hit)
		local _, char = humanoidFrom(hit)
		local player = char and Players:GetPlayerFromCharacter(char)
		if player and setProgress(player, index) then
			pad.Color = Color3.new(1, 1, 1)
			TweenService:Create(pad, TweenInfo.new(0.6), { Color = CONFIG.GoldColor }):Play()
		end
	end)
	return cp
end

---------------------------------------------------------------------------
-- จุดเกิด
---------------------------------------------------------------------------

local z = CONFIG.StartZ
local startPos = Vector3.new(0, 0, z)
local startPlat = disk("StartPlatform", 18, 3, startPos, { color = CONFIG.DarkColor })
ringAround(startPlat, startPos + Vector3.new(0, 0.1, 0), 18, 40, 0.7, CONFIG.GlowColor)
for i = 1, 6 do
	local ang = i / 6 * math.pi * 2
	crystal(startPlat, startPos + Vector3.new(math.cos(ang) * 14, 0, math.sin(ang) * 14), 7)
end

local spawnPad = Instance.new("SpawnLocation")
spawnPad.Name = "CosmicSpawn"
spawnPad.Size = Vector3.new(8, 1, 8)
spawnPad.CFrame = CFrame.new(startPos + Vector3.new(0, 0.5, 0))
spawnPad.Anchored = true
spawnPad.Material = Enum.Material.Neon
spawnPad.Color = CONFIG.GlowColor
spawnPad.Neutral = true
spawnPad.Duration = 0
spawnPad.Parent = map
glow(spawnPad, CONFIG.GlowColor, 18, 2)
label(spawnPad, "COSMIC OBBY", CONFIG.GlowColor, 9)
checkpoints[0] = startPlat

z = z - 18 -- ขอบจุดเกิด

---------------------------------------------------------------------------
-- ด่าน 1: หินคริสตัลลอยฟ้า (กระโดดขึ้นทีละก้อน)
---------------------------------------------------------------------------

local stage1 = folder("Stage1_Stones")
for i = 1, 6 do
	z = z - 9
	local pos = Vector3.new((i % 2 == 0) and 3 or -3, i * 1.2, z)
	local stone = newPart("Stone" .. i, Vector3.new(6, 1.5, 6), CFrame.new(pos) * A(0, rad(i * 17), 0), {
		parent = stage1, material = Enum.Material.Glass, color = CONFIG.MainColor,
	})
	crystal(stage1, pos - Vector3.new(0, 0.75, 0), 3, CONFIG.MainColor, true)
	glow(stone, CONFIG.MainColor, 10, 1)
end
z = z - 3 - 3 - 8
addCheckpoint(1, Vector3.new(0, 7.2, z), 8)
z = z - 8

---------------------------------------------------------------------------
-- ด่าน 2: แพลตฟอร์มเลื่อนซ้าย-ขวา
---------------------------------------------------------------------------

local stage2 = folder("Stage2_Movers")
local movers = {}
for i = 1, 3 do
	z = z - ((i == 1) and 8 or 13)
	local base = CFrame.new(0, 7.2 - 0.6, z)
	local p = newPart("Mover" .. i, Vector3.new(8, 1.2, 10), base, {
		parent = stage2, material = Enum.Material.Neon, color = CONFIG.GlowColor, transparency = 0.2,
	})
	glow(p, CONFIG.GlowColor, 14, 1.5)
	table.insert(movers, { part = p, base = base, amp = 13, speed = 1.1 + i * 0.15, phase = i * 2.1 })
end
z = z - 5 - 3 - 8
addCheckpoint(2, Vector3.new(0, 7.2, z), 8)
z = z - 8

---------------------------------------------------------------------------
-- ด่าน 3: คานพลาสมาหมุน (กระโดดข้าม ห้ามโดน)
---------------------------------------------------------------------------

local stage3 = folder("Stage3_Spinner")
z = z - 3 - 14
local spinCenter = Vector3.new(0, 7.2, z)
local spinPlat = disk("SpinPlatform", 14, 1.2, spinCenter, { parent = stage3, color = CONFIG.DarkColor })
ringAround(spinPlat, spinCenter + Vector3.new(0, 0.1, 0), 14, 32, 0.5, CONFIG.DangerColor)
local hub = newPart("Hub", Vector3.new(2.5, 3, 2.5), CFrame.new(spinCenter + Vector3.new(0, 1.5, 0)), {
	parent = stage3, material = Enum.Material.Neon, color = CONFIG.DangerColor,
})
makeKiller(hub)
local spinners = {}
for i = 0, 1 do
	local bar = newPart("PlasmaBar", Vector3.new(27, 1, 1), CFrame.new(spinCenter), {
		parent = stage3, material = Enum.Material.Neon, color = CONFIG.DangerColor, collide = false,
	})
	glow(bar, CONFIG.DangerColor, 10, 1)
	makeKiller(bar)
	-- 2 คานหมุนคนละความเร็วและสวนทางกัน ต้องกระโดดข้ามให้จังหวะดี ๆ
	table.insert(spinners, { part = bar, height = 1.1, speed = (i == 0) and 1.6 or -1.1, phase = i * 1.3 })
end
z = z - 14 - 3 - 8
addCheckpoint(3, Vector3.new(0, 7.2, z), 8)
z = z - 8

---------------------------------------------------------------------------
-- ด่าน 4: พื้นแตกหาย (เหยียบแล้วหายไป 2.5 วินาที)
---------------------------------------------------------------------------

local stage4 = folder("Stage4_Fading")
local function fadingTile(pos)
	local tile = newPart("FadeTile", Vector3.new(6, 1, 6), CFrame.new(pos), {
		parent = stage4, material = Enum.Material.Glass, color = CONFIG.MainColor, transparency = 0.1,
	})
	local busy = false
	tile.Touched:Connect(function(hit)
		if busy or not humanoidFrom(hit) then
			return
		end
		busy = true
		local fade = TweenService:Create(tile, TweenInfo.new(0.6), { Transparency = 0.85, Color = CONFIG.DangerColor })
		fade:Play()
		fade.Completed:Wait()
		tile.CanCollide = false
		tile.Transparency = 1
		task.wait(2.5)
		tile.CanCollide = true
		tile.Color = CONFIG.MainColor
		TweenService:Create(tile, TweenInfo.new(0.3), { Transparency = 0.1 }):Play()
		busy = false
	end)
end
for row = 1, 5 do
	z = z - ((row == 1) and 5 or 8)
	for col = -1, 1 do
		-- ทุกแถวมีบางช่องหายไป จะได้ไม่เดินตรงได้ง่าย ๆ
		if (row + col) % 3 ~= 0 then
			fadingTile(Vector3.new(col * 8, 8, z))
		end
	end
end
z = z - 3 - 3 - 10

---------------------------------------------------------------------------
-- ประตูมิติ: ส่งเข้าลานบอส
---------------------------------------------------------------------------

local portalPos = Vector3.new(0, 8.6, z)
addCheckpoint(4, portalPos, 10, "STAGE 4")
local portalRing = Instance.new("Model")
portalRing.Name = "Portal"
portalRing.Parent = map
local portalCenter = portalPos + Vector3.new(0, 6.5, -5)
ringAround(portalRing, portalCenter, 6, 28, 1, CONFIG.GlowColor, A(rad(90), 0, 0))
local portal = newPart("PortalCore", Vector3.new(10, 10, 0.6), CFrame.new(portalCenter), {
	parent = portalRing, material = Enum.Material.ForceField, color = CONFIG.MainColor, collide = false,
})
glow(portal, CONFIG.MainColor, 24, 3)
label(portal, "BOSS ARENA", CONFIG.DangerColor, 8)

---------------------------------------------------------------------------
-- ลานบอส
---------------------------------------------------------------------------

local arena = folder("BossArena")
local AC = CONFIG.ArenaCenter
local R = CONFIG.ArenaRadius
local floor = disk("ArenaFloor", R, 4, AC, { parent = arena, color = CONFIG.DarkColor })
floor.Material = Enum.Material.Glass
disk("ArenaInlay", R * 0.45, 0.2, AC + Vector3.new(0, 0.1, 0), {
	parent = arena, material = Enum.Material.Neon, color = CONFIG.MainColor, transparency = 0.6, collide = false,
})
ringAround(arena, AC + Vector3.new(0, 0.1, 0), R, 64, 1, CONFIG.GlowColor)
ringAround(arena, AC + Vector3.new(0, 0.1, 0), R * 0.45, 40, 0.6, CONFIG.GoldColor)

-- เสาคริสตัลรอบลาน มีลูกแก้วเรืองแสงลอยบนยอด
local orbs = {}
for i = 1, 8 do
	local ang = (i / 8) * math.pi * 2 + rad(22.5)
	local base = AC + Vector3.new(math.cos(ang), 0, math.sin(ang)) * (R - 6)
	newPart("Pillar", Vector3.new(4, 24, 4), CFrame.new(base + Vector3.new(0, 12, 0)) * A(0, ang, 0), {
		parent = arena, material = Enum.Material.Glass, color = CONFIG.MainColor, transparency = 0.2,
	})
	crystal(arena, base, 8)
	local orb = newPart("PillarOrb", Vector3.new(4, 4, 4), CFrame.new(base + Vector3.new(0, 28, 0)), {
		parent = arena, shape = Enum.PartType.Ball, material = Enum.Material.Neon,
		color = (i % 2 == 0) and CONFIG.GlowColor or CONFIG.GoldColor, collide = false,
	})
	glow(orb, orb.Color, 30, 2)
	table.insert(orbs, { part = orb, base = orb.Position, phase = i })
end

-- วงแหวนลอยเหนือลาน หมุนช้า ๆ
local halos = {}
for i = 1, 2 do
	local halo = Instance.new("Model")
	halo.Name = "Halo" .. i
	halo.Parent = arena
	ringAround(halo, Vector3.zero, R * (0.55 + i * 0.15), 48, 0.8, (i == 1) and CONFIG.GlowColor or CONFIG.MainColor)
	local pivot = Instance.new("Part")
	pivot.Name = "Pivot"
	pivot.Anchored = true
	pivot.CanCollide = false
	pivot.Transparency = 1
	pivot.Size = Vector3.one
	pivot.CFrame = CFrame.new()
	pivot.Parent = halo
	halo.PrimaryPart = pivot
	table.insert(halos, { model = halo, height = 45 + i * 12, speed = (i == 1) and 0.15 or -0.1, tilt = rad(8 + i * 6) })
end

local arenaEntry = AC + Vector3.new(0, 0, R - 10)
addCheckpoint(5, arenaEntry + Vector3.new(0, 0.6, 0), 5, "ARENA")

local portalCooldown = {}
portal.Touched:Connect(function(hit)
	local _, char = humanoidFrom(hit)
	if not char or portalCooldown[char] then
		return
	end
	portalCooldown[char] = true
	local player = Players:GetPlayerFromCharacter(char)
	if player then
		setProgress(player, 5)
	end
	char:PivotTo(CFrame.lookAt(arenaEntry + Vector3.new(0, 4, 0), AC + Vector3.new(0, 4, 0)))
	task.delay(1, function()
		portalCooldown[char] = nil
	end)
end)

---------------------------------------------------------------------------
-- ฉากอวกาศ: ดาวเคราะห์ + อุกกาบาต
---------------------------------------------------------------------------

local space = folder("Space")
local planets = {
	{ pos = Vector3.new(-260, 120, -200), size = 90, color = Color3.fromRGB(255, 120, 190), ring = true },
	{ pos = Vector3.new(300, 60, 120), size = 55, color = Color3.fromRGB(90, 200, 255), ring = false },
	{ pos = Vector3.new(120, 180, -420), size = 140, color = Color3.fromRGB(140, 90, 255), ring = true },
}
for _, spec in ipairs(planets) do
	local p = newPart("Planet", Vector3.one * spec.size, CFrame.new(spec.pos), {
		parent = space, shape = Enum.PartType.Ball, material = Enum.Material.SmoothPlastic,
		color = spec.color, collide = false,
	})
	glow(p, spec.color, 60, 0.6)
	if spec.ring then
		ringAround(space, spec.pos, spec.size * 0.85, 56, spec.size * 0.05, CONFIG.GoldColor, A(rad(18), 0, rad(-12)))
	end
end

local asteroids = {}
for i = 1, CONFIG.Asteroids do
	local pos
	repeat
		pos = Vector3.new(rng:NextNumber(-320, 320), rng:NextNumber(-50, 110), rng:NextNumber(-360, 420))
		-- เว้นทางเดิน obby และลานบอสไว้
	until math.abs(pos.X) > 75 or pos.Y < -30 or pos.Y > 70
	local s = rng:NextNumber(3, 14)
	local rock = newPart("Asteroid", Vector3.new(s, s * rng:NextNumber(0.6, 1), s * rng:NextNumber(0.7, 1.2)),
		CFrame.new(pos) * A(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), 0), {
			parent = space, material = Enum.Material.Slate, color = Color3.fromRGB(70, 60, 95),
			collide = false,
		})
	if i % 4 == 0 then
		crystal(space, pos + Vector3.new(0, s * 0.4, 0), s * 0.6, CONFIG.MainColor)
	end
	table.insert(asteroids, { part = rock, spin = Vector3.new(rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.3, 0.3), 0) })
end

map.Parent = workspace

---------------------------------------------------------------------------
-- แสง / ท้องฟ้า
---------------------------------------------------------------------------

if CONFIG.SetupLighting then
	for _, c in ipairs(Lighting:GetChildren()) do
		if c:IsA("Sky") or c:IsA("Atmosphere") or c:IsA("BloomEffect") or c:IsA("ColorCorrectionEffect") then
			c:Destroy()
		end
	end
	Lighting.ClockTime = 0
	Lighting.Brightness = 1
	Lighting.Ambient = Color3.fromRGB(60, 40, 110)
	Lighting.OutdoorAmbient = Color3.fromRGB(90, 70, 160)
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 1

	local sky = Instance.new("Sky")
	sky.StarCount = 5000
	sky.CelestialBodiesShown = false
	sky.Parent = Lighting

	local atmo = Instance.new("Atmosphere")
	atmo.Density = 0.25
	atmo.Offset = 0.1
	atmo.Color = Color3.fromRGB(110, 70, 200)
	atmo.Decay = Color3.fromRGB(40, 20, 90)
	atmo.Glare = 0.4
	atmo.Haze = 1.5
	atmo.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.9
	bloom.Size = 28
	bloom.Threshold = 0.85
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.2
	cc.Contrast = 0.1
	cc.TintColor = Color3.fromRGB(235, 225, 255)
	cc.Parent = Lighting
end

if CONFIG.RemoveBaseplate then
	local bp = workspace:FindFirstChild("Baseplate")
	if bp and bp:IsA("BasePart") then
		bp:Destroy()
	end
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("SpawnLocation") and d ~= spawnPad then
			d.Enabled = false
		end
	end
end
workspace.FallenPartsDestroyHeight = CONFIG.FallHeight

---------------------------------------------------------------------------
-- ผู้เล่น: leaderstats + เกิดที่ checkpoint ล่าสุด
---------------------------------------------------------------------------

local function onCharacter(player, char)
	local index = progress[player] or 0
	if index == 0 then
		return
	end
	char:WaitForChild("HumanoidRootPart")
	task.wait()
	local cp = checkpoints[index]
	char:PivotTo(CFrame.new(cp.Position + Vector3.new(0, 5, 0))) -- หันไปทาง -Z ตามทางเดิน
end

local function onPlayer(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local stage = Instance.new("IntValue")
	stage.Name = "Stage"
	stage.Parent = stats
	stats.Parent = player
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	onPlayer(p)
end
Players.PlayerRemoving:Connect(function(player)
	progress[player] = nil
end)

---------------------------------------------------------------------------
-- ขยับฉาก
---------------------------------------------------------------------------

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
overlap.FilterDescendantsInstances = { map }

local connection
connection = RunService.Heartbeat:Connect(function(dt)
	if not map.Parent then
		connection:Disconnect()
		return
	end
	local t = os.clock()

	-- แพลตฟอร์มเลื่อน: ตั้ง AssemblyLinearVelocity ให้พาตัวละครที่ยืนอยู่ไปด้วย
	for _, m in ipairs(movers) do
		local w = t * m.speed + m.phase
		m.part.CFrame = m.base * CFrame.new(math.sin(w) * m.amp, 0, 0)
		m.part.AssemblyLinearVelocity = m.base.RightVector * (math.cos(w) * m.amp * m.speed)
	end

	-- คานหมุน: เช็คชนเองทุกเฟรม เพราะ Touched ของชิ้น Anchored ที่ย้ายด้วย CFrame พลาดได้
	for _, s in ipairs(spinners) do
		s.part.CFrame = CFrame.new(spinCenter + Vector3.new(0, s.height, 0)) * A(0, t * s.speed + s.phase, 0)
		for _, hit in ipairs(workspace:GetPartsInPart(s.part, overlap)) do
			local hum = humanoidFrom(hit)
			if hum then
				hum.Health = 0
			end
		end
	end

	for _, o in ipairs(orbs) do
		o.part.CFrame = CFrame.new(o.base + Vector3.new(0, math.sin(t * 1.5 + o.phase) * 1.5, 0))
	end

	for _, h in ipairs(halos) do
		h.model:PivotTo(CFrame.new(AC + Vector3.new(0, h.height, 0)) * A(h.tilt, t * h.speed, 0))
	end

	for _, a in ipairs(asteroids) do
		a.part.CFrame = a.part.CFrame * A(a.spin.X * dt, a.spin.Y * dt, 0)
	end
end)
