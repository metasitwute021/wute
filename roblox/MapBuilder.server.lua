--[[
	MapBuilder.server.lua
	สคริปต์สร้างแมพอัตโนมัติสำหรับ Roblox Studio

	แมพที่ได้:
	  1. เกาะหญ้า (Terrain) ล้อมด้วยทะเล
	  2. Lobby: จุดเกิด, ต้นไม้, ป้ายต้อนรับ
	  3. Obby (ด่านกระโดด) 5 โซน + Checkpoint + ลาวา + แท่นเคลื่อนที่
	  4. แท่นเส้นชัย + ระบบนับด่าน (leaderstats "Stage")

	วิธีใช้: ดู roblox/README.md
	  - วางใน ServerScriptService แล้วกด Play  หรือ
	  - ก๊อปทั้งไฟล์ไปวางใน Command Bar (View > Command Bar) แล้วกด Enter
	    (ไฟล์นี้ใช้ได้ทั้งสองแบบ)
]]

-------------------------------------------------------------------------------
-- ตั้งค่า
-------------------------------------------------------------------------------
local CONFIG = {
	MapName = "GeneratedMap",
	ClearTerrain = true,     -- ล้าง Terrain เดิมก่อนสร้าง
	RemoveBaseplate = true,  -- ลบ Baseplate เดิมของเทมเพลต
	IslandRadius = 220,
	SeaSize = 1200,
	TreeCount = 25,
	ObbyStart = Vector3.new(0, 80, -40), -- จุดเริ่มด่าน (ลอยบนฟ้า เหนือเกาะ)
	FallKillY = 60,                       -- ตกต่ำกว่านี้ใต้ Obby = ตาย แล้วเกิดที่ checkpoint
	Seed = 42,
}

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local rng = Random.new(CONFIG.Seed)
local terrain = workspace.Terrain

-------------------------------------------------------------------------------
-- ตัวช่วย
-------------------------------------------------------------------------------
local mapFolder

local function part(props)
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		if k ~= "ClassName" and k ~= "Parent" then
			p[k] = v
		end
	end
	p.Parent = props.Parent or mapFolder
	return p
end

local function folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent or mapFolder
	return f
end

local function billboardText(adornee, text, color)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(12, 3)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = false
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

-------------------------------------------------------------------------------
-- 1) ล้างของเดิม + ตั้งแสง
-------------------------------------------------------------------------------
local function reset()
	local old = workspace:FindFirstChild(CONFIG.MapName)
	if old then
		old:Destroy()
	end
	if CONFIG.RemoveBaseplate then
		local bp = workspace:FindFirstChild("Baseplate")
		if bp then
			bp:Destroy()
		end
	end
	if CONFIG.ClearTerrain then
		terrain:Clear()
	end

	mapFolder = Instance.new("Folder")
	mapFolder.Name = CONFIG.MapName
	mapFolder.Parent = workspace
end

local function setupLighting()
	Lighting.ClockTime = 14
	Lighting.Brightness = 2
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 150)
	Lighting.GlobalShadows = true

	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmo = Instance.new("Atmosphere")
		atmo.Density = 0.3
		atmo.Haze = 1
		atmo.Color = Color3.fromRGB(199, 220, 255)
		atmo.Parent = Lighting
	end
end

-------------------------------------------------------------------------------
-- 2) เกาะ + ทะเล (Terrain)
-------------------------------------------------------------------------------
local function buildIsland()
	-- ทะเล
	terrain:FillBlock(
		CFrame.new(0, -10, 0),
		Vector3.new(CONFIG.SeaSize, 20, CONFIG.SeaSize),
		Enum.Material.Water
	)
	-- พื้นทะเล
	terrain:FillBlock(
		CFrame.new(0, -24, 0),
		Vector3.new(CONFIG.SeaSize, 8, CONFIG.SeaSize),
		Enum.Material.Sand
	)

	-- ตัวเกาะ: ทรายรอบนอก + หญ้าด้านบน
	local r = CONFIG.IslandRadius
	terrain:FillCylinder(CFrame.new(0, 0, 0), 20, r + 20, Enum.Material.Sand)
	terrain:FillCylinder(CFrame.new(0, 4, 0), 16, r, Enum.Material.Grass)

	-- เนินเขาเล็ก ๆ รอบเกาะ
	for _ = 1, 8 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(r * 0.55, r * 0.85)
		local pos = Vector3.new(math.cos(angle) * dist, 6, math.sin(angle) * dist)
		terrain:FillBall(pos, rng:NextNumber(18, 32), Enum.Material.Grass)
		terrain:FillBall(pos + Vector3.new(0, 10, 0), rng:NextNumber(6, 10), Enum.Material.Rock)
	end
