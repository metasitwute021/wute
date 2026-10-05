--[[
	MapBuilder.server.lua
	สร้างโลกแฟนตาซีขนาดใหญ่ (Open World + Roleplay) ใน Roblox อัตโนมัติ

	ในแมพมี:
	  🏘️ เมืองกลางเกาะ   ถนน บ้าน 32 หลัง ร้านค้า ลานน้ำพุ ตลาด ไฟถนน
	  🏰 ปราสาท (ทิศตะวันตก)   กำแพง หอคอย ห้องบัลลังก์
	  🌲 ป่ามหัศจรรย์ (ทิศตะวันออก)   ต้นไม้หนาแน่น เห็ดยักษ์ คริสตัลเรืองแสง
	  🏔️ ภูเขาหิมะ (ทิศเหนือ)   ศาลเจ้าบนยอดเขา
	  ⚓ ท่าเรือ + ประภาคาร (ทิศใต้)
	  💀 ซากปรักหักพัง + สุสาน (ทิศตะวันออกเฉียงใต้)
	  🌳 ต้นไม้โลก + หมู่บ้านเอลฟ์ (ทิศตะวันออกไกล)   บันไดวน บ้านห้อยกิ่ง สะพานเชือก
	  👺 ค่ายก็อบลิน, 🐍 หนองน้ำแม่มด, 🌋 ภูเขาไฟรังมังกร
	  💀 ดันเจี้ยนใต้ดิน 9 ห้อง + บอสมิโนทอร์
	  🌀 ลานวาร์ปในเมือง ไปได้ทุกโซน
	  🌊 ทะเลล้อมรอบเกาะ

	ระบบเกม:
	  - มอนสเตอร์ 6 ชนิด มีท่าเดิน/ท่าโจมตี: สไลม์ + หมาป่า (ป่า),
	    โครงกระดูก + วิญญาณ + ค้างคาว (ซากปรักหักพัง), โกเลมหิน + ค้างคาว (ภูเขา)
	  - อาวุธ 5 แบบ: ดาบเหล็ก (ฟรี), ขวานนักรบ, ดาบทองคำ, ค้อนยักษ์, เคียวยมทูต
	  - ฆ่ามอนสเตอร์ได้เหรียญ เอาไปซื้ออาวุธที่ร้านอาวุธ
	  - หีบสมบัติ 3 จุด, โรงพยาบาลฟื้นเลือด
	  - เลือกอาชีพ (ทีม) ที่ลานกลางเมือง
	  - กลางวัน/กลางคืน ไฟถนนเปิดเองตอนกลางคืน

	วิธีใช้: อ่าน roblox/README.md
	  (สรุป: สร้าง Script ใน ServerScriptService → วางโค้ดนี้ทั้งหมด → กด Play)
]]

-------------------------------------------------------------------------------
-- ⚙️ ตั้งค่า (แก้ตัวเลขตรงนี้ได้เลย)
-------------------------------------------------------------------------------
local CONFIG = {
	MapName = "FantasyWorld",
	Seed = 7,                -- เปลี่ยนเลขนี้ = ภูเขา/ต้นไม้/หินจะสุ่มตำแหน่งใหม่
	WorldHalfSize = 1536,    -- ครึ่งหนึ่งของความกว้างโลก (โลกกว้าง 3072 studs)
	ClearTerrain = true,     -- ล้าง Terrain เดิมก่อนสร้าง
	RemoveBaseplate = true,  -- ลบ Baseplate เดิมของเทมเพลต
	TreeCount = 750,         -- ต้นไม้ทั่วเกาะ
	ForestTreeCount = 220,   -- ต้นไม้เพิ่มเติมในป่ามหัศจรรย์
	ElderwoodTreeCount = 260, -- ต้นไม้ยักษ์ในป่าโบราณรอบต้นไม้โลก
	RockCount = 180,
	DarkTheme = true,        -- ธีมภาพมืด หมอก แสงเงา (false = สว่างสดใส)
	LeafDetail = 2,          -- ความละเอียดพุ่มใบ 1 = เบาเครื่อง, 2 = ปกติ, 3 = ละเอียดมาก
	DayLengthMinutes = 12,   -- 1 วันในเกม = กี่นาทีจริง
	SpawnMonsters = true,
	StartCoins = 0,
}

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Teams = game:GetService("Teams")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ServerStorage = game:GetService("ServerStorage")

local terrain = workspace.Terrain
local rng = Random.new(CONFIG.Seed)
local HALF = CONFIG.WorldHalfSize
local SEA_LEVEL = 0
local NOISE_SEED = CONFIG.Seed * 0.731

local MAT = Enum.Material

-------------------------------------------------------------------------------
-- 🗺️ ผังโลก: พื้นที่ที่ถูกปรับให้เรียบ
-------------------------------------------------------------------------------
local ZONES = {
	{ name = "Town", x = 0, z = 0, radius = 235, blend = 90, height = 8 },
	{ name = "Castle", x = -430, z = 40, radius = 100, blend = 80, height = 44 },
	{ name = "Ruins", x = 330, z = 330, radius = 55, blend = 60, height = 12 },
	{ name = "Harbor", x = 0, z = 1180, radius = 55, blend = 30, height = 4 },
	{ name = "WorldTree", x = 950, z = 80, radius = 130, blend = 110, height = 18 },
	{ name = "GoblinCamp", x = -620, z = 520, radius = 80, blend = 70, height = 14 },
	{ name = "DungeonGate", x = -380, z = -420, radius = 35, blend = 60, height = 28 },
	{ name = "Swamp", x = 650, z = 800, radius = 170, blend = 80, height = 1, bumps = 5 },
}
local ZONE = {}
for _, zn in ipairs(ZONES) do
	ZONE[zn.name] = zn
end

local FOREST = { minX = 270, maxX = 620, minZ = -230, maxZ = 230 }
local ELDERWOOD = { minX = 650, maxX = 1350, minZ = -420, maxZ = 560 } -- ป่าโบราณรอบต้นไม้โลก
local SHRINE_POS = Vector2.new(0, -470) -- ศาลเจ้าบนภูเขา
local VOLCANO = { x = -1100, z = -350, radius = 330, height = 190, crater = 50 }
local PEAKS = { -- ยอดเขาเดี่ยว ๆ กระจายทั่วเกาะ
	{ x = 1250, z = -600, radius = 320, height = 170 },
	{ x = 500, z = -1050, radius = 260, height = 140 },
	{ x = -1150, z = 520, radius = 250, height = 130 },
	{ x = -500, z = 1100, radius = 220, height = 110 },
}

-------------------------------------------------------------------------------
-- ตัวช่วยทั่วไป
-------------------------------------------------------------------------------
local mapFolder
local monstersFolder
local lampLights = {} -- { light = PointLight, bulb = Part }
local pathPoints = {} -- จุดบนเส้นทาง ใช้กันไม่ให้ต้นไม้ขึ้นกลางทาง
local monsterSpawns = {} -- { kind = "Slime", pos = Vector3 }

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function smooth(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function part(props)
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then
		p.Shape = props.Shape -- ต้องตั้ง Shape ก่อน Size (ลูกบอลต้องเป็นทรงกลมเท่ากันทุกด้าน)
	end
	for k, v in pairs(props) do
		if k ~= "ClassName" and k ~= "Parent" and k ~= "Shape" then
			p[k] = v
		end
	end
	p.Parent = props.Parent or mapFolder
	return p
end

-- ทรงกระบอกตั้งตรง: Position = จุดกึ่งกลาง
local function cylinder(props)
	local pos, height, dia = props.Position, props.Height, props.Diameter
	props.Position, props.Height, props.Diameter = nil, nil, nil
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, dia, dia)
	props.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	return part(props)
end

local function folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent or mapFolder
	return f
end

local function model(name, parent)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent or mapFolder
	return m
end

local function billboardText(adornee, text, color, offsetY, width)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(width or 14, 3)
	gui.StudsOffset = Vector3.new(0, offsetY or 5, 0)
	gui.MaxDistance = 180
	gui.Adornee = adornee
	gui.Parent = adornee

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Parent = gui
end

-- ป้ายติดผนัง (ข้อความอยู่ด้านหน้า = -Z ของชิ้นส่วน)
local function surfaceText(p, text, textColor)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = p

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = textColor or Color3.new(1, 1, 1)
	label.Parent = gui
end

local function pointLight(parent, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range or 16
	l.Brightness = brightness or 1.5
	l.Shadows = false
	l.Parent = parent
	return l
end

-------------------------------------------------------------------------------
-- 🧩 โมเดลของคุณเอง (ไม่บังคับ)
--   วางโมเดลสมจริง (MeshPart จาก Creator Store หรือ Blender) ไว้ที่
--   ServerStorage > โฟลเดอร์ชื่อ CustomModels แล้วตั้งชื่อตามนี้ สคริปต์จะใช้แทนทั้งแมพ:
--     Tree = ต้นไม้ทั่วไป, PineTree = ต้นสน, AncientTree = ต้นไม้ยักษ์ในป่าโบราณ,
--     Rock = ก้อนหิน, LeafCluster = พุ่มใบ (ใช้กับต้นไม้โลก)
-------------------------------------------------------------------------------
local function customTemplate(name)
	local f = ServerStorage:FindFirstChild("CustomModels")
	local m = f and f:FindFirstChild(name)
	if m and (m:IsA("Model") or m:IsA("BasePart")) then
		return m
	end
	return nil
end

-- วางสำเนาโมเดลให้ฐานแตะพื้นที่ pos และสูงประมาณ height
local function placeCustom(template, parent, pos, height, yaw)
	local clone = template:Clone()
	if clone:IsA("BasePart") then
		local wrap = Instance.new("Model")
		wrap.Name = clone.Name
		clone.Parent = wrap
		clone = wrap
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("ModuleScript") then
			d:Destroy() -- ลบสคริปต์ที่ติดมากับโมเดลจาก Toolbox เพื่อความปลอดภัย
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local _, size = clone:GetBoundingBox()
	if height and size.Y > 0 then
		clone:ScaleTo(clone:GetScale() * height / size.Y)
	end
	local box, size2 = clone:GetBoundingBox()
	local lift = clone:GetPivot().Position.Y - (box.Position.Y - size2.Y / 2)
	clone:PivotTo(CFrame.new(pos + Vector3.new(0, lift, 0)) * CFrame.Angles(0, yaw or rng:NextNumber(0, math.pi * 2), 0))
	clone.Parent = parent
	return clone
end

-- พุ่มใบ: ก้อนใบไม้หลายชิ้นวางเอียงคละกัน (แทนลูกบอลกลมเรียบ)
local function leafClump(parent, center, size, colorA, colorB, collide, pieces)
	local tpl = customTemplate("LeafCluster")
	if tpl then
		return placeCustom(tpl, parent, center - Vector3.new(0, size / 2, 0), size)
	end
	local count = pieces or math.clamp(math.floor(size / 4), 3, 12)
	count = math.max(2, math.floor(count * CONFIG.LeafDetail / 2 + 0.5))
	for i = 1, count do
		local s = size * rng:NextNumber(0.38, 0.58)
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.6, 0.8), rng:NextNumber(-1, 1))
		local off = (dir.Magnitude > 0.01) and dir.Unit * size * rng:NextNumber(0.05, 0.3) or Vector3.zero
		part({
			ClassName = (i % 3 == 0) and "WedgePart" or "Part",
			Name = "Leaves",
			Size = Vector3.new(s, s * rng:NextNumber(0.55, 0.85), s * rng:NextNumber(0.8, 1.1)),
			CFrame = CFrame.new(center + off * Vector3.new(1, 0.7, 1))
				* CFrame.Angles(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.6, 0.6)),
			Color = colorA:Lerp(colorB, rng:NextNumber()),
			Material = MAT.LeafyGrass,
			CanCollide = collide ~= false,
			Parent = parent,
		})
	end
	return nil
end

-- ชั้นใบสนทรงพีระมิด 4 ด้าน
local function pineTier(parent, center, base, height, color)
	for k = 0, 3 do
		part({
			ClassName = "WedgePart",
			Name = "Needles",
			Size = Vector3.new(base, height, base / 2),
			CFrame = CFrame.new(center) * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, 0, -base / 4),
			Color = color,
			Material = MAT.LeafyGrass,
			Parent = parent,
		})
	end
end

-------------------------------------------------------------------------------
-- 🏔️ ภูมิประเทศ: ความสูงพื้นดินที่ตำแหน่ง (x, z)
-------------------------------------------------------------------------------
local TERRAIN_TOP = 256

local function heightAt(x, z)
	local noise = math.noise
	-- เนินเขาทั่วไป
	local h = 12 + noise(x / 180, z / 180, NOISE_SEED) * 18 + noise(x / 55, z / 55, NOISE_SEED + 3.3) * 4

	-- เทือกเขาทางทิศเหนือ มีสันเขาหลายยอด (z ติดลบ)
	local m = smooth((-z - 330) / 300)
	if m > 0 then
		local ridge = math.max(0, 1 - math.abs(noise(x / 260, z / 260, NOISE_SEED + 7.7)) * 2.2)
		h += m * (45 + ridge * ridge * 160 + noise(x / 90, z / 90, NOISE_SEED + 8.8) * 25)
	end

	-- ยอดเขาเดี่ยว
	for _, pk in ipairs(PEAKS) do
		local dx, dz = x - pk.x, z - pk.z
		local t = 1 - math.sqrt(dx * dx + dz * dz) / pk.radius
		if t > 0 then
			h += pk.height * t ^ 1.6 * (0.8 + noise(x / 70, z / 70, NOISE_SEED + 4.4) * 0.5)
		end
	end

	-- ภูเขาไฟ: กรวยสูง มีปล่องลาวาตรงกลาง
	local vx, vz = x - VOLCANO.x, z - VOLCANO.z
	local dv = math.sqrt(vx * vx + vz * vz)
	if dv < VOLCANO.radius then
		local rim = VOLCANO.height * (1 - VOLCANO.crater / VOLCANO.radius) ^ 1.2
		if dv < VOLCANO.crater then
			h += rim - (VOLCANO.crater - dv) * 0.9
		else
			h += VOLCANO.height * (1 - dv / VOLCANO.radius) ^ 1.2
		end
	end

	-- ขอบเกาะค่อย ๆ ลาดลงทะเล
	local d = math.sqrt(x * x + z * z)
	local coast = 1330 + noise(x / 400, z / 400, NOISE_SEED + 1.1) * 90
	h = lerp(h, -14, smooth((d - (coast - 140)) / 140))

	-- อ่าวทางทิศใต้ สำหรับท่าเรือ
	local hb = ZONE.Harbor
	local bay = smooth((z - (hb.z + 30)) / 50) * (1 - smooth((math.abs(x - hb.x) - 110) / 80))
	h = lerp(h, -14, bay)

	-- ปรับพื้นที่เมือง/ปราสาท/ฯลฯ ให้เรียบ (หนองน้ำมีหลุมบ่อเป็นแอ่งน้ำ)
	for _, zn in ipairs(ZONES) do
		local dx, dz = x - zn.x, z - zn.z
		local t = smooth((math.sqrt(dx * dx + dz * dz) - zn.radius) / zn.blend)
		if t < 1 then
			h = lerp(zn.height, h, t)
			if zn.bumps then
				h += noise(x / 35, z / 35, NOISE_SEED + 5.5) * zn.bumps * 2 * (1 - t)
			end
		end
	end

	return math.clamp(h, -20, TERRAIN_TOP - 8)
end

local function inForest(x, z)
	return x > FOREST.minX and x < FOREST.maxX and z > FOREST.minZ and z < FOREST.maxZ
end

local function nearZone(name, x, z, extra)
	local zn = ZONE[name]
	local r = zn.radius + (extra or 0)
	return (x - zn.x) ^ 2 + (z - zn.z) ^ 2 < r * r
end

local function surfaceMaterial(h, x, z)
	local dv = math.sqrt((x - VOLCANO.x) ^ 2 + (z - VOLCANO.z) ^ 2)
	if dv < VOLCANO.crater + 4 then
		return MAT.CrackedLava
	elseif dv < VOLCANO.radius * 0.6 then
		return MAT.Basalt
	end
	if nearZone("Swamp", x, z, 30) then
		return (h < 5) and MAT.Mud or MAT.LeafyGrass
	end
	if h < 3 then
		return MAT.Sand
	elseif h > 150 then
		return MAT.Snow
	elseif h > 85 then
		return MAT.Rock
	elseif inForest(x, z) then
		return MAT.LeafyGrass
	elseif x > ELDERWOOD.minX and x < ELDERWOOD.maxX and z > ELDERWOOD.minZ and z < ELDERWOOD.maxZ then
		return (math.noise(x / 40, z / 40, NOISE_SEED + 9.9) > 0.25) and MAT.Ground or MAT.LeafyGrass
	end
	if nearZone("Ruins", x, z, 20) or nearZone("GoblinCamp", x, z, 10) then
		return MAT.Ground
	end
	return MAT.Grass
end

local function groundPos(x, z, extraY)
	return Vector3.new(x, heightAt(x, z) + (extraY or 0), z)
end

-------------------------------------------------------------------------------
-- ⚔️ อาวุธ: รูปร่างและค่าพลัง
--   ทุกชิ้นส่วนวางในพื้นที่ของด้ามจับ (Handle): แกน +Z = ปลายอาวุธ, แกน -X = ด้านหน้า
-------------------------------------------------------------------------------
local STEEL = Color3.fromRGB(200, 205, 215)
local DARK_STEEL = Color3.fromRGB(85, 90, 100)
local LEATHER = Color3.fromRGB(90, 55, 35)
local WOOD = Color3.fromRGB(120, 80, 45)
local GOLD = Color3.fromRGB(255, 200, 40)

local function at(x, y, z, ry)
	return CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(ry or 0), 0)
end

local function swordParts(bladeColor, bladeMat, fullerColor, gemColor)
	return {
		{ name = "Handle", size = Vector3.new(0.35, 0.35, 1.6), cf = at(0, 0, 0), color = LEATHER, mat = MAT.Fabric },
		{ name = "Pommel", shape = Enum.PartType.Ball, size = Vector3.new(0.6, 0.6, 0.6), cf = at(0, 0, -1), color = DARK_STEEL, mat = MAT.Metal },
		{ name = "Guard", size = Vector3.new(2, 0.4, 0.35), cf = at(0, 0, 0.95), color = DARK_STEEL, mat = MAT.Metal },
		{ name = "Gem", shape = Enum.PartType.Ball, size = Vector3.new(0.5, 0.5, 0.5), cf = at(0, 0, 0.95), color = gemColor, mat = MAT.Neon, light = gemColor },
		{ name = "Blade", size = Vector3.new(0.7, 0.15, 4.2), cf = at(0, 0, 3.2), color = bladeColor, mat = bladeMat, trail = { -1.8, 2.1 } },
		{ name = "Fuller", size = Vector3.new(0.15, 0.2, 3.4), cf = at(0, 0, 3), color = fullerColor, mat = MAT.Neon },
		{ name = "Tip", size = Vector3.new(0.4, 0.15, 0.5), cf = at(0, 0, 5.5), color = bladeColor, mat = bladeMat },
	}
end

local function axeParts()
	return {
		{ name = "Handle", size = Vector3.new(0.4, 0.4, 1.6), cf = at(0, 0, 0), color = LEATHER, mat = MAT.Fabric },
		{ name = "Shaft", size = Vector3.new(0.4, 0.4, 3.2), cf = at(0, 0, 2.4), color = WOOD, mat = MAT.Wood },
		{ name = "Band1", size = Vector3.new(0.5, 0.5, 0.25), cf = at(0, 0, 0.9), color = DARK_STEEL, mat = MAT.Metal },
		{ name = "Band2", size = Vector3.new(0.5, 0.5, 0.25), cf = at(0, 0, 3), color = DARK_STEEL, mat = MAT.Metal },
		{ name = "AxeHead", size = Vector3.new(0.9, 0.5, 1.2), cf = at(0, 0, 3.6), color = DARK_STEEL, mat = MAT.Metal },
		{ name = "AxeBlade", size = Vector3.new(1.8, 0.2, 1.8), cf = at(-1.3, 0, 3.6), color = STEEL, mat = MAT.Metal },
		{ name = "AxeEdge", size = Vector3.new(0.3, 0.25, 2.6), cf = at(-2.3, 0, 3.6), color = Color3.fromRGB(235, 240, 245), mat = MAT.Metal, trail = { -1.2, 1.2 } },
		{ name = "BackSpike", size = Vector3.new(0.9, 0.2, 0.5), cf = at(0.85, 0, 3.6), color = DARK_STEEL, mat = MAT.Metal },
		{ name = "Cap", size = Vector3.new(0.5, 0.5, 0.4), cf = at(0, 0, 4.4), color = DARK_STEEL, mat = MAT.Metal },
	}
end

local function hammerParts()
	local rune = Color3.fromRGB(80, 220, 255)
	return {
		{ name = "Handle", size = Vector3.new(0.45, 0.45, 1.6), cf = at(0, 0, 0), color = LEATHER, mat = MAT.Fabric },
		{ name = "Pommel", size = Vector3.new(0.7, 0.7, 0.5), cf = at(0, 0, -1.05), color = DARK_STEEL, mat = MAT.Metal },
		{ name = "Shaft", size = Vector3.new(0.45, 0.45, 3.8), cf = at(0, 0, 2.7), color = Color3.fromRGB(70, 50, 35), mat = MAT.Wood },
		{ name = "HammerHead", size = Vector3.new(3.2, 1.8, 1.8), cf = at(0, 0, 5.4), color = DARK_STEEL, mat = MAT.Metal, trail = { -1.6, 1.6, "X" } },
		{ name = "FaceFront", size = Vector3.new(0.3, 2, 2), cf = at(-1.75, 0, 5.4), color = GOLD, mat = MAT.Foil },
		{ name = "FaceBack", size = Vector3.new(0.3, 2, 2), cf = at(1.75, 0, 5.4), color = GOLD, mat = MAT.Foil },
		{ name = "RuneFront", size = Vector3.new(0.1, 0.8, 0.8), cf = at(-1.95, 0, 5.4), color = rune, mat = MAT.Neon, light = rune },
		{ name = "RuneBack", size = Vector3.new(0.1, 0.8, 0.8), cf = at(1.95, 0, 5.4), color = rune, mat = MAT.Neon },
		{ name = "TopSpike", size = Vector3.new(0.5, 0.5, 0.8), cf = at(0, 0, 6.7), color = DARK_STEEL, mat = MAT.Metal },
	}
end

local function scytheParts()
	local purple = Color3.fromRGB(170, 70, 255)
	local list = {
		{ name = "Handle", size = Vector3.new(0.35, 0.35, 1.6), cf = at(0, 0, 0), color = Color3.fromRGB(30, 25, 35), mat = MAT.Fabric },
		{ name = "Shaft", size = Vector3.new(0.35, 0.35, 5.6), cf = at(0, 0, 3.6), color = Color3.fromRGB(60, 40, 70), mat = MAT.Wood },
		{ name = "Wrap1", size = Vector3.new(0.42, 0.42, 0.15), cf = at(0, 0, 1.2), color = purple, mat = MAT.Neon },
		{ name = "Wrap2", size = Vector3.new(0.42, 0.42, 0.15), cf = at(0, 0, 5.8), color = purple, mat = MAT.Neon },
		{ name = "Skull", shape = Enum.PartType.Ball, size = Vector3.new(0.9, 0.9, 0.9), cf = at(0, 0, 6.8), color = Color3.fromRGB(230, 225, 210), mat = MAT.SmoothPlastic, light = purple },
		{ name = "BladeMount", size = Vector3.new(0.6, 0.3, 0.6), cf = at(-0.3, 0, 6.3), color = DARK_STEEL, mat = MAT.Metal },
	}
	-- ใบเคียวโค้งลง ต่อกันเป็นช่วง ๆ
	local x, z = -0.5, 6.3
	for i, seg in ipairs({ { 2.2, 0.75, 0 }, { 1.9, 0.65, 18 }, { 1.6, 0.5, 38 }, { 1.0, 0.35, 60 } }) do
		local len, width, deg = seg[1], seg[2], seg[3]
		local a = math.rad(deg)
		local dx, dz = -math.cos(a), -math.sin(a)
		local cx, cz = x + dx * len / 2, z + dz * len / 2
		local segCf = CFrame.new(cx, 0, cz) * CFrame.Angles(0, -a, 0)
		table.insert(list, { name = "Blade" .. i, size = Vector3.new(len + 0.1, 0.12, width), cf = segCf, color = Color3.fromRGB(60, 60, 72), mat = MAT.Metal, trail = (i == 2) and { -0.9, 0.9, "X" } or nil })
		table.insert(list, { name = "Edge" .. i, size = Vector3.new(len + 0.1, 0.14, 0.12), cf = segCf * CFrame.new(0, 0, -width / 2), color = purple, mat = MAT.Neon })
		x, z = x + dx * len, z + dz * len
	end
	return list
end

-- damage = ดาเมจ, range = ระยะ, cooldown = หน่วงระหว่างฟัน, arc = มุมด้านหน้า (-1 = รอบตัว)
local WEAPONS = {
	Iron = {
		name = "ดาบเหล็ก", damage = 25, range = 8, cooldown = 0.45, arc = 0.1, knockback = 15,
		color = STEEL, trailColor = Color3.fromRGB(220, 230, 255), anim = "Slash",
		parts = swordParts(STEEL, MAT.Metal, DARK_STEEL, Color3.fromRGB(230, 50, 50)),
	},
	Axe = {
		name = "ขวานนักรบ", price = 60, damage = 40, range = 8, cooldown = 0.7, arc = 0.2, knockback = 35,
		color = Color3.fromRGB(190, 120, 70), trailColor = Color3.fromRGB(255, 240, 220), anim = "Slash",
		parts = axeParts(),
	},
	Gold = {
		name = "ดาบทองคำ", price = 100, damage = 45, range = 9, cooldown = 0.4, arc = 0.1, knockback = 20,
		color = GOLD, trailColor = Color3.fromRGB(255, 220, 90), anim = "Slash",
		parts = swordParts(GOLD, MAT.Foil, Color3.fromRGB(255, 240, 150), Color3.fromRGB(60, 160, 255)),
	},
	Hammer = {
		name = "ค้อนยักษ์", price = 150, damage = 70, cooldown = 1.3, knockback = 90,
		aoe = { forward = 5, radius = 10 }, shockwave = true,
		color = Color3.fromRGB(80, 220, 255), trailColor = Color3.fromRGB(120, 230, 255), anim = "Lunge",
		parts = hammerParts(),
	},
	Scythe = {
		name = "เคียวยมทูต", price = 250, damage = 50, range = 13, cooldown = 0.8, arc = -1, knockback = 25, lifesteal = 0.2,
		color = Color3.fromRGB(170, 70, 255), trailColor = Color3.fromRGB(190, 110, 255), anim = "Slash",
		parts = scytheParts(),
	},
}
local SHOP_WEAPONS = { "Axe", "Gold", "Hammer", "Scythe" } -- เรียงตามราคา

-- สร้างชิ้นส่วนอาวุธ: anchored = true สำหรับโชว์บนเคาน์เตอร์, false สำหรับถือจริง (เชื่อมด้วย Weld)
local function buildWeaponParts(id, parent, baseCf, anchored)
	local def = WEAPONS[id]
	local handle
	for _, s in ipairs(def.parts) do
		local p = Instance.new("Part")
		p.Name = s.name
		if s.shape then
			p.Shape = s.shape
		end
		p.Size = s.size
		p.Color = s.color
		p.Material = s.mat
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = false
		p.Massless = true
		p.Anchored = anchored
		p.CFrame = baseCf * s.cf
		if s.name == "Handle" then
			handle = p
		elseif not anchored then
			local weld = Instance.new("Weld")
			weld.Part0 = handle
			weld.Part1 = p
			weld.C0 = s.cf
			weld.Parent = p
		end
		if s.light then
			pointLight(p, s.light, 8, 1)
		end
		if s.trail and not anchored then
			local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
			local axisX = s.trail[3] == "X"
			a0.Position = axisX and Vector3.new(s.trail[1], 0, 0) or Vector3.new(0, 0, s.trail[1])
			a1.Position = axisX and Vector3.new(s.trail[2], 0, 0) or Vector3.new(0, 0, s.trail[2])
			a0.Parent, a1.Parent = p, p
			local trail = Instance.new("Trail")
			trail.Attachment0, trail.Attachment1 = a0, a1
			trail.Color = ColorSequence.new(def.trailColor)
			trail.Transparency = NumberSequence.new(0.35, 1)
			trail.Lifetime = 0.18
			trail.LightEmission = 0.6
			trail.Parent = p
		end
		p.Parent = parent
	end
	return handle
end

