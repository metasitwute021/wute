--[[
	Cosmic Hydra — มังกร 3 หัวร่างใส พลังจักรวาล (Roblox)

	วิธีใช้
	  1) เปิด Roblox Studio > ServerScriptService > คลิก + > Script
	  2) ลบโค้ดเดิม แล้ววางโค้ดทั้งไฟล์นี้
	  3) กด Play — มังกรจะถูกสร้างใน Workspace ชื่อ "CosmicHydra"

	ทุกส่วนต่อกันด้วย Motor6D (คอ 3 ท่อน x 3, หัว, กราม, แขน, ข้อศอก, มือ, นิ้ว,
	ปีก 2 ท่อน, ขา, เข่า, เท้า, หาง 7 ท่อน) และมี AnimationController + Animator
	จึงใช้ Animation Editor / Moon Animator ทำท่าเองได้ทุกข้อต่อ

	ถ้าจะทำอนิเมชันเอง: ตั้ง AutoAnimate = false (หรือ Attribute "AutoAnimate"
	ของโมเดล) เพื่อปิดท่าขยับอัตโนมัติ ส่วนลูกบอลดาวเคราะห์ยังโคจรต่อ
]]

local RunService = game:GetService("RunService")

local CONFIG = {
	Scale = 1,                                  -- ขนาด (1 = สูงราว 30 stud)
	SpawnCFrame = CFrame.new(0, 0, -40),        -- จุดที่วางมังกร
	BodyColor = Color3.fromRGB(120, 85, 255),
	BodyMaterial = Enum.Material.ForceField,    -- ForceField = ใสแบบโฮโลแกรม, ลอง Glass ได้
	BodyTransparency = 0.1,
	AccentColor = Color3.fromRGB(215, 190, 255),
	GoldColor = Color3.fromRGB(255, 205, 110),
	EyeColor = Color3.fromRGB(170, 245, 255),
	VoxelDensity = 1,                           -- ก้อนพิกเซลเรืองแสงบนตัว (0 = ไม่มี)
	AutoAnimate = true,                         -- ท่าขยับ idle อัตโนมัติ
	Seed = 7,
}

local A = CFrame.Angles
local rad = math.rad
local rng = Random.new(CONFIG.Seed)

local model = Instance.new("Model")
model.Name = "CosmicHydra"

local motors = {}

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
	p.Material = opts.material or CONFIG.BodyMaterial
	p.Color = opts.color or CONFIG.BodyColor
	p.Transparency = opts.transparency or CONFIG.BodyTransparency
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = opts.parent or model
	return p
end

local function weld(p0, p1)
	local w = Instance.new("WeldConstraint")
	w.Part0 = p0
	w.Part1 = p1
	w.Parent = p1
end

-- ข้อต่อขยับได้: jointCF คือจุดหมุนในพิกัดโลก
local function motor(p0, p1, jointCF, name)
	local m = Instance.new("Motor6D")
	m.Name = name or p1.Name
	m.Part0 = p0
	m.Part1 = p1
	m.C0 = p0.CFrame:ToObjectSpace(jointCF)
	m.C1 = p1.CFrame:ToObjectSpace(jointCF)
	m.Parent = p0
	motors[m.Name] = { motor = m, base = m.C0 }
	return m
end

-- ชิ้นตกแต่ง เชื่อมติดกับชิ้นแม่
local function decor(parent, name, size, cf, opts)
	opts = opts or {}
	opts.parent = parent
	local p = newPart(name, size, cf, opts)
	weld(parent, p)
	return p
end

local function lookAt(from, to)
	local dir = (to - from).Unit
	local up = math.abs(dir.Y) > 0.98 and Vector3.zAxis or Vector3.yAxis
	return CFrame.lookAt(from, to, up)
end

-- กระดูก 1 ท่อนจากจุด a ไป b ต่อข้อต่อกับ parentPart ที่จุด a
local function bone(name, a, b, w, parentPart, opts)
	local len = (b - a).Magnitude
	local jointCF = lookAt(a, b)
	local p = newPart(name, Vector3.new(w, w, len + w * 0.35), jointCF * CFrame.new(0, 0, -len / 2), opts)
	if parentPart then
		motor(parentPart, p, jointCF)
	end
	return p
