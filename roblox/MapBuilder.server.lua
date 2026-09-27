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
	  🌊 ทะเลล้อมรอบเกาะ

	ระบบเกม:
	  - มอนสเตอร์ 3 ชนิด: สไลม์ (ป่า), โครงกระดูก (ซากปรักหักพัง), โกเลม (ภูเขา)
	  - ดาบให้ทุกคน, ฆ่ามอนสเตอร์ได้เหรียญ, ซื้อดาบทองคำที่ร้านอาวุธ
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
	WorldHalfSize = 768,     -- ครึ่งหนึ่งของความกว้างโลก (โลกกว้าง 1536 studs)
	ClearTerrain = true,     -- ล้าง Terrain เดิมก่อนสร้าง
	RemoveBaseplate = true,  -- ลบ Baseplate เดิมของเทมเพลต
	TreeCount = 450,         -- ต้นไม้ทั่วเกาะ
	ForestTreeCount = 260,   -- ต้นไม้เพิ่มเติมในป่า
	RockCount = 70,
	DayLengthMinutes = 12,   -- 1 วันในเกม = กี่นาทีจริง
	SpawnMonsters = true,
	StartCoins = 0,
}

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Teams = game:GetService("Teams")
local Debris = game:GetService("Debris")

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
	{ name = "Harbor", x = 0, z = 560, radius = 55, blend = 30, height = 4 },
}
local ZONE = {}
for _, zn in ipairs(ZONES) do
	ZONE[zn.name] = zn
end

local FOREST = { minX = 270, maxX = 620, minZ = -230, maxZ = 230 }
local SHRINE_POS = Vector2.new(0, -470) -- ศาลเจ้าบนภูเขา

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

local function billboardText(adornee, text, color, offsetY)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(14, 3)
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
-- 🏔️ ภูมิประเทศ: ความสูงพื้นดินที่ตำแหน่ง (x, z)
-------------------------------------------------------------------------------
local function heightAt(x, z)
	local noise = math.noise
	-- เนินเขาทั่วไป
	local h = 12 + noise(x / 180, z / 180, NOISE_SEED) * 18 + noise(x / 55, z / 55, NOISE_SEED + 3.3) * 4

	-- เทือกเขาทางทิศเหนือ (z ติดลบ)
	local m = smooth((-z - 250) / 250)
	if m > 0 then
		h += m * (60 + (noise(x / 110, z / 110, NOISE_SEED + 7.7) + 0.6) * 90)
	end

	-- ขอบเกาะค่อย ๆ ลาดลงทะเล
	local d = math.sqrt(x * x + z * z)
	local coast = 660 + noise(x / 300, z / 300, NOISE_SEED + 1.1) * 60
	h = lerp(h, -14, smooth((d - (coast - 120)) / 120))

	-- อ่าวทางทิศใต้ สำหรับท่าเรือ
	local bay = smooth((z - 590) / 50) * (1 - smooth((math.abs(x) - 110) / 80))
	h = lerp(h, -14, bay)

	-- ปรับพื้นที่เมือง/ปราสาท/ฯลฯ ให้เรียบ
	for _, zn in ipairs(ZONES) do
		local dx, dz = x - zn.x, z - zn.z
		local t = smooth((math.sqrt(dx * dx + dz * dz) - zn.radius) / zn.blend)
		if t < 1 then
			h = lerp(zn.height, h, t)
		end
	end

	return math.clamp(h, -20, 190)
end

local function inForest(x, z)
	return x > FOREST.minX and x < FOREST.maxX and z > FOREST.minZ and z < FOREST.maxZ
end

local function surfaceMaterial(h, x, z)
	if h < 3 then
		return MAT.Sand
	elseif h > 120 then
		return MAT.Snow
	elseif h > 70 then
		return MAT.Rock
	elseif inForest(x, z) then
		return MAT.LeafyGrass
	end
	local r = ZONE.Ruins
	if (x - r.x) ^ 2 + (z - r.z) ^ 2 < 75 ^ 2 then
		return MAT.Ground
	end
	return MAT.Grass
end

local function groundPos(x, z, extraY)
	return Vector3.new(x, heightAt(x, z) + (extraY or 0), z)
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