-------------------------------------------------------------------------------
-- 1) ล้างของเดิม + แสง + ทีม
-------------------------------------------------------------------------------
local function reset()
	local old = workspace:FindFirstChild(CONFIG.MapName)
	if old then
		old:Destroy()
	end
	if CONFIG.RemoveBaseplate then
		for _, name in ipairs({ "Baseplate", "SpawnLocation" }) do
			local obj = workspace:FindFirstChild(name)
			if obj then
				obj:Destroy()
			end
		end
	end
	if CONFIG.ClearTerrain then
		terrain:Clear()
	end

	mapFolder = Instance.new("Folder")
	mapFolder.Name = CONFIG.MapName
	mapFolder.Parent = workspace
	monstersFolder = folder("Monsters")
end

local function effect(className, props)
	local e = Lighting:FindFirstChildOfClass(className) or Instance.new(className)
	for k, v in pairs(props) do
		e[k] = v
	end
	e.Parent = Lighting
	return e
end

local function setupLighting()
	-- ระบบแสงแบบ Future ให้เงาจากไฟทุกดวง (บางเวอร์ชันตั้งจากสคริปต์ไม่ได้ ดู README)
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)
	pcall(function()
		terrain.Decoration = true -- ใบหญ้าบนพื้น
	end)
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1 -- เงาสะท้อนบนผิววัตถุ

	if CONFIG.DarkTheme then
		-- 🌙 ธีมมืด: ป่าลึกยามโพล้เพล้ หมอกหนา แสงไฟเรืองรอง
		Lighting.ClockTime = 17.6
		Lighting.Brightness = 1.6
		Lighting.Ambient = Color3.fromRGB(25, 25, 35)
		Lighting.OutdoorAmbient = Color3.fromRGB(70, 78, 100)
		Lighting.ExposureCompensation = -0.15
		effect("Atmosphere", { Density = 0.42, Offset = 0.1, Haze = 2.2, Glare = 0.4, Color = Color3.fromRGB(140, 160, 185), Decay = Color3.fromRGB(55, 65, 90) })
		effect("ColorCorrectionEffect", { Brightness = -0.03, Contrast = 0.18, Saturation = -0.1, TintColor = Color3.fromRGB(220, 232, 255) })
		effect("BloomEffect", { Intensity = 0.9, Size = 36, Threshold = 1.1 })
		effect("SunRaysEffect", { Intensity = 0.12, Spread = 0.8 })
		effect("DepthOfFieldEffect", { FarIntensity = 0.12, FocusDistance = 80, InFocusRadius = 70, NearIntensity = 0 })
		terrain.WaterColor = Color3.fromRGB(20, 60, 75)
	else
		Lighting.ClockTime = 13
		Lighting.Brightness = 2.5
		Lighting.Ambient = Color3.fromRGB(70, 70, 70)
		Lighting.OutdoorAmbient = Color3.fromRGB(135, 135, 150)
		effect("Atmosphere", { Density = 0.32, Offset = 0, Haze = 1.2, Glare = 0, Color = Color3.fromRGB(199, 220, 255), Decay = Color3.fromRGB(106, 112, 125) })
		effect("BloomEffect", { Intensity = 0.6, Size = 30, Threshold = 1.5 })
		terrain.WaterColor = Color3.fromRGB(30, 120, 160)
	end

	-- 🌊 น้ำสะท้อนแสง
	terrain.WaterReflectance = 1
	terrain.WaterTransparency = 0.35
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 8

	-- ☁️ เมฆ
	local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = CONFIG.DarkTheme and 0.65 or 0.45
	clouds.Density = 0.5
	clouds.Color = CONFIG.DarkTheme and Color3.fromRGB(120, 125, 140) or Color3.new(1, 1, 1)
	clouds.Parent = terrain
end

-- หิ่งห้อย: อนุภาคเรืองแสงลอยในพื้นที่กล่อง
local function fireflies(parent, center, size, color, rate)
	local box = part({ Name = "Fireflies", Size = size, CFrame = CFrame.new(center), Transparency = 1, CanCollide = false, CanTouch = false, Parent = parent })
	local fx = Instance.new("ParticleEmitter")
	fx.Shape = Enum.ParticleEmitterShape.Box
	fx.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	fx.Color = ColorSequence.new(color or Color3.fromRGB(200, 255, 140))
	fx.LightEmission = 1
	fx.Size = NumberSequence.new(0.25)
	fx.Transparency = NumberSequence.new(0.1, 1)
	fx.Lifetime = NumberRange.new(3, 6)
	fx.Speed = NumberRange.new(0.5, 1.5)
	fx.SpreadAngle = Vector2.new(180, 180)
	fx.Rate = rate or 15
	fx.Parent = box
end

local TEAM_DEFS = {
	{ name = "ชาวเมือง", color = "Bright blue", auto = true },
	{ name = "อัศวิน", color = "Really red" },
	{ name = "พ่อค้า", color = "Bright yellow" },
	{ name = "นักผจญภัย", color = "Lime green" },
}

local function setupTeams()
	for _, def in ipairs(TEAM_DEFS) do
		if not Teams:FindFirstChild(def.name) then
			local team = Instance.new("Team")
			team.Name = def.name
			team.TeamColor = BrickColor.new(def.color)
			team.AutoAssignable = def.auto == true
			team.Parent = Teams
		end
	end
end

-- จุดเกิดสร้างก่อนสิ่งอื่น ผู้เล่นที่เข้ามาระหว่างสร้างแมพจะได้ไม่ร่วงลงไป
local function buildSpawn()
	local y = ZONE.Town.height + 1.2
	local spawn = part({
		ClassName = "SpawnLocation",
		Name = "TownSpawn",
		Size = Vector3.new(12, 1, 12),
		CFrame = CFrame.new(0, y + 0.5, 28),
		Color = Color3.fromRGB(0, 170, 255),
		Material = MAT.Neon,
		Neutral = true,
		Duration = 3,
	})
	billboardText(spawn, "🏘️ เมืองกลางเกาะ", Color3.fromRGB(180, 230, 255), 6)
end

-------------------------------------------------------------------------------
-- 2) สร้างภูมิประเทศ (Terrain) ด้วย WriteVoxels
-------------------------------------------------------------------------------
local function buildTerrain()
	local VOX = 4
	local Y0, Y1 = -24, TERRAIN_TOP
	local CHUNK = 128
	local ny = (Y1 - Y0) / VOX
	local n = CHUNK / VOX

	local done, total = 0, (2 * HALF / CHUNK) ^ 2

	-- ทะเลรอบนอกสุด
	terrain:FillBlock(CFrame.new(0, -8, 0), Vector3.new(HALF * 5, 16, HALF * 5), MAT.Water)

	for cx = -HALF, HALF - CHUNK, CHUNK do
		for cz = -HALF, HALF - CHUNK, CHUNK do
			local mats, occs = table.create(n), table.create(n)
			for ix = 1, n do
				local wx = cx + (ix - 0.5) * VOX
				local hcol, mcol = table.create(n), table.create(n)
				for iz = 1, n do
					local wz = cz + (iz - 0.5) * VOX
					local h = heightAt(wx, wz)
					hcol[iz] = h
					mcol[iz] = surfaceMaterial(h, wx, wz)
				end

				local mx, ox = table.create(ny), table.create(ny)
				for iy = 1, ny do
					local cy = Y0 + (iy - 0.5) * VOX
					local mrow, orow = table.create(n), table.create(n)
					for iz = 1, n do
						local h = hcol[iz]
						local o = (h - (cy - 2)) / VOX
						if o >= 1 then
							mrow[iz] = (h - cy > 12) and MAT.Rock or mcol[iz]
							orow[iz] = 1
						elseif o > 0 then
							if cy < SEA_LEVEL then
								-- ช่องใต้น้ำ เลือกเป็นดินหรือน้ำเต็มช่อง จะได้ไม่มีฟองอากาศ
								mrow[iz] = (o >= 0.5) and mcol[iz] or MAT.Water
								orow[iz] = 1
							else
								mrow[iz] = mcol[iz]
								orow[iz] = o
							end
						elseif cy < SEA_LEVEL then
							mrow[iz] = MAT.Water
							orow[iz] = 1
						else
							mrow[iz] = MAT.Air
							orow[iz] = 0
						end
					end
					mx[iy] = mrow
					ox[iy] = orow
				end
				mats[ix] = mx
				occs[ix] = ox
			end

			local region = Region3.new(Vector3.new(cx, Y0, cz), Vector3.new(cx + CHUNK, Y1, cz + CHUNK))
			terrain:WriteVoxels(region, VOX, mats, occs)
			done += 1
			if done % 36 == 0 then
				print(string.format("   ภูมิประเทศ %d%%", done * 100 // total))
			end
			task.wait() -- พักให้ Studio ไม่ค้าง
		end
	end
end

-------------------------------------------------------------------------------
-- 🏠 อาคาร
-------------------------------------------------------------------------------
-- ห้องสี่เหลี่ยมมีประตูด้านหน้า: cf = จุดกลางพื้นระดับดิน, ด้านหน้า = -Z
local function buildRoom(parent, cf, w, d, h, opt)
	opt = opt or {}
	local color = opt.wallColor or Color3.fromRGB(235, 225, 200)
	local mat = opt.material or MAT.SmoothPlastic
	local t = opt.thickness or 1
	local doorW, doorH = opt.doorWidth or 6, opt.doorHeight or 8

	local function wall(name, size, offset)
		return part({
			Name = name,
			Size = size,
			CFrame = cf * CFrame.new(offset),
			Color = color,
			Material = mat,
			Parent = parent,
		})
	end

	part({
		Name = "Floor",
		Size = Vector3.new(w, 1, d),
		CFrame = cf * CFrame.new(0, 0.5, 0),
		Color = opt.floorColor or Color3.fromRGB(150, 105, 70),
		Material = opt.floorMaterial or MAT.WoodPlanks,
		Parent = parent,
	})

	local y = 1 + h / 2
	local side = (w - doorW) / 2
	wall("BackWall", Vector3.new(w, h, t), Vector3.new(0, y, d / 2 - t / 2))
	wall("LeftWall", Vector3.new(t, h, d - 2 * t), Vector3.new(-w / 2 + t / 2, y, 0))
	wall("RightWall", Vector3.new(t, h, d - 2 * t), Vector3.new(w / 2 - t / 2, y, 0))
	wall("FrontLeft", Vector3.new(side, h, t), Vector3.new(-(doorW / 2 + side / 2), y, -d / 2 + t / 2))
	wall("FrontRight", Vector3.new(side, h, t), Vector3.new(doorW / 2 + side / 2, y, -d / 2 + t / 2))
	wall("FrontTop", Vector3.new(doorW, h - doorH, t), Vector3.new(0, 1 + doorH + (h - doorH) / 2, -d / 2 + t / 2))

	if opt.windows ~= false then
		local wy = 1 + h / 2 + 0.5
		local function window(size, offset)
			part({
				Name = "Window",
				Size = size,
				CFrame = cf * CFrame.new(offset),
				Color = Color3.fromRGB(170, 220, 255),
				Material = MAT.Glass,
				Transparency = 0.4,
				Parent = parent,
			})
		end
		for _, sx in ipairs({ -1, 1 }) do
			window(Vector3.new(t + 0.4, 4, 5), Vector3.new(sx * (w / 2 - t / 2), wy, 0))
			if side >= 6 then
				window(Vector3.new(4, 4, t + 0.4), Vector3.new(sx * (doorW / 2 + side / 2), wy, -d / 2 + t / 2))
			end
		end
	end
end

-- หลังคาจั่ว: baseCf = กึ่งกลางด้านบนของผนัง (ด้านลาดของ WedgePart หันไปทาง -Z)
local function gableRoof(parent, baseCf, w, d, rh, color)
	local half = d / 2 + 1
	for _, dir in ipairs({ -1, 1 }) do
		local cf = baseCf * CFrame.new(0, rh / 2, dir * half / 2)
		if dir == 1 then
			cf *= CFrame.Angles(0, math.pi, 0)
		end
		part({
			ClassName = "WedgePart",
			Name = "Roof",
			Size = Vector3.new(w + 2, rh, half),
			CFrame = cf,
			Color = color,
			Material = MAT.Slate,
			Parent = parent,
		})
	end
end

local WALL_COLORS = {
	Color3.fromRGB(245, 235, 210),
	Color3.fromRGB(230, 200, 170),
	Color3.fromRGB(210, 225, 235),
	Color3.fromRGB(240, 220, 225),
	Color3.fromRGB(220, 235, 210),
}
local ROOF_COLORS = {
	Color3.fromRGB(170, 60, 50),
	Color3.fromRGB(60, 90, 150),
	Color3.fromRGB(90, 70, 60),
	Color3.fromRGB(60, 120, 80),
}

local function buildHouse(parent, pos, facing, info)
	info = info or {}
	local w, d, h = 22, 20, 11
	local cf = CFrame.lookAt(pos, Vector3.new(facing.X, pos.Y, facing.Z))
	local house = model(info.label and ("Shop_" .. info.id) or "House", parent)

	buildRoom(house, cf, w, d, h, {
		wallColor = info.wallColor or WALL_COLORS[rng:NextInteger(1, #WALL_COLORS)],
	})
	gableRoof(house, cf * CFrame.new(0, 1 + h, 0), w, d, 6, info.roofColor or ROOF_COLORS[rng:NextInteger(1, #ROOF_COLORS)])

	if info.label then
		local sign = part({
			Name = "Sign",
			Size = Vector3.new(12, 2.2, 0.4),
			CFrame = cf * CFrame.new(0, 10.6, -d / 2 - 0.3),
			Color = Color3.fromRGB(70, 45, 30),
			Material = MAT.Wood,
			Parent = house,
		})
		surfaceText(sign, info.label, Color3.fromRGB(255, 230, 150))
		part({
			Name = "Counter",
			Size = Vector3.new(w - 8, 3, 2),
			CFrame = cf * CFrame.new(0, 2.5, 4),
			Color = Color3.fromRGB(120, 80, 50),
			Material = MAT.Wood,
			Parent = house,
		})
	else
		-- โต๊ะ + เก้าอี้ (นั่งได้) + เตียง
		part({
			Name = "Table",
			Size = Vector3.new(6, 0.5, 4),
			CFrame = cf * CFrame.new(0, 3.75, 3),
			Color = Color3.fromRGB(140, 95, 60),
			Material = MAT.Wood,
			Parent = house,
		})
		part({
			Name = "TableLeg",
			Size = Vector3.new(1, 2.5, 1),
			CFrame = cf * CFrame.new(0, 2.25, 3),
			Color = Color3.fromRGB(110, 75, 45),
			Material = MAT.Wood,
			Parent = house,
		})
		local tablePos = (cf * CFrame.new(0, 1.75, 3)).Position
		for _, sx in ipairs({ -1, 1 }) do
			local seatPos = (cf * CFrame.new(sx * 4.5, 1.75, 3)).Position
			part({
				ClassName = "Seat",
				Name = "Chair",
				Size = Vector3.new(2, 1, 2),
				CFrame = CFrame.lookAt(seatPos, tablePos),
				Color = Color3.fromRGB(160, 110, 70),
				Material = MAT.Wood,
				Parent = house,
			})
		end
		part({
			Name = "Bed",
			Size = Vector3.new(5, 1.5, 8),
			CFrame = cf * CFrame.new(-w / 2 + 4, 1.75, d / 2 - 5.5),
			Color = Color3.fromRGB(80, 110, 190),
			Material = MAT.Fabric,
			Parent = house,
		})
	end
	return house, cf
end

-------------------------------------------------------------------------------
-- 3) 🏘️ เมือง
-------------------------------------------------------------------------------
local SHOPS = {
	{ id = "Bakery", label = "🍞 ร้านขนมปัง" },
	{ id = "Weapons", label = "⚔️ ร้านอาวุธ" },
	{ id = "Inn", label = "🏨 โรงแรม" },
	{ id = "Hospital", label = "🏥 โรงพยาบาล", wallColor = Color3.fromRGB(250, 250, 250), roofColor = Color3.fromRGB(200, 50, 50) },
	{ id = "Potions", label = "🧪 ร้านยาวิเศษ" },
	{ id = "Fish", label = "🐟 ร้านปลา" },
	{ id = "Cafe", label = "☕ คาเฟ่" },
	{ id = "TownHall", label = "🏛️ ศาลากลาง", wallColor = Color3.fromRGB(235, 230, 220), roofColor = Color3.fromRGB(60, 60, 70) },
}

local function buildLamp(parent, pos)
	cylinder({
		Name = "LampPost",
		Position = pos + Vector3.new(0, 6, 0),
		Height = 12,
		Diameter = 0.8,
		Color = Color3.fromRGB(40, 40, 45),
		Material = MAT.Metal,
		Parent = parent,
	})
	local bulb = part({
		Name = "LampBulb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2, 2, 2),
		CFrame = CFrame.new(pos + Vector3.new(0, 12.5, 0)),
		Color = Color3.fromRGB(255, 220, 150),
		Material = MAT.Glass,
		Parent = parent,
	})
	local light = pointLight(bulb, Color3.fromRGB(255, 210, 140), 24, 2)
	light.Enabled = false
	table.insert(lampLights, { light = light, bulb = bulb })
end

local function buildFountain(parent, center)
	local marble = Color3.fromRGB(215, 215, 220)
	cylinder({ Name = "FountainBasin", Position = center + Vector3.new(0, 1, 0), Height = 2, Diameter = 22, Color = marble, Material = MAT.Marble, Parent = parent })
	cylinder({
		Name = "FountainWater",
		Position = center + Vector3.new(0, 2.1, 0),
		Height = 0.4,
		Diameter = 19,
		Color = Color3.fromRGB(80, 170, 230),
		Material = MAT.Glass,
		Transparency = 0.3,
		CanCollide = false,
		Parent = parent,
	})
	cylinder({ Name = "FountainPillar", Position = center + Vector3.new(0, 4.5, 0), Height = 7, Diameter = 3, Color = marble, Material = MAT.Marble, Parent = parent })
	local top = cylinder({ Name = "FountainTop", Position = center + Vector3.new(0, 8.5, 0), Height = 1, Diameter = 8, Color = marble, Material = MAT.Marble, Parent = parent })

	local spray = Instance.new("ParticleEmitter")
	spray.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(170, 220, 255))
	spray.Size = NumberSequence.new(0.6)
	spray.Transparency = NumberSequence.new(0.3)
	spray.Speed = NumberRange.new(10, 14)
	spray.SpreadAngle = Vector2.new(25, 25)
	spray.Acceleration = Vector3.new(0, -30, 0)
	spray.Lifetime = NumberRange.new(0.8, 1.1)
	spray.Rate = 60
	spray.EmissionDirection = Enum.NormalId.Right -- ทรงกระบอกถูกหมุน 90° ด้าน Right จึงชี้ขึ้นฟ้า
	spray.Parent = top
end

local function buildStall(parent, pos, facing, canopyColor)
	local cf = CFrame.lookAt(pos, Vector3.new(facing.X, pos.Y, facing.Z))
	local stall = model("MarketStall", parent)
	part({ Name = "Counter", Size = Vector3.new(8, 3, 3), CFrame = cf * CFrame.new(0, 1.5, 0), Color = Color3.fromRGB(140, 95, 60), Material = MAT.WoodPlanks, Parent = stall })
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			part({ Name = "Pole", Size = Vector3.new(0.4, 8, 0.4), CFrame = cf * CFrame.new(sx * 3.8, 4, sz * 2.5), Color = Color3.fromRGB(110, 75, 45), Material = MAT.Wood, Parent = stall })
		end
	end
	part({ Name = "Canopy", Size = Vector3.new(9, 0.4, 6.5), CFrame = cf * CFrame.new(0, 8.2, 0), Color = canopyColor, Material = MAT.Fabric, Parent = stall })
	local fruitColors = { Color3.fromRGB(230, 50, 40), Color3.fromRGB(255, 170, 30), Color3.fromRGB(120, 200, 60) }
	for i = 1, 5 do
		part({
			Name = "Fruit",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1, 1, 1),
			CFrame = cf * CFrame.new(-3.3 + i * 1.1, 3.5, 0),
			Color = fruitColors[i % 3 + 1],
			CanCollide = false,
			Parent = stall,
		})
	end
end

local function buildTown()
	local town = folder("Town")
	local Y = ZONE.Town.height -- ระดับผิวดินในเมือง

	-- ถนนหลัก 2 เส้นตัดกัน
	for _, size in ipairs({ Vector3.new(470, 1, 24), Vector3.new(24, 1, 470) }) do
		part({ Name = "Road", Size = size, CFrame = CFrame.new(0, Y + 0.5, 0), Color = Color3.fromRGB(70, 70, 75), Material = MAT.Asphalt, Parent = town })
	end

	-- ลานกลางเมือง + น้ำพุ
	local plazaTop = Y + 1.2
	part({ Name = "Plaza", Size = Vector3.new(90, 1.2, 90), CFrame = CFrame.new(0, Y + 0.6, 0), Color = Color3.fromRGB(190, 160, 130), Material = MAT.Brick, Parent = town })
	buildFountain(town, Vector3.new(0, plazaTop, 0))

	-- ม้านั่งรอบน้ำพุ
	for i = 0, 3 do
		local angle = math.rad(45 + i * 90)
		local pos = Vector3.new(math.cos(angle) * 20, plazaTop + 0.5, math.sin(angle) * 20)
		local cf = CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0))
		part({ ClassName = "Seat", Name = "Bench", Size = Vector3.new(5, 1, 2), CFrame = cf, Color = Color3.fromRGB(150, 100, 60), Material = MAT.Wood, Parent = town })
		part({ Name = "BenchBack", Size = Vector3.new(5, 2.5, 0.5), CFrame = cf * CFrame.new(0, 1.5, 1), Color = Color3.fromRGB(150, 100, 60), Material = MAT.Wood, Parent = town })
	end

	-- แผงตลาด
	local canopyColors = { Color3.fromRGB(220, 60, 60), Color3.fromRGB(60, 140, 220), Color3.fromRGB(240, 190, 40), Color3.fromRGB(80, 180, 90) }
	local stallSpots = { Vector2.new(-32, -15), Vector2.new(-32, 15), Vector2.new(32, -15), Vector2.new(32, 15) }
	for i, s in ipairs(stallSpots) do
		buildStall(town, Vector3.new(s.X, plazaTop, s.Y), Vector3.new(0, 0, s.Y), canopyColors[i])
	end

	-- แท่นเลือกอาชีพ (ทีม) 4 มุมลาน
	local corners = { Vector2.new(-35, -35), Vector2.new(35, -35), Vector2.new(-35, 35), Vector2.new(35, 35) }
	for i, def in ipairs(TEAM_DEFS) do
		local c = corners[i]
		local color = BrickColor.new(def.color).Color
		local pad = part({ Name = "TeamPad", Size = Vector3.new(8, 0.6, 8), CFrame = CFrame.new(c.X, plazaTop + 0.3, c.Y), Color = color, Material = MAT.Neon, Parent = town })
		pad:SetAttribute("TeamName", def.name)
		billboardText(pad, "เป็น " .. def.name, color, 4)
	end

	-- ทางเท้า ไฟถนน และบ้านสองข้างถนน
	local arms = { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }
	local shopIndex = 0
	for _, dir in ipairs(arms) do
		local perp = Vector3.new(dir.Z, 0, dir.X)
		for _, side in ipairs({ -1, 1 }) do
			local walkCenter = dir * 140 + perp * side * 15
			part({
				Name = "Sidewalk",
				Size = (dir.X ~= 0) and Vector3.new(190, 1.2, 6) or Vector3.new(6, 1.2, 190),
				CFrame = CFrame.new(walkCenter.X, Y + 0.6, walkCenter.Z),
				Color = Color3.fromRGB(175, 175, 180),
				Material = MAT.Concrete,
				Parent = town,
			})
			for _, dist in ipairs({ 50, 92, 137, 182, 226 }) do
				local p = dir * dist + perp * side * 14
				buildLamp(town, Vector3.new(p.X, plazaTop, p.Z))
			end
			for slot, dist in ipairs({ 70, 115, 160, 205 }) do
				local p = dir * dist + perp * side * 28
				local info
				if slot == 1 then
					shopIndex += 1
					info = SHOPS[shopIndex]
				end
				local house, cf = buildHouse(town, Vector3.new(p.X, Y, p.Z), dir * dist, info)
				if info and info.id == "Weapons" then
					-- แท่นซื้ออาวุธ 4 แบบ + ตัวอย่างอาวุธตั้งโชว์บนเคาน์เตอร์
					for i, id in ipairs(SHOP_WEAPONS) do
						local wdef = WEAPONS[id]
						local x = -6 + (i - 1) * 4
						local pad = part({ Name = "Buy_" .. id, Size = Vector3.new(3.4, 0.4, 3.4), CFrame = cf * CFrame.new(x, 1.2, -1), Color = wdef.color, Material = MAT.Neon, Parent = house })
						pad:SetAttribute("BuyWeapon", id)
						billboardText(pad, wdef.name .. "\n💰 " .. wdef.price, wdef.color, (i % 2 == 1) and 3 or 5.5, 6)
						buildWeaponParts(id, house, cf * CFrame.new(x, 5.2, 4) * CFrame.Angles(math.rad(-90), 0, 0), true)
					end
				elseif info and info.id == "Hospital" then
					local pad = part({ Name = "HealPad", Size = Vector3.new(6, 0.4, 6), CFrame = cf * CFrame.new(0, 1.2, 0), Color = Color3.fromRGB(90, 230, 120), Material = MAT.Neon, Parent = house })
					pad:SetAttribute("Heal", true)
					billboardText(pad, "💚 ยืนเพื่อฟื้นเลือด", Color3.fromRGB(150, 255, 170), 4)
				end
			end
		end
	end
end

-------------------------------------------------------------------------------
-- 4) 🏰 ปราสาท
-------------------------------------------------------------------------------
-- หลังคาทรงกรวยแบบขั้นบันได คืนค่าตำแหน่งยอด
local function coneRoof(parent, base, baseDia, color)
	local y, dia = base.Y, baseDia
	for _ = 1, 4 do
		cylinder({ Name = "TowerRoof", Position = Vector3.new(base.X, y + 1.5, base.Z), Height = 3, Diameter = dia, Color = color, Material = MAT.Slate, Parent = parent })
		y += 3
		dia *= 0.7
	end
	return Vector3.new(base.X, y, base.Z)
end

local function buildFlag(parent, base, color)
	cylinder({ Name = "FlagPole", Position = base + Vector3.new(0, 4, 0), Height = 8, Diameter = 0.4, Color = Color3.fromRGB(80, 80, 80), Material = MAT.Metal, Parent = parent })
	part({ Name = "Flag", Size = Vector3.new(0.2, 3, 5), CFrame = CFrame.new(base + Vector3.new(0, 6.5, 2.6)), Color = color, Material = MAT.Fabric, Parent = parent })
end

local function buildCastle()
	local castle = folder("Castle")
	local cx, cz = ZONE.Castle.x, ZONE.Castle.z
	local floorY = ZONE.Castle.height + 1
	local WH, T, HW = 24, 4, 60 -- ความสูงกำแพง, ความหนา, ครึ่งความกว้าง
	local stone = Color3.fromRGB(150, 150, 155)
	local wallTop = floorY + WH

	local function block(name, size, pos, color, material)
		return part({ Name = name, Size = size, CFrame = CFrame.new(pos), Color = color or stone, Material = material or MAT.Cobblestone, Parent = castle })
	end

	-- ลานกลางปราสาท
	block("Courtyard", Vector3.new(124, 1, 124), Vector3.new(cx, floorY - 0.5, cz), Color3.fromRGB(130, 130, 130))

	-- กำแพง 4 ด้าน (ด้านตะวันออกมีประตู หันหน้าไปทางเมือง)
	local wy = floorY + WH / 2
	block("WallNorth", Vector3.new(124, WH, T), Vector3.new(cx, wy, cz - HW))
	block("WallSouth", Vector3.new(124, WH, T), Vector3.new(cx, wy, cz + HW))
	block("WallWest", Vector3.new(T, WH, 116), Vector3.new(cx - HW, wy, cz))
	local GATE_W, GATE_H = 18, 16
	local segLen = (116 - GATE_W) / 2
	for _, s in ipairs({ -1, 1 }) do
		block("WallEast", Vector3.new(T, WH, segLen), Vector3.new(cx + HW, wy, cz + s * (GATE_W / 2 + segLen / 2)))
	end
	block("GateTop", Vector3.new(T, WH - GATE_H, GATE_W), Vector3.new(cx + HW, floorY + GATE_H + (WH - GATE_H) / 2, cz))

	-- ใบเสมาบนขอบนอกกำแพง (ทางเดินบนกำแพงยังเดินได้)
	for t = -57, 57, 6 do
		block("Merlon", Vector3.new(3, 3, 1.2), Vector3.new(cx + t, wallTop + 1.5, cz - HW - 1.4))
		block("Merlon", Vector3.new(3, 3, 1.2), Vector3.new(cx + t, wallTop + 1.5, cz + HW + 1.4))
		block("Merlon", Vector3.new(1.2, 3, 3), Vector3.new(cx - HW - 1.4, wallTop + 1.5, cz + t))
		block("Merlon", Vector3.new(1.2, 3, 3), Vector3.new(cx + HW + 1.4, wallTop + 1.5, cz + t))
	end

	-- บันไดขึ้นกำแพง (ชิดกำแพงทิศใต้ ด้านใน)
	for i = 1, 12 do
		block("Stairs", Vector3.new(3, i * 2, 6), Vector3.new(cx + 33 - i * 3, floorY + i, cz + HW - 5))
	end

	-- หอคอย 4 มุม
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local base = Vector3.new(cx + sx * HW, floorY, cz + sz * HW)
			cylinder({ Name = "Tower", Position = base + Vector3.new(0, 17, 0), Height = 34, Diameter = 16, Color = stone, Material = MAT.Cobblestone, Parent = castle })
			local tip = coneRoof(castle, base + Vector3.new(0, 34, 0), 19, Color3.fromRGB(150, 40, 45))
			buildFlag(castle, tip, Color3.fromRGB(200, 30, 40))
		end
	end

	-- ธงหน้าประตู
	for _, s in ipairs({ -1, 1 }) do
		block("Banner", Vector3.new(0.3, 12, 5), Vector3.new(cx + HW + 2.2, floorY + 13, cz + s * 15), Color3.fromRGB(180, 30, 40), MAT.Fabric)
	end

	-- ตัวปราสาทหลัก (ประตูหันไปทางทิศตะวันออก)
	local keepPos = Vector3.new(cx - 25, floorY - 0.95, cz)
	local keepCf = CFrame.lookAt(keepPos, keepPos + Vector3.new(1, 0, 0))
	local keep = model("Keep", castle)
	local KW, KD, KH = 44, 30, 22
	buildRoom(keep, keepCf, KW, KD, KH, {
		wallColor = Color3.fromRGB(170, 170, 175),
		material = MAT.Cobblestone,
		floorColor = Color3.fromRGB(230, 225, 215),
		floorMaterial = MAT.Marble,
		doorWidth = 10,
		doorHeight = 14,
		windows = false,
	})
	local roofY = 1 + KH
	part({ Name = "KeepRoof", Size = Vector3.new(KW + 2, 1, KD + 2), CFrame = keepCf * CFrame.new(0, roofY + 0.5, 0), Color = stone, Material = MAT.Cobblestone, Parent = keep })
	cylinder({ Name = "KeepTower", Position = (keepCf * CFrame.new(0, roofY + 9, 4)).Position, Height = 16, Diameter = 14, Color = stone, Material = MAT.Cobblestone, Parent = keep })
	local tip = coneRoof(keep, (keepCf * CFrame.new(0, roofY + 17, 4)).Position, 17, Color3.fromRGB(150, 40, 45))
	buildFlag(keep, tip, Color3.fromRGB(255, 200, 40))

	-- ห้องบัลลังก์
	local gold = Color3.fromRGB(255, 200, 40)
	part({ Name = "Carpet", Size = Vector3.new(6, 0.1, KD - 6), CFrame = keepCf * CFrame.new(0, 1.05, -1), Color = Color3.fromRGB(170, 20, 30), Material = MAT.Fabric, Parent = keep })
	part({ Name = "ThronePlatform", Size = Vector3.new(12, 1, 6), CFrame = keepCf * CFrame.new(0, 1.5, KD / 2 - 4), Color = Color3.fromRGB(120, 20, 30), Material = MAT.Fabric, Parent = keep })
	local throne = part({ ClassName = "Seat", Name = "Throne", Size = Vector3.new(4, 1, 4), CFrame = keepCf * CFrame.new(0, 2.5, KD / 2 - 4), Color = gold, Material = MAT.Foil, Parent = keep })
	part({ Name = "ThroneBack", Size = Vector3.new(4, 7, 1), CFrame = keepCf * CFrame.new(0, 6, KD / 2 - 1.8), Color = gold, Material = MAT.Foil, Parent = keep })
	billboardText(throne, "👑 บัลลังก์", Color3.fromRGB(255, 220, 90), 6)

	-- คบเพลิง + ธงในห้อง
	for _, sx in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -6, 6 }) do
			local torch = part({ Name = "Torch", Size = Vector3.new(0.6, 1.2, 0.6), CFrame = keepCf * CFrame.new(sx * (KW / 2 - 1.5), 9, z), Color = Color3.fromRGB(255, 140, 40), Material = MAT.Neon, Parent = keep })
			pointLight(torch, Color3.fromRGB(255, 150, 60), 22, 2)
			part({ Name = "WallBanner", Size = Vector3.new(0.2, 8, 3), CFrame = keepCf * CFrame.new(sx * (KW / 2 - 1.1), 12, z + (z > 0 and 4 or -4)), Color = Color3.fromRGB(170, 20, 30), Material = MAT.Fabric, Parent = keep })
		end
	end

	local sign = block("CastleSign", Vector3.new(1, 1, 1), Vector3.new(cx + HW + 3, floorY + 20, cz))
	sign.Transparency = 1
	sign.CanCollide = false
	billboardText(sign, "🏰 ปราสาทหลวง", Color3.fromRGB(255, 230, 150), 2)