end

local VOXEL_COLORS = {
	Color3.fromRGB(205, 180, 255),
	Color3.fromRGB(150, 110, 255),
	Color3.fromRGB(240, 232, 255),
	Color3.fromRGB(105, 70, 235),
}

-- ก้อนพิกเซลเรืองแสงกระจายบนผิว (ลุคโวเซลแบบในคลิป)
local function voxels(part, count)
	count = math.floor(count * CONFIG.VoxelDensity)
	local half = part.Size / 2
	for _ = 1, count do
		local s = rng:NextNumber(0.3, 0.85)
		local pos
		if part.Shape == Enum.PartType.Ball then
			pos = rng:NextUnitVector() * half.X
		else
			pos = Vector3.new(rng:NextNumber(-1, 1) * half.X, rng:NextNumber(-1, 1) * half.Y, rng:NextNumber(-1, 1) * half.Z)
			local axis = rng:NextInteger(1, 3)
			local sign = rng:NextNumber() < 0.5 and -1 or 1
			if axis == 1 then
				pos = Vector3.new(sign * half.X, pos.Y, pos.Z)
			elseif axis == 2 then
				pos = Vector3.new(pos.X, sign * half.Y, pos.Z)
			else
				pos = Vector3.new(pos.X, pos.Y, sign * half.Z)
			end
		end
		local gold = rng:NextNumber() < 0.05
		decor(part, "Voxel", Vector3.new(s, s, s), part.CFrame * CFrame.new(pos), {
			material = rng:NextNumber() < 0.6 and Enum.Material.Neon or Enum.Material.Glass,
			color = gold and CONFIG.GoldColor or VOXEL_COLORS[rng:NextInteger(1, #VOXEL_COLORS)],
			transparency = rng:NextNumber(0, 0.35),
		})
	end
end

local function claw(parent, base, tip, w)
	local len = (tip - base).Magnitude
	decor(parent, "Claw", Vector3.new(w, w, len), lookAt(base, tip) * CFrame.new(0, 0, -len / 2), {
		material = Enum.Material.Neon,
		color = CONFIG.GoldColor,
		transparency = 0.05,
	})
end

---------------------------------------------------------------------------
-- ลำตัว
---------------------------------------------------------------------------

local root = newPart("HumanoidRootPart", Vector3.new(2, 2, 2), CFrame.new(0, 10, 0), { transparency = 1 })
model.PrimaryPart = root

local hips = newPart("Hips", Vector3.new(8, 8, 8), CFrame.new(0, 10, 0.5), { shape = Enum.PartType.Ball })
motor(root, hips, CFrame.new(0, 10, 0), "RootJoint")
voxels(hips, 22)

local torso = newPart("Torso", Vector3.new(9, 10, 7), CFrame.new(0, 16.5, -0.5))
motor(hips, torso, CFrame.new(0, 12.5, 0))
voxels(torso, 30)

local chest = decor(torso, "Chest", Vector3.new(10, 10, 10), CFrame.new(0, 18.5, -0.3), { shape = Enum.PartType.Ball })
voxels(chest, 26)

-- ซี่โครงเรืองแสง
for i = 0, 4 do
	local w = 6.4 - math.abs(i - 2) * 0.8
	decor(torso, "Rib", Vector3.new(w, 0.55, 0.7), CFrame.new(0, 12.4 + i * 1.35, -4.2), {
		material = Enum.Material.Neon,
		color = CONFIG.AccentColor,
		transparency = 0.1,
	})
end
decor(torso, "Sternum", Vector3.new(0.7, 6.5, 0.7), CFrame.new(0, 15.1, -4.3), {
	material = Enum.Material.Neon,
	color = CONFIG.AccentColor,
	transparency = 0.15,
})

-- หนามบนหลัง
for i = 0, 4 do
	decor(torso, "BackSpike", Vector3.new(0.9, 0.9, 2.2),
		CFrame.new(0, 21 - i * 2.2, 3.6) * A(rad(-35), 0, rad(45)), {
		material = Enum.Material.Neon,
		color = i % 2 == 0 and CONFIG.GoldColor or CONFIG.AccentColor,
		transparency = 0.1,
	})
end

-- แกนพลังกลางอก (หลุมดำ + วงแหวนหมุน)
local corePos = Vector3.new(0, 18, -5.2)
local core = decor(torso, "Core", Vector3.new(3, 3, 3), CFrame.new(corePos), {
	shape = Enum.PartType.Ball,
	material = Enum.Material.SmoothPlastic,
	color = Color3.fromRGB(10, 5, 25),
	transparency = 0,
})
local coreLight = Instance.new("PointLight")
coreLight.Color = Color3.fromRGB(190, 110, 255)
coreLight.Range = 22
coreLight.Brightness = 3
coreLight.Parent = core

local coreRing = newPart("CoreRing", Vector3.new(0.4, 0.4, 0.4), CFrame.new(corePos + Vector3.new(0, 0, -0.4)), { transparency = 1 })
motor(torso, coreRing, coreRing.CFrame, "CoreSpin")
for i = 0, 17 do
	local a = i / 18 * math.pi * 2
	decor(coreRing, "RingBit", Vector3.new(0.45, 1.1, 0.45), coreRing.CFrame * A(0, 0, a) * CFrame.new(2.4, 0, 0), {
		material = Enum.Material.Neon,
		color = i % 3 == 0 and Color3.fromRGB(255, 120, 230) or Color3.fromRGB(175, 95, 255),
		transparency = 0,
	})
end
for i = 0, 7 do
	local a = i / 8 * math.pi * 2 + 0.2
	decor(coreRing, "RingDot", Vector3.new(0.35, 0.35, 0.35), coreRing.CFrame * A(0, 0, a) * CFrame.new(3.5, 0, 0), {
		material = Enum.Material.Neon,
		color = Color3.fromRGB(110, 235, 255),
		transparency = 0,
	})
end

-- ประกายระยิบรอบตัว
local sparkle = Instance.new("ParticleEmitter")
sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
sparkle.Rate = 18
sparkle.Lifetime = NumberRange.new(1.5, 3)
sparkle.Speed = NumberRange.new(1, 3)
sparkle.SpreadAngle = Vector2.new(180, 180)
sparkle.LightEmission = 1
sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
sparkle.Color = ColorSequence.new(Color3.fromRGB(200, 150, 255), Color3.fromRGB(120, 230, 255))
sparkle.Parent = torso

---------------------------------------------------------------------------
-- 3 คอ 3 หัว
---------------------------------------------------------------------------

local NECKS = {
	{ key = "L", base = Vector3.new(-3.2, 21, -1.5), dir = Vector3.new(-0.75, 1, -0.35) },
	{ key = "C", base = Vector3.new(0, 21.5, -2), dir = Vector3.new(0, 1, -0.45) },
	{ key = "R", base = Vector3.new(3.2, 21, -1.5), dir = Vector3.new(0.75, 1, -0.35) },
}
local NECK_WIDTH = { 2.7, 2.3, 2 }

for _, n in ipairs(NECKS) do
	local key = n.key
	local dir = n.dir.Unit
	local pos = n.base
	local prev = torso
	for j = 1, 3 do
		local nextPos = pos + dir * 2.7
		local seg = bone("Neck" .. j .. "_" .. key, pos, nextPos, NECK_WIDTH[j], prev)
		voxels(seg, 7)
		prev = seg
		pos = nextPos
		dir = (dir + Vector3.new(0, 0, -0.22)).Unit
	end

	-- หัว
	local headCF = lookAt(pos, pos + Vector3.new(n.dir.X * 0.5, -0.15, -1))
	local head = newPart("Head_" .. key, Vector3.new(2.8, 2.2, 4.2), headCF * CFrame.new(0, 0.3, -1.7))
	motor(prev, head, headCF)
	voxels(head, 10)

	decor(head, "Snout", Vector3.new(2.1, 1.3, 1.8), head.CFrame * CFrame.new(0, -0.15, -2.7))

	for _, s in ipairs({ -1, 1 }) do
		decor(head, "Eye", Vector3.new(0.6, 0.6, 0.6), head.CFrame * CFrame.new(s * 1.15, 0.55, -1), {
			shape = Enum.PartType.Ball,
			material = Enum.Material.Neon,
			color = CONFIG.EyeColor,
			transparency = 0,
		})
		-- เขา 2 ท่อน
		local hornBase = (head.CFrame * CFrame.new(s * 0.9, 1.1, 1)).Position
		local hornMid = hornBase + head.CFrame:VectorToWorldSpace(Vector3.new(s * 0.5, 1.1, 1.4))
		local hornTip = hornMid + head.CFrame:VectorToWorldSpace(Vector3.new(s * 0.2, 0.2, 1.3))
		claw(head, hornBase, hornMid, 0.55)
		claw(head, hornMid, hornTip, 0.35)
	end

	-- กราม (ขยับอ้าปากได้)
	local jawCF = headCF * CFrame.new(0, -0.6, -0.4)
	local jaw = newPart("Jaw_" .. key, Vector3.new(2.1, 0.7, 3.9), jawCF * CFrame.new(0, -0.35, -1.95))
	motor(head, jaw, jawCF)
	for t = 0, 3 do
		for _, s in ipairs({ -1, 1 }) do
			decor(jaw, "Tooth", Vector3.new(0.25, 0.45, 0.25), jaw.CFrame * CFrame.new(s * 0.8, 0.5, -1.6 + t * 0.6 - 0.2), {
				material = Enum.Material.Neon,
				color = Color3.fromRGB(245, 240, 255),
				transparency = 0,
			})
		end
	end
end

---------------------------------------------------------------------------
-- แขน ปีก ขา (ซ้าย/ขวา)
---------------------------------------------------------------------------

for _, side in ipairs({ { "L", -1 }, { "R", 1 } }) do
	local k, s = side[1], side[2]

	-- แขน: ยกออกด้านข้าง ถือดาวในมือ
	local shoulder = Vector3.new(5 * s, 19.5, -1)
	local elbow = shoulder + Vector3.new(4.2 * s, 1, -1.2)
	local wrist = elbow + Vector3.new(1.5 * s, 2.5, -2.5)
	local upper = bone("UpperArm_" .. k, shoulder, elbow, 2.4, torso)
	local fore = bone("Forearm_" .. k, elbow, wrist, 2, upper)
	voxels(upper, 8)
	voxels(fore, 7)

	local handCF = lookAt(wrist, wrist + (wrist - elbow))
	local hand = newPart("Hand_" .. k, Vector3.new(2.2, 2.2, 2.2), handCF, { shape = Enum.PartType.Ball })
	motor(fore, hand, handCF)
	for f = 1, 3 do
		local x = (f - 2) * 0.65
		local base = (handCF * CFrame.new(x, 0.3, -0.8)).Position
		local tip = (handCF * CFrame.new(x * 1.4, 1.1, -2.3)).Position
		local finger = bone("Finger" .. f .. "_" .. k, base, tip, 0.5, hand)
		local fcf = finger.CFrame
		claw(finger, (fcf * CFrame.new(0, 0, -finger.Size.Z / 2)).Position, (fcf * CFrame.new(0, -0.2, -finger.Size.Z / 2 - 0.8)).Position, 0.3)
	end

	-- ปีก 2 ท่อน + พังผืดใส
	local wBase = Vector3.new(2.5 * s, 20.5, 2.5)
	local wElbow = wBase + Vector3.new(5 * s, 3.5, 2)
	local wTip = wElbow + Vector3.new(6 * s, -1, 1.5)
	local w1 = bone("WingArm_" .. k, wBase, wElbow, 1.1, torso, { material = Enum.Material.Neon, color = CONFIG.AccentColor, transparency = 0.2 })
	local w2 = bone("WingHand_" .. k, wElbow, wTip, 0.9, w1, { material = Enum.Material.Neon, color = CONFIG.AccentColor, transparency = 0.2 })
	for _, wb in ipairs({ w1, w2 }) do
		local mem = decor(wb, "Membrane", Vector3.new(0.25, 5.5, wb.Size.Z), wb.CFrame * CFrame.new(0, -2.9, 0), {
			color = Color3.fromRGB(160, 120, 255),
			transparency = 0.3,
		})
		voxels(mem, 9)
	end

	-- ขา
	local hip = Vector3.new(3.4 * s, 9, 0.5)
	local knee = hip + Vector3.new(1.2 * s, -3, -2.6)
	local ankle = knee + Vector3.new(0.2 * s, -4.6, 1.4)
	local thigh = bone("Thigh_" .. k, hip, knee, 3.2, hips)
	local shin = bone("Shin_" .. k, knee, ankle, 2.4, thigh)
	voxels(thigh, 10)
	voxels(shin, 8)

	local footCF = CFrame.lookAt(ankle, ankle + Vector3.new(0, 0, -1))
	local foot = newPart("Foot_" .. k, Vector3.new(2.8, 1.2, 3.6), footCF * CFrame.new(0, -0.3, -1.2))
	motor(shin, foot, footCF)
	for t = -1, 1 do
		local base = (foot.CFrame * CFrame.new(t * 0.9, -0.2, -1.8)).Position
		claw(foot, base, base + Vector3.new(t * 0.3, -0.3, -1.2), 0.35)
	end
end

---------------------------------------------------------------------------
-- หาง 7 ท่อน
---------------------------------------------------------------------------

do
	local pos = Vector3.new(0, 8.5, 4)
	local dir = Vector3.new(0, -0.35, 1).Unit
	local prev = hips
	local count = 7
	for j = 1, count do
		local w = 3 - (j - 1) * (2.2 / (count - 1))
		local nextPos = pos + dir * 2.8
		local seg = bone("Tail" .. j, pos, nextPos, w, prev)
		voxels(seg, math.max(3, 9 - j))
		prev = seg
		pos = nextPos
		dir = (dir + Vector3.new(0.12, 0.08, 0)).Unit
	end
	decor(prev, "TailCrystal", Vector3.new(1, 2.4, 1), CFrame.new(pos) * A(rad(70), 0, rad(45)), {
		material = Enum.Material.Neon,
		color = Color3.fromRGB(120, 235, 255),
		transparency = 0.1,
	})
end

---------------------------------------------------------------------------
-- ประกอบร่าง: ปรับขนาด, ปลด Anchor, ใส่ Animator และเรืองแสง
---------------------------------------------------------------------------

if CONFIG.Scale ~= 1 then
	model:ScaleTo(CONFIG.Scale)
end
local S = model:GetScale()
for _, m in pairs(motors) do
	m.base = m.motor.C0
end

for _, d in ipairs(model:GetDescendants()) do
	if d:IsA("BasePart") and d ~= root then
		d.Anchored = false
	end
end

local controller = Instance.new("AnimationController")
controller.Parent = model
Instance.new("Animator").Parent = controller

local glow = Instance.new("Highlight")
glow.FillColor = Color3.fromRGB(150, 100, 255)
glow.FillTransparency = 0.85
glow.OutlineColor = Color3.fromRGB(205, 170, 255)
glow.OutlineTransparency = 0.35
glow.DepthMode = Enum.HighlightDepthMode.Occluded
glow.Parent = model

model:SetAttribute("AutoAnimate", CONFIG.AutoAnimate)
model:PivotTo(CONFIG.SpawnCFrame)
model.Parent = workspace

---------------------------------------------------------------------------
-- ลูกบอลดาวเคราะห์ที่มังกรควบคุม (โคจรรอบตัว)
---------------------------------------------------------------------------

local orbFolder = Instance.new("Folder")
orbFolder.Name = "Orbs"
orbFolder.Parent = model

-- anchor = ชิ้นส่วนที่เป็นศูนย์กลางวงโคจร
local ORBS = {
	{ name = "BlueSaturn", size = 3.4, color = Color3.fromRGB(90, 205, 255), ring = true, anchor = "Torso", radius = 14, speed = 0.55, tilt = Vector2.new(0.25, 0.1), phase = 0 },
	{ name = "PurpleSaturn", size = 3.8, color = Color3.fromRGB(185, 90, 255), ring = true, anchor = "Torso", radius = 16, speed = -0.4, tilt = Vector2.new(-0.35, 0.2), phase = 2.2 },
	{ name = "GoldMoon", size = 2, color = CONFIG.GoldColor, ring = true, anchor = "Torso", radius = 9.5, speed = 0.9, tilt = Vector2.new(0.5, -0.3), phase = 4 },
	{ name = "CyanStar", size = 1.6, color = Color3.fromRGB(130, 255, 240), anchor = "Torso", radius = 11.5, speed = 1.2, tilt = Vector2.new(-0.6, 0.4), phase = 1 },
	{ name = "PinkPlanet", size = 2.6, color = Color3.fromRGB(255, 120, 220), anchor = "Torso", radius = 19, speed = 0.3, tilt = Vector2.new(0.15, -0.5), phase = 3.3 },
	{ name = "HandOrb_L", size = 1.5, color = Color3.fromRGB(110, 225, 255), anchor = "Hand_L", radius = 2.6, speed = 2.2, tilt = Vector2.new(0.4, 0), phase = 0 },
	{ name = "HandOrb_R", size = 1.5, color = Color3.fromRGB(205, 130, 255), anchor = "Hand_R", radius = 2.6, speed = -2.2, tilt = Vector2.new(-0.4, 0), phase = 1.5 },
	{ name = "Crystal1", size = 1.3, color = CONFIG.AccentColor, crystal = true, anchor = "Torso", radius = 12.5, speed = -0.7, tilt = Vector2.new(0.9, 0), phase = 0.5 },
	{ name = "Crystal2", size = 1.1, color = Color3.fromRGB(240, 235, 255), crystal = true, anchor = "Torso", radius = 13.5, speed = 0.65, tilt = Vector2.new(-0.8, 0.5), phase = 2.8 },
	{ name = "Crystal3", size = 1.2, color = Color3.fromRGB(150, 230, 255), crystal = true, anchor = "Head_C", radius = 4.5, speed = 1.4, tilt = Vector2.new(0.3, 0.3), phase = 1.1 },
}

local orbs = {}
for _, spec in ipairs(ORBS) do
	local d = spec.size * S
	local orb
	if spec.crystal then
		orb = newPart(spec.name, Vector3.new(d, d * 1.8, d), CFrame.new(), {
			parent = orbFolder, material = Enum.Material.Neon, color = spec.color, transparency = 0.15,
		})
	else
		orb = newPart(spec.name, Vector3.new(d, d, d), CFrame.new(), {
			parent = orbFolder, shape = Enum.PartType.Ball, material = Enum.Material.Neon, color = spec.color, transparency = 0.05,
		})
		local light = Instance.new("PointLight")
		light.Color = spec.color
		light.Range = d * 4
		light.Brightness = 1.5
		light.Parent = orb
	end

	if spec.ring then
		local ring = newPart("Ring", Vector3.new(0.15 * S, d * 2.3, d * 2.3), orb.CFrame * A(rad(20), 0, rad(90)), {
			parent = orb, shape = Enum.PartType.Cylinder, material = Enum.Material.Neon,
			color = spec.color:Lerp(Color3.new(1, 1, 1), 0.35), transparency = 0.45,
		})
		ring.Anchored = false
		weld(orb, ring)
	end

	-- หางแสงตามวงโคจร
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, d * 0.4, 0)
	a0.Parent = orb
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -d * 0.4, 0)
	a1.Parent = orb
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.5
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(spec.color)
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Parent = orb

	table.insert(orbs, { part = orb, spec = spec, center = model:FindFirstChild(spec.anchor, true) })