local function setupLighting()
	Lighting.ClockTime = 13
	Lighting.Brightness = 2.5
	Lighting.OutdoorAmbient = Color3.fromRGB(135, 135, 150)
	Lighting.GlobalShadows = true

	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmo = Instance.new("Atmosphere")
		atmo.Density = 0.32
		atmo.Haze = 1.2
		atmo.Color = Color3.fromRGB(199, 220, 255)
		atmo.Decay = Color3.fromRGB(106, 112, 125)
		atmo.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("BloomEffect") then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.6
		bloom.Size = 30
		bloom.Threshold = 1.5
		bloom.Parent = Lighting
	end

	terrain.WaterColor = Color3.fromRGB(30, 120, 160)
	terrain.WaterWaveSize = 0.2
	terrain.WaterReflectance = 0.6
	terrain.WaterTransparency = 0.5
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
	local Y0, Y1 = -24, 200
	local CHUNK = 128
	local ny = (Y1 - Y0) / VOX
	local n = CHUNK / VOX

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
					local pad = part({ Name = "BuyGoldSword", Size = Vector3.new(4, 0.4, 4), CFrame = cf * CFrame.new(0, 1.2, 0), Color = Color3.fromRGB(255, 200, 40), Material = MAT.Neon, Parent = house })
					pad:SetAttribute("BuySword", "Gold")
					billboardText(pad, "⚔️ ดาบทองคำ 100 เหรียญ", Color3.fromRGB(255, 220, 90), 4)
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
	part({ Name = "Pier", Size = Vector3.new(14, 1, 110), CFrame = CFrame.new(hz.x, hz.height + 0.5, 645), Color = wood, Material = MAT.WoodPlanks, Parent = harbor })
	for z = 600, 696, 12 do
		for _, sx in ipairs({ -6, 6 }) do
			cylinder({ Name = "PierPost", Position = Vector3.new(hz.x + sx, -5.5, z), Height = 20, Diameter = 1.5, Color = Color3.fromRGB(100, 70, 45), Material = MAT.Wood, Parent = harbor })
		end
	end

	-- เรือใบ (นั่งที่พวงมาลัยได้)
	local boat = model("Boat", harbor)
	local bx, bz = hz.x + 20, 675
	part({ Name = "Hull", Size = Vector3.new(10, 3, 30), CFrame = CFrame.new(bx, 1.5, bz), Color = Color3.fromRGB(120, 70, 40), Material = MAT.WoodPlanks, Parent = boat })
	for _, sx in ipairs({ -1, 1 }) do
		part({ Name = "HullSide", Size = Vector3.new(1, 3, 30), CFrame = CFrame.new(bx + sx * 5.5, 4.5, bz), Color = Color3.fromRGB(150, 40, 40), Material = MAT.Wood, Parent = boat })
	end
	part({ Name = "Mast", Size = Vector3.new(1, 22, 1), CFrame = CFrame.new(bx, 14, bz), Color = Color3.fromRGB(110, 75, 45), Material = MAT.Wood, Parent = boat })
	part({ Name = "Sail", Size = Vector3.new(0.3, 14, 16), CFrame = CFrame.new(bx + 0.7, 16, bz), Color = Color3.fromRGB(245, 240, 225), Material = MAT.Fabric, Parent = boat })
	part({ ClassName = "Seat", Name = "Helm", Size = Vector3.new(2, 1, 2), CFrame = CFrame.new(bx, 3.5, bz + 11), Color = Color3.fromRGB(110, 75, 45), Material = MAT.Wood, Parent = boat })

	-- ประภาคาร
	local lx, lz = hz.x + 42, 612
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

	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		table.insert(monsterSpawns, { kind = "Skeleton", pos = center + Vector3.new(math.cos(a) * 20, 0, math.sin(a) * 20) })
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
end