end

-------------------------------------------------------------------------------
-- 5) ⚓ ท่าเรือ + ประภาคาร
-------------------------------------------------------------------------------
local function buildHarbor()
	local harbor = folder("Harbor")
	local hz = ZONE.Harbor
	local top = hz.height + 1
	local wood = Color3.fromRGB(150, 110, 70)

	part({ Name = "Boardwalk", Size = Vector3.new(80, 1, 70), CFrame = CFrame.new(hz.x, hz.height + 0.5, hz.z), Color = Color3.fromRGB(160, 120, 80), Material = MAT.WoodPlanks, Parent = harbor })
	part({ Name = "Pier", Size = Vector3.new(14, 1, 110), CFrame = CFrame.new(hz.x, hz.height + 0.5, hz.z + 85), Color = wood, Material = MAT.WoodPlanks, Parent = harbor })
	for z = hz.z + 40, hz.z + 136, 12 do
		for _, sx in ipairs({ -6, 6 }) do
			cylinder({ Name = "PierPost", Position = Vector3.new(hz.x + sx, -5.5, z), Height = 20, Diameter = 1.5, Color = Color3.fromRGB(100, 70, 45), Material = MAT.Wood, Parent = harbor })
		end
	end

	-- เรือใบ (นั่งที่พวงมาลัยได้)
	local boat = model("Boat", harbor)
	local bx, bz = hz.x + 20, hz.z + 115
	part({ Name = "Hull", Size = Vector3.new(10, 3, 30), CFrame = CFrame.new(bx, 1.5, bz), Color = Color3.fromRGB(120, 70, 40), Material = MAT.WoodPlanks, Parent = boat })
	for _, sx in ipairs({ -1, 1 }) do
		part({ Name = "HullSide", Size = Vector3.new(1, 3, 30), CFrame = CFrame.new(bx + sx * 5.5, 4.5, bz), Color = Color3.fromRGB(150, 40, 40), Material = MAT.Wood, Parent = boat })
	end
	part({ Name = "Mast", Size = Vector3.new(1, 22, 1), CFrame = CFrame.new(bx, 14, bz), Color = Color3.fromRGB(110, 75, 45), Material = MAT.Wood, Parent = boat })
	part({ Name = "Sail", Size = Vector3.new(0.3, 14, 16), CFrame = CFrame.new(bx + 0.7, 16, bz), Color = Color3.fromRGB(245, 240, 225), Material = MAT.Fabric, Parent = boat })
	part({ ClassName = "Seat", Name = "Helm", Size = Vector3.new(2, 1, 2), CFrame = CFrame.new(bx, 3.5, bz + 11), Color = Color3.fromRGB(110, 75, 45), Material = MAT.Wood, Parent = boat })

	-- ประภาคาร
	local lx, lz = hz.x + 42, hz.z + 52
	cylinder({ Name = "LighthouseRock", Position = Vector3.new(lx, -5, lz), Height = 20, Diameter = 18, Color = Color3.fromRGB(110, 110, 110), Material = MAT.Rock, Parent = harbor })
	for i = 0, 5 do
		cylinder({
			Name = "Lighthouse",
			Position = Vector3.new(lx, 5 + i * 6 + 3, lz),
			Height = 6,
			Diameter = 10 - i * 0.6,
			Color = (i % 2 == 0) and Color3.fromRGB(240, 240, 240) or Color3.fromRGB(210, 40, 40),
			Material = MAT.SmoothPlastic,
			Parent = harbor,
		})
	end
	local lamp = cylinder({ Name = "LighthouseLamp", Position = Vector3.new(lx, 43, lz), Height = 4, Diameter = 6, Color = Color3.fromRGB(255, 240, 180), Material = MAT.Neon, Parent = harbor })
	pointLight(lamp, Color3.fromRGB(255, 240, 180), 60, 3)
	cylinder({ Name = "LighthouseCap", Position = Vector3.new(lx, 46, lz), Height = 2, Diameter = 7, Color = Color3.fromRGB(210, 40, 40), Material = MAT.SmoothPlastic, Parent = harbor })

	-- ลังไม้ + ถังไม้
	for i = 1, 8 do
		local pos = Vector3.new(hz.x + rng:NextNumber(-36, -15), top, hz.z + rng:NextNumber(-28, 28))
		if i % 2 == 0 then
			part({ Name = "Crate", Size = Vector3.new(3, 3, 3), CFrame = CFrame.new(pos + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, rng:NextNumber(0, 1.5), 0), Color = Color3.fromRGB(170, 130, 80), Material = MAT.WoodPlanks, Parent = harbor })
		else
			cylinder({ Name = "Barrel", Position = pos + Vector3.new(0, 1.75, 0), Height = 3.5, Diameter = 2.5, Color = Color3.fromRGB(130, 85, 50), Material = MAT.Wood, Parent = harbor })
		end
	end

	local anchor = part({ Name = "HarborSign", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(hz.x, top + 8, hz.z - 30), Transparency = 1, CanCollide = false, Parent = harbor })
	billboardText(anchor, "⚓ ท่าเรือ", Color3.fromRGB(170, 220, 255), 2)
end

-------------------------------------------------------------------------------
-- 6) 💀 ซากปรักหักพัง + สุสาน
-------------------------------------------------------------------------------
local function buildChest(parent, pos, reward, label)
	local chest = model("TreasureChest", parent)
	local base = part({ Name = "ChestBase", Size = Vector3.new(4, 2.5, 3), CFrame = CFrame.new(pos + Vector3.new(0, 1.25, 0)), Color = Color3.fromRGB(120, 75, 35), Material = MAT.WoodPlanks, Parent = chest })
	part({ Name = "ChestLid", Size = Vector3.new(4.2, 1, 3.2), CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)), Color = Color3.fromRGB(255, 200, 40), Material = MAT.Foil, Parent = chest })
	base:SetAttribute("ChestReward", reward)
	local sparkle = Instance.new("Sparkles")
	sparkle.SparkleColor = Color3.fromRGB(255, 220, 90)
	sparkle.Parent = base
	billboardText(base, "💰 " .. label .. " (+" .. reward .. ")", Color3.fromRGB(255, 220, 90), 4)
end

local function buildRuins()
	local ruins = folder("Ruins")
	local r = ZONE.Ruins
	local center = Vector3.new(r.x, r.height, r.z)
	local stone = Color3.fromRGB(120, 115, 110)

	-- แผ่นหินแตก
	for _ = 1, 30 do
		local a, d = rng:NextNumber(0, math.pi * 2), rng:NextNumber(0, 34)
		part({
			Name = "BrokenTile",
			Size = Vector3.new(rng:NextNumber(4, 8), 0.8, rng:NextNumber(4, 8)),
			CFrame = CFrame.new(center + Vector3.new(math.cos(a) * d, 0.2, math.sin(a) * d))
				* CFrame.Angles(math.rad(rng:NextNumber(-4, 4)), rng:NextNumber(0, math.pi), math.rad(rng:NextNumber(-4, 4))),
			Color = stone,
			Material = MAT.Cobblestone,
			Parent = ruins,
		})
	end

	-- เสาหักเป็นวงกลม
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		local h = rng:NextNumber(4, 18)
		part({
			Name = "BrokenPillar",
			Size = Vector3.new(3, h, 3),
			CFrame = CFrame.new(center + Vector3.new(math.cos(a) * 28, h / 2, math.sin(a) * 28))
				* CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), 0, math.rad(rng:NextNumber(-6, 6))),
			Color = Color3.fromRGB(200, 195, 185),
			Material = MAT.Marble,
			Parent = ruins,
		})
	end

	-- หลุมศพ
	for gx = 0, 3 do
		for gz = 0, 3 do
			local p = center + Vector3.new(12 + gx * 8, 0, -44 + gz * 8)
			part({
				Name = "Tombstone",
				Size = Vector3.new(3, 4, 0.8),
				CFrame = CFrame.new(p + Vector3.new(0, 1.8, 0)) * CFrame.Angles(math.rad(rng:NextNumber(-10, 10)), 0, math.rad(rng:NextNumber(-8, 8))),
				Color = Color3.fromRGB(110, 110, 115),
				Material = MAT.Slate,
				Parent = ruins,
			})
		end
	end

	-- ต้นไม้ตาย
	for _ = 1, 6 do
		local a, d = rng:NextNumber(0, math.pi * 2), rng:NextNumber(38, 52)
		local p = groundPos(center.X + math.cos(a) * d, center.Z + math.sin(a) * d)
		part({
			Name = "DeadTree",
			Size = Vector3.new(1.5, 14, 1.5),
			CFrame = CFrame.new(p + Vector3.new(0, 6, 0)) * CFrame.Angles(math.rad(rng:NextNumber(-10, 10)), 0, math.rad(rng:NextNumber(-10, 10))),
			Color = Color3.fromRGB(70, 55, 45),
			Material = MAT.Wood,
			Parent = ruins,
		})
	end

	-- แท่นบูชากลาง + คริสตัลต้องสาป + หีบสมบัติ
	part({ Name = "Altar", Size = Vector3.new(10, 2, 10), CFrame = CFrame.new(center + Vector3.new(0, 1, 0)), Color = stone, Material = MAT.Slate, Parent = ruins })
	local cursed = part({
		Name = "CursedCrystal",
		Size = Vector3.new(2, 6, 2),
		CFrame = CFrame.new(center + Vector3.new(-3, 6, -3)) * CFrame.Angles(0, math.rad(45), math.rad(15)),
		Color = Color3.fromRGB(160, 60, 255),
		Material = MAT.Neon,
		Parent = ruins,
	})
	pointLight(cursed, Color3.fromRGB(160, 60, 255), 30, 2)
	billboardText(cursed, "💀 ซากปรักหักพัง", Color3.fromRGB(210, 170, 255), 6)
	buildChest(ruins, center + Vector3.new(2, 2, 2), 50, "หีบสุสาน")

	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		local kind = (i % 3 == 0) and "Ghost" or "Skeleton"
		table.insert(monsterSpawns, { kind = kind, pos = center + Vector3.new(math.cos(a) * 20, 0, math.sin(a) * 20) })
	end
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2 + 0.4
		table.insert(monsterSpawns, { kind = "Bat", pos = center + Vector3.new(math.cos(a) * 32, 0, math.sin(a) * 32) })
	end
end

-------------------------------------------------------------------------------
-- 7) 🏔️ ศาลเจ้าบนภูเขา
-------------------------------------------------------------------------------
local function buildShrine()
	local shrine = folder("MountainShrine")
	local x, z = SHRINE_POS.X, SHRINE_POS.Y
	local y = heightAt(x, z)
	local top = y + 1
	local red = Color3.fromRGB(200, 40, 30)
	part({ Name = "ShrineBase", Size = Vector3.new(26, 10, 26), CFrame = CFrame.new(x, y - 4, z), Color = Color3.fromRGB(140, 140, 150), Material = MAT.Slate, Parent = shrine })
	for _, sx in ipairs({ -1, 1 }) do
		part({ Name = "GatePillar", Size = Vector3.new(1.6, 14, 1.6), CFrame = CFrame.new(x + sx * 6, top + 7, z + 10), Color = red, Material = MAT.SmoothPlastic, Parent = shrine })
	end
	part({ Name = "GateBeam", Size = Vector3.new(18, 1.4, 2), CFrame = CFrame.new(x, top + 14.5, z + 10), Color = red, Material = MAT.SmoothPlastic, Parent = shrine })
	part({ Name = "GateBeam2", Size = Vector3.new(15, 1, 1.4), CFrame = CFrame.new(x, top + 12, z + 10), Color = red, Material = MAT.SmoothPlastic, Parent = shrine })
	local orb = part({ Name = "IceOrb", Shape = Enum.PartType.Ball, Size = Vector3.new(4, 4, 4), CFrame = CFrame.new(x, top + 9, z - 4), Color = Color3.fromRGB(120, 220, 255), Material = MAT.Neon, Parent = shrine })
	pointLight(orb, Color3.fromRGB(120, 220, 255), 40, 2)
	billboardText(orb, "🏔️ ศาลเจ้าน้ำแข็ง", Color3.fromRGB(190, 240, 255), 5)
	buildChest(shrine, Vector3.new(x, top, z - 4), 100, "หีบยอดเขา")

	for _, off in ipairs({ Vector2.new(50, 30), Vector2.new(-50, 30), Vector2.new(40, -40), Vector2.new(-40, -40) }) do
		table.insert(monsterSpawns, { kind = "Golem", pos = groundPos(x + off.X, z + off.Y) })
	end
	for _, off in ipairs({ Vector2.new(0, 45), Vector2.new(60, -10), Vector2.new(-60, -10) }) do
		table.insert(monsterSpawns, { kind = "Bat", pos = groundPos(x + off.X, z + off.Y) })
	end
end

-------------------------------------------------------------------------------
-- 🌀 จุดวาร์ป: ประตูวงกลมเรืองแสง แตะแล้วพาไปยังตำแหน่ง WarpTarget
-------------------------------------------------------------------------------
local WARPS = {} -- { name, color, landing } ใช้สร้างลานวาร์ปในเมือง
local WARP_HOME -- จุดโผล่ที่ลานวาร์ปในเมือง (ตั้งค่าใน buildWarpCircle)
local returnPortals = {} -- ประตู "กลับลานวาร์ป" ที่ยังไม่ได้ตั้งปลายทาง

local function buildPortal(parent, pos, color, label, target)
	local pad = cylinder({ Name = "Portal", Position = pos + Vector3.new(0, 0.4, 0), Height = 0.6, Diameter = 8, Color = color, Material = MAT.Neon, Transparency = 0.15, Parent = parent })
	if target then
		pad:SetAttribute("WarpTarget", target)
	end
	cylinder({ Name = "PortalRim", Position = pos + Vector3.new(0, 0.25, 0), Height = 0.5, Diameter = 10.5, Color = Color3.fromRGB(55, 55, 65), Material = MAT.Slate, Parent = parent })
	local gem = part({ Name = "PortalCrystal", Size = Vector3.new(1.4, 3, 1.4), CFrame = CFrame.new(pos + Vector3.new(0, 5, 0)) * CFrame.Angles(0, math.rad(45), 0), Color = color, Material = MAT.Neon, CanCollide = false, Parent = parent })
	pointLight(gem, color, 18, 1.5)
	local swirl = Instance.new("ParticleEmitter")
	swirl.Color = ColorSequence.new(color)
	swirl.LightEmission = 1
	swirl.Size = NumberSequence.new(0.4, 0)
	swirl.Transparency = NumberSequence.new(0, 1)
	swirl.Lifetime = NumberRange.new(1, 1.6)
	swirl.Speed = NumberRange.new(3, 5)
	swirl.SpreadAngle = Vector2.new(20, 20)
	swirl.Rate = 25
	swirl.EmissionDirection = Enum.NormalId.Right -- ทรงกระบอกถูกหมุน 90° ด้าน Right จึงชี้ขึ้น
	swirl.Parent = pad
	billboardText(gem, label, color, 3, 10)
	return pad
end

-- ลงทะเบียนจุดวาร์ป + สร้างประตูกลับเมืองข้างจุดโผล่
local function registerWarp(parent, name, color, landing, portalPos)
	table.insert(WARPS, { name = name, color = color, landing = landing })
	local pad = buildPortal(parent, portalPos, Color3.fromRGB(120, 200, 255), "🌀 กลับลานวาร์ป", nil)
	table.insert(returnPortals, pad)
end

local function buildWarpCircle()
	local circle = folder("WarpCircle")
	local center = Vector3.new(-110, ZONE.Town.height, -110)
	local top = center.Y + 1.2
	cylinder({ Name = "WarpPlaza", Position = center + Vector3.new(0, 0.6, 0), Height = 1.2, Diameter = 76, Color = Color3.fromRGB(70, 75, 90), Material = MAT.Slate, Parent = circle })
	cylinder({ Name = "WarpRing", Position = center + Vector3.new(0, 1.25, 0), Height = 0.1, Diameter = 60, Color = Color3.fromRGB(90, 170, 255), Material = MAT.Neon, Transparency = 0.6, Parent = circle })
	local core = part({ Name = "WarpCore", Size = Vector3.new(4, 12, 4), CFrame = CFrame.new(center + Vector3.new(0, 9, 0)) * CFrame.Angles(0, math.rad(45), math.rad(8)), Color = Color3.fromRGB(110, 190, 255), Material = MAT.Neon, CanCollide = false, Parent = circle })
	pointLight(core, Color3.fromRGB(110, 190, 255), 40, 2)
	billboardText(core, "🌀 ลานวาร์ป: เหยียบวงกลมเพื่อเดินทาง", Color3.fromRGB(170, 220, 255), 9, 22)

	WARP_HOME = Vector3.new(center.X + 12, top + 3, center.Z)
	for i, w in ipairs(WARPS) do
		local a = (i - 1) / #WARPS * math.pi * 2
		local pos = Vector3.new(center.X + math.cos(a) * 28, top, center.Z + math.sin(a) * 28)
		buildPortal(circle, pos, w.color, w.name, w.landing)
	end
	for _, pad in ipairs(returnPortals) do
		pad:SetAttribute("WarpTarget", WARP_HOME)
	end
end

-------------------------------------------------------------------------------
-- 🪵 ตัวช่วยสร้างของยาว ๆ (กิ่งไม้ เชือก สะพาน)
-------------------------------------------------------------------------------
-- ทรงกระบอกเชื่อมจุด a ไป b
local function limb(parent, a, b, dia, color, material, name)
	local len = (b - a).Magnitude
	return part({
		Name = name or "Limb",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(len + dia * 0.3, dia, dia),
		CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0),
		Color = color,
		Material = material,
		Parent = parent,
	})
end

-- 🌿 กิ่งไม้แตกแขนงแบบธรรมชาติ: กิ่งใหญ่แตกเป็นกิ่งเล็กลงเรื่อย ๆ ปลายกิ่งมีพุ่มใบ
--   opt = { bark, leafA, leafB, tuft = ขนาดพุ่มใบ, pieces, depth, firstSplit, lift = แรงชี้ขึ้นฟ้า }
local function growBranch(parent, p, dir, len, dia, depth, opt)
	local q = p + dir * len
	limb(parent, p, q, dia, opt.bark, MAT.Wood, "Branch")
	if depth <= 0 then
		leafClump(parent, q + dir * opt.tuft * 0.2, opt.tuft * rng:NextNumber(0.85, 1.15), opt.leafA, opt.leafB, false, opt.pieces)
		return
	end
	local n = (depth == opt.depth) and opt.firstSplit or 2
	local u = dir:Cross((math.abs(dir.Y) < 0.95) and Vector3.new(0, 1, 0) or Vector3.new(1, 0, 0)).Unit
	local v = dir:Cross(u)
	local spin = rng:NextNumber(0, math.pi * 2)
	for k = 1, n do
		local phi = spin + k / n * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
		local spread = math.rad(rng:NextNumber(28, 50))
		local side = u * math.cos(phi) + v * math.sin(phi)
		local nd = (dir * math.cos(spread) + side * math.sin(spread) + Vector3.new(0, opt.lift, 0)).Unit
		growBranch(parent, q, nd, len * rng:NextNumber(0.65, 0.8), dia * 0.65, depth - 1, opt)
	end
	-- พุ่มใบเล็กตามข้อกิ่ง ให้ทรงพุ่มดูเต็ม
	if depth == 1 and (opt.nodeTufts or CONFIG.LeafDetail >= 3) then
		leafClump(parent, q, opt.tuft * 0.7, opt.leafA, opt.leafB, false, opt.pieces)
	end
end

-- ต้นไม้ทรงธรรมชาติ: ลำต้นเอียงคดเล็กน้อย รากแผ่ แตกกิ่งเป็นทอด ๆ
local function naturalTree(parent, name, pos, cfg)
	local tree = model(name, parent)
	local h = rng:NextNumber(cfg.height[1], cfg.height[2])
	local d = rng:NextNumber(cfg.width[1], cfg.width[2])
	local lean = Vector3.new(rng:NextNumber(-0.12, 0.12), 1, rng:NextNumber(-0.12, 0.12)).Unit
	local mid = pos + lean * h * 0.55
	local bend = (lean + Vector3.new(rng:NextNumber(-0.18, 0.18), 0, rng:NextNumber(-0.18, 0.18))).Unit
	local top = mid + bend * h * 0.45
	limb(tree, pos - Vector3.new(0, 1.5, 0), mid, d, cfg.bark, MAT.Wood, "Trunk")
	limb(tree, mid, top, d * 0.78, cfg.bark, MAT.Wood, "Trunk")
	for k = 1, cfg.roots or 0 do
		local a = k / cfg.roots * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		limb(tree, pos + Vector3.new(0, d * 0.9, 0), pos + Vector3.new(math.cos(a) * d * 1.5, -0.5, math.sin(a) * d * 1.5), d * 0.42, cfg.bark, MAT.Wood, "Root")
	end
	-- LeafDetail = 1: แตกกิ่งน้อยลงหนึ่งทอด แต่พุ่มใบใหญ่ขึ้น (เบาเครื่อง)
	local depth = (CONFIG.LeafDetail <= 1) and math.max(1, cfg.depth - 1) or cfg.depth
	local tuft = (depth < cfg.depth) and cfg.tuft * 1.4 or cfg.tuft
	local opt = { bark = cfg.bark, leafA = cfg.leafA, leafB = cfg.leafB, tuft = tuft, pieces = cfg.pieces, depth = depth, firstSplit = 3, lift = 0.35 }
	-- กิ่งข้างกลางลำต้น
	if CONFIG.LeafDetail >= 3 then
		local a = rng:NextNumber(0, math.pi * 2)
		local sideDir = (Vector3.new(math.cos(a), 0.9, math.sin(a))).Unit
		growBranch(tree, mid, sideDir, h * 0.28, d * 0.45, 1, opt)
	end
	growBranch(tree, top, bend, h * 0.25, d * 0.6, depth, opt)
	return tree
end

-- เส้นเชือก/คานสี่เหลี่ยมบาง ๆ เชื่อมจุด a ไป b
local function rope(parent, a, b, thick, color)
	return part({
		Name = "Rope",
		Size = Vector3.new(thick or 0.3, thick or 0.3, (b - a).Magnitude),
		CFrame = CFrame.lookAt((a + b) / 2, b),
		Color = color or Color3.fromRGB(150, 120, 80),
		Material = MAT.Fabric,
		CanCollide = false,
		Parent = parent,
	})
end

-- สะพานไม้ห้อยโค้งลงตรงกลาง
local function plankBridge(parent, a, b, width, sag)
	local dist = (b - a).Magnitude
	local n = math.ceil(dist / 1.6)
	local prev
	for i = 0, n do
		local t = i / n
		local p = a:Lerp(b, t) - Vector3.new(0, math.sin(t * math.pi) * sag, 0)
		if prev then
			part({
				Name = "Plank",
				Size = Vector3.new(width, 0.4, (p - prev).Magnitude + 0.2),
				CFrame = CFrame.lookAt((p + prev) / 2, p),
				Color = Color3.fromRGB(140 + (i % 3) * 8, 100, 65),
				Material = MAT.WoodPlanks,
				Parent = parent,
			})
		end
		prev = p
	end
	local dir = (b - a).Unit
	local side = dir:Cross(Vector3.new(0, 1, 0)).Unit * (width / 2)
	for _, s in ipairs({ -1, 1 }) do
		rope(parent, a + side * s + Vector3.new(0, 2.8, 0), b + side * s + Vector3.new(0, 2.8, 0), 0.25)
	end
end