end

---------------------------------------------------------------------------
-- ท่าขยับ idle
---------------------------------------------------------------------------

local function pose(name, cf)
	local m = motors[name]
	if m then
		m.motor.C0 = m.base * cf
	end
end

local sin = math.sin

local function animateBody(t)
	pose("RootJoint", CFrame.new(0, sin(t * 1.4) * 0.4 * S, 0))
	pose("Torso", A(sin(t * 1.4) * 0.03, sin(t * 0.5) * 0.06, 0))
	pose("CoreSpin", A(0, 0, t * 1.5))

	for i, key in ipairs({ "L", "C", "R" }) do
		local ph = i * 2.1
		for j = 1, 3 do
			pose("Neck" .. j .. "_" .. key, A(sin(t * 1.3 + ph + j * 0.5) * 0.1, sin(t * 0.9 + ph + j * 0.4) * 0.14, 0))
		end
		pose("Head_" .. key, A(sin(t * 1.7 + ph) * 0.15, sin(t * 1.1 + ph) * 0.2, sin(t * 0.8 + ph) * 0.1))
		local roar = math.max(0, sin(t * 0.7 + ph)) ^ 6
		pose("Jaw_" .. key, A(-(0.08 + 0.1 * (sin(t * 3 + ph) + 1) / 2 + roar * 0.5), 0, 0))
	end

	local flap = sin(t * 2.4)
	for _, side in ipairs({ { "L", 0 }, { "R", math.pi } }) do
		local k, ph = side[1], side[2]
		pose("UpperArm_" .. k, A(sin(t * 1.2 + ph) * 0.25, 0, sin(t * 0.9 + ph) * 0.2))
		pose("Forearm_" .. k, A(sin(t * 1.6 + ph) * 0.3, 0, 0))
		pose("Hand_" .. k, A(sin(t * 2 + ph) * 0.3, 0, sin(t * 1.3 + ph) * 0.4))
		for f = 1, 3 do
			pose("Finger" .. f .. "_" .. k, A((sin(t * 2.5 + f + ph) + 1) * 0.25, 0, 0))
		end
		pose("WingArm_" .. k, A(flap * 0.4, 0, 0))
		pose("WingHand_" .. k, A(sin(t * 2.4 - 0.7) * 0.35, 0, 0))
		pose("Thigh_" .. k, A(sin(t * 1.4 + ph) * 0.08, 0, 0))
		pose("Shin_" .. k, A(-sin(t * 1.4 + ph) * 0.1, 0, 0))
		pose("Foot_" .. k, A(sin(t * 1.4 + ph) * 0.1, 0, 0))
	end

	for j = 1, 7 do
		pose("Tail" .. j, A(sin(t * 1.8 - j * 0.6) * 0.08, sin(t * 1.5 - j * 0.7) * 0.18, 0))
	end
end

local function animateOrbs(t)
	for _, o in ipairs(orbs) do
		local spec = o.spec
		if o.center then
			local ang = spec.phase + t * spec.speed
			local offset = Vector3.new(math.cos(ang), sin(ang * 2) * 0.15, sin(ang)) * spec.radius * S
			local pos = o.center.Position + A(spec.tilt.X, 0, spec.tilt.Y) * offset
			if spec.crystal then
				o.part.CFrame = CFrame.new(pos) * A(t * 1.3, t * 0.9, rad(45))
			else
				o.part.CFrame = CFrame.new(pos) * A(0, t * 0.8, 0)
			end
		end
	end
end

local connection
connection = RunService.Heartbeat:Connect(function()
	if not model.Parent then
		connection:Disconnect()
		return
	end
	local t = os.clock()
	if model:GetAttribute("AutoAnimate") then
		animateBody(t)
	end
	animateOrbs(t)
end)