-------------------------------------------------------------------------------
-- 8) 🛤️ เส้นทางเชื่อมแต่ละพื้นที่
-------------------------------------------------------------------------------
local function buildPath(parent, a, b, width, color, material)
	local steps = math.ceil((b - a).Magnitude / 8)
	for i = 0, steps - 1 do
		local p1 = a:Lerp(b, i / steps)
		local p2 = a:Lerp(b, (i + 1) / steps)
		local v1 = Vector3.new(p1.X, heightAt(p1.X, p1.Y) + 0.1, p1.Y)
		local v2 = Vector3.new(p2.X, heightAt(p2.X, p2.Y) + 0.1, p2.Y)
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
	buildPath(paths, Vector2.new(0, 238), Vector2.new(0, 522), 10, dirt, dirtMat) -- ไปท่าเรือ
	buildPath(paths, Vector2.new(238, 0), Vector2.new(440, 0), 8, dirt, dirtMat) -- เข้าป่า
	buildPath(paths, Vector2.new(168, 168), Vector2.new(300, 300), 8, dirt, dirtMat) -- ไปซากปรักหักพัง
	buildPath(paths, Vector2.new(0, -238), Vector2.new(SHRINE_POS.X, SHRINE_POS.Y + 14), 8, dirt, dirtMat) -- ขึ้นเขา
end

-------------------------------------------------------------------------------
-- 9) 🌲 ธรรมชาติ: ต้นไม้ หิน เห็ดยักษ์ คริสตัล
-------------------------------------------------------------------------------
local BLOCK_MARGIN = { Town = 25, Castle = 35, Ruins = 5, Harbor = 50 }

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
	for _, p in ipairs(pathPoints) do
		if (x - p.X) ^ 2 + (z - p.Y) ^ 2 < 10 ^ 2 then
			return true
		end
	end
	return false
end

local function roundTree(parent, pos)
	local tree = model("Tree", parent)
	local h = rng:NextNumber(10, 18)
	part({ Name = "Trunk", Size = Vector3.new(2, h, 2), CFrame = CFrame.new(pos + Vector3.new(0, h / 2 - 1, 0)), Color = Color3.fromRGB(105, 64, 40), Material = MAT.Wood, Parent = tree })
	part({
		Name = "Leaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * rng:NextNumber(9, 14),
		CFrame = CFrame.new(pos + Vector3.new(0, h + 1, 0)),
		Color = Color3.fromRGB(56, 142, 60):Lerp(Color3.fromRGB(130, 185, 60), rng:NextNumber()),
		Material = MAT.Grass,
		Parent = tree,
	})
end

local function pineTree(parent, pos)
	local tree = model("PineTree", parent)
	local s = rng:NextNumber(0.8, 1.3)
	part({ Name = "Trunk", Size = Vector3.new(1.6, 8 * s, 1.6), CFrame = CFrame.new(pos + Vector3.new(0, 4 * s - 1, 0)), Color = Color3.fromRGB(90, 60, 40), Material = MAT.Wood, Parent = tree })
	for i = 0, 2 do
		cylinder({
			Name = "Needles",
			Position = pos + Vector3.new(0, (6 + i * 4.5) * s, 0),
			Height = 4.5 * s,
			Diameter = (12 - i * 3.5) * s,
			Color = Color3.fromRGB(30, 90, 50),
			Material = MAT.Grass,
			Parent = tree,
		})
	end
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
	for _ = 1, 10 do
		local p = forestSpot(30, 60)
		if p then
			table.insert(monsterSpawns, { kind = "Slime", pos = p })
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
-- 10) ⚔️ ระบบเกม (ทำงานตอนกด Play เท่านั้น)
-------------------------------------------------------------------------------
local SWORDS = {
	Iron = { name = "ดาบเหล็ก", damage = 25, color = Color3.fromRGB(200, 200, 210) },
	Gold = { name = "ดาบทองคำ", damage = 45, color = Color3.fromRGB(255, 200, 40), price = 100 },
}