local function lantern(parent, pos, color, withLight)
	part({ Name = "LanternHook", Size = Vector3.new(0.15, 1, 0.15), CFrame = CFrame.new(pos + Vector3.new(0, 0.9, 0)), Color = Color3.fromRGB(60, 50, 40), Material = MAT.Metal, CanCollide = false, Parent = parent })
	local l = part({ Name = "Lantern", Shape = Enum.PartType.Ball, Size = Vector3.new(1.1, 1.1, 1.1), CFrame = CFrame.new(pos), Color = color, Material = MAT.Neon, CanCollide = false, Parent = parent })
	if withLight then
		pointLight(l, color, 16, 1.4)
	end
	return l
end

-------------------------------------------------------------------------------
-- 🌳 ต้นไม้โลก + หมู่บ้านเอลฟ์
-------------------------------------------------------------------------------
local ELF_WALL = Color3.fromRGB(235, 232, 220)
local ELF_ROOF = Color3.fromRGB(45, 120, 115)
local ELF_GOLD = Color3.fromRGB(230, 190, 90)
local ELF_GLOW = Color3.fromRGB(140, 240, 220)
local BARK = Color3.fromRGB(78, 58, 46)
local BARK_DARK = Color3.fromRGB(58, 42, 36)
local LEAF_A = Color3.fromRGB(35, 85, 65)
local LEAF_B = Color3.fromRGB(60, 118, 78)

local function trunkRadius(y)
	return 30 - 15 * math.clamp(y / 180, 0, 1)
end

-- บ้านเอลฟ์: ผนังขาว หลังคาเขียวอมฟ้า ขอบทอง โคมไฟข้างใน
local function buildElfHouse(parent, cf)
	local house = model("ElfHouse", parent)
	buildRoom(house, cf, 12, 10, 9, { wallColor = ELF_WALL, material = MAT.Marble, floorColor = Color3.fromRGB(170, 130, 90), doorWidth = 4, doorHeight = 7 })
	gableRoof(house, cf * CFrame.new(0, 10, 0), 12, 10, 5, ELF_ROOF)
	part({ Name = "RoofTrim", Size = Vector3.new(14.2, 0.4, 0.4), CFrame = cf * CFrame.new(0, 15, 0), Color = ELF_GOLD, Material = MAT.Foil, Parent = house })
	for _, sx in ipairs({ -1, 1 }) do
		part({ Name = "DoorFrame", Size = Vector3.new(0.4, 7.4, 0.4), CFrame = cf * CFrame.new(sx * 2.2, 4.7, -5.2), Color = ELF_GOLD, Material = MAT.Foil, Parent = house })
	end
	local lamp = part({ Name = "HouseLamp", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2), CFrame = cf * CFrame.new(0, 8.5, 1), Color = Color3.fromRGB(255, 220, 150), Material = MAT.Neon, CanCollide = false, Parent = house })
	pointLight(lamp, Color3.fromRGB(255, 210, 150), 16, 1.2)
	-- กระบะดอกไม้ใต้หน้าต่าง
	for _, sx in ipairs({ -1, 1 }) do
		local box = cf * CFrame.new(sx * 6.6, 3.6, 0)
		part({ Name = "FlowerBox", Size = Vector3.new(0.8, 0.6, 4), CFrame = box, Color = Color3.fromRGB(120, 85, 55), Material = MAT.Wood, Parent = house })
		for k = -1, 1 do
			part({ Name = "Flower", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6), CFrame = box * CFrame.new(0, 0.5, k * 1.2), Color = ({ Color3.fromRGB(255, 120, 190), Color3.fromRGB(250, 230, 120), Color3.fromRGB(150, 200, 255) })[k + 2], Material = MAT.Neon, CanCollide = false, Parent = house })
		end
	end
	return house
end

-- บ้านรูปผลไม้ห้อยจากกิ่ง (ตกแต่ง)
local function elfPod(parent, anchor, drop)
	local pos = anchor - Vector3.new(0, drop, 0)
	rope(parent, anchor, pos + Vector3.new(0, 3.2, 0), 0.3)
	local pod = model("ElfPod", parent)
	part({ Name = "PodBody", Shape = Enum.PartType.Ball, Size = Vector3.new(7, 7, 7), CFrame = CFrame.new(pos), Color = Color3.fromRGB(150, 110, 75), Material = MAT.Wood, Parent = pod })
	coneRoof(pod, pos + Vector3.new(0, 2.5, 0), 8, ELF_ROOF)
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2
		part({ Name = "PodWindow", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2), CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 3.1, 0.3, math.sin(a) * 3.1)), Color = Color3.fromRGB(255, 210, 130), Material = MAT.Neon, CanCollide = false, Parent = pod })
	end
	pointLight(pod:FindFirstChild("PodBody"), Color3.fromRGB(255, 200, 130), 14, 1)
end

local function buildWorldTree()
	local tree = folder("WorldTree")
	local WT = ZONE.WorldTree
	local base = Vector3.new(WT.x, WT.height, WT.z)
	local function ring(angleDeg, radius, y)
		local a = math.rad(angleDeg)
		return base + Vector3.new(math.cos(a) * radius, y, math.sin(a) * radius)
	end
	local function facingTrunk(pos)
		return CFrame.lookAt(pos, Vector3.new(base.X, pos.Y, base.Z))
	end

	-- ลำต้น 9 ท่อนเรียวขึ้น + สันเปลือกไม้ + รูนเรืองแสง
	for i = 0, 8 do
		cylinder({ Name = "Trunk", Position = base + Vector3.new(0, i * 20 + 10, 0), Height = 22, Diameter = trunkRadius(i * 20 + 10) * 2 + 1, Color = BARK, Material = MAT.Wood, Parent = tree })
	end
	-- ปุ่มเปลือกไม้ขรุขระ ช่วยลบรอยต่อของลำต้น
	for _ = 1, 90 do
		local y = rng:NextNumber(2, 178)
		local ang = rng:NextNumber(0, 360)
		local p = ring(ang, trunkRadius(y) + 0.3, y)
		part({ Name = "BarkKnot", Size = Vector3.new(rng:NextNumber(3, 7), rng:NextNumber(4, 12), 1.6), CFrame = facingTrunk(p) * CFrame.Angles(0, 0, rng:NextNumber(-0.5, 0.5)), Color = BARK:Lerp(BARK_DARK, rng:NextNumber()), Material = MAT.Wood, Parent = tree })
	end
	for k = 0, 17 do
		local ang = k * 20 + rng:NextNumber(-6, 6)
		limb(tree, ring(ang, trunkRadius(0) + 0.5, 0), ring(ang + rng:NextNumber(-15, 15), trunkRadius(180) + 0.5, 180), rng:NextNumber(2.5, 4.5), BARK_DARK, MAT.Wood, "BarkRidge")
	end
	for _ = 1, 26 do
		local y = rng:NextNumber(8, 170)
		local ang = rng:NextNumber(0, 360)
		local p = ring(ang, trunkRadius(y) + 0.6, y)
		part({ Name = "Rune", Size = Vector3.new(0.3, rng:NextNumber(1.5, 4), 0.3), CFrame = facingTrunk(p) * CFrame.Angles(0, 0, rng:NextNumber(-0.6, 0.6)), Color = ELF_GLOW, Material = MAT.Neon, CanCollide = false, Parent = tree })
	end
	task.wait()

	-- รากใหญ่แผ่ออก (เว้นช่วงมุม 0-70° ที่บันไดเริ่ม)
	for ang = 85, 355, 30 do
		local a = ring(ang, trunkRadius(0) - 4, 7)
		local b = ring(ang + rng:NextNumber(-8, 8), trunkRadius(0) + 42, -3)
		limb(tree, a, b, 8, BARK, MAT.Wood, "Root")
		limb(tree, a:Lerp(b, 0.5), ring(ang + 18, trunkRadius(0) + 30, -3), 4, BARK_DARK, MAT.Wood, "RootBranch")
	end

	-- ลานรอบลำต้น 3 ชั้น + บันไดวนขึ้น
	local DECKS = { 40, 85, 130 }
	local deckTopY = {}
	for di, dy in ipairs(DECKS) do
		local rIn = trunkRadius(dy) + 0.5
		local rMid = rIn + 7
		for k = 0, 35 do
			local ang = k * 10 + 5
			if ang < 290 then -- เว้นช่องให้บันไดที่ขึ้นมาจากชั้นล่าง
				local p = ring(ang, rMid, dy)
				part({ Name = "Deck", Size = Vector3.new(rMid * math.rad(10) + 0.8, 1, 14), CFrame = facingTrunk(p), Color = Color3.fromRGB(150, 110, 72), Material = MAT.WoodPlanks, Parent = tree })
				if k % 3 == 0 then
					local post = ring(ang, rIn + 13.5, dy)
					cylinder({ Name = "RailPost", Position = post + Vector3.new(0, 2, 0), Height = 3.5, Diameter = 0.5, Color = ELF_GOLD, Material = MAT.Wood, Parent = tree })
					if k % 6 == 0 then
						lantern(tree, post + Vector3.new(0, 4.8, 0), (k % 12 == 0) and ELF_GLOW or Color3.fromRGB(255, 210, 140), k % 12 == 0)
					end
				end
			end
		end
		deckTopY[di] = base.Y + dy + 0.5

		-- ระเบียงยื่นออกไป + บ้านเอลฟ์ 3 หลังต่อชั้น
		for _, ang in ipairs({ 20, 140, 250 }) do
			local bc = ring(ang, rIn + 14 + 9, dy)
			local bcf = facingTrunk(bc)
			part({ Name = "Balcony", Size = Vector3.new(18, 1, 18), CFrame = bcf, Color = Color3.fromRGB(150, 110, 72), Material = MAT.WoodPlanks, Parent = tree })
			limb(tree, ring(ang, trunkRadius(dy - 14), dy - 14), ring(ang, rIn + 26, dy - 0.5), 1.4, BARK, MAT.Wood, "Strut")
			buildElfHouse(tree, bcf * CFrame.new(0, 0.5, 2))
		end

		-- บันไดวนจากชั้นล่าง (หรือพื้นดิน) ขึ้นมาที่ชั้นนี้
		local fromY = (di == 1) and 0 or DECKS[di - 1]
		for sIdx = 0, 71 do
			local y = fromY + (dy - fromY) * sIdx / 72
			local ang = sIdx * 5
			local r = trunkRadius(y) + 7
			local p = ring(ang, r, y)
			part({ Name = "Stair", Size = Vector3.new(r * math.rad(5) + 0.7, 1, 6), CFrame = facingTrunk(p), Color = Color3.fromRGB(135, 98, 62), Material = MAT.WoodPlanks, Parent = tree })
			if sIdx % 4 == 0 then
				cylinder({ Name = "StairPost", Position = ring(ang, r + 3.2, y + 1.8), Height = 3, Diameter = 0.35, Color = ELF_GOLD, Material = MAT.Wood, Parent = tree })
			end
			if sIdx % 18 == 9 then
				lantern(tree, ring(ang, r + 3.2, y + 4), ELF_GLOW, true)
			end
		end
		task.wait()
	end

	-- กิ่งใหญ่ + พุ่มใบ + เถาวัลย์ + บ้านห้อยกิ่ง
	local BRIDGE_ANGLES = { [80] = true, [190] = true }
	local branchTips = {}
	for _, br in ipairs({ { 80, 158 }, { 190, 156 }, { 10, 150 }, { 130, 165 }, { 240, 152 }, { 290, 168 }, { 335, 160 }, { 160, 176 }, { 265, 177 } }) do
		local ang, y = br[1], br[2]
		local dir = Vector3.new(math.cos(math.rad(ang)), 0, math.sin(math.rad(ang)))
		local p = base + Vector3.new(0, y, 0) + dir * trunkRadius(y) * 0.8
		local segs = { { 32, 0.25, 10 }, { 30, 0.05, 7.5 }, { 26, -0.12, 5 } }
		for si, sg in ipairs(segs) do
			local q = p + (dir + Vector3.new(0, sg[2], 0)).Unit * sg[1]
			limb(tree, p, q, sg[3], BARK, MAT.Wood, "Branch")
			-- เถาวัลย์ห้อย ปลายเรืองแสง
			if si >= 2 then
				for _ = 1, 2 do
					local top = p:Lerp(q, rng:NextNumber(0.2, 0.9))
					local len = rng:NextNumber(10, 24)
					part({ Name = "Vine", Size = Vector3.new(0.35, len, 0.35), CFrame = CFrame.new(top - Vector3.new(0, len / 2, 0)), Color = Color3.fromRGB(45, 95, 55), Material = MAT.Grass, CanCollide = false, Parent = tree })
					part({ Name = "VineGlow", Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.8, 0.8), CFrame = CFrame.new(top - Vector3.new(0, len, 0)), Color = ELF_GLOW, Material = MAT.Neon, CanCollide = false, Parent = tree })
				end
			end
			p = q
		end
		-- ปลายกิ่งแตกแขนงต่อ แล้วมีพุ่มใบที่ปลายกิ่งย่อย (เดินทะลุได้)
		growBranch(tree, p, (dir + Vector3.new(0, 0.35, 0)).Unit, 16, 3.6, 2, { bark = BARK, leafA = LEAF_A, leafB = LEAF_B, tuft = 20, depth = 2, firstSplit = 3, lift = 0.3, nodeTufts = true })
		for _ = 1, 4 do
			part({ Name = "SpiritLight", Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(p + Vector3.new(rng:NextNumber(-14, 14), rng:NextNumber(-12, 0), rng:NextNumber(-14, 14))), Color = ELF_GLOW, Material = MAT.Neon, CanCollide = false, Parent = tree })
		end
		pointLight(tree:GetChildren()[#tree:GetChildren()], ELF_GLOW, 24, 1)
		if not BRIDGE_ANGLES[ang] then
			elfPod(tree, p - dir * 8 - Vector3.new(0, 3, 0), rng:NextNumber(9, 14))
		end
		branchTips[ang] = { dir = dir, y = y }
	end
	task.wait()

	-- ลานห้อยจากกิ่ง + สะพานเชือกจากชั้นบนสุด
	local topDeck = DECKS[3]
	for ang in pairs(BRIDGE_ANGLES) do
		local dir = branchTips[ang].dir
		local center = base + Vector3.new(0, topDeck, 0) + dir * 75
		local pcf = facingTrunk(center)
		part({ Name = "HangingPlatform", Size = Vector3.new(18, 1, 18), CFrame = pcf, Color = Color3.fromRGB(150, 110, 72), Material = MAT.WoodPlanks, Parent = tree })
		local anchor = base + Vector3.new(0, branchTips[ang].y + 9, 0) + dir * 75
		for _, c in ipairs({ Vector3.new(-8.5, 0, -8.5), Vector3.new(8.5, 0, -8.5), Vector3.new(-8.5, 0, 8.5), Vector3.new(8.5, 0, 8.5) }) do
			rope(tree, (pcf * CFrame.new(c)).Position, anchor, 0.35)
		end
		buildElfHouse(tree, pcf * CFrame.new(0, 0.5, 2))
		lantern(tree, (pcf * CFrame.new(7, 3.5, -7)).Position, Color3.fromRGB(255, 210, 140), true)
		local from = base + Vector3.new(0, topDeck + 0.5, 0) + dir * (trunkRadius(topDeck) + 14.2)
		local to = center + Vector3.new(0, 0.5, 0) - dir * 9
		plankBridge(tree, from, to, 5, 2.5)
	end

	-- บันไดปีนเถาวัลย์ (TrussPart) จากชั้นบนสุดขึ้นยอดต้นไม้
	local topY = 180
	local trussPos = ring(45, trunkRadius(topDeck) + 5, (topDeck + topY) / 2 + 1)
	part({ ClassName = "TrussPart", Name = "VineLadder", Size = Vector3.new(2, topY - topDeck + 2, 2), CFrame = CFrame.new(trussPos), Color = Color3.fromRGB(70, 120, 60), Material = MAT.Grass, Parent = tree })

	-- 💚 ยอดต้นไม้: ลานหัวใจต้นไม้โลก
	local crown = base + Vector3.new(0, topY, 0)
	cylinder({ Name = "CrownPlatform", Position = crown + Vector3.new(0, 1, 0), Height = 2, Diameter = 46, Color = Color3.fromRGB(150, 110, 72), Material = MAT.WoodPlanks, Parent = tree })
	local heart = part({ Name = "HeartOfWorldTree", Size = Vector3.new(4, 10, 4), CFrame = CFrame.new(crown + Vector3.new(0, 8, 0)) * CFrame.Angles(0, math.rad(45), 0), Color = Color3.fromRGB(120, 255, 170), Material = MAT.Neon, Parent = tree })
	pointLight(heart, Color3.fromRGB(120, 255, 170), 60, 2.5)
	local sparkle = Instance.new("Sparkles")
	sparkle.SparkleColor = Color3.fromRGB(150, 255, 200)
	sparkle.Parent = heart
	billboardText(heart, "💚 หัวใจต้นไม้โลก", Color3.fromRGB(170, 255, 200), 7, 16)
	buildChest(tree, crown + Vector3.new(-9, 2, -9), 150, "หีบต้นไม้โลก")
	for k = 0, 11 do
		local a = k * 30
		local s = rng:NextNumber(40, 60)
		leafClump(tree, ring(a, rng:NextNumber(42, 60), topY + rng:NextNumber(18, 34)), s, LEAF_A, LEAF_B, false)
	end

	fireflies(tree, base + Vector3.new(0, 50, 0), Vector3.new(320, 100, 320), Color3.fromRGB(180, 255, 200), 45)

	registerWarp(tree, "🌳 ต้นไม้โลก", Color3.fromRGB(120, 230, 160), groundPos(WT.x - 80, WT.z, 4), groundPos(WT.x - 92, WT.z))
	registerWarp(tree, "🧝 หมู่บ้านเอลฟ์ (ยอดต้นไม้)", ELF_GLOW, crown + Vector3.new(10, 5, 6), crown + Vector3.new(10, 2, -10))

	for i = 1, 4 do
		local a = i / 4 * math.pi * 2
		table.insert(monsterSpawns, { kind = "EvilEye", pos = groundPos(WT.x + math.cos(a) * 200, WT.z + math.sin(a) * 200) })
	end
end

-------------------------------------------------------------------------------
-- 👺 ค่ายก็อบลิน
-------------------------------------------------------------------------------
local function campfire(parent, pos, big)
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		part({ Name = "FireStone", Size = Vector3.new(1.4, 0.9, 1.4), CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 2.4, 0.4, math.sin(a) * 2.4)) * CFrame.Angles(0, a, 0), Color = Color3.fromRGB(90, 90, 95), Material = MAT.Rock, Parent = parent })
	end
	for k = 0, 2 do
		part({ Name = "FireLog", Size = Vector3.new(0.7, 0.7, 3.4), CFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, k * 1.05, 0.2), Color = Color3.fromRGB(70, 45, 30), Material = MAT.Wood, Parent = parent })
	end
	local core = part({ Name = "Embers", Size = Vector3.new(1.5, 0.5, 1.5), CFrame = CFrame.new(pos + Vector3.new(0, 0.8, 0)), Color = Color3.fromRGB(255, 120, 30), Material = MAT.Neon, CanCollide = false, Parent = parent })
	local fire = Instance.new("Fire")
	fire.Size = big and 8 or 5
	fire.Heat = 9
	fire.Parent = core
	pointLight(core, Color3.fromRGB(255, 140, 60), big and 36 or 24, 2)
end

local function buildGoblinCamp()
	local camp = folder("GoblinCamp")
	local gc = ZONE.GoblinCamp
	local center = Vector3.new(gc.x, gc.height, gc.z)
	local gateAngle = math.deg(math.atan2(-center.Z, -center.X)) -- ประตูหันไปทางเมือง

	-- รั้วไม้ปลายแหลม
	for deg = 0, 359, 3 do
		local diff = math.abs(((deg - gateAngle + 180) % 360) - 180)
		if diff > 12 then
			local a = math.rad(deg)
			local h = rng:NextNumber(9, 12)
			local p = center + Vector3.new(math.cos(a) * 58, h / 2 - 1, math.sin(a) * 58)
			cylinder({ Name = "Palisade", Position = p, Height = h, Diameter = 2.6, Color = Color3.fromRGB(95, 70, 45), Material = MAT.Wood, Parent = camp })
			part({ Name = "Spike", Size = Vector3.new(1.2, 1.6, 1.2), CFrame = CFrame.new(p + Vector3.new(0, h / 2 + 0.6, 0)) * CFrame.Angles(0, a, math.rad(45)), Color = Color3.fromRGB(80, 60, 40), Material = MAT.Wood, Parent = camp })
		end
	end

	-- เต็นท์
	local tentColors = { Color3.fromRGB(120, 85, 55), Color3.fromRGB(140, 60, 45), Color3.fromRGB(100, 95, 70) }
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2 + 0.3
		local pos = center + Vector3.new(math.cos(a) * 34, 0, math.sin(a) * 34)
		local cf = CFrame.lookAt(pos, center)
		gableRoof(camp, cf, 10, 12, 7, tentColors[i % 3 + 1])
		part({ Name = "TentFlap", Size = Vector3.new(3, 5, 0.2), CFrame = cf * CFrame.new(0, 2.5, -7), Color = Color3.fromRGB(60, 40, 25), Material = MAT.Fabric, Parent = camp })
	end

	-- ไฟกองกลาง + เสาโทเทม + กรงขัง
	campfire(camp, center, true)
	for _, off in ipairs({ Vector3.new(14, 0, 8), Vector3.new(-12, 0, -14) }) do
		local p = center + off
		cylinder({ Name = "Totem", Position = p + Vector3.new(0, 6, 0), Height = 12, Diameter = 2, Color = Color3.fromRGB(110, 75, 45), Material = MAT.Wood, Parent = camp })
		part({ Name = "TotemSkull", Shape = Enum.PartType.Ball, Size = Vector3.new(2.6, 2.6, 2.6), CFrame = CFrame.new(p + Vector3.new(0, 13, 0)), Color = Color3.fromRGB(225, 220, 200), Material = MAT.SmoothPlastic, Parent = camp })
		for _, sx in ipairs({ -0.5, 0.5 }) do
			part({ Name = "TotemEye", Size = Vector3.new(0.4, 0.4, 0.2), CFrame = CFrame.lookAt(p + Vector3.new(sx, 13.3, 0), center + Vector3.new(0, 13.3, 0)) * CFrame.new(0, 0, -1.25), Color = Color3.fromRGB(255, 60, 40), Material = MAT.Neon, CanCollide = false, Parent = camp })
		end
	end
	local cage = center + Vector3.new(-20, 0, 18)
	part({ Name = "CageFloor", Size = Vector3.new(7, 0.6, 7), CFrame = CFrame.new(cage + Vector3.new(0, 0.3, 0)), Color = Color3.fromRGB(80, 60, 40), Material = MAT.WoodPlanks, Parent = camp })
	part({ Name = "CageTop", Size = Vector3.new(7, 0.6, 7), CFrame = CFrame.new(cage + Vector3.new(0, 7.3, 0)), Color = Color3.fromRGB(80, 60, 40), Material = MAT.WoodPlanks, Parent = camp })
	for k = -3, 3, 1.5 do
		for _, side in ipairs({ -3.3, 3.3 }) do
			part({ Name = "CageBar", Size = Vector3.new(0.3, 7, 0.3), CFrame = CFrame.new(cage + Vector3.new(k, 3.8, side)), Color = Color3.fromRGB(70, 70, 75), Material = MAT.Metal, Parent = camp })
			part({ Name = "CageBar", Size = Vector3.new(0.3, 7, 0.3), CFrame = CFrame.new(cage + Vector3.new(side, 3.8, k)), Color = Color3.fromRGB(70, 70, 75), Material = MAT.Metal, Parent = camp })
		end
	end
	for _ = 1, 10 do
		local a, d = rng:NextNumber(0, math.pi * 2), rng:NextNumber(18, 48)
		part({ Name = "Crate", Size = Vector3.new(3, 3, 3), CFrame = CFrame.new(center + Vector3.new(math.cos(a) * d, 1.5, math.sin(a) * d)) * CFrame.Angles(0, a, 0), Color = Color3.fromRGB(150, 110, 70), Material = MAT.WoodPlanks, Parent = camp })
	end
	buildChest(camp, center + Vector3.new(8, 0, -20), 60, "หีบก็อบลิน")

	local g = math.rad(gateAngle)
	local gateDir = Vector3.new(math.cos(g), 0, math.sin(g))
	registerWarp(camp, "👺 ค่ายก็อบลิน", Color3.fromRGB(150, 200, 80), groundPos(center.X + gateDir.X * 75, center.Z + gateDir.Z * 75, 4), groundPos(center.X + gateDir.X * 88, center.Z + gateDir.Z * 88))
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2
		table.insert(monsterSpawns, { kind = "Goblin", pos = center + Vector3.new(math.cos(a) * 22, 0, math.sin(a) * 22) })
	end
end

-------------------------------------------------------------------------------
-- 🐍 หนองน้ำ + กระท่อมแม่มด
-------------------------------------------------------------------------------
local function buildSwamp()
	local swamp = folder("Swamp")
	local sw = ZONE.Swamp
	local center = Vector3.new(sw.x, 0, sw.z)

	for _ = 1, 28 do
		local a, d = rng:NextNumber(0, math.pi * 2), rng:NextNumber(20, sw.radius)
		local p = groundPos(center.X + math.cos(a) * d, center.Z + math.sin(a) * d)
		local h = rng:NextNumber(12, 22)
		local top = p + Vector3.new(rng:NextNumber(-3, 3), h, rng:NextNumber(-3, 3))
		limb(swamp, p - Vector3.new(0, 2, 0), top, 1.8, Color3.fromRGB(60, 55, 50), MAT.Wood, "DeadTree")
		for _ = 1, 2 do
			local arm = top:Lerp(p, rng:NextNumber(0.1, 0.4))
			limb(swamp, arm, arm + Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(1, 4), rng:NextNumber(-6, 6)), 0.8, Color3.fromRGB(60, 55, 50), MAT.Wood, "DeadBranch")
		end
		rope(swamp, top - Vector3.new(0, 2, 0), top - Vector3.new(0, 8, 0), 0.5, Color3.fromRGB(80, 100, 60)) -- ตะไคร่ห้อย
	end

	-- ใบบัว + ดอกบัว บนแอ่งน้ำ, ต้นกก
	for _ = 1, 140 do
		local a, d = rng:NextNumber(0, math.pi * 2), rng:NextNumber(0, sw.radius)
		local x, z = center.X + math.cos(a) * d, center.Z + math.sin(a) * d
		local h = heightAt(x, z)
		if h < -0.8 then
			cylinder({ Name = "LilyPad", Position = Vector3.new(x, 0.05, z), Height = 0.1, Diameter = rng:NextNumber(2, 4), Color = Color3.fromRGB(60, 130, 60), Material = MAT.Grass, CanCollide = false, Parent = swamp })
			if rng:NextNumber() < 0.2 then
				part({ Name = "LotusFlower", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9), CFrame = CFrame.new(x, 0.4, z), Color = Color3.fromRGB(255, 150, 200), Material = MAT.Neon, CanCollide = false, Parent = swamp })
			end
		elseif h < 3 and rng:NextNumber() < 0.5 then
			for _ = 1, 4 do
				local rh = rng:NextNumber(3, 5)
				part({ Name = "Reed", Size = Vector3.new(0.2, rh, 0.2), CFrame = CFrame.new(x + rng:NextNumber(-1, 1), h + rh / 2, z + rng:NextNumber(-1, 1)) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), 0, rng:NextNumber(-0.2, 0.2)), Color = Color3.fromRGB(110, 130, 60), Material = MAT.Grass, CanCollide = false, Parent = swamp })
			end
		end
	end

	-- ไฟผี (Will-o'-wisp)
	for _ = 1, 12 do
		local a, d = rng:NextNumber(0, math.pi * 2), rng:NextNumber(10, sw.radius)
		local p = center + Vector3.new(math.cos(a) * d, rng:NextNumber(4, 8), math.sin(a) * d)
		local wisp = part({ Name = "Wisp", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2), CFrame = CFrame.new(p), Color = Color3.fromRGB(120, 255, 200), Material = MAT.Neon, CanCollide = false, Parent = swamp })
		pointLight(wisp, Color3.fromRGB(120, 255, 200), 14, 1.2)
	end

	-- กระท่อมแม่มดบนเสาไม้
	local hutBase = center + Vector3.new(0, 9, 0)
	for _, c in ipairs({ Vector3.new(-6, 0, -5), Vector3.new(6, 0, -5), Vector3.new(-6, 0, 5), Vector3.new(6, 0, 5) }) do
		limb(swamp, hutBase + c - Vector3.new(0, 14, 0), hutBase + c, 1.2, Color3.fromRGB(70, 55, 40), MAT.Wood, "Stilt")
	end
	local hutCf = CFrame.lookAt(hutBase, hutBase + Vector3.new(-1, 0, 0))
	local hut = model("WitchHut", swamp)
	buildRoom(hut, hutCf, 14, 12, 9, { wallColor = Color3.fromRGB(80, 65, 55), material = MAT.WoodPlanks, floorColor = Color3.fromRGB(70, 55, 45), doorWidth = 4 })
	gableRoof(hut, hutCf * CFrame.new(0, 10, 0), 14, 12, 7, Color3.fromRGB(80, 50, 100))
	local cauldron = cylinder({ Name = "Cauldron", Position = (hutCf * CFrame.new(0, 2.2, 2)).Position, Height = 2.4, Diameter = 3, Color = Color3.fromRGB(35, 35, 40), Material = MAT.Metal, Parent = hut })
	local brew = cylinder({ Name = "Brew", Position = cauldron.Position + Vector3.new(0, 1.25, 0), Height = 0.1, Diameter = 2.6, Color = Color3.fromRGB(120, 255, 90), Material = MAT.Neon, CanCollide = false, Parent = hut })
	pointLight(brew, Color3.fromRGB(120, 255, 90), 18, 1.5)
	-- ทางลาดขึ้นกระท่อม
	local rampFrom = (hutCf * CFrame.new(0, 0, -6)).Position
	local rampTo = rampFrom + Vector3.new(-18, 0, 0)
	plankBridge(swamp, Vector3.new(rampTo.X, heightAt(rampTo.X, rampTo.Z) + 0.5, rampTo.Z), rampFrom + Vector3.new(0, 1, 0), 4, 0)
	buildChest(hut, (hutCf * CFrame.new(4, 1, 3)).Position, 70, "หีบแม่มด")

	fireflies(swamp, center + Vector3.new(0, 8, 0), Vector3.new(300, 16, 300), Color3.fromRGB(150, 255, 120), 30)
	local land = groundPos(center.X - 40, center.Z - 20, 4)
	registerWarp(swamp, "🐍 หนองน้ำแม่มด", Color3.fromRGB(120, 200, 120), land, land + Vector3.new(0, -4, 12))
	for i = 1, 11 do
		local a = i / 11 * math.pi * 2
		local p = groundPos(center.X + math.cos(a) * 70, center.Z + math.sin(a) * 70)
		table.insert(monsterSpawns, { kind = (i % 2 == 0) and "PoisonSlime" or "Snake", pos = Vector3.new(p.X, math.max(p.Y, 0.5), p.Z) })
	end