end

-------------------------------------------------------------------------------
-- 3) Lobby
-------------------------------------------------------------------------------
local function buildTree(position, parent)
	local tree = Instance.new("Model")
	tree.Name = "Tree"
	local height = rng:NextNumber(10, 18)

	local trunk = part({
		Name = "Trunk",
		Size = Vector3.new(2, height, 2),
		CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)),
		Color = Color3.fromRGB(105, 64, 40),
		Material = Enum.Material.Wood,
		Parent = tree,
	})
	part({
		Name = "Leaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * rng:NextNumber(9, 13),
		CFrame = CFrame.new(position + Vector3.new(0, height + 2, 0)),
		Color = Color3.fromRGB(56, 142, 60):Lerp(Color3.fromRGB(120, 180, 60), rng:NextNumber()),
		Material = Enum.Material.Grass,
		Parent = tree,
	})
	tree.PrimaryPart = trunk
	tree.Parent = parent
end

local function buildLobby()
	local lobby = folder("Lobby")

	-- พื้น lobby
	local floor = part({
		Name = "LobbyFloor",
		Size = Vector3.new(80, 2, 80),
		CFrame = CFrame.new(0, 13, 0),
		Color = Color3.fromRGB(200, 200, 205),
		Material = Enum.Material.Slate,
		Parent = lobby,
	})

	-- จุดเกิด
	local spawn = part({
		ClassName = "SpawnLocation",
		Name = "LobbySpawn",
		Size = Vector3.new(12, 1, 12),
		CFrame = floor.CFrame * CFrame.new(0, 1.5, 15),
		Color = Color3.fromRGB(0, 170, 255),
		Material = Enum.Material.Neon,
		Duration = 0,
		Parent = lobby,
	})
	spawn:SetAttribute("Stage", 0)

	-- แท่นวาร์ปขึ้นไปเริ่ม Obby
	local pad = part({
		Name = "StartPad",
		Size = Vector3.new(10, 1, 10),
		CFrame = floor.CFrame * CFrame.new(0, 1.5, -25),
		Color = Color3.fromRGB(76, 175, 80),
		Material = Enum.Material.Neon,
		Parent = lobby,
	})
	pad:SetAttribute("StartPad", true)
	billboardText(pad, "แตะเพื่อเริ่ม Obby", Color3.fromRGB(180, 255, 180))

	-- ป้ายต้อนรับ
	local sign = part({
		Name = "WelcomeSign",
		Size = Vector3.new(20, 1, 1),
		CFrame = floor.CFrame * CFrame.new(0, 10, -30),
		Transparency = 1,
		CanCollide = false,
		Parent = lobby,
	})
	billboardText(sign, "ยินดีต้อนรับ! เหยียบแท่นเขียวเพื่อเริ่ม Obby", Color3.fromRGB(255, 230, 90))

	-- เสาประดับ 4 มุม
	for _, c in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
		part({
			Name = "Pillar",
			Size = Vector3.new(3, 14, 3),
			CFrame = floor.CFrame * CFrame.new(c[1] * 37, 8, c[2] * 37),
			Color = Color3.fromRGB(240, 240, 240),
			Material = Enum.Material.Marble,
			Parent = lobby,
		})
	end

	-- ต้นไม้รอบเกาะ (เว้นบริเวณ lobby)
	local trees = folder("Trees")
	for _ = 1, CONFIG.TreeCount do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(55, CONFIG.IslandRadius - 20)
		buildTree(Vector3.new(math.cos(angle) * dist, 12, math.sin(angle) * dist), trees)
	end
end

-------------------------------------------------------------------------------
-- 4) Obby
-------------------------------------------------------------------------------
local ZONE_COLORS = {
	Color3.fromRGB(76, 175, 80),   -- เขียว
	Color3.fromRGB(33, 150, 243),  -- ฟ้า
	Color3.fromRGB(255, 193, 7),   -- เหลือง
	Color3.fromRGB(156, 39, 176),  -- ม่วง
	Color3.fromRGB(244, 67, 54),   -- แดง
}