local MONSTER_TYPES = {
	Slime = {
		displayName = "สไลม์",
		hp = 40, damage = 8, speed = 10, coins = 5, reach = 3, aggro = 45, hip = 0.2, respawn = 15,
		color = Color3.fromRGB(90, 220, 90), material = MAT.Glass,
		parts = {
			{ name = "HumanoidRootPart", size = Vector3.new(4, 3, 4), transparency = 0.25 },
			{ name = "Head", size = Vector3.new(1, 1, 1), offset = Vector3.new(0, 1.2, 0), transparency = 1 },
			{ name = "EyeL", size = Vector3.new(0.5, 0.8, 0.2), offset = Vector3.new(-0.7, 0.4, -2.05), color = Color3.new(0, 0, 0), material = MAT.SmoothPlastic },
			{ name = "EyeR", size = Vector3.new(0.5, 0.8, 0.2), offset = Vector3.new(0.7, 0.4, -2.05), color = Color3.new(0, 0, 0), material = MAT.SmoothPlastic },
		},
	},
	Skeleton = {
		displayName = "โครงกระดูก",
		hp = 80, damage = 12, speed = 14, coins = 12, reach = 4, aggro = 60, hip = 2.4, respawn = 20,
		color = Color3.fromRGB(230, 225, 210), material = MAT.SmoothPlastic,
		parts = {
			{ name = "HumanoidRootPart", size = Vector3.new(2, 2.5, 1) },
			{ name = "Head", size = Vector3.new(1.5, 1.5, 1.5), offset = Vector3.new(0, 2.05, 0) },
			{ name = "EyeL", size = Vector3.new(0.3, 0.3, 0.1), offset = Vector3.new(-0.35, 2.15, -0.78), color = Color3.fromRGB(255, 40, 40), material = MAT.Neon },
			{ name = "EyeR", size = Vector3.new(0.3, 0.3, 0.1), offset = Vector3.new(0.35, 2.15, -0.78), color = Color3.fromRGB(255, 40, 40), material = MAT.Neon },
			{ name = "ArmL", size = Vector3.new(0.6, 2.3, 0.6), offset = Vector3.new(-1.35, -0.05, 0) },
			{ name = "ArmR", size = Vector3.new(0.6, 2.3, 0.6), offset = Vector3.new(1.35, -0.05, 0) },
			{ name = "LegL", size = Vector3.new(0.7, 2.4, 0.7), offset = Vector3.new(-0.5, -2.45, 0) },
			{ name = "LegR", size = Vector3.new(0.7, 2.4, 0.7), offset = Vector3.new(0.5, -2.45, 0) },
			{ name = "RustySword", size = Vector3.new(0.3, 0.3, 3), offset = Vector3.new(1.35, -1.2, -1.4), color = Color3.fromRGB(120, 110, 100), material = MAT.CorrodedMetal },
		},
	},
	Golem = {
		displayName = "โกเลมหิน",
		hp = 250, damage = 25, speed = 9, coins = 40, reach = 5, aggro = 70, hip = 3, respawn = 40,
		color = Color3.fromRGB(110, 110, 115), material = MAT.Rock,
		parts = {
			{ name = "HumanoidRootPart", size = Vector3.new(6, 6, 4) },
			{ name = "Head", size = Vector3.new(3, 3, 3), offset = Vector3.new(0, 4.5, 0) },
			{ name = "EyeL", size = Vector3.new(0.6, 0.4, 0.2), offset = Vector3.new(-0.7, 4.8, -1.55), color = Color3.fromRGB(80, 230, 255), material = MAT.Neon },
			{ name = "EyeR", size = Vector3.new(0.6, 0.4, 0.2), offset = Vector3.new(0.7, 4.8, -1.55), color = Color3.fromRGB(80, 230, 255), material = MAT.Neon },
			{ name = "Core", size = Vector3.new(1.5, 1.5, 0.4), offset = Vector3.new(0, 0.5, -2.1), color = Color3.fromRGB(80, 230, 255), material = MAT.Neon },
			{ name = "ArmL", size = Vector3.new(2, 6, 2), offset = Vector3.new(-4.1, -0.5, 0) },
			{ name = "ArmR", size = Vector3.new(2, 6, 2), offset = Vector3.new(4.1, -0.5, 0) },
			{ name = "LegL", size = Vector3.new(2.2, 3, 2.2), offset = Vector3.new(-1.6, -4.5, 0) },
			{ name = "LegR", size = Vector3.new(2.2, 3, 2.2), offset = Vector3.new(1.6, -4.5, 0) },
		},
	},
}