end

-------------------------------------------------------------------------------
-- 🌋 ภูเขาไฟ + รังมังกร
-------------------------------------------------------------------------------
local function buildVolcano()
	local volc = folder("Volcano")
	local v = VOLCANO
	local bottom = heightAt(v.x, v.z)

	local lava = cylinder({ Name = "LavaPool", Position = Vector3.new(v.x, bottom + 1.5, v.z), Height = 1, Diameter = v.crater * 1.7, Color = Color3.fromRGB(255, 90, 20), Material = MAT.Neon, Transparency = 0.1, Parent = volc })
	lava:SetAttribute("Lava", true)
	pointLight(lava, Color3.fromRGB(255, 110, 40), 60, 3)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(60, 55, 55))
	smoke.Size = NumberSequence.new(8, 30)
	smoke.Transparency = NumberSequence.new(0.3, 1)
	smoke.Lifetime = NumberRange.new(6, 10)
	smoke.Speed = NumberRange.new(10, 18)
	smoke.SpreadAngle = Vector2.new(15, 15)
	smoke.Rate = 6
	smoke.EmissionDirection = Enum.NormalId.Right
	smoke.Parent = lava
	local embers = Instance.new("ParticleEmitter")
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 160, 60))
	embers.LightEmission = 1
	embers.Size = NumberSequence.new(0.5, 0)
	embers.Lifetime = NumberRange.new(2, 4)
	embers.Speed = NumberRange.new(15, 30)
	embers.SpreadAngle = Vector2.new(30, 30)
	embers.Rate = 30
	embers.EmissionDirection = Enum.NormalId.Right
	embers.Parent = lava

	-- เสาหินบะซอลต์บนไหล่เขา
	for _ = 1, 16 do
		local a, d = rng:NextNumber(0, math.pi * 2), rng:NextNumber(v.crater + 30, v.radius * 0.8)
		local p = groundPos(v.x + math.cos(a) * d, v.z + math.sin(a) * d)
		local h = rng:NextNumber(8, 20)
		part({ Name = "BasaltSpire", Size = Vector3.new(4, h, 4), CFrame = CFrame.new(p + Vector3.new(0, h / 2 - 1, 0)) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, 3), rng:NextNumber(-0.2, 0.2)), Color = Color3.fromRGB(45, 40, 42), Material = MAT.Basalt, Parent = volc })
	end

	-- รังมังกรบนปากปล่อง: กองทอง + หีบ
	local lairPos = groundPos(v.x + v.crater + 14, v.z)
	for _ = 1, 24 do
		part({ Name = "Gold", Size = Vector3.new(rng:NextNumber(0.8, 2), rng:NextNumber(0.4, 1), rng:NextNumber(0.8, 2)), CFrame = CFrame.new(lairPos + Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(0, 1.5), rng:NextNumber(-6, 6))) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 3), 0), Color = Color3.fromRGB(255, 200, 50), Material = MAT.Foil, Parent = volc })
	end
	buildChest(volc, lairPos + Vector3.new(0, 1, 0), 400, "สมบัติมังกร")
	table.insert(monsterSpawns, { kind = "Dragon", pos = lairPos })
	for i = 1, 6 do
		local a = math.rad(-75 + (i - 1) * 30) -- ไหล่เขาฝั่งตะวันออก (ฝั่งตะวันตกติดทะเล)
		table.insert(monsterSpawns, { kind = "MagmaSlime", pos = groundPos(v.x + math.cos(a) * 170, v.z + math.sin(a) * 170) })
	end

	local foot = groundPos(v.x + v.radius - 40, v.z, 4)
	registerWarp(volc, "🌋 ภูเขาไฟ (รังมังกร)", Color3.fromRGB(255, 120, 50), foot, foot + Vector3.new(0, -4, 12))
end

-------------------------------------------------------------------------------
-- 💀 ดันเจี้ยนใต้ดิน 9 ห้อง
-------------------------------------------------------------------------------
local DUNGEON = { origin = Vector3.new(-380, -320, -760), spacing = 90, room = 60, height = 22, door = 14 }
local DUNGEON_ORDER = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 2, 1 }, { 1, 1 }, { 0, 1 }, { 0, 2 }, { 1, 2 }, { 2, 2 } }
local DUNGEON_ROOMS = { "entrance", "goblins", "slimes", "snakes", "eyes", "armory", "crypt", "treasure", "boss" }

local function dungeonTorch(parent, pos, facingPos)
	local cf = CFrame.lookAt(pos, Vector3.new(facingPos.X, pos.Y, facingPos.Z))
	part({ Name = "TorchHolder", Size = Vector3.new(0.5, 1.8, 0.5), CFrame = cf * CFrame.Angles(math.rad(-25), 0, 0), Color = Color3.fromRGB(60, 50, 40), Material = MAT.Metal, Parent = parent })
	local flame = part({ Name = "TorchFlame", Size = Vector3.new(0.6, 0.6, 0.6), CFrame = cf * CFrame.new(0, 1.1, -0.4), Color = Color3.fromRGB(255, 150, 50), Material = MAT.Neon, CanCollide = false, Parent = parent })
	local fire = Instance.new("Fire")
	fire.Size = 2.5
	fire.Heat = 6
	fire.Parent = flame
	pointLight(flame, Color3.fromRGB(255, 140, 60), 28, 1.8)
end

local function buildDungeon()
	local dg = folder("Dungeon")
	local D = DUNGEON
	local wallColor, floorColor = Color3.fromRGB(78, 76, 82), Color3.fromRGB(58, 56, 60)
	local function roomCenter(i, j)
		return D.origin + Vector3.new(i * D.spacing, 0, j * D.spacing)
	end
	local doors = {}
	local function key(i, j)
		return i .. "," .. j
	end
	for k = 1, #DUNGEON_ORDER - 1 do
		local a, b = DUNGEON_ORDER[k], DUNGEON_ORDER[k + 1]
		doors[key(a[1], a[2])] = doors[key(a[1], a[2])] or {}
		doors[key(b[1], b[2])] = doors[key(b[1], b[2])] or {}
		local dx, dz = b[1] - a[1], b[2] - a[2]
		doors[key(a[1], a[2])][dx .. "," .. dz] = true
		doors[key(b[1], b[2])][(0 - dx) .. "," .. (0 - dz)] = true

		-- ทางเดินเชื่อมห้อง
		local ca, cb = roomCenter(a[1], a[2]), roomCenter(b[1], b[2])
		local mid = (ca + cb) / 2
		local side = Vector3.new(dz, 0, dx)
		local len = D.spacing - D.room + 2
		local sizeAlong = function(w, h, l)
			return (dx ~= 0) and Vector3.new(l, h, w) or Vector3.new(w, h, l)
		end
		part({ Name = "CorridorFloor", Size = sizeAlong(D.door, 2, len), CFrame = CFrame.new(mid - Vector3.new(0, 1, 0)), Color = floorColor, Material = MAT.Slate, Parent = dg })
		part({ Name = "CorridorCeiling", Size = sizeAlong(D.door + 4, 2, len), CFrame = CFrame.new(mid + Vector3.new(0, 15, 0)), Color = wallColor, Material = MAT.Rock, Parent = dg })
		for _, s in ipairs({ -1, 1 }) do
			part({ Name = "CorridorWall", Size = sizeAlong(2, 14, len), CFrame = CFrame.new(mid + side * s * (D.door / 2 + 1) + Vector3.new(0, 7, 0)), Color = wallColor, Material = MAT.Cobblestone, Parent = dg })
		end
		dungeonTorch(dg, mid + side * (D.door / 2 - 0.2) + Vector3.new(0, 7, 0), mid)
	end

	local H, S, T = D.height, D.room, 2
	for idx, rc in ipairs(DUNGEON_ORDER) do
		local c = roomCenter(rc[1], rc[2])
		local kind = DUNGEON_ROOMS[idx]
		local room = folder("Room" .. idx .. "_" .. kind, dg)
		part({ Name = "Floor", Size = Vector3.new(S, 2, S), CFrame = CFrame.new(c - Vector3.new(0, 1, 0)), Color = floorColor, Material = MAT.Slate, Parent = room })
		part({ Name = "Ceiling", Size = Vector3.new(S + 4, 2, S + 4), CFrame = CFrame.new(c + Vector3.new(0, H + 1, 0)), Color = wallColor, Material = MAT.Rock, Parent = room })
		local d = doors[key(rc[1], rc[2])]
		for _, w in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local normal = Vector3.new(w[1], 0, w[2])
			local tangent = Vector3.new(w[2], 0, w[1])
			local wallC = c + normal * (S / 2 + T / 2) + Vector3.new(0, H / 2, 0)
			local function wsize(len, h)
				return (w[1] ~= 0) and Vector3.new(T, h, len) or Vector3.new(len, h, T)
			end
			if d[w[1] .. "," .. w[2]] then
				local segLen = (S + 2 * T - D.door) / 2
				for _, s in ipairs({ -1, 1 }) do
					part({ Name = "Wall", Size = wsize(segLen, H), CFrame = CFrame.new(wallC + tangent * s * (D.door / 2 + segLen / 2)), Color = wallColor, Material = MAT.Cobblestone, Parent = room })
				end
				part({ Name = "Lintel", Size = wsize(D.door, H - 12), CFrame = CFrame.new(c + normal * (S / 2 + T / 2) + Vector3.new(0, 12 + (H - 12) / 2, 0)), Color = wallColor, Material = MAT.Cobblestone, Parent = room })
			else
				part({ Name = "Wall", Size = wsize(S + 2 * T, H), CFrame = CFrame.new(wallC), Color = wallColor, Material = MAT.Cobblestone, Parent = room })
			end
			-- คบเพลิงสองข้างของทุกผนัง
			for _, s in ipairs({ -1, 1 }) do
				dungeonTorch(room, c + normal * (S / 2 - 0.3) + tangent * s * 18 + Vector3.new(0, 8, 0), c)
			end
		end
		-- เสาหิน
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				part({ Name = "Pillar", Size = Vector3.new(4, H, 4), CFrame = CFrame.new(c + Vector3.new(sx * 17, H / 2, sz * 17)), Color = Color3.fromRGB(95, 92, 98), Material = MAT.Cobblestone, Parent = room })
			end
		end
		-- กระดูกกระจายตามพื้น
		for _ = 1, 8 do
			part({ Name = "Bone", Size = Vector3.new(0.4, 0.4, rng:NextNumber(1.5, 3)), CFrame = CFrame.new(c + Vector3.new(rng:NextNumber(-26, 26), 0.2, rng:NextNumber(-26, 26))) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color = Color3.fromRGB(220, 215, 195), Material = MAT.SmoothPlastic, CanCollide = false, Parent = room })
		end

		local function spawns(kindName, count)
			for n = 1, count do
				local a = n / count * math.pi * 2
				table.insert(monsterSpawns, { kind = kindName, pos = c + Vector3.new(math.cos(a) * 10, 0, math.sin(a) * 10) })
			end
		end

		if kind == "entrance" then
			registerWarp(room, "💀 ดันเจี้ยน (ห้องแรก)", Color3.fromRGB(190, 90, 255), c + Vector3.new(-12, 4, 0), c + Vector3.new(-12, 0, 12))
			for _, sz in ipairs({ -1, 1 }) do
				part({ Name = "Statue", Size = Vector3.new(4, 10, 4), CFrame = CFrame.new(c + Vector3.new(20, 5, sz * 8)), Color = Color3.fromRGB(120, 120, 125), Material = MAT.Marble, Parent = room })
				part({ Name = "StatueHead", Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), CFrame = CFrame.new(c + Vector3.new(20, 11.5, sz * 8)), Color = Color3.fromRGB(120, 120, 125), Material = MAT.Marble, Parent = room })
			end
		elseif kind == "goblins" or kind == "armory" then
			for _ = 1, 8 do
				part({ Name = "Crate", Size = Vector3.new(3, 3, 3), CFrame = CFrame.new(c + Vector3.new(rng:NextNumber(-24, 24), 1.5, rng:NextNumber(-24, 24))) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color = Color3.fromRGB(130, 95, 60), Material = MAT.WoodPlanks, Parent = room })
			end
			if kind == "armory" then
				for k = -2, 2 do
					part({ Name = "SpearRack", Size = Vector3.new(0.3, 8, 0.3), CFrame = CFrame.new(c + Vector3.new(k * 2, 4, 27)) * CFrame.Angles(math.rad(-10), 0, 0), Color = Color3.fromRGB(110, 110, 120), Material = MAT.Metal, Parent = room })
				end
			end
			spawns("Goblin", kind == "goblins" and 4 or 3)
		elseif kind == "slimes" then
			for _ = 1, 10 do
				cylinder({ Name = "Ooze", Position = c + Vector3.new(rng:NextNumber(-24, 24), 0.05, rng:NextNumber(-24, 24)), Height = 0.1, Diameter = rng:NextNumber(3, 7), Color = Color3.fromRGB(150, 60, 200), Material = MAT.Neon, Transparency = 0.3, CanCollide = false, Parent = room })
			end
			spawns("PoisonSlime", 4)
		elseif kind == "snakes" then
			for _ = 1, 12 do
				part({ Name = "Egg", Shape = Enum.PartType.Ball, Size = Vector3.new(1.3, 1.3, 1.3), CFrame = CFrame.new(c + Vector3.new(rng:NextNumber(-8, 8), 0.6, rng:NextNumber(-8, 8))), Color = Color3.fromRGB(235, 230, 200), Material = MAT.SmoothPlastic, Parent = room })
			end
			spawns("Snake", 4)
		elseif kind == "eyes" then
			for _ = 1, 6 do
				local cr = part({ Name = "EyeCrystal", Size = Vector3.new(2, rng:NextNumber(4, 8), 2), CFrame = CFrame.new(c + Vector3.new(rng:NextNumber(-22, 22), 2, rng:NextNumber(-22, 22))) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)), Color = Color3.fromRGB(190, 70, 255), Material = MAT.Neon, Parent = room })
				pointLight(cr, Color3.fromRGB(190, 70, 255), 14, 1)
			end
			spawns("EvilEye", 3)
		elseif kind == "crypt" then
			for k = -1, 1 do
				part({ Name = "Coffin", Size = Vector3.new(3.5, 2, 8), CFrame = CFrame.new(c + Vector3.new(k * 9, 1, -20)), Color = Color3.fromRGB(60, 45, 35), Material = MAT.Wood, Parent = room })
				local candle = part({ Name = "Candle", Size = Vector3.new(0.4, 1.2, 0.4), CFrame = CFrame.new(c + Vector3.new(k * 9, 2.6, -15)), Color = Color3.fromRGB(240, 235, 210), Material = MAT.SmoothPlastic, Parent = room })
				pointLight(candle, Color3.fromRGB(255, 200, 120), 10, 1)
			end
			spawns("Skeleton", 4)
		elseif kind == "treasure" then
			for _ = 1, 30 do
				part({ Name = "Gold", Size = Vector3.new(rng:NextNumber(0.8, 2), rng:NextNumber(0.4, 1), rng:NextNumber(0.8, 2)), CFrame = CFrame.new(c + Vector3.new(rng:NextNumber(-7, 7), rng:NextNumber(0, 1.5), rng:NextNumber(-7, 7))), Color = Color3.fromRGB(255, 200, 50), Material = MAT.Foil, Parent = room })
			end
			buildChest(room, c, 120, "หีบห้องสมบัติ")
			spawns("Bat", 3)
		elseif kind == "boss" then
			for _, sx in ipairs({ -1, 1 }) do
				local ch = part({ Name = "LavaChannel", Size = Vector3.new(4, 0.4, S - 6), CFrame = CFrame.new(c + Vector3.new(sx * 24, 0.2, 0)), Color = Color3.fromRGB(255, 90, 20), Material = MAT.Neon, Parent = room })
				ch:SetAttribute("Lava", true)
				pointLight(ch, Color3.fromRGB(255, 110, 40), 30, 2)
			end
			local throne = part({ Name = "BossThrone", Size = Vector3.new(10, 8, 4), CFrame = CFrame.new(c + Vector3.new(0, 4, 27)), Color = Color3.fromRGB(70, 30, 30), Material = MAT.Basalt, Parent = room })
			billboardText(throne, "🐂 ห้องบอส: มิโนทอร์", Color3.fromRGB(255, 120, 90), 7, 16)
			buildChest(room, c + Vector3.new(0, 0, 22), 500, "สมบัติบอส")
			table.insert(monsterSpawns, { kind = "Minotaur", pos = c })
		end
		task.wait()
	end

	-- ประตูทางเข้าดันเจี้ยนบนพื้นดิน
	local gate = folder("DungeonGate")
	local gz = ZONE.DungeonGate
	local g = Vector3.new(gz.x, gz.height, gz.z)
	part({ Name = "GatePlatform", Size = Vector3.new(30, 2, 30), CFrame = CFrame.new(g - Vector3.new(0, 0.5, 0)), Color = Color3.fromRGB(80, 78, 85), Material = MAT.Cobblestone, Parent = gate })
	for _, sx in ipairs({ -1, 1 }) do
		part({ Name = "GatePillar", Size = Vector3.new(4, 18, 4), CFrame = CFrame.new(g + Vector3.new(sx * 8, 9, 0)), Color = Color3.fromRGB(90, 88, 95), Material = MAT.Cobblestone, Parent = gate })
		dungeonTorch(gate, g + Vector3.new(sx * 8, 11, -2.3), g + Vector3.new(sx * 8, 11, -10))
	end
	part({ Name = "GateLintel", Size = Vector3.new(22, 4, 5), CFrame = CFrame.new(g + Vector3.new(0, 20, 0)), Color = Color3.fromRGB(80, 78, 85), Material = MAT.Cobblestone, Parent = gate })
	local skull = part({ Name = "GateSkull", Shape = Enum.PartType.Ball, Size = Vector3.new(4, 4, 4), CFrame = CFrame.new(g + Vector3.new(0, 23.5, 0)), Color = Color3.fromRGB(225, 220, 200), Material = MAT.SmoothPlastic, Parent = gate })
	pointLight(skull, Color3.fromRGB(190, 90, 255), 25, 1.5)
	local entry = WARPS[#WARPS] -- ห้องแรกของดันเจี้ยน (เพิ่งลงทะเบียนด้านบน)
	table.remove(WARPS, #WARPS)
	buildPortal(gate, g + Vector3.new(0, 0.5, 0), Color3.fromRGB(190, 90, 255), "💀 เข้าดันเจี้ยน", entry.landing)
	registerWarp(gate, "💀 ประตูดันเจี้ยน", Color3.fromRGB(190, 90, 255), g + Vector3.new(0, 4, -14), g + Vector3.new(12, 0.5, -10))
end

-- จุดวาร์ปของพื้นที่เดิม
local function registerClassicWarps()
	local warps = folder("Warps")
	local c = ZONE.Castle
	registerWarp(warps, "🏰 ปราสาทหลวง", Color3.fromRGB(255, 210, 120), groundPos(c.x + 80, c.z, 4), groundPos(c.x + 80, c.z + 14))
	registerWarp(warps, "🌲 ป่ามหัศจรรย์", Color3.fromRGB(120, 255, 140), groundPos(425, 12, 4), groundPos(425, 26))
	local r = ZONE.Ruins
	registerWarp(warps, "🦴 ซากปรักหักพัง", Color3.fromRGB(200, 170, 255), groundPos(r.x - 45, r.z - 45, 4), groundPos(r.x - 58, r.z - 45))
	local hb = ZONE.Harbor
	registerWarp(warps, "⚓ ท่าเรือ", Color3.fromRGB(120, 200, 255), Vector3.new(hb.x - 12, hb.height + 5, hb.z - 20), Vector3.new(hb.x - 26, hb.height + 1, hb.z - 20))
	local sy = heightAt(SHRINE_POS.X, SHRINE_POS.Y) + 1
	registerWarp(warps, "🏔️ ศาลเจ้าบนเขา", Color3.fromRGB(170, 230, 255), Vector3.new(SHRINE_POS.X - 6, sy + 4, SHRINE_POS.Y + 4), Vector3.new(SHRINE_POS.X + 6, sy, SHRINE_POS.Y + 4))
end

-------------------------------------------------------------------------------
-- 8) 🛤️ เส้นทางเชื่อมแต่ละพื้นที่
-------------------------------------------------------------------------------
local function buildPath(parent, a, b, width, color, material)
	local steps = math.ceil((b - a).Magnitude / 8)
	for i = 0, steps - 1 do
		local p1 = a:Lerp(b, i / steps)
		local p2 = a:Lerp(b, (i + 1) / steps)
		-- ช่วงที่ผ่านน้ำ ทางเดินลอยเหนือน้ำเหมือนสะพานไม้
		local v1 = Vector3.new(p1.X, math.max(heightAt(p1.X, p1.Y), 0.4) + 0.1, p1.Y)
		local v2 = Vector3.new(p2.X, math.max(heightAt(p2.X, p2.Y), 0.4) + 0.1, p2.Y)
		part({
			Name = "Path",
			Size = Vector3.new(width, 1, (v2 - v1).Magnitude + 1.5),
			CFrame = CFrame.lookAt((v1 + v2) / 2, v2),
			Color = color,
			Material = material,
			Parent = parent,
		})
		table.insert(pathPoints, p1)
	end
	table.insert(pathPoints, b)
end

local function buildPaths()
	local paths = folder("Paths")
	local dirt, dirtMat = Color3.fromRGB(150, 120, 90), MAT.Pebble
	buildPath(paths, Vector2.new(-238, 0), Vector2.new(-368, ZONE.Castle.z), 12, Color3.fromRGB(140, 140, 145), MAT.Cobblestone) -- ไปปราสาท
	buildPath(paths, Vector2.new(0, 238), Vector2.new(0, ZONE.Harbor.z - 38), 10, dirt, dirtMat) -- ไปท่าเรือ
	buildPath(paths, Vector2.new(440, 0), Vector2.new(ZONE.WorldTree.x - 150, ZONE.WorldTree.z), 10, dirt, dirtMat) -- ไปต้นไม้โลก
	buildPath(paths, Vector2.new(-168, 168), Vector2.new(-560, 470), 8, dirt, dirtMat) -- ไปค่ายก็อบลิน
	buildPath(paths, Vector2.new(-168, -168), Vector2.new(ZONE.DungeonGate.x + 14, ZONE.DungeonGate.z + 20), 8, Color3.fromRGB(110, 105, 110), MAT.Cobblestone) -- ไปประตูดันเจี้ยน
	buildPath(paths, Vector2.new(360, 360), Vector2.new(ZONE.Swamp.x - 60, ZONE.Swamp.z - 110), 8, dirt, dirtMat) -- ไปหนองน้ำ
	buildPath(paths, Vector2.new(238, 0), Vector2.new(440, 0), 8, dirt, dirtMat) -- เข้าป่า
	buildPath(paths, Vector2.new(168, 168), Vector2.new(300, 300), 8, dirt, dirtMat) -- ไปซากปรักหักพัง
	buildPath(paths, Vector2.new(0, -238), Vector2.new(SHRINE_POS.X, SHRINE_POS.Y + 14), 8, dirt, dirtMat) -- ขึ้นเขา
end

-------------------------------------------------------------------------------
-- 9) 🌲 ธรรมชาติ: ต้นไม้ หิน เห็ดยักษ์ คริสตัล
-------------------------------------------------------------------------------
local BLOCK_MARGIN = { Town = 25, Castle = 35, Ruins = 5, Harbor = 50, WorldTree = 40, GoblinCamp = 15, DungeonGate = 15, Swamp = 0 }

local function isBlocked(x, z)
	for _, zn in ipairs(ZONES) do
		local r = zn.radius + BLOCK_MARGIN[zn.name]
		if (x - zn.x) ^ 2 + (z - zn.z) ^ 2 < r * r then
			return true
		end
	end
	if (x - SHRINE_POS.X) ^ 2 + (z - SHRINE_POS.Y) ^ 2 < 30 ^ 2 then
		return true
	end
	if (x - VOLCANO.x) ^ 2 + (z - VOLCANO.z) ^ 2 < (VOLCANO.radius * 0.75) ^ 2 then
		return true
	end
	for _, p in ipairs(pathPoints) do
		if (x - p.X) ^ 2 + (z - p.Y) ^ 2 < 10 ^ 2 then
			return true
		end
	end
	return false
end

local function roundTree(parent, pos)
	local tpl = customTemplate("Tree")
	if tpl then
		placeCustom(tpl, parent, pos - Vector3.new(0, 0.5, 0), rng:NextNumber(16, 26))
		return
	end
	local leafA, leafB = Color3.fromRGB(50, 120, 50), Color3.fromRGB(120, 170, 60)
	if CONFIG.DarkTheme then
		leafA, leafB = Color3.fromRGB(35, 85, 50), Color3.fromRGB(75, 125, 60)
	end
	naturalTree(parent, "Tree", pos, {
		height = { 11, 18 }, width = { 1.4, 2.2 }, bark = Color3.fromRGB(95, 62, 42),
		leafA = leafA, leafB = leafB, tuft = 9, pieces = 2, depth = 2,
	})
end

-- ต้นสน: กิ่งแผ่เป็นชั้นรอบลำต้น ปลายกิ่งห้อยลง ชั้นล่างกว้าง ชั้นบนแคบ
local function pineTree(parent, pos)
	local tpl = customTemplate("PineTree")
	if tpl then
		placeCustom(tpl, parent, pos - Vector3.new(0, 0.5, 0), rng:NextNumber(20, 32))
		return
	end
	local tree = model("PineTree", parent)
	local h = rng:NextNumber(18, 30)
	cylinder({ Name = "Trunk", Position = pos + Vector3.new(0, h / 2 - 1, 0), Height = h + 1, Diameter = h * 0.06 + 0.4, Color = Color3.fromRGB(80, 55, 40), Material = MAT.Wood, Parent = tree })
	local whorls = ({ 4, 5, 7 })[CONFIG.LeafDetail] or 5
	local dark, light = Color3.fromRGB(24, 70, 44), Color3.fromRGB(48, 102, 60)
	for i = 1, whorls do
		local t = (i - 1) / whorls
		local y = h * (0.2 + t * 0.7)
		local len = h * 0.34 * (1 - t * 0.85) + 1.5
		local spin = rng:NextNumber(0, math.pi * 2)
		for k = 1, 4 do
			local a = spin + k * math.pi / 2 + rng:NextNumber(-0.25, 0.25)
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			local c = pos + Vector3.new(0, y, 0) + dir * (len / 2)
			part({
				ClassName = (k % 2 == 0) and "WedgePart" or "Part",
				Name = "Needles",
				Size = Vector3.new(len * 0.6, 0.9, len),
				CFrame = CFrame.lookAt(c, c + dir) * CFrame.Angles(math.rad(-rng:NextNumber(12, 24)), 0, 0),
				Color = dark:Lerp(light, rng:NextNumber() * 0.6 + t * 0.4),
				Material = MAT.LeafyGrass,
				CanCollide = false,
				Parent = tree,
			})
		end
	end
	pineTier(tree, pos + Vector3.new(0, h + 0.5, 0), 3.2, 4, light)