local checkpoints = {}

local function makeCheckpoint(parent, cf, stage, color)
	local cp = part({
		ClassName = "SpawnLocation",
		Name = "Checkpoint" .. stage,
		Size = Vector3.new(10, 1, 10),
		CFrame = cf,
		Color = color,
		Material = Enum.Material.Neon,
		Neutral = true,
		Enabled = false, -- ใช้ระบบ Stage ของเราเองแทนการสุ่มจุดเกิด
		Duration = 0,
		Parent = parent,
	})
	cp:SetAttribute("Stage", stage)
	billboardText(cp, "ด่าน " .. stage)
	checkpoints[stage] = cp
	return cp
end

local function makeKillBrick(props)
	props.Color = props.Color or Color3.fromRGB(255, 85, 0)
	props.Material = props.Material or Enum.Material.Neon
	local p = part(props)
	p:SetAttribute("Kill", true)
	return p
end

local function makeMover(p, offset, duration)
	local goal = { CFrame = p.CFrame * CFrame.new(offset) }
	local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	-- tween จะเล่นตอนรันเกมเท่านั้น (Command Bar แค่สร้างชิ้นส่วน)
	p:SetAttribute("MoveOffset", offset)
	p:SetAttribute("MoveTime", duration)
	if RunService:IsRunning() then
		TweenService:Create(p, info, goal):Play()
	end
end

local function buildObby()
	local obby = folder("Obby")
	local cursor = CFrame.new(CONFIG.ObbyStart)
	local stage = 0

	local function step(dz, dy, dx)
		cursor = cursor * CFrame.new(dx or 0, dy or 0, -dz)
		return cursor
	end

	for zone = 1, #ZONE_COLORS do
		local color = ZONE_COLORS[zone]
		local zf = folder("Zone" .. zone, obby)

		stage += 1
		makeCheckpoint(zf, step(10, 0), stage, color)

		if zone == 1 then
			-- กระโดดแท่นธรรมดา
			for i = 1, 6 do
				part({
					Name = "Jump",
					Size = Vector3.new(6, 1, 6),
					CFrame = step(12, 1, (i % 2 == 0) and 4 or -4),
					Color = color,
					Parent = zf,
				})
			end
		elseif zone == 2 then
			-- ทางแคบ + ลาวาข้างล่าง
			part({
				Name = "Beam",
				Size = Vector3.new(1.5, 1, 50),
				CFrame = step(30, 0),
				Color = color,
				Parent = zf,
			})
			makeKillBrick({
				Name = "Lava",
				Size = Vector3.new(30, 1, 50),
				CFrame = cursor * CFrame.new(0, -8, 0),
				Parent = zf,
			})
			step(25, 0)
		elseif zone == 3 then
			-- แท่นเคลื่อนที่ซ้าย-ขวา
			for i = 1, 4 do
				local p = part({
					Name = "Mover",
					Size = Vector3.new(7, 1, 7),
					CFrame = step(14, 0),
					Color = color,
					Material = Enum.Material.SmoothPlastic,
					Parent = zf,
				})
				makeMover(p, Vector3.new((i % 2 == 0) and 14 or -14, 0, 0), 2.5 + i * 0.3)
			end
		elseif zone == 4 then
			-- บันไดขึ้นสูง + ขอบลาวา
			for i = 1, 8 do
				part({
					Name = "Stair",
					Size = Vector3.new(5, 1, 5),
					CFrame = step(8, 3, (i % 2 == 0) and 6 or -6),
					Color = color,
					Parent = zf,
				})
			end
			makeKillBrick({
				Name = "LavaFloor",
				Size = Vector3.new(40, 1, 70),
				CFrame = cursor * CFrame.new(0, -26, 32),
				Parent = zf,
			})
		elseif zone == 5 then
			-- แท่นลาวาเคลื่อนที่ขวางทาง
			part({
				Name = "Runway",
				Size = Vector3.new(14, 1, 70),
				CFrame = step(40, 0),
				Color = color,
				Parent = zf,
			})
			for i = 1, 4 do
				local blocker = makeKillBrick({
					Name = "Sweeper",
					Size = Vector3.new(2, 4, 2),
					CFrame = cursor * CFrame.new(-6, 2.5, 30 - i * 14),
					Parent = zf,
				})
				makeMover(blocker, Vector3.new(12, 0, 0), 1.2 + i * 0.25)
			end
			step(35, 0)
		end
	end

	-- เส้นชัย
	local finishF = folder("Finish", obby)
	local finish = part({
		Name = "FinishPad",
		Size = Vector3.new(24, 1, 24),
		CFrame = step(16, 0),
		Color = Color3.fromRGB(255, 215, 0),
		Material = Enum.Material.Neon,
		Parent = finishF,
	})
	finish:SetAttribute("Finish", true)
	billboardText(finish, "🏆 เส้นชัย! 🏆", Color3.fromRGB(255, 215, 0))

	-- ถ้วยรางวัล
	part({
		Name = "Trophy",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(6, 4, 4),
		CFrame = finish.CFrame * CFrame.new(0, 4, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 200, 0),
		Material = Enum.Material.Foil,
		Parent = finishF,
	})

	-- พื้นที่ตกตาย (มองไม่เห็น) ใต้ Obby ทั้งหมด
	local startZ = CONFIG.ObbyStart.Z
	local endZ = finish.Position.Z
	makeKillBrick({
		Name = "FallZone",
		Size = Vector3.new(160, 1, math.abs(endZ - startZ) + 80),
		CFrame = CFrame.new(0, CONFIG.FallKillY, (startZ + endZ) / 2),
		Transparency = 1,
		CanCollide = false,
		Parent = obby,
	})