local LEASH = 120 -- มอนสเตอร์ไม่ไล่ผู้เล่นไกลจากบ้านเกินนี้

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
	local rootSpec = def.parts[1]
	local m = Instance.new("Model")
	m.Name = def.displayName

	local baseCf = CFrame.new(home + Vector3.new(0, def.hip + rootSpec.size.Y / 2 + 1, 0))
		* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local root
	for i, spec in ipairs(def.parts) do
		local p = Instance.new("Part")
		p.Name = spec.name
		p.Size = spec.size
		p.CFrame = baseCf * CFrame.new(spec.offset or Vector3.zero)
		p.Color = spec.color or def.color
		p.Material = spec.material or def.material
		p.Transparency = spec.transparency or 0
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Anchored = false
		if i == 1 then
			root = p
		else
			p.CanCollide = false
			p.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = p
			weld.Parent = p
		end
		p.Parent = m
	end
	m.PrimaryPart = root

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

	hum.Died:Connect(function()
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
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Transparency = math.max(p.Transparency, 0.6)
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
				hum:MoveTo(targetRoot.Position)
				if best <= def.reach + rootSpec.size.X / 2 and os.clock() - lastHit > 1 then
					lastHit = os.clock()
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

local function makeSword(player, swordId)
	local def = SWORDS[swordId]
	local tool = Instance.new("Tool")
	tool.Name = def.name
	tool.CanBeDropped = false
	tool.ToolTip = "คลิกเพื่อฟัน (ดาเมจ " .. def.damage .. ")"
	tool.GripPos = Vector3.new(0, 0, -1.5)
	tool.GripForward = Vector3.new(-1, 0, 0)
	tool.GripRight = Vector3.new(0, 1, 0)
	tool.GripUp = Vector3.new(0, 0, 1)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 0.8, 4)
	handle.Color = def.color
	handle.Material = MAT.Metal
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local cooling = false
	tool.Activated:Connect(function()
		if cooling then
			return
		end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		cooling = true
		task.delay(0.45, function()
			cooling = false
		end)

		-- ท่าฟัน: สคริปต์ Animate มาตรฐานของตัวละครจะเล่นท่า Slash เมื่อเจอค่านี้
		local anim = Instance.new("StringValue")
		anim.Name = "toolanim"
		anim.Value = "Slash"
		anim.Parent = tool
		Debris:AddItem(anim, 1)

		for _, m in ipairs(monstersFolder:GetChildren()) do
			local hum = m:FindFirstChildOfClass("Humanoid")
			local mr = m.PrimaryPart
			if hum and mr and hum.Health > 0 then
				local offset = mr.Position - root.Position
				local inRange = offset.Magnitude <= 8 + mr.Size.X / 2
				if inRange and root.CFrame.LookVector:Dot(offset.Unit) > 0.1 then
					local tag = hum:FindFirstChild("creator") or Instance.new("ObjectValue")
					tag.Name = "creator"
					tag.Value = player
					tag.Parent = hum
					hum:TakeDamage(def.damage)
				end
			end
		end
	end)
	return tool
end

local function giveSword(player, swordId)
	local name = SWORDS[swordId].name
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	if backpack:FindFirstChild(name) or (player.Character and player.Character:FindFirstChild(name)) then
		return
	end
	makeSword(player, swordId).Parent = backpack
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
			giveSword(player, "Iron")
			if player:GetAttribute("OwnsGold") then
				giveSword(player, "Gold")
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
		elseif obj:GetAttribute("Heal") then
			obj.Touched:Connect(function(hit)
				local _, hum = playerFromHit(hit)
				if hum then
					hum.Health = hum.MaxHealth
				end
			end)
		elseif obj:GetAttribute("BuySword") then
			local swordId = obj:GetAttribute("BuySword")
			obj.Touched:Connect(function(hit)
				local player = playerFromHit(hit)
				if not player or player:GetAttribute("OwnsGold") then
					return
				end
				local coins = getStat(player, "Coins")
				if coins and coins.Value >= SWORDS[swordId].price then
					coins.Value -= SWORDS[swordId].price
					player:SetAttribute("OwnsGold", true)
					giveSword(player, swordId)
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
	end)

	-- กลางวัน/กลางคืน + ไฟถนนเปิดตอนกลางคืน
	task.spawn(function()
		local secondsPerHour = CONFIG.DayLengthMinutes * 60 / 24
		local wasNight = nil
		while true do
			local dt = task.wait(0.5)
			Lighting.ClockTime = (Lighting.ClockTime + dt / secondsPerHour) % 24
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
buildPaths()
print("⏳ กำลังปลูกต้นไม้...")
buildNature()

if RunService:IsRunning() then
	hookGameplay()
end

print(string.format("✅ สร้างโลก '%s' เสร็จแล้ว (%.1f วินาที)", CONFIG.MapName, os.clock() - started))