end

local function giantMushroom(parent, pos)
	local m = model("GiantMushroom", parent)
	local h = rng:NextNumber(6, 12)
	cylinder({ Name = "Stem", Position = pos + Vector3.new(0, h / 2, 0), Height = h, Diameter = 2.5, Color = Color3.fromRGB(245, 240, 225), Material = MAT.SmoothPlastic, Parent = m })
	local capColor = ({ Color3.fromRGB(220, 50, 60), Color3.fromRGB(150, 70, 220), Color3.fromRGB(60, 150, 230) })[rng:NextInteger(1, 3)]
	local cap = cylinder({ Name = "Cap", Position = pos + Vector3.new(0, h + 1, 0), Height = 2.5, Diameter = rng:NextNumber(9, 13), Color = capColor, Material = MAT.SmoothPlastic, Parent = m })
	pointLight(cap, capColor, 14, 0.8)
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2
		part({
			Name = "Spot",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.2, 1.2, 1.2),
			CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 3, h + 2.1, math.sin(a) * 3)),
			Color = Color3.new(1, 1, 1),
			CanCollide = false,
			Parent = m,
		})
	end
end

local function crystal(parent, pos)
	local color = ({ Color3.fromRGB(120, 230, 255), Color3.fromRGB(200, 120, 255), Color3.fromRGB(120, 255, 180) })[rng:NextInteger(1, 3)]
	local c = model("Crystal", parent)
	for i = 1, 3 do
		local p = part({
			Name = "Shard",
			Size = Vector3.new(1.5, rng:NextNumber(3, 7), 1.5),
			CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-1.5, 1.5), 2, rng:NextNumber(-1.5, 1.5)))
				* CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), rng:NextNumber(0, math.pi), math.rad(rng:NextNumber(-25, 25))),
			Color = color,
			Material = MAT.Neon,
			Transparency = 0.15,
			Parent = c,
		})
		if i == 1 then
			pointLight(p, color, 16, 1.2)
		end
	end
end

local function boulder(parent, pos)
	local tpl = customTemplate("Rock")
	if tpl then
		placeCustom(tpl, parent, pos - Vector3.new(0, 1, 0), rng:NextNumber(3, 9))
		return
	end
	local s = rng:NextNumber(4, 11)
	part({
		Name = "Boulder",
		Size = Vector3.new(s, s * rng:NextNumber(0.6, 1), s * rng:NextNumber(0.7, 1.2)),
		CFrame = CFrame.new(pos + Vector3.new(0, s * 0.25, 0)) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 3), rng:NextNumber(0, 1)),
		Color = Color3.fromRGB(115, 115, 110),
		Material = MAT.Rock,
		Parent = parent,
	})
end

-- สุ่มจุดบนพื้นดินที่ความสูงอยู่ในช่วง และไม่ทับเมือง/เส้นทาง
local function randomSpot(minX, maxX, minZ, maxZ, minH, maxH)
	for _ = 1, 20 do
		local x, z = rng:NextNumber(minX, maxX), rng:NextNumber(minZ, maxZ)
		local h = heightAt(x, z)
		if h >= minH and h <= maxH and not isBlocked(x, z) then
			return Vector3.new(x, h, z)
		end
	end
	return nil
end

local function buildNature()
	local nature = folder("Nature")
	local E = HALF - 40

	for i = 1, CONFIG.TreeCount do
		local p = randomSpot(-E, E, -E, E, 3.5, 100)
		if p then
			if p.Y > 45 then
				pineTree(nature, p)
			else
				roundTree(nature, p)
			end
		end
		if i % 60 == 0 then
			task.wait()
		end
	end

	local forest = folder("EnchantedForest")
	local function forestSpot(inset, maxH)
		inset = inset or 0
		return randomSpot(FOREST.minX + inset, FOREST.maxX - inset, FOREST.minZ + inset, FOREST.maxZ - inset, 3.5, maxH or 90)
	end
	for i = 1, CONFIG.ForestTreeCount do
		local p = forestSpot()
		if p then
			if rng:NextNumber() < 0.25 then
				pineTree(forest, p)
			else
				roundTree(forest, p)
			end
		end
		if i % 60 == 0 then
			task.wait()
		end
	end
	for _ = 1, 22 do
		local p = forestSpot()
		if p then
			giantMushroom(forest, p)
		end
	end
	for _ = 1, 14 do
		local p = forestSpot()
		if p then
			crystal(forest, p)
		end
	end
	for i = 1, 12 do
		local p = forestSpot(30, 60)
		if p then
			table.insert(monsterSpawns, { kind = (i % 2 == 0) and "Wolf" or "Slime", pos = p })
		end
	end

	fireflies(forest, Vector3.new((FOREST.minX + FOREST.maxX) / 2, 30, (FOREST.minZ + FOREST.maxZ) / 2), Vector3.new(FOREST.maxX - FOREST.minX, 40, FOREST.maxZ - FOREST.minZ), nil, 40)

	-- 🌲 ป่าโบราณ (Elderwood): ต้นไม้ยักษ์สีเข้มรอบต้นไม้โลก
	local elder = folder("Elderwood")
	for i = 1, CONFIG.ElderwoodTreeCount do
		local p = randomSpot(ELDERWOOD.minX, ELDERWOOD.maxX, ELDERWOOD.minZ, ELDERWOOD.maxZ, 3.5, 90)
		if p then
			local h = rng:NextNumber(28, 46)
			local w = rng:NextNumber(3.5, 6.5)
			local tpl = customTemplate("AncientTree")
			if tpl then
				placeCustom(tpl, elder, p - Vector3.new(0, 1, 0), h + 12)
				continue
			end
			local t = naturalTree(elder, "AncientTree", p, {
				height = { h * 0.85, h }, width = { w, w }, bark = Color3.fromRGB(58, 44, 38),
				leafA = Color3.fromRGB(26, 58, 44), leafB = Color3.fromRGB(48, 88, 56), tuft = 15, pieces = 3, depth = 2, roots = 4,
			})
			if rng:NextNumber() < 0.15 then
				local g = part({ Name = "GlowShroom", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), CFrame = CFrame.new(p + Vector3.new(w * 0.7, 0.6, 0)), Color = Color3.fromRGB(90, 220, 255), Material = MAT.Neon, CanCollide = false, Parent = t })
				pointLight(g, Color3.fromRGB(90, 220, 255), 10, 0.8)
			end
		end
		if i % 50 == 0 then
			task.wait()
		end
	end
	fireflies(elder, Vector3.new((ELDERWOOD.minX + ELDERWOOD.maxX) / 2, 25, (ELDERWOOD.minZ + ELDERWOOD.maxZ) / 2), Vector3.new(ELDERWOOD.maxX - ELDERWOOD.minX, 40, ELDERWOOD.maxZ - ELDERWOOD.minZ), Color3.fromRGB(150, 230, 255), 50)
	for i = 1, 5 do
		local p = randomSpot(ELDERWOOD.minX, ELDERWOOD.maxX, ELDERWOOD.minZ, ELDERWOOD.maxZ, 3.5, 60)
		if p then
			table.insert(monsterSpawns, { kind = "Wolf", pos = p })
		end
	end

	-- หีบสมบัติกลางป่า (ปลายทางเดิน)
	buildChest(forest, groundPos(446, 0), 25, "หีบกลางป่า")
	local signPart = part({ Name = "ForestSign", Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(groundPos(262, 0, 10)), Transparency = 1, CanCollide = false, Parent = forest })
	billboardText(signPart, "🌲 ป่ามหัศจรรย์", Color3.fromRGB(170, 255, 170), 2)

	for _ = 1, CONFIG.RockCount do
		local p = randomSpot(-E, E, -E, E, 1, 150)
		if p then
			boulder(nature, p)
		end
	end
end

-------------------------------------------------------------------------------
-- 10) 👾 มอนสเตอร์: รูปร่าง + ท่าเดิน
--   แต่ละชิ้นส่วนต่อกับชิ้นแม่ด้วยข้อต่อ (Motor6D) ที่จุด joint
--   ตำแหน่งทั้งหมดวัดจากกึ่งกลางตัว (HumanoidRootPart), ด้านหน้า = -Z
-------------------------------------------------------------------------------
local Ball = Enum.PartType.Ball
local Cyl = Enum.PartType.Cylinder
local sin = math.sin