end

-------------------------------------------------------------------------------
-- 5) ระบบเกม (ทำงานเฉพาะตอนกด Play / เซิร์ฟเวอร์จริง)
-------------------------------------------------------------------------------
local function getStage(player)
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild("Stage")
end

local function hookGameplay()
	-- leaderstats + เกิดที่ checkpoint ล่าสุด
	local function onPlayer(player)
		local ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
		local st = Instance.new("IntValue")
		st.Name = "Stage"
		st.Value = 0
		st.Parent = ls

		player.CharacterAdded:Connect(function(char)
			local cp = checkpoints[st.Value]
			if cp then
				local root = char:WaitForChild("HumanoidRootPart")
				task.wait() -- รอให้ตัวละครโหลดตำแหน่งเสร็จ
				root.CFrame = cp.CFrame * CFrame.new(0, 4, 0)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end

	local function playerFromHit(hit)
		local char = hit:FindFirstAncestorOfClass("Model")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			return Players:GetPlayerFromCharacter(char), hum
		end
	end

	for _, obj in ipairs(mapFolder:GetDescendants()) do
		if not obj:IsA("BasePart") then
			continue
		end
		if obj:GetAttribute("Kill") then
			obj.Touched:Connect(function(hit)
				local _, hum = playerFromHit(hit)
				if hum then
					hum.Health = 0
				end
			end)
		elseif obj.Name:match("^Checkpoint") then
			local stage = obj:GetAttribute("Stage")
			obj.Touched:Connect(function(hit)
				local player = playerFromHit(hit)
				local st = player and getStage(player)
				if st and st.Value < stage then
					st.Value = stage
				end
			end)
		elseif obj:GetAttribute("StartPad") then
			obj.Touched:Connect(function(hit)
				local player = playerFromHit(hit)
				local st = player and getStage(player)
				local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if st and root then
					local cp = checkpoints[math.clamp(st.Value, 1, #ZONE_COLORS)]
					root.CFrame = cp.CFrame * CFrame.new(0, 4, 0)
				end
			end)
		elseif obj:GetAttribute("Finish") then
			local done = {}
			obj.Touched:Connect(function(hit)
				local player = playerFromHit(hit)
				if player and not done[player] then
					done[player] = true
					local st = getStage(player)
					if st then
						st.Value = #ZONE_COLORS + 1
					end
					print(player.Name .. " จบ Obby แล้ว!")
				end
			end)
		end
	end
end

-------------------------------------------------------------------------------
-- รัน
-------------------------------------------------------------------------------
reset()
setupLighting()
buildIsland()
buildLobby()
buildObby()

if RunService:IsRunning() then
	hookGameplay()
end

print("✅ สร้างแมพ '" .. CONFIG.MapName .. "' เสร็จแล้ว")