local MONSTER_TYPES = {
	Slime = {
		displayName = "สไลม์",
		hp = 40, damage = 8, speed = 10, coins = 5, reach = 3, aggro = 45, hip = 0.3, respawn = 15,
		root = Vector3.new(4, 3.2, 4), stepRate = 7,
		parts = {
			{ name = "Body", shape = Ball, size = 4.2, pos = Vector3.new(0, 0.3, 0), joint = Vector3.new(0, -1.6, 0), color = Color3.fromRGB(90, 220, 90), mat = MAT.Glass, transparency = 0.25 },
			{ name = "Core", parent = "Body", shape = Ball, size = 1.5, pos = Vector3.new(0, 0.1, 0.3), color = Color3.fromRGB(40, 150, 50), mat = MAT.Neon, transparency = 0.2 },
			{ name = "Shine", parent = "Body", shape = Ball, size = 0.8, pos = Vector3.new(-1, 1.5, -1.1), color = Color3.new(1, 1, 1), mat = MAT.SmoothPlastic, transparency = 0.3 },
			{ name = "EyeL", parent = "Body", shape = Ball, size = 1, pos = Vector3.new(-0.75, 0.8, -1.7), color = Color3.new(1, 1, 1), mat = MAT.SmoothPlastic },
			{ name = "EyeR", parent = "Body", shape = Ball, size = 1, pos = Vector3.new(0.75, 0.8, -1.7), color = Color3.new(1, 1, 1), mat = MAT.SmoothPlastic },
			{ name = "PupilL", parent = "Body", shape = Ball, size = 0.5, pos = Vector3.new(-0.75, 0.8, -2.15), color = Color3.new(0, 0, 0), mat = MAT.SmoothPlastic },
			{ name = "PupilR", parent = "Body", shape = Ball, size = 0.5, pos = Vector3.new(0.75, 0.8, -2.15), color = Color3.new(0, 0, 0), mat = MAT.SmoothPlastic },
			{ name = "Mouth", parent = "Body", size = Vector3.new(1.1, 0.2, 0.2), pos = Vector3.new(0, -0.1, -2.05), color = Color3.fromRGB(20, 60, 20), mat = MAT.SmoothPlastic },
			{ name = "LeafStem", parent = "Body", size = Vector3.new(0.2, 0.8, 0.2), pos = Vector3.new(0, 2.7, 0), color = Color3.fromRGB(90, 60, 30), mat = MAT.Wood },
			{ name = "Leaf", parent = "LeafStem", size = Vector3.new(1.2, 0.15, 0.7), pos = Vector3.new(0.5, 3.05, 0), rot = CFrame.Angles(0, 0, math.rad(25)), color = Color3.fromRGB(60, 170, 60), mat = MAT.Grass },
			{ name = "Head", size = Vector3.new(0.5, 0.5, 0.5), pos = Vector3.new(0, 1.8, 0), transparency = 1 },
		},
		animate = function(pose, phase, walk, atk, now)
			local hop = math.abs(sin(phase)) * walk
			pose("Body", CFrame.new(0, hop * 1.4 + sin(now * 3) * 0.08, 0) * CFrame.Angles(-atk * 0.5, 0, sin(phase) * 0.1 * walk))
			pose("Leaf", CFrame.Angles(0, 0, sin(now * 4) * 0.2))
		end,
	},

	Wolf = {
		displayName = "หมาป่า",
		hp = 60, damage = 10, speed = 18, coins = 8, reach = 4, aggro = 55, hip = 2.2, respawn = 18,
		root = Vector3.new(3, 2.4, 6), stepRate = 11,
		color = Color3.fromRGB(95, 90, 95), mat = MAT.Fabric,
		parts = {
			{ name = "Body", size = Vector3.new(2.6, 2.3, 5.4), pos = Vector3.zero },
			{ name = "Mane", parent = "Body", size = Vector3.new(3, 2.7, 1.8), pos = Vector3.new(0, 0.15, -2), color = Color3.fromRGB(150, 145, 150) },
			{ name = "Head", parent = "Body", size = Vector3.new(2.1, 1.9, 2.1), pos = Vector3.new(0, 1, -3.6), joint = Vector3.new(0, 0.6, -2.8) },
			{ name = "Snout", parent = "Head", size = Vector3.new(1.1, 0.9, 1.6), pos = Vector3.new(0, 0.6, -5.2) },
			{ name = "Nose", parent = "Head", size = Vector3.new(0.5, 0.4, 0.3), pos = Vector3.new(0, 1, -6), color = Color3.new(0, 0, 0), mat = MAT.SmoothPlastic },
			{ name = "Fangs", parent = "Head", size = Vector3.new(0.8, 0.3, 0.15), pos = Vector3.new(0, 0.1, -5.9), color = Color3.new(1, 1, 1), mat = MAT.SmoothPlastic },
			{ name = "EarL", parent = "Head", size = Vector3.new(0.5, 1, 0.3), pos = Vector3.new(-0.65, 2.35, -3.4), rot = CFrame.Angles(0, 0, math.rad(-12)) },
			{ name = "EarR", parent = "Head", size = Vector3.new(0.5, 1, 0.3), pos = Vector3.new(0.65, 2.35, -3.4), rot = CFrame.Angles(0, 0, math.rad(12)) },
			{ name = "EyeL", parent = "Head", size = Vector3.new(0.35, 0.25, 0.1), pos = Vector3.new(-0.55, 1.4, -4.7), color = Color3.fromRGB(255, 60, 40), mat = MAT.Neon },
			{ name = "EyeR", parent = "Head", size = Vector3.new(0.35, 0.25, 0.1), pos = Vector3.new(0.55, 1.4, -4.7), color = Color3.fromRGB(255, 60, 40), mat = MAT.Neon },
			{ name = "LegFL", parent = "Body", size = Vector3.new(0.7, 2.4, 0.7), pos = Vector3.new(-0.85, -2.2, -1.9), joint = Vector3.new(-0.85, -1, -1.9) },
			{ name = "LegFR", parent = "Body", size = Vector3.new(0.7, 2.4, 0.7), pos = Vector3.new(0.85, -2.2, -1.9), joint = Vector3.new(0.85, -1, -1.9) },
			{ name = "LegBL", parent = "Body", size = Vector3.new(0.75, 2.4, 0.75), pos = Vector3.new(-0.85, -2.2, 2), joint = Vector3.new(-0.85, -1, 2) },
			{ name = "LegBR", parent = "Body", size = Vector3.new(0.75, 2.4, 0.75), pos = Vector3.new(0.85, -2.2, 2), joint = Vector3.new(0.85, -1, 2) },
			{ name = "Tail", parent = "Body", size = Vector3.new(0.55, 0.55, 2.6), pos = Vector3.new(0, 1, 3.7), rot = CFrame.Angles(math.rad(30), 0, 0), joint = Vector3.new(0, 0.6, 2.7), color = Color3.fromRGB(150, 145, 150) },
		},
		animate = function(pose, phase, walk, atk, now)
			local s = sin(phase) * 0.7 * walk
			pose("LegFL", CFrame.Angles(s, 0, 0))
			pose("LegBR", CFrame.Angles(s, 0, 0))
			pose("LegFR", CFrame.Angles(-s, 0, 0))
			pose("LegBL", CFrame.Angles(-s, 0, 0))
			pose("Body", CFrame.new(0, math.abs(sin(phase)) * 0.25 * walk, 0))
			pose("Head", CFrame.new(0, 0, -atk * 0.8) * CFrame.Angles(-atk * 0.6 + sin(phase * 2) * 0.06 * walk, 0, 0))
			pose("Tail", CFrame.Angles(0, sin(now * 8) * 0.5, 0))
		end,
	},

	Skeleton = {
		displayName = "โครงกระดูก",
		hp = 80, damage = 12, speed = 13, coins = 12, reach = 4, aggro = 60, hip = 2.6, respawn = 20,
		root = Vector3.new(2, 2.6, 1.2), stepRate = 8,
		color = Color3.fromRGB(230, 225, 210), mat = MAT.SmoothPlastic,
		parts = {
			{ name = "Pelvis", size = Vector3.new(1.8, 0.5, 0.8), pos = Vector3.new(0, -1.1, 0) },
			{ name = "Spine", size = Vector3.new(0.4, 2.4, 0.4), pos = Vector3.new(0, 0.1, 0.2), joint = Vector3.new(0, -1, 0.2) },
			{ name = "Rib1", parent = "Spine", size = Vector3.new(2, 0.25, 1), pos = Vector3.new(0, 0.9, 0) },
			{ name = "Rib2", parent = "Spine", size = Vector3.new(1.9, 0.25, 0.95), pos = Vector3.new(0, 0.4, 0) },
			{ name = "Rib3", parent = "Spine", size = Vector3.new(1.7, 0.25, 0.9), pos = Vector3.new(0, -0.1, 0) },
			{ name = "Cape", parent = "Spine", size = Vector3.new(1.9, 2.6, 0.1), pos = Vector3.new(0, -0.2, 0.75), color = Color3.fromRGB(80, 30, 100), mat = MAT.Fabric, transparency = 0.1 },
			{ name = "Head", parent = "Spine", size = Vector3.new(1.4, 1.4, 1.5), pos = Vector3.new(0, 2.05, 0), joint = Vector3.new(0, 1.3, 0) },
			{ name = "Jaw", parent = "Head", size = Vector3.new(1.2, 0.35, 1.2), pos = Vector3.new(0, 1.2, -0.1), joint = Vector3.new(0, 1.4, 0.5) },
			{ name = "SocketL", parent = "Head", size = Vector3.new(0.4, 0.4, 0.1), pos = Vector3.new(-0.32, 2.2, -0.76), color = Color3.new(0, 0, 0) },
			{ name = "SocketR", parent = "Head", size = Vector3.new(0.4, 0.4, 0.1), pos = Vector3.new(0.32, 2.2, -0.76), color = Color3.new(0, 0, 0) },
			{ name = "EyeL", parent = "Head", size = Vector3.new(0.18, 0.18, 0.1), pos = Vector3.new(-0.32, 2.2, -0.8), color = Color3.fromRGB(255, 40, 40), mat = MAT.Neon },
			{ name = "EyeR", parent = "Head", size = Vector3.new(0.18, 0.18, 0.1), pos = Vector3.new(0.32, 2.2, -0.8), color = Color3.fromRGB(255, 40, 40), mat = MAT.Neon },
			{ name = "Helmet", parent = "Head", size = Vector3.new(1.6, 0.5, 1.7), pos = Vector3.new(0, 2.8, 0), color = Color3.fromRGB(110, 100, 90), mat = MAT.CorrodedMetal },
			{ name = "ArmL", parent = "Spine", size = Vector3.new(0.45, 2.4, 0.45), pos = Vector3.new(-1.3, 0.1, 0), joint = Vector3.new(-1.3, 1.2, 0) },
			{ name = "ArmR", parent = "Spine", size = Vector3.new(0.45, 2.4, 0.45), pos = Vector3.new(1.3, 0.1, 0), joint = Vector3.new(1.3, 1.2, 0) },
			{ name = "Shield", parent = "ArmL", size = Vector3.new(0.3, 2.2, 2), pos = Vector3.new(-1.65, -0.2, -0.3), color = Color3.fromRGB(100, 70, 45), mat = MAT.WoodPlanks },
			{ name = "ShieldBoss", parent = "ArmL", shape = Ball, size = 0.6, pos = Vector3.new(-1.8, -0.2, -0.3), color = Color3.fromRGB(110, 100, 90), mat = MAT.CorrodedMetal },
			{ name = "SwordGuard", parent = "ArmR", size = Vector3.new(0.3, 0.3, 1), pos = Vector3.new(1.3, -1.1, -0.3), color = Color3.fromRGB(90, 80, 70), mat = MAT.CorrodedMetal },
			{ name = "SwordBlade", parent = "ArmR", size = Vector3.new(0.15, 0.4, 3.2), pos = Vector3.new(1.3, -1.1, -2.2), color = Color3.fromRGB(130, 120, 110), mat = MAT.CorrodedMetal },
			{ name = "LegL", parent = "Pelvis", size = Vector3.new(0.5, 2.6, 0.5), pos = Vector3.new(-0.45, -2.6, 0), joint = Vector3.new(-0.45, -1.3, 0) },
			{ name = "LegR", parent = "Pelvis", size = Vector3.new(0.5, 2.6, 0.5), pos = Vector3.new(0.45, -2.6, 0), joint = Vector3.new(0.45, -1.3, 0) },
		},
		animate = function(pose, phase, walk, atk, now)
			local s = sin(phase) * 0.7 * walk
			pose("LegL", CFrame.Angles(s, 0, 0))
			pose("LegR", CFrame.Angles(-s, 0, 0))
			pose("ArmL", CFrame.Angles(-s * 0.6 + 0.3, 0, 0))
			pose("ArmR", CFrame.Angles(s * 0.6 + atk * 2, 0, 0))
			pose("Spine", CFrame.Angles(0, sin(phase) * 0.1 * walk, 0))
			pose("Jaw", CFrame.Angles(math.max(0, sin(now * 10)) * 0.3, 0, 0))
		end,
	},

	Ghost = {
		displayName = "วิญญาณ",
		hp = 55, damage = 10, speed = 12, coins = 10, reach = 4, aggro = 50, hip = 3, respawn = 20,
		root = Vector3.new(2.4, 3, 2.4), stepRate = 3,
		color = Color3.fromRGB(225, 235, 255), mat = MAT.Glass,
		parts = {
			{ name = "Head", shape = Ball, size = 3.2, pos = Vector3.new(0, 0.4, 0), transparency = 0.35, light = Color3.fromRGB(170, 200, 255) },
			{ name = "Tail1", parent = "Head", shape = Cyl, size = Vector3.new(1.2, 2.6, 2.6), pos = Vector3.new(0, -1.4, 0), rot = CFrame.Angles(0, 0, math.rad(90)), joint = Vector3.new(0, -0.8, 0), transparency = 0.4 },
			{ name = "Tail2", parent = "Tail1", shape = Cyl, size = Vector3.new(1.2, 1.8, 1.8), pos = Vector3.new(0, -2.4, 0.2), rot = CFrame.Angles(0, 0, math.rad(90)), joint = Vector3.new(0, -1.9, 0), transparency = 0.5 },
			{ name = "Tail3", parent = "Tail2", shape = Ball, size = 1, pos = Vector3.new(0, -3.3, 0.5), joint = Vector3.new(0, -2.9, 0.2), transparency = 0.6 },
			{ name = "EyeL", parent = "Head", shape = Ball, size = 0.6, pos = Vector3.new(-0.55, 0.9, -1.35), color = Color3.new(0, 0, 0), mat = MAT.SmoothPlastic },
			{ name = "EyeR", parent = "Head", shape = Ball, size = 0.6, pos = Vector3.new(0.55, 0.9, -1.35), color = Color3.new(0, 0, 0), mat = MAT.SmoothPlastic },
			{ name = "Mouth", parent = "Head", size = Vector3.new(0.6, 0.8, 0.1), pos = Vector3.new(0, -0.1, -1.55), color = Color3.new(0, 0, 0), mat = MAT.SmoothPlastic },
			{ name = "ArmL", parent = "Head", size = Vector3.new(0.5, 1.6, 0.5), pos = Vector3.new(-1.75, -0.2, -0.3), joint = Vector3.new(-1.4, 0.6, 0), transparency = 0.4 },
			{ name = "ArmR", parent = "Head", size = Vector3.new(0.5, 1.6, 0.5), pos = Vector3.new(1.75, -0.2, -0.3), joint = Vector3.new(1.4, 0.6, 0), transparency = 0.4 },
		},
		animate = function(pose, phase, walk, atk, now)
			pose("Head", CFrame.new(0, sin(now * 2) * 0.5, 0) * CFrame.Angles(-atk * 0.4 + walk * 0.15, 0, 0))
			pose("Tail1", CFrame.Angles(sin(now * 3) * 0.15, 0, sin(now * 2) * 0.1))
			pose("Tail2", CFrame.Angles(sin(now * 3 + 1) * 0.25, 0, 0))
			pose("Tail3", CFrame.Angles(sin(now * 3 + 2) * 0.35, 0, 0))
			pose("ArmL", CFrame.Angles(0.4 + atk * 1.4 + sin(now * 3) * 0.3, 0, 0))
			pose("ArmR", CFrame.Angles(0.4 + atk * 1.4 + sin(now * 3 + 1.5) * 0.3, 0, 0))
		end,
	},

	Bat = {
		displayName = "ค้างคาว",
		hp = 30, damage = 6, speed = 20, coins = 6, reach = 5, aggro = 50, hip = 5, respawn = 15,
		root = Vector3.new(2, 2, 2), stepRate = 1,
		color = Color3.fromRGB(60, 45, 70), mat = MAT.Fabric,
		parts = {
			{ name = "Body", shape = Ball, size = 1.8, pos = Vector3.zero },
			{ name = "Belly", parent = "Body", shape = Ball, size = 1.3, pos = Vector3.new(0, -0.2, -0.4), color = Color3.fromRGB(105, 85, 105) },
			{ name = "Head", parent = "Body", shape = Ball, size = 1.4, pos = Vector3.new(0, 1.1, -0.3), joint = Vector3.new(0, 0.6, -0.2) },
			{ name = "EarL", parent = "Head", size = Vector3.new(0.35, 1, 0.35), pos = Vector3.new(-0.45, 1.95, -0.3), rot = CFrame.Angles(0, 0, math.rad(15)) },
			{ name = "EarR", parent = "Head", size = Vector3.new(0.35, 1, 0.35), pos = Vector3.new(0.45, 1.95, -0.3), rot = CFrame.Angles(0, 0, math.rad(-15)) },
			{ name = "EarInL", parent = "Head", size = Vector3.new(0.15, 0.7, 0.1), pos = Vector3.new(-0.45, 1.9, -0.5), rot = CFrame.Angles(0, 0, math.rad(15)), color = Color3.fromRGB(230, 130, 160), mat = MAT.SmoothPlastic },
			{ name = "EarInR", parent = "Head", size = Vector3.new(0.15, 0.7, 0.1), pos = Vector3.new(0.45, 1.9, -0.5), rot = CFrame.Angles(0, 0, math.rad(-15)), color = Color3.fromRGB(230, 130, 160), mat = MAT.SmoothPlastic },
			{ name = "EyeL", parent = "Head", shape = Ball, size = 0.3, pos = Vector3.new(-0.3, 1.25, -0.9), color = Color3.fromRGB(255, 40, 40), mat = MAT.Neon },
			{ name = "EyeR", parent = "Head", shape = Ball, size = 0.3, pos = Vector3.new(0.3, 1.25, -0.9), color = Color3.fromRGB(255, 40, 40), mat = MAT.Neon },
			{ name = "Nose", parent = "Head", shape = Ball, size = 0.25, pos = Vector3.new(0, 1.0, -1), color = Color3.fromRGB(230, 130, 160), mat = MAT.SmoothPlastic },
			{ name = "FangL", parent = "Head", size = Vector3.new(0.1, 0.3, 0.1), pos = Vector3.new(-0.15, 0.7, -0.88), color = Color3.new(1, 1, 1), mat = MAT.SmoothPlastic },
			{ name = "FangR", parent = "Head", size = Vector3.new(0.1, 0.3, 0.1), pos = Vector3.new(0.15, 0.7, -0.88), color = Color3.new(1, 1, 1), mat = MAT.SmoothPlastic },
			-- ปีก 2 ท่อนต่อข้าง: ท่อนในติดตัว ท่อนนอกติดท่อนใน
			{ name = "WingL1", parent = "Body", size = Vector3.new(2.3, 0.1, 1.7), pos = Vector3.new(-1.9, 0.3, 0), joint = Vector3.new(-0.8, 0.3, 0), color = Color3.fromRGB(45, 30, 55), transparency = 0.1 },
			{ name = "WingBoneL", parent = "WingL1", size = Vector3.new(4.4, 0.2, 0.2), pos = Vector3.new(-3, 0.35, -0.8), color = Color3.fromRGB(80, 60, 90) },
			{ name = "WingL2", parent = "WingL1", size = Vector3.new(2.2, 0.08, 1.4), pos = Vector3.new(-4.1, 0.3, 0.1), joint = Vector3.new(-3, 0.3, 0), color = Color3.fromRGB(45, 30, 55), transparency = 0.1 },
			{ name = "WingR1", parent = "Body", size = Vector3.new(2.3, 0.1, 1.7), pos = Vector3.new(1.9, 0.3, 0), joint = Vector3.new(0.8, 0.3, 0), color = Color3.fromRGB(45, 30, 55), transparency = 0.1 },
			{ name = "WingBoneR", parent = "WingR1", size = Vector3.new(4.4, 0.2, 0.2), pos = Vector3.new(3, 0.35, -0.8), color = Color3.fromRGB(80, 60, 90) },
			{ name = "WingR2", parent = "WingR1", size = Vector3.new(2.2, 0.08, 1.4), pos = Vector3.new(4.1, 0.3, 0.1), joint = Vector3.new(3, 0.3, 0), color = Color3.fromRGB(45, 30, 55), transparency = 0.1 },
			{ name = "FootL", parent = "Body", size = Vector3.new(0.25, 0.5, 0.25), pos = Vector3.new(-0.35, -1.1, 0.2), color = Color3.fromRGB(40, 30, 45) },
			{ name = "FootR", parent = "Body", size = Vector3.new(0.25, 0.5, 0.25), pos = Vector3.new(0.35, -1.1, 0.2), color = Color3.fromRGB(40, 30, 45) },
		},
		animate = function(pose, phase, walk, atk, now)
			local flap = sin(now * 16) * 0.7
			local tip = sin(now * 16 - 0.6) * 0.45
			pose("WingL1", CFrame.Angles(0, 0, flap))
			pose("WingR1", CFrame.Angles(0, 0, -flap))
			pose("WingL2", CFrame.Angles(0, 0, tip))
			pose("WingR2", CFrame.Angles(0, 0, -tip))
			-- บินขึ้นลงเบา ๆ และโฉบลงกัดตอนโจมตี
			pose("Body", CFrame.new(0, sin(now * 4) * 0.4 - atk * 2.5, -atk * 1.5) * CFrame.Angles(-atk * 0.6 - walk * 0.2, 0, 0))
			pose("Head", CFrame.Angles(0, sin(now * 1.3) * 0.3, 0))
		end,
	},

	Goblin = {
		displayName = "ก็อบลิน",
		hp = 50, damage = 9, speed = 16, coins = 7, reach = 3.5, aggro = 55, hip = 1.6, respawn = 18,
		root = Vector3.new(1.8, 2, 1.2), stepRate = 11,
		color = Color3.fromRGB(110, 160, 70), mat = MAT.SmoothPlastic,
		parts = {
			{ name = "Torso", size = Vector3.new(1.8, 2, 1.1), pos = Vector3.zero, joint = Vector3.new(0, -1, 0), color = Color3.fromRGB(100, 70, 45), mat = MAT.Fabric },
			{ name = "Belt", parent = "Torso", size = Vector3.new(1.9, 0.3, 1.2), pos = Vector3.new(0, -0.8, 0), color = Color3.fromRGB(55, 40, 30), mat = MAT.Fabric },
			{ name = "Loincloth", parent = "Torso", size = Vector3.new(1.2, 0.9, 0.15), pos = Vector3.new(0, -1.3, -0.6), color = Color3.fromRGB(120, 80, 50), mat = MAT.Fabric },
			{ name = "Head", parent = "Torso", size = Vector3.new(1.6, 1.4, 1.4), pos = Vector3.new(0, 1.75, -0.1), joint = Vector3.new(0, 1, 0) },
			{ name = "Nose", parent = "Head", size = Vector3.new(0.35, 0.5, 0.6), pos = Vector3.new(0, 1.65, -0.95) },
			{ name = "EarL", parent = "Head", size = Vector3.new(1.2, 0.25, 0.5), pos = Vector3.new(-1.25, 1.95, 0), rot = CFrame.Angles(0, 0, math.rad(-20)), joint = Vector3.new(-0.8, 1.9, 0) },
			{ name = "EarR", parent = "Head", size = Vector3.new(1.2, 0.25, 0.5), pos = Vector3.new(1.25, 1.95, 0), rot = CFrame.Angles(0, 0, math.rad(20)), joint = Vector3.new(0.8, 1.9, 0) },
			{ name = "EyeL", parent = "Head", size = Vector3.new(0.3, 0.25, 0.1), pos = Vector3.new(-0.35, 1.95, -0.82), color = Color3.fromRGB(255, 230, 40), mat = MAT.Neon },
			{ name = "EyeR", parent = "Head", size = Vector3.new(0.3, 0.25, 0.1), pos = Vector3.new(0.35, 1.95, -0.82), color = Color3.fromRGB(255, 230, 40), mat = MAT.Neon },
			{ name = "Teeth", parent = "Head", size = Vector3.new(0.7, 0.15, 0.1), pos = Vector3.new(0, 1.3, -0.82), color = Color3.fromRGB(240, 235, 200) },
			{ name = "Bandana", parent = "Head", size = Vector3.new(1.7, 0.35, 1.5), pos = Vector3.new(0, 2.35, -0.1), color = Color3.fromRGB(170, 40, 40), mat = MAT.Fabric },
			{ name = "ArmL", parent = "Torso", size = Vector3.new(0.5, 1.8, 0.5), pos = Vector3.new(-1.15, 0.1, 0), joint = Vector3.new(-1.15, 0.9, 0) },
			{ name = "ArmR", parent = "Torso", size = Vector3.new(0.5, 1.8, 0.5), pos = Vector3.new(1.15, 0.1, 0), joint = Vector3.new(1.15, 0.9, 0) },
			{ name = "Club", parent = "ArmR", size = Vector3.new(0.4, 0.4, 2.4), pos = Vector3.new(1.15, -0.8, -1), color = Color3.fromRGB(110, 75, 45), mat = MAT.Wood },
			{ name = "ClubHead", parent = "ArmR", size = Vector3.new(0.9, 0.9, 1.1), pos = Vector3.new(1.15, -0.8, -2.5), color = Color3.fromRGB(90, 60, 40), mat = MAT.Wood },
			{ name = "LegL", parent = "Torso", size = Vector3.new(0.6, 1.6, 0.6), pos = Vector3.new(-0.45, -1.8, 0), joint = Vector3.new(-0.45, -1, 0) },
			{ name = "LegR", parent = "Torso", size = Vector3.new(0.6, 1.6, 0.6), pos = Vector3.new(0.45, -1.8, 0), joint = Vector3.new(0.45, -1, 0) },
			{ name = "FootL", parent = "LegL", size = Vector3.new(0.7, 0.3, 0.9), pos = Vector3.new(-0.45, -2.5, -0.15) },
			{ name = "FootR", parent = "LegR", size = Vector3.new(0.7, 0.3, 0.9), pos = Vector3.new(0.45, -2.5, -0.15) },
		},
		animate = function(pose, phase, walk, atk, now)
			local s = sin(phase) * 0.8 * walk
			pose("LegL", CFrame.Angles(s, 0, 0))
			pose("LegR", CFrame.Angles(-s, 0, 0))
			pose("ArmL", CFrame.Angles(-s * 0.7, 0, 0))
			pose("ArmR", CFrame.Angles(s * 0.7 + atk * 2.2, 0, 0))
			pose("Torso", CFrame.new(0, math.abs(sin(phase)) * 0.15 * walk, 0) * CFrame.Angles(0.15 * walk, 0, 0))
			pose("EarL", CFrame.Angles(0, 0, sin(now * 6) * 0.15))
			pose("EarR", CFrame.Angles(0, 0, -sin(now * 6) * 0.15))
		end,
	},

	Minotaur = {
		displayName = "👑 มิโนทอร์ (บอส)",
		hp = 900, damage = 35, speed = 13, coins = 200, reach = 6, aggro = 70, hip = 3.5, respawn = 90,
		root = Vector3.new(5, 5, 3), stepRate = 6,
		color = Color3.fromRGB(95, 60, 40), mat = MAT.Fabric,
		parts = {
			{ name = "Torso", size = Vector3.new(5, 5, 3), pos = Vector3.zero, joint = Vector3.new(0, -2.5, 0) },
			{ name = "Chest", parent = "Torso", size = Vector3.new(4.4, 2.4, 0.4), pos = Vector3.new(0, 1, -1.55), color = Color3.fromRGB(140, 95, 70) },
			{ name = "Belt", parent = "Torso", size = Vector3.new(5.2, 0.8, 3.2), pos = Vector3.new(0, -2.2, 0), color = Color3.fromRGB(50, 35, 25) },
			{ name = "Buckle", parent = "Torso", size = Vector3.new(1, 0.8, 0.2), pos = Vector3.new(0, -2.2, -1.65), color = Color3.fromRGB(255, 200, 60), mat = MAT.Foil },
			{ name = "Loin", parent = "Torso", size = Vector3.new(3, 2, 0.3), pos = Vector3.new(0, -3.4, -1.5), color = Color3.fromRGB(120, 25, 30) },
			{ name = "Head", parent = "Torso", size = Vector3.new(2.6, 2.6, 2.8), pos = Vector3.new(0, 3.8, -0.8), joint = Vector3.new(0, 2.6, -0.3) },
			{ name = "Snout", parent = "Head", size = Vector3.new(1.8, 1.3, 1.2), pos = Vector3.new(0, 3.3, -2.6), color = Color3.fromRGB(130, 90, 70) },
			{ name = "NoseRing", parent = "Head", shape = Ball, size = 0.5, pos = Vector3.new(0, 2.75, -3.25), color = Color3.fromRGB(255, 200, 60), mat = MAT.Foil },
			{ name = "HornL", parent = "Head", size = Vector3.new(1.8, 0.7, 0.7), pos = Vector3.new(-2, 4.8, -0.8), rot = CFrame.Angles(0, 0, math.rad(20)), color = Color3.fromRGB(230, 220, 190), mat = MAT.SmoothPlastic },
			{ name = "HornTipL", parent = "Head", size = Vector3.new(0.5, 1.6, 0.5), pos = Vector3.new(-2.9, 5.7, -0.8), rot = CFrame.Angles(0, 0, math.rad(-15)), color = Color3.fromRGB(230, 220, 190), mat = MAT.SmoothPlastic },
			{ name = "HornR", parent = "Head", size = Vector3.new(1.8, 0.7, 0.7), pos = Vector3.new(2, 4.8, -0.8), rot = CFrame.Angles(0, 0, math.rad(-20)), color = Color3.fromRGB(230, 220, 190), mat = MAT.SmoothPlastic },
			{ name = "HornTipR", parent = "Head", size = Vector3.new(0.5, 1.6, 0.5), pos = Vector3.new(2.9, 5.7, -0.8), rot = CFrame.Angles(0, 0, math.rad(15)), color = Color3.fromRGB(230, 220, 190), mat = MAT.SmoothPlastic },
			{ name = "EyeL", parent = "Head", size = Vector3.new(0.4, 0.3, 0.1), pos = Vector3.new(-0.7, 4.2, -2.22), color = Color3.fromRGB(255, 40, 30), mat = MAT.Neon },
			{ name = "EyeR", parent = "Head", size = Vector3.new(0.4, 0.3, 0.1), pos = Vector3.new(0.7, 4.2, -2.22), color = Color3.fromRGB(255, 40, 30), mat = MAT.Neon },
			{ name = "ArmL", parent = "Torso", size = Vector3.new(1.6, 4, 1.6), pos = Vector3.new(-3.4, 0.4, 0), joint = Vector3.new(-3.2, 2.2, 0) },
			{ name = "BracerL", parent = "ArmL", size = Vector3.new(1.8, 1, 1.8), pos = Vector3.new(-3.4, -0.8, 0), color = Color3.fromRGB(90, 90, 100), mat = MAT.Metal },
			{ name = "ArmR", parent = "Torso", size = Vector3.new(1.6, 4, 1.6), pos = Vector3.new(3.4, 0.4, 0), joint = Vector3.new(3.2, 2.2, 0) },
			{ name = "BracerR", parent = "ArmR", size = Vector3.new(1.8, 1, 1.8), pos = Vector3.new(3.4, -0.8, 0), color = Color3.fromRGB(90, 90, 100), mat = MAT.Metal },
			{ name = "AxeHandle", parent = "ArmR", size = Vector3.new(0.4, 0.4, 7), pos = Vector3.new(3.4, -1.5, -2.8), color = Color3.fromRGB(70, 50, 35), mat = MAT.Wood },
			{ name = "AxeBladeTop", parent = "ArmR", size = Vector3.new(0.3, 2.4, 2.6), pos = Vector3.new(3.4, -0.1, -5.6), color = Color3.fromRGB(150, 150, 160), mat = MAT.Metal },
			{ name = "AxeBladeBottom", parent = "ArmR", size = Vector3.new(0.3, 2.4, 2.6), pos = Vector3.new(3.4, -2.9, -5.6), color = Color3.fromRGB(150, 150, 160), mat = MAT.Metal },
			{ name = "LegL", parent = "Torso", size = Vector3.new(1.8, 3, 1.8), pos = Vector3.new(-1.2, -4, 0), joint = Vector3.new(-1.2, -2.5, 0) },
			{ name = "HoofL", parent = "LegL", size = Vector3.new(1.9, 0.8, 2), pos = Vector3.new(-1.2, -5.6, -0.1), color = Color3.fromRGB(40, 35, 30) },
			{ name = "LegR", parent = "Torso", size = Vector3.new(1.8, 3, 1.8), pos = Vector3.new(1.2, -4, 0), joint = Vector3.new(1.2, -2.5, 0) },
			{ name = "HoofR", parent = "LegR", size = Vector3.new(1.9, 0.8, 2), pos = Vector3.new(1.2, -5.6, -0.1), color = Color3.fromRGB(40, 35, 30) },
			{ name = "Tail", parent = "Torso", size = Vector3.new(0.3, 2.5, 0.3), pos = Vector3.new(0, -2.2, 1.9), rot = CFrame.Angles(math.rad(30), 0, 0), joint = Vector3.new(0, -1.2, 1.6) },
		},
		animate = function(pose, phase, walk, atk, now)
			local s = sin(phase) * 0.55 * walk
			pose("LegL", CFrame.Angles(s, 0, 0))
			pose("LegR", CFrame.Angles(-s, 0, 0))
			pose("ArmL", CFrame.Angles(-s * 0.6 + atk * 1.2, 0, 0))
			pose("ArmR", CFrame.Angles(s * 0.6 + atk * 2.6, 0, 0))
			pose("Torso", CFrame.new(0, math.abs(sin(phase)) * 0.3 * walk, 0) * CFrame.Angles(atk * 0.25, sin(phase) * 0.08 * walk, 0))
			pose("Head", CFrame.Angles(-atk * 0.3 + sin(now * 2) * 0.05, 0, 0))
			pose("Tail", CFrame.Angles(0, 0, sin(now * 5) * 0.4))
		end,
	},

	Dragon = {
		displayName = "🐉 มังกรเพลิง (บอส)",
		hp = 1500, damage = 40, speed = 24, coins = 400, reach = 20, aggro = 110, hip = 16, respawn = 150,
		root = Vector3.new(8, 6, 14), stepRate = 3, ranged = true, attackEffect = "fire",
		color = Color3.fromRGB(150, 30, 30), mat = MAT.Slate,
		parts = {
			{ name = "Body", size = Vector3.new(7, 6, 12), pos = Vector3.zero },
			{ name = "Belly", parent = "Body", size = Vector3.new(6, 3, 10), pos = Vector3.new(0, -2, 0), color = Color3.fromRGB(210, 150, 70), mat = MAT.SmoothPlastic },
			{ name = "Spike1", parent = "Body", size = Vector3.new(0.6, 1.8, 1.2), pos = Vector3.new(0, 3.8, -4), color = Color3.fromRGB(60, 20, 20) },
			{ name = "Spike2", parent = "Body", size = Vector3.new(0.6, 2.2, 1.2), pos = Vector3.new(0, 3.9, -1), color = Color3.fromRGB(60, 20, 20) },
			{ name = "Spike3", parent = "Body", size = Vector3.new(0.6, 2, 1.2), pos = Vector3.new(0, 3.8, 2), color = Color3.fromRGB(60, 20, 20) },
			{ name = "Spike4", parent = "Body", size = Vector3.new(0.6, 1.6, 1.2), pos = Vector3.new(0, 3.7, 5), color = Color3.fromRGB(60, 20, 20) },
			{ name = "Neck1", parent = "Body", size = Vector3.new(3, 3, 5), pos = Vector3.new(0, 2.5, -8), rot = CFrame.Angles(math.rad(30), 0, 0), joint = Vector3.new(0, 1.5, -5.5) },
			{ name = "Neck2", parent = "Neck1", size = Vector3.new(2.6, 2.6, 5), pos = Vector3.new(0, 5, -11.5), rot = CFrame.Angles(math.rad(20), 0, 0), joint = Vector3.new(0, 4, -10) },
			{ name = "Head", parent = "Neck2", size = Vector3.new(3.6, 3, 5.5), pos = Vector3.new(0, 6.5, -15.5), joint = Vector3.new(0, 6, -13.5) },
			{ name = "Jaw", parent = "Head", size = Vector3.new(3, 1, 4.5), pos = Vector3.new(0, 4.6, -16), joint = Vector3.new(0, 5.2, -14) },
			{ name = "Teeth", parent = "Head", size = Vector3.new(2.8, 0.4, 0.3), pos = Vector3.new(0, 5.1, -18.1), color = Color3.new(1, 1, 1), mat = MAT.SmoothPlastic },
			{ name = "Mouth", parent = "Head", size = Vector3.new(1, 1, 1), pos = Vector3.new(0, 5.4, -18.6), transparency = 1 },
			{ name = "HornL", parent = "Head", size = Vector3.new(0.6, 0.6, 3.5), pos = Vector3.new(-1.2, 8.3, -13.6), rot = CFrame.Angles(math.rad(-30), 0, 0), color = Color3.fromRGB(230, 220, 190), mat = MAT.SmoothPlastic },
			{ name = "HornR", parent = "Head", size = Vector3.new(0.6, 0.6, 3.5), pos = Vector3.new(1.2, 8.3, -13.6), rot = CFrame.Angles(math.rad(-30), 0, 0), color = Color3.fromRGB(230, 220, 190), mat = MAT.SmoothPlastic },
			{ name = "EyeL", parent = "Head", size = Vector3.new(0.5, 0.4, 0.2), pos = Vector3.new(-1.3, 7.2, -17.1), color = Color3.fromRGB(255, 220, 40), mat = MAT.Neon },
			{ name = "EyeR", parent = "Head", size = Vector3.new(0.5, 0.4, 0.2), pos = Vector3.new(1.3, 7.2, -17.1), color = Color3.fromRGB(255, 220, 40), mat = MAT.Neon },
			{ name = "WingL1", parent = "Body", size = Vector3.new(10, 0.4, 7), pos = Vector3.new(-8.5, 3, 0), joint = Vector3.new(-3.5, 3, 0), color = Color3.fromRGB(110, 20, 25), transparency = 0.05 },
			{ name = "WingBoneL", parent = "WingL1", size = Vector3.new(19, 0.6, 0.6), pos = Vector3.new(-12.5, 3.3, -3.3), color = Color3.fromRGB(70, 20, 20) },
			{ name = "WingL2", parent = "WingL1", size = Vector3.new(10, 0.3, 6), pos = Vector3.new(-18, 3, 0.8), joint = Vector3.new(-13.5, 3, 0), color = Color3.fromRGB(110, 20, 25), transparency = 0.05 },
			{ name = "WingR1", parent = "Body", size = Vector3.new(10, 0.4, 7), pos = Vector3.new(8.5, 3, 0), joint = Vector3.new(3.5, 3, 0), color = Color3.fromRGB(110, 20, 25), transparency = 0.05 },
			{ name = "WingBoneR", parent = "WingR1", size = Vector3.new(19, 0.6, 0.6), pos = Vector3.new(12.5, 3.3, -3.3), color = Color3.fromRGB(70, 20, 20) },
			{ name = "WingR2", parent = "WingR1", size = Vector3.new(10, 0.3, 6), pos = Vector3.new(18, 3, 0.8), joint = Vector3.new(13.5, 3, 0), color = Color3.fromRGB(110, 20, 25), transparency = 0.05 },
			{ name = "LegFL", parent = "Body", size = Vector3.new(1.8, 5, 1.8), pos = Vector3.new(-2.5, -4.5, -3.5), joint = Vector3.new(-2.5, -2, -3.5) },
			{ name = "LegFR", parent = "Body", size = Vector3.new(1.8, 5, 1.8), pos = Vector3.new(2.5, -4.5, -3.5), joint = Vector3.new(2.5, -2, -3.5) },
			{ name = "LegBL", parent = "Body", size = Vector3.new(2, 5, 2), pos = Vector3.new(-2.5, -4.5, 3.5), joint = Vector3.new(-2.5, -2, 3.5) },
			{ name = "LegBR", parent = "Body", size = Vector3.new(2, 5, 2), pos = Vector3.new(2.5, -4.5, 3.5), joint = Vector3.new(2.5, -2, 3.5) },
			{ name = "Tail1", parent = "Body", size = Vector3.new(2.6, 2.6, 6), pos = Vector3.new(0, 0.5, 9), joint = Vector3.new(0, 0.5, 6) },
			{ name = "Tail2", parent = "Tail1", size = Vector3.new(2, 2, 6), pos = Vector3.new(0, 0.5, 15), joint = Vector3.new(0, 0.5, 12) },
			{ name = "Tail3", parent = "Tail2", size = Vector3.new(1.4, 1.4, 6), pos = Vector3.new(0, 0.5, 21), joint = Vector3.new(0, 0.5, 18) },
			{ name = "TailSpike", parent = "Tail3", size = Vector3.new(0.4, 3, 3), pos = Vector3.new(0, 0.5, 24.5), rot = CFrame.Angles(math.rad(45), 0, 0), color = Color3.fromRGB(60, 20, 20) },
		},
		animate = function(pose, phase, walk, atk, now)
			local flap = sin(now * 4) * 0.6
			pose("WingL1", CFrame.Angles(0, 0, flap))
			pose("WingR1", CFrame.Angles(0, 0, -flap))
			pose("WingL2", CFrame.Angles(0, 0, sin(now * 4 - 0.7) * 0.5))
			pose("WingR2", CFrame.Angles(0, 0, -sin(now * 4 - 0.7) * 0.5))
			pose("Body", CFrame.new(0, sin(now * 2) * 1.5, 0))
			pose("Tail1", CFrame.Angles(0, sin(now * 1.5) * 0.25, 0))
			pose("Tail2", CFrame.Angles(0, sin(now * 1.5 - 0.8) * 0.3, 0))
			pose("Tail3", CFrame.Angles(0, sin(now * 1.5 - 1.6) * 0.35, 0))
			pose("Neck1", CFrame.Angles(-atk * 0.3, sin(now * 0.8) * 0.15, 0))
			pose("Head", CFrame.Angles(-atk * 0.4, 0, 0))
			pose("Jaw", CFrame.Angles(atk * 0.7, 0, 0))
			local s = sin(now * 3) * 0.2
			pose("LegFL", CFrame.Angles(0.4 + s, 0, 0))
			pose("LegFR", CFrame.Angles(0.4 - s, 0, 0))
			pose("LegBL", CFrame.Angles(0.6 - s, 0, 0))
			pose("LegBR", CFrame.Angles(0.6 + s, 0, 0))
		end,
	},

	Snake = {
		displayName = "งูยักษ์",
		hp = 45, damage = 10, speed = 14, coins = 7, reach = 3, aggro = 45, hip = 0.2, respawn = 15,
		root = Vector3.new(2, 1.2, 3), stepRate = 6,
		color = Color3.fromRGB(60, 110, 50), mat = MAT.Slate,
		parts = (function()
			local list = {
				{ name = "Head", size = Vector3.new(1.6, 1, 2.2), pos = Vector3.new(0, 0.3, -2), joint = Vector3.new(0, 0.2, -1) },
				{ name = "Hood", parent = "Head", size = Vector3.new(3, 2, 0.3), pos = Vector3.new(0, 0.9, -0.9), color = Color3.fromRGB(200, 180, 60) },
				{ name = "EyeL", parent = "Head", size = Vector3.new(0.3, 0.3, 0.3), pos = Vector3.new(-0.62, 0.65, -2.6), color = Color3.fromRGB(255, 230, 40), mat = MAT.Neon },
				{ name = "EyeR", parent = "Head", size = Vector3.new(0.3, 0.3, 0.3), pos = Vector3.new(0.62, 0.65, -2.6), color = Color3.fromRGB(255, 230, 40), mat = MAT.Neon },
				{ name = "Tongue", parent = "Head", size = Vector3.new(0.15, 0.1, 1), pos = Vector3.new(0, 0.1, -3.5), joint = Vector3.new(0, 0.1, -3), color = Color3.fromRGB(220, 30, 60), mat = MAT.SmoothPlastic },
			}
			local parent = "Root"
			for i = 1, 7 do
				local w = 1.5 - i * 0.13
				table.insert(list, {
					name = "Seg" .. i, parent = parent,
					size = Vector3.new(w, w * 0.8, 2.1), pos = Vector3.new(0, -0.1, 0.5 + i * 2), joint = Vector3.new(0, -0.1, -0.5 + i * 2),
					color = (i % 2 == 0) and Color3.fromRGB(200, 180, 60) or Color3.fromRGB(60, 110, 50),
				})
				parent = "Seg" .. i
			end
			return list
		end)(),
		animate = function(pose, phase, walk, atk, now)
			local amp = 0.35 * (0.3 + walk)
			for i = 1, 7 do
				pose("Seg" .. i, CFrame.Angles(0, sin(phase - i * 0.7) * amp, 0))
			end
			pose("Head", CFrame.new(0, atk * 0.6, -atk * 1.5) * CFrame.Angles(atk * 0.3, -sin(phase) * amp * 0.5, 0))
			pose("Tongue", CFrame.new(0, 0, -math.max(0, sin(now * 8)) * 0.4))
		end,
	},

	EvilEye = {
		displayName = "ตาปีศาจ",
		hp = 60, damage = 12, speed = 11, coins = 12, reach = 18, aggro = 60, hip = 6, respawn = 25,
		root = Vector3.new(3, 3, 3), stepRate = 1, ranged = true, attackEffect = "beam",
		color = Color3.fromRGB(120, 40, 70), mat = MAT.SmoothPlastic,
		parts = {
			{ name = "Head", shape = Ball, size = 3.6, pos = Vector3.zero, color = Color3.fromRGB(240, 235, 225) },
			{ name = "Iris", parent = "Head", shape = Cyl, size = Vector3.new(0.2, 1.9, 1.9), pos = Vector3.new(0, 0, -1.72), rot = CFrame.Angles(0, math.rad(90), 0), color = Color3.fromRGB(190, 40, 220), mat = MAT.Neon, light = Color3.fromRGB(200, 60, 255) },
			{ name = "Pupil", parent = "Head", shape = Cyl, size = Vector3.new(0.2, 0.8, 0.8), pos = Vector3.new(0, 0, -1.82), rot = CFrame.Angles(0, math.rad(90), 0), color = Color3.new(0, 0, 0) },
			{ name = "Glint", parent = "Head", shape = Ball, size = 0.3, pos = Vector3.new(0.35, 0.4, -1.85), color = Color3.new(1, 1, 1), mat = MAT.Neon },
			{ name = "LidTop", parent = "Head", size = Vector3.new(3.2, 0.6, 1.4), pos = Vector3.new(0, 1.55, -1), rot = CFrame.Angles(math.rad(-25), 0, 0), joint = Vector3.new(0, 1.5, 0) },
			{ name = "LidBottom", parent = "Head", size = Vector3.new(3, 0.5, 1.2), pos = Vector3.new(0, -1.55, -1), rot = CFrame.Angles(math.rad(25), 0, 0) },
			{ name = "Vein1", parent = "Head", size = Vector3.new(0.1, 0.1, 1.4), pos = Vector3.new(-1.1, 0.6, -1.3), rot = CFrame.Angles(0, math.rad(30), 0), color = Color3.fromRGB(230, 40, 40), mat = MAT.Neon },
			{ name = "Vein2", parent = "Head", size = Vector3.new(0.1, 0.1, 1.4), pos = Vector3.new(1.1, -0.5, -1.3), rot = CFrame.Angles(0, math.rad(-30), 0), color = Color3.fromRGB(230, 40, 40), mat = MAT.Neon },
			{ name = "WingL1", parent = "Head", size = Vector3.new(2.6, 0.1, 1.8), pos = Vector3.new(-2.9, 0.6, 0.5), joint = Vector3.new(-1.6, 0.6, 0.5), color = Color3.fromRGB(90, 30, 60), transparency = 0.1 },
			{ name = "WingL2", parent = "WingL1", size = Vector3.new(2.2, 0.08, 1.4), pos = Vector3.new(-5.2, 0.6, 0.7), joint = Vector3.new(-4.2, 0.6, 0.5), color = Color3.fromRGB(90, 30, 60), transparency = 0.1 },
			{ name = "WingR1", parent = "Head", size = Vector3.new(2.6, 0.1, 1.8), pos = Vector3.new(2.9, 0.6, 0.5), joint = Vector3.new(1.6, 0.6, 0.5), color = Color3.fromRGB(90, 30, 60), transparency = 0.1 },
			{ name = "WingR2", parent = "WingR1", size = Vector3.new(2.2, 0.08, 1.4), pos = Vector3.new(5.2, 0.6, 0.7), joint = Vector3.new(4.2, 0.6, 0.5), color = Color3.fromRGB(90, 30, 60), transparency = 0.1 },
			{ name = "Tent1a", parent = "Head", size = Vector3.new(0.45, 1.4, 0.45), pos = Vector3.new(-0.8, -2.1, 0.8), joint = Vector3.new(-0.8, -1.4, 0.8) },
			{ name = "Tent1b", parent = "Tent1a", size = Vector3.new(0.35, 1.3, 0.35), pos = Vector3.new(-0.8, -3.4, 0.8), joint = Vector3.new(-0.8, -2.8, 0.8), color = Color3.fromRGB(200, 60, 230), mat = MAT.Neon },
			{ name = "Tent2a", parent = "Head", size = Vector3.new(0.45, 1.4, 0.45), pos = Vector3.new(0, -2.1, 1), joint = Vector3.new(0, -1.4, 1) },
			{ name = "Tent2b", parent = "Tent2a", size = Vector3.new(0.35, 1.3, 0.35), pos = Vector3.new(0, -3.4, 1), joint = Vector3.new(0, -2.8, 1), color = Color3.fromRGB(200, 60, 230), mat = MAT.Neon },
			{ name = "Tent3a", parent = "Head", size = Vector3.new(0.45, 1.4, 0.45), pos = Vector3.new(0.8, -2.1, 0.8), joint = Vector3.new(0.8, -1.4, 0.8) },
			{ name = "Tent3b", parent = "Tent3a", size = Vector3.new(0.35, 1.3, 0.35), pos = Vector3.new(0.8, -3.4, 0.8), joint = Vector3.new(0.8, -2.8, 0.8), color = Color3.fromRGB(200, 60, 230), mat = MAT.Neon },
		},
		animate = function(pose, phase, walk, atk, now)
			local flap = sin(now * 14) * 0.6
			pose("WingL1", CFrame.Angles(0, 0, flap))
			pose("WingR1", CFrame.Angles(0, 0, -flap))
			pose("WingL2", CFrame.Angles(0, 0, sin(now * 14 - 0.6) * 0.4))
			pose("WingR2", CFrame.Angles(0, 0, -sin(now * 14 - 0.6) * 0.4))
			pose("Head", CFrame.new(0, sin(now * 2.5) * 0.6, 0) * CFrame.Angles(sin(now * 0.9) * 0.15, sin(now * 0.6) * 0.4, 0))
			local blink = (now % 4 < 0.15) and 0.9 or 0
			pose("LidTop", CFrame.Angles(blink - atk * 0.3, 0, 0))
			for k = 1, 3 do
				pose("Tent" .. k .. "a", CFrame.Angles(sin(now * 3 + k) * 0.35, 0, sin(now * 2 + k) * 0.2))
				pose("Tent" .. k .. "b", CFrame.Angles(sin(now * 3 + k - 0.8) * 0.45, 0, 0))
			end
		end,
	},

	Golem = {
		displayName = "โกเลมหิน",
		hp = 250, damage = 25, speed = 9, coins = 40, reach = 5, aggro = 70, hip = 3, respawn = 40,
		root = Vector3.new(6, 6, 4), stepRate = 5,
		color = Color3.fromRGB(110, 110, 115), mat = MAT.Rock,
		parts = {
			{ name = "Torso", size = Vector3.new(6, 6, 4), pos = Vector3.zero, joint = Vector3.new(0, -3, 0) },
			{ name = "Core", parent = "Torso", size = Vector3.new(1.6, 1.6, 0.4), pos = Vector3.new(0, 0.5, -2.1), color = Color3.fromRGB(80, 230, 255), mat = MAT.Neon, light = Color3.fromRGB(80, 230, 255) },
			{ name = "Crack1", parent = "Torso", size = Vector3.new(0.2, 3, 0.1), pos = Vector3.new(1.6, -0.6, -2.05), rot = CFrame.Angles(0, 0, math.rad(20)), color = Color3.fromRGB(80, 230, 255), mat = MAT.Neon },
			{ name = "Crack2", parent = "Torso", size = Vector3.new(0.2, 2.2, 0.1), pos = Vector3.new(-1.8, 1.4, -2.05), rot = CFrame.Angles(0, 0, math.rad(-30)), color = Color3.fromRGB(80, 230, 255), mat = MAT.Neon },
			{ name = "ShoulderL", parent = "Torso", size = Vector3.new(3, 2, 3), pos = Vector3.new(-3.4, 3, 0), rot = CFrame.Angles(0.3, 0.4, 0.2), color = Color3.fromRGB(95, 95, 100) },
			{ name = "ShoulderR", parent = "Torso", size = Vector3.new(3, 2, 3), pos = Vector3.new(3.4, 3, 0), rot = CFrame.Angles(-0.2, -0.3, -0.2), color = Color3.fromRGB(95, 95, 100) },
			{ name = "MossL", parent = "ShoulderL", size = Vector3.new(2.2, 0.4, 1.8), pos = Vector3.new(-3.4, 4.1, 0), color = Color3.fromRGB(70, 130, 60), mat = MAT.Grass },
			{ name = "MossTop", parent = "Torso", size = Vector3.new(3.5, 0.4, 2.5), pos = Vector3.new(0.5, 3.1, 0.3), color = Color3.fromRGB(70, 130, 60), mat = MAT.Grass },
			{ name = "Crystal1", parent = "Torso", size = Vector3.new(0.8, 3, 0.8), pos = Vector3.new(-1, 3.8, 1.5), rot = CFrame.Angles(0.4, 0, 0.3), color = Color3.fromRGB(120, 230, 255), mat = MAT.Neon, transparency = 0.1 },
			{ name = "Crystal2", parent = "Torso", size = Vector3.new(0.7, 2.4, 0.7), pos = Vector3.new(1, 3.6, 1.6), rot = CFrame.Angles(0.5, 0, -0.4), color = Color3.fromRGB(120, 230, 255), mat = MAT.Neon, transparency = 0.1 },
			{ name = "Head", parent = "Torso", size = Vector3.new(3, 2.6, 3), pos = Vector3.new(0, 4.3, -0.4), joint = Vector3.new(0, 3, -0.4) },
			{ name = "Brow", parent = "Head", size = Vector3.new(3.2, 0.6, 0.8), pos = Vector3.new(0, 5, -1.6), color = Color3.fromRGB(90, 90, 95) },
			{ name = "EyeL", parent = "Head", size = Vector3.new(0.7, 0.35, 0.2), pos = Vector3.new(-0.7, 4.5, -1.95), color = Color3.fromRGB(80, 230, 255), mat = MAT.Neon },
			{ name = "EyeR", parent = "Head", size = Vector3.new(0.7, 0.35, 0.2), pos = Vector3.new(0.7, 4.5, -1.95), color = Color3.fromRGB(80, 230, 255), mat = MAT.Neon },
			{ name = "ArmL", parent = "Torso", size = Vector3.new(2.2, 4, 2.2), pos = Vector3.new(-4.3, 0.6, 0), joint = Vector3.new(-4.1, 2.6, 0) },
			{ name = "FistL", parent = "ArmL", size = Vector3.new(2.8, 2.4, 2.8), pos = Vector3.new(-4.3, -2.4, -0.2), color = Color3.fromRGB(95, 95, 100) },
			{ name = "ArmR", parent = "Torso", size = Vector3.new(2.2, 4, 2.2), pos = Vector3.new(4.3, 0.6, 0), joint = Vector3.new(4.1, 2.6, 0) },
			{ name = "FistR", parent = "ArmR", size = Vector3.new(2.8, 2.4, 2.8), pos = Vector3.new(4.3, -2.4, -0.2), color = Color3.fromRGB(95, 95, 100) },
			{ name = "LegL", parent = "Torso", size = Vector3.new(2.4, 3, 2.4), pos = Vector3.new(-1.6, -4.5, 0), joint = Vector3.new(-1.6, -3, 0) },
			{ name = "LegR", parent = "Torso", size = Vector3.new(2.4, 3, 2.4), pos = Vector3.new(1.6, -4.5, 0), joint = Vector3.new(1.6, -3, 0) },
		},
		animate = function(pose, phase, walk, atk, now)
			local s = sin(phase) * 0.45 * walk
			pose("LegL", CFrame.Angles(s, 0, 0))
			pose("LegR", CFrame.Angles(-s, 0, 0))
			pose("ArmL", CFrame.Angles(-s * 0.8 + atk * 1.7, 0, 0))
			pose("ArmR", CFrame.Angles(s * 0.8 + atk * 1.7, 0, 0))
			pose("Torso", CFrame.new(0, math.abs(sin(phase)) * 0.3 * walk, 0) * CFrame.Angles(atk * 0.2, 0, sin(phase) * 0.06 * walk))
			pose("Head", CFrame.Angles(0, sin(now * 0.7) * 0.3, 0))
		end,
	},
}

-- สไลม์สีอื่น ๆ: ใช้ร่างเดียวกับสไลม์เขียว เปลี่ยนสีและค่าพลัง
local function slimeVariant(displayName, body, core, stem, stats)
	local base = MONSTER_TYPES.Slime
	local v = table.clone(base)
	v.displayName = displayName
	v.parts = {}
	for _, spec in ipairs(base.parts) do
		local c = table.clone(spec)
		if c.name == "Body" then
			c.color = body
		elseif c.name == "Core" then
			c.color = core
			c.light = core
		elseif c.name == "Leaf" or c.name == "LeafStem" then
			c.color = stem
		end
		table.insert(v.parts, c)
	end
	for k, val in pairs(stats) do
		v[k] = val
	end
	return v
end
MONSTER_TYPES.MagmaSlime = slimeVariant("สไลม์ลาวา", Color3.fromRGB(255, 110, 40), Color3.fromRGB(255, 230, 90), Color3.fromRGB(50, 35, 30), { hp = 70, damage = 14, coins = 12 })
MONSTER_TYPES.PoisonSlime = slimeVariant("สไลม์พิษ", Color3.fromRGB(150, 60, 200), Color3.fromRGB(130, 255, 90), Color3.fromRGB(90, 40, 110), { hp = 55, damage = 11, coins = 9 })

local LEASH = 120 -- มอนสเตอร์ไม่ไล่ผู้เล่นไกลจากบ้านเกินนี้
local ANIM_DISTANCE = 180 -- ขยับท่าเฉพาะตัวที่มีผู้เล่นอยู่ใกล้ (ประหยัดเน็ต)
local liveMonsters = {} -- [model] = { root, hum, def, motors, walk, phase, attackAt }

-- ประกอบร่างมอนสเตอร์จากรายการชิ้นส่วน
local function buildMonsterRig(def, baseCf)
	local m = Instance.new("Model")
	m.Name = def.displayName

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = def.root
	root.Transparency = 1
	root.CFrame = baseCf
	root.Parent = m

	local parts, motors = { Root = root }, {}
	for _, spec in ipairs(def.parts) do
		local p = Instance.new("Part")
		p.Name = spec.name
		if spec.shape then
			p.Shape = spec.shape
		end
		p.Size = (type(spec.size) == "number") and Vector3.one * spec.size or spec.size
		p.Color = spec.color or def.color
		p.Material = spec.mat or def.mat
		p.Transparency = spec.transparency or 0
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = false
		p.Massless = true
		p.CFrame = baseCf * CFrame.new(spec.pos) * (spec.rot or CFrame.identity)

		local parent = parts[spec.parent or "Root"]
		local jointCf = baseCf * CFrame.new(spec.joint or spec.pos)
		local motor = Instance.new("Motor6D")
		motor.Name = spec.name
		motor.Part0 = parent
		motor.Part1 = p
		motor.C0 = parent.CFrame:Inverse() * jointCf
		motor.C1 = p.CFrame:Inverse() * jointCf
		motor.Parent = parent
		motors[spec.name] = { motor = motor, c0 = motor.C0 }

		if spec.light then
			pointLight(p, spec.light, 14, 1.2)
		end
		parts[spec.name] = p
		p.Parent = m
	end
	m.PrimaryPart = root
	return m, root, motors
end

local function getStat(player, name)
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild(name)
end

local function playerFromHit(hit)
	local char = hit:FindFirstAncestorOfClass("Model")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		return Players:GetPlayerFromCharacter(char), hum
	end
end

local function spawnMonster(kind, home)
	local def = MONSTER_TYPES[kind]
	local baseCf = CFrame.new(home + Vector3.new(0, def.hip + def.root.Y / 2 + 1, 0))
		* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local m, root, motors = buildMonsterRig(def, baseCf)

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.HipHeight = def.hip
	hum.MaxHealth = def.hp
	hum.Health = def.hp
	hum.WalkSpeed = def.speed
	hum.RequiresNeck = false
	hum.BreakJointsOnDeath = false
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	hum.Parent = m

	m.Parent = monstersFolder
	root:SetNetworkOwner(nil)

	local state = { root = root, hum = hum, def = def, motors = motors, walk = 0, phase = rng:NextNumber(0, 6), attackAt = -10 }
	liveMonsters[m] = state

	-- เอฟเฟกต์โจมตีพิเศษ: มังกรพ่นไฟ / ตาปีศาจยิงลำแสง
	if def.attackEffect == "fire" then
		local fire = Instance.new("ParticleEmitter")
		fire.Color = ColorSequence.new(Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 60, 20))
		fire.LightEmission = 1
		fire.Size = NumberSequence.new(2, 7)
		fire.Transparency = NumberSequence.new(0, 1)
		fire.Lifetime = NumberRange.new(0.5, 0.8)
		fire.Speed = NumberRange.new(40, 60)
		fire.SpreadAngle = Vector2.new(12, 12)
		fire.Rate = 0
		fire.EmissionDirection = Enum.NormalId.Front
		fire.Parent = m:FindFirstChild("Mouth")
		state.fx = fire
	end

	hum.Died:Connect(function()
		liveMonsters[m] = nil
		local tag = hum:FindFirstChild("creator")
		local killer = tag and tag.Value
		if killer and killer:IsA("Player") and killer.Parent then
			local coins, kills = getStat(killer, "Coins"), getStat(killer, "Kills")
			if coins then
				coins.Value += def.coins
			end
			if kills then
				kills.Value += 1
			end
		end
		-- ล้มคว่ำแล้วจางหาย
		local fall = motors[def.parts[1].name]
		if fall then
			fall.motor.C0 = fall.c0 * CFrame.Angles(math.rad(-80), 0, 0)
		end
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") and p ~= root then
				TweenService:Create(p, TweenInfo.new(1.5), { Transparency = 1 }):Play()
			end
		end
		task.delay(2, function()
			m:Destroy()
		end)
		task.delay(def.respawn, function()
			spawnMonster(kind, home)
		end)
	end)

	-- AI: ไล่ผู้เล่นที่อยู่ใกล้ ถ้าไม่มีก็เดินเล่นรอบบ้าน
	task.spawn(function()
		local lastHit, nextWander = 0, 0
		while m.Parent and hum.Health > 0 do
			local best, targetHum, targetRoot = def.aggro, nil, nil
			if (root.Position - home).Magnitude < LEASH then
				for _, pl in ipairs(Players:GetPlayers()) do
					local c = pl.Character
					local h = c and c:FindFirstChildOfClass("Humanoid")
					local r = c and c:FindFirstChild("HumanoidRootPart")
					if h and r and h.Health > 0 then
						local dist = (r.Position - root.Position).Magnitude
						if dist < best then
							best, targetHum, targetRoot = dist, h, r
						end
					end
				end
			end
			if targetRoot then
				if def.ranged and best < def.reach * 0.6 then
					hum:MoveTo(root.Position) -- ตัวที่โจมตีไกล หยุดยิงจากระยะนี้
				else
					hum:MoveTo(targetRoot.Position)
				end
				if best <= def.reach + def.root.X / 2 and os.clock() - lastHit > (def.ranged and 1.8 or 1.1) then
					lastHit = os.clock()
					state.attackAt = os.clock() -- เล่นท่าโจมตี
					if def.ranged then
						local flat = Vector3.new(targetRoot.Position.X, root.Position.Y, targetRoot.Position.Z)
						if (flat - root.Position).Magnitude > 0.5 then
							root.CFrame = CFrame.lookAt(root.Position, flat)
						end
					end
					if state.fx then
						state.fx:Emit(60)
					elseif def.attackEffect == "beam" then
						local eye = m:FindFirstChild("Iris")
						if eye then
							local a, b = eye.Position, targetRoot.Position
							local beam = part({ Name = "EyeBeam", Size = Vector3.new(0.5, 0.5, (b - a).Magnitude), CFrame = CFrame.lookAt((a + b) / 2, b), Color = Color3.fromRGB(220, 70, 255), Material = MAT.Neon, CanCollide = false, CanTouch = false })
							Debris:AddItem(beam, 0.2)
						end
					end
					targetHum:TakeDamage(def.damage)
				end
			elseif os.clock() > nextWander then
				nextWander = os.clock() + rng:NextNumber(3, 6)
				hum:MoveTo(home + Vector3.new(rng:NextNumber(-25, 25), 0, rng:NextNumber(-25, 25)))
			end
			task.wait(0.25)
		end
	end)
end

-- ลูปอนิเมชั่น: ขยับข้อต่อตามความเร็วที่เดิน ประมาณ 15 ครั้งต่อวินาที
local function startMonsterAnimation()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 1 / 15 then
			return
		end
		local step = acc
		acc = 0
		local now = os.clock()

		local playerPositions = {}
		for _, pl in ipairs(Players:GetPlayers()) do
			local r = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
			if r then
				table.insert(playerPositions, r.Position)
			end
		end

		for m, st in pairs(liveMonsters) do
			if not m.Parent then
				liveMonsters[m] = nil
				continue
			end
			local near = false
			for _, pos in ipairs(playerPositions) do
				if (pos - st.root.Position).Magnitude < ANIM_DISTANCE then
					near = true
					break
				end
			end
			if near then
				local v = st.root.AssemblyLinearVelocity
				local speed = Vector3.new(v.X, 0, v.Z).Magnitude
				st.walk = lerp(st.walk, math.clamp(speed / st.def.speed, 0, 1), 0.35)
				st.phase += step * st.def.stepRate * (0.4 + st.walk)
				local atk = math.clamp(1 - (now - st.attackAt) / 0.45, 0, 1)
				local motors = st.motors
				st.def.animate(function(name, cf)
					local mo = motors[name]
					if mo then
						mo.motor.C0 = mo.c0 * cf
					end
				end, st.phase, st.walk, atk, now)
			end
		end
	end)
end

-------------------------------------------------------------------------------
-- 11) ⚔️ ระบบต่อสู้ + ร้านค้า + เวลา (ทำงานตอนกด Play เท่านั้น)
-------------------------------------------------------------------------------
local function hitSpark(pos, color)
	local p = part({ Name = "HitSpark", Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(pos), Color = color, Material = MAT.Neon, CanCollide = false })
	TweenService:Create(p, TweenInfo.new(0.3), { Size = Vector3.new(4, 4, 4), Transparency = 1 }):Play()
	Debris:AddItem(p, 0.35)
end

local function shockwave(pos, color)
	local ring = cylinder({ Name = "Shockwave", Position = pos, Height = 0.4, Diameter = 2, Color = color, Material = MAT.Neon, CanCollide = false, Transparency = 0.2 })
	TweenService:Create(ring, TweenInfo.new(0.4), { Size = Vector3.new(0.4, 24, 24), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.45)
end

local function flashRed(m)
	local hl = Instance.new("Highlight")
	hl.FillColor = Color3.fromRGB(255, 60, 60)
	hl.FillTransparency = 0.4
	hl.OutlineTransparency = 1
	hl.Parent = m
	Debris:AddItem(hl, 0.15)
end

local function makeWeapon(player, id)
	local def = WEAPONS[id]
	local tool = Instance.new("Tool")
	tool.Name = def.name
	tool.CanBeDropped = false
	tool.ToolTip = string.format("ดาเมจ %d • คลิกเพื่อโจมตี", def.damage)
	tool.GripPos = Vector3.zero
	tool.GripForward = Vector3.new(-1, 0, 0)
	tool.GripRight = Vector3.new(0, 1, 0)
	tool.GripUp = Vector3.new(0, 0, 1)
	buildWeaponParts(id, tool, CFrame.new(), false)

	local cooling = false
	tool.Activated:Connect(function()
		if cooling then
			return
		end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local myHum = char and char:FindFirstChildOfClass("Humanoid")
		if not root or not myHum then
			return
		end
		cooling = true
		task.delay(def.cooldown, function()
			cooling = false
		end)

		-- ท่าฟัน/ทุบ: สคริปต์ Animate มาตรฐานของตัวละครจะเล่นท่าเมื่อเจอค่านี้
		local anim = Instance.new("StringValue")
		anim.Name = "toolanim"
		anim.Value = def.anim
		anim.Parent = tool
		Debris:AddItem(anim, 1)

		local look = root.CFrame.LookVector
		local center = def.aoe and (root.Position + look * def.aoe.forward) or root.Position
		local radius = def.aoe and def.aoe.radius or def.range
		if def.shockwave then
			shockwave(center - Vector3.new(0, 2.8, 0), def.color)
		end

		for m, st in pairs(liveMonsters) do
			local mr = st.root
			if m.Parent and st.hum.Health > 0 then
				local offset = mr.Position - center
				local inRange = offset.Magnitude <= radius + mr.Size.X / 2
				local fromMe = mr.Position - root.Position
				local inFront = def.aoe or def.arc <= -1 or (fromMe.Magnitude > 0.1 and look:Dot(fromMe.Unit) > def.arc)
				if inRange and inFront then
					local tag = st.hum:FindFirstChild("creator") or Instance.new("ObjectValue")
					tag.Name = "creator"
					tag.Value = player
					tag.Parent = st.hum
					st.hum:TakeDamage(def.damage)
					flashRed(m)
					hitSpark(mr.Position, def.color)
					local push = Vector3.new(fromMe.X, 0, fromMe.Z)
					if push.Magnitude > 0.1 then
						mr:ApplyImpulse((push.Unit + Vector3.new(0, 0.4, 0)) * mr.AssemblyMass * def.knockback)
					end
					if def.lifesteal then
						myHum.Health = math.min(myHum.MaxHealth, myHum.Health + def.damage * def.lifesteal)
					end
				end
			end
		end
	end)
	return tool
end

local function giveWeapon(player, id)
	local name = WEAPONS[id].name
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	if backpack:FindFirstChild(name) or (player.Character and player.Character:FindFirstChild(name)) then
		return
	end
	makeWeapon(player, id).Parent = backpack
end

local function hookGameplay()
	local function onPlayer(player)
		local ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
		for _, stat in ipairs({ "Coins", "Kills" }) do
			local v = Instance.new("IntValue")
			v.Name = stat
			v.Value = (stat == "Coins") and CONFIG.StartCoins or 0
			v.Parent = ls
		end

		local function equip()
			player:WaitForChild("Backpack")
			giveWeapon(player, "Iron")
			for _, id in ipairs(SHOP_WEAPONS) do
				if player:GetAttribute("Owns_" .. id) then
					giveWeapon(player, id)
				end
			end
		end
		player.CharacterAdded:Connect(equip)
		if player.Character then
			task.spawn(equip)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end

	local chestCooldown = {} -- [chest][player] = เวลาที่เปิดล่าสุด
	local warpCooldown, lavaCooldown = {}, {}
	for _, obj in ipairs(mapFolder:GetDescendants()) do
		if not obj:IsA("BasePart") then
			continue
		end
		if obj:GetAttribute("TeamName") then
			local team = Teams:FindFirstChild(obj:GetAttribute("TeamName"))
			obj.Touched:Connect(function(hit)
				local player = playerFromHit(hit)
				if player and team and player.Team ~= team then
					player.Neutral = false
					player.Team = team
				end
			end)
		elseif obj:GetAttribute("WarpTarget") then
			obj.Touched:Connect(function(hit)
				local player = playerFromHit(hit)
				local target = obj:GetAttribute("WarpTarget")
				if not player or not target or not player.Character then
					return
				end
				local last = warpCooldown[player]
				if last and os.clock() - last < 2 then
					return
				end
				warpCooldown[player] = os.clock()
				player.Character:PivotTo(CFrame.new(target))
			end)
		elseif obj:GetAttribute("Lava") then
			obj.Touched:Connect(function(hit)
				local player, hum = playerFromHit(hit)
				if not player then
					return
				end
				local last = lavaCooldown[player]
				if last and os.clock() - last < 0.5 then
					return
				end
				lavaCooldown[player] = os.clock()
				hum:TakeDamage(15)
			end)
		elseif obj:GetAttribute("Heal") then
			obj.Touched:Connect(function(hit)
				local _, hum = playerFromHit(hit)
				if hum then
					hum.Health = hum.MaxHealth
				end
			end)
		elseif obj:GetAttribute("BuyWeapon") then
			local id = obj:GetAttribute("BuyWeapon")
			obj.Touched:Connect(function(hit)
				local player = playerFromHit(hit)
				if not player or player:GetAttribute("Owns_" .. id) then
					return
				end
				local coins = getStat(player, "Coins")
				if coins and coins.Value >= WEAPONS[id].price then
					coins.Value -= WEAPONS[id].price
					player:SetAttribute("Owns_" .. id, true)
					giveWeapon(player, id)
				end
			end)
		elseif obj:GetAttribute("ChestReward") then
			local reward = obj:GetAttribute("ChestReward")
			chestCooldown[obj] = {}
			obj.Touched:Connect(function(hit)
				local player = playerFromHit(hit)
				if not player then
					return
				end
				local last = chestCooldown[obj][player]
				if last and os.clock() - last < 120 then
					return -- เปิดซ้ำได้ทุก 2 นาที
				end
				chestCooldown[obj][player] = os.clock()
				local coins = getStat(player, "Coins")
				if coins then
					coins.Value += reward
				end
			end)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		for _, list in pairs(chestCooldown) do
			list[player] = nil
		end
		warpCooldown[player], lavaCooldown[player] = nil, nil
	end)

	-- กลางวัน/กลางคืน + ไฟถนนเปิดตอนกลางคืน
	task.spawn(function()
		local secondsPerHour = CONFIG.DayLengthMinutes * 60 / 24
		local wasNight = nil
		while true do
			local dt = task.wait(0.5)
			local clock = Lighting.ClockTime
			-- ธีมมืด: ช่วงกลางวันผ่านเร็วขึ้น 4 เท่า ให้เวลาส่วนใหญ่เป็นโพล้เพล้/กลางคืน
			local speed = (CONFIG.DarkTheme and clock > 7 and clock < 16) and 4 or 1
			Lighting.ClockTime = (clock + dt * speed / secondsPerHour) % 24
			local night = Lighting.ClockTime >= 18 or Lighting.ClockTime < 6.2
			if night ~= wasNight then
				wasNight = night
				for _, lamp in ipairs(lampLights) do
					lamp.light.Enabled = night
					lamp.bulb.Material = night and MAT.Neon or MAT.Glass
				end
			end
		end
	end)

	if CONFIG.SpawnMonsters then
		for _, s in ipairs(monsterSpawns) do
			spawnMonster(s.kind, s.pos)
		end
		startMonsterAnimation()
	end
end

-------------------------------------------------------------------------------
-- 🚀 เริ่มสร้าง
-------------------------------------------------------------------------------
local started = os.clock()
reset()
setupLighting()
setupTeams()
buildSpawn()
print("⏳ กำลังสร้างภูมิประเทศ...")
buildTerrain()
print("⏳ กำลังสร้างเมือง ปราสาท ท่าเรือ...")
buildTown()
buildCastle()
buildHarbor()
buildRuins()
buildShrine()
print("⏳ กำลังสร้างต้นไม้โลก หมู่บ้านเอลฟ์ ดันเจี้ยน...")
registerClassicWarps()
buildWorldTree()
buildGoblinCamp()
buildSwamp()
buildVolcano()
buildDungeon()
buildWarpCircle()
buildPaths()
print("⏳ กำลังปลูกต้นไม้...")
buildNature()

if RunService:IsRunning() then
	hookGameplay()
end

print(string.format("✅ สร้างโลก '%s' เสร็จแล้ว (%.1f วินาที)", CONFIG.MapName, os.clock() - started))
