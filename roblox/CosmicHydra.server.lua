--[[
	Cosmic Hydra — มังกร 3 หัวร่างใส พลังจักรวาล (Roblox)

	วิธีใช้
	  1) เปิด Roblox Studio > ServerScriptService > คลิก + > Script
	  2) ลบโค้ดเดิม แล้ววางโค้ดทั้งไฟล์นี้
	  3) กด Play — มังกรจะถูกสร้างใน Workspace ชื่อ "CosmicHydra"

	ทุกส่วนต่อกันด้วย Motor6D (คอ 3 ท่อน x 3, หัว, กราม, แขน, ข้อศอก, มือ, นิ้ว,
	ปีก 2 ท่อน + ก้านปีก 4 ก้าน, ขา, เข่า, ข้อเท้า, เท้า, หาง 8 ท่อน) และมี AnimationController + Animator
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
	PixelSkin = true,                           -- ผิวพิกเซลสี่เหลี่ยมเล็กๆ ต่อกันเป็นรูปร่าง (แบบในคลิป)
	PixelSize = 0.8,                            -- ขนาดพิกเซล (เล็ก = ละเอียดแต่ชิ้นเยอะ, ถ้าเกมแลคให้เพิ่มเป็น 1-1.2)
	SkinEnabled = true,                         -- ผิวเรียบชั้นใน (ใช้เมื่อ PixelSkin = false)
	SkinColor = Color3.fromRGB(85, 55, 200),
	SkinMaterial = Enum.Material.SmoothPlastic,
	SkinTransparency = 0.25,                    -- 0 = ทึบ, 1 = มองไม่เห็น
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
	local round = part.Shape == Enum.PartType.Ball or part:GetAttribute("Ellipsoid")
	for _ = 1, count do
		local s = rng:NextNumber(0.3, 0.85)
		local pos
		if round then
			pos = rng:NextUnitVector() * half
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
			material = rng:NextNumber() < 0.5 and Enum.Material.Neon or Enum.Material.Glass,
			color = gold and CONFIG.GoldColor or VOXEL_COLORS[rng:NextInteger(1, #VOXEL_COLORS)],
			transparency = rng:NextNumber(0.1, 0.45),
		})
	end
end

-- ทรงรี (ใช้ SpecialMesh ทรงกลมยืดตามขนาดชิ้น)
local function ellipsoid(name, size, cf, opts)
	opts = opts or {}
	local p = newPart(name, size, cf, opts)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	p:SetAttribute("Ellipsoid", true)
	return p
end

local function decorEllipsoid(parent, name, size, cf, opts)
	opts = opts or {}
	opts.parent = parent
	local p = ellipsoid(name, size, cf, opts)
	weld(parent, p)
	return p
end

-- แท่งเรืองแสงตรงระหว่างจุด a ถึง b
local function bar(parent, a, b, w, color, transparency)
	local len = (b - a).Magnitude
	return decor(parent, "Bar", Vector3.new(w, w, len), lookAt(a, b) * CFrame.new(0, 0, -len / 2), {
		material = Enum.Material.Neon,
		color = color,
		transparency = transparency or 0,
	})
end

local function claw(parent, base, tip, w, color)
	return bar(parent, base, tip, w, color or CONFIG.GoldColor, 0.05)
end

-- หนามสองช่วง โคนหนา ปลายเรียว
local function spike(parent, base, dir, len, w, color)
	dir = dir.Unit
	local mid = base + dir * (len * 0.55)
	claw(parent, base, mid, w, color)
	claw(parent, mid, base + dir * len, w * 0.5, color)
end

-- พังผืดปีก: สามเหลี่ยมจาก WedgePart 2 ชิ้น, t = ความสว่าง (0 โคน .. 1 ขอบ)
local MEMBRANE_DEEP = Color3.fromRGB(55, 25, 130)
local MEMBRANE_MID = Color3.fromRGB(130, 80, 255)
local MEMBRANE_EDGE = Color3.fromRGB(255, 150, 240)
local function membraneColor(t)
	if t < 0.6 then
		return MEMBRANE_DEEP:Lerp(MEMBRANE_MID, t / 0.6)
	end
	return MEMBRANE_MID:Lerp(MEMBRANE_EDGE, (t - 0.6) / 0.4)
end

local function triangle(parent, a, b, c, t)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local pieces = {
		{ Vector3.new(0.15, height, math.abs(ab:Dot(back))), CFrame.fromMatrix((a + b) / 2, right, up, back) },
		{ Vector3.new(0.15, height, math.abs(ac:Dot(back))), CFrame.fromMatrix((a + c) / 2, -right, up, -back) },
	}
	for _, piece in ipairs(pieces) do
		local w = Instance.new("WedgePart")
		w.Name = "Membrane"
		w.Size = piece[1]
		w.CFrame = piece[2]
		w.Material = Enum.Material.Glass
		w.Color = membraneColor(t)
		w.Transparency = 0.55 - 0.3 * t
		w.Anchored = true
		w.CanCollide = false
		w.CanTouch = false
		w.CastShadow = false
		w.Massless = true
		w.Parent = parent
		weld(parent, w)
	end
end

local function pt(cf, x, y, z)
	return (cf * CFrame.new(x, y, z)).Position
end

---------------------------------------------------------------------------
-- ลำตัว: อก ท้อง หลังโหนก ไหล่ สะโพก
---------------------------------------------------------------------------

local root = newPart("HumanoidRootPart", Vector3.new(2, 2, 2), CFrame.new(0, 10, 0), { transparency = 1 })
model.PrimaryPart = root

local hips = ellipsoid("Hips", Vector3.new(8.5, 7, 8.5), CFrame.new(0, 10, 1.2))
motor(root, hips, CFrame.new(0, 10, 0), "RootJoint")
voxels(hips, 18)

local torso = ellipsoid("Torso", Vector3.new(10, 9.5, 8), CFrame.new(0, 17.5, -0.6))
motor(hips, torso, CFrame.new(0, 12.5, 0))
voxels(torso, 24)

voxels(decorEllipsoid(torso, "Belly", Vector3.new(8.6, 7.5, 7.6), CFrame.new(0, 13.2, -0.1)), 12)
voxels(decorEllipsoid(torso, "Hump", Vector3.new(8.4, 5, 6.4), CFrame.new(0, 20.6, 1)), 10)
decorEllipsoid(torso, "Collar", Vector3.new(7.6, 3.6, 5.2), CFrame.new(0, 22, -1.3))
for _, s in ipairs({ -1, 1 }) do
	voxels(decorEllipsoid(torso, "ShoulderMuscle", Vector3.new(4.2, 4.4, 4.8), CFrame.new(s * 4.6, 19.6, -0.8)), 6)
end

-- เกล็ดท้อง
for i = 0, 6 do
	local y = 9.8 + i
	local w = 3.7 - math.abs(i - 3) * 0.28
	decor(torso, "BellyPlate", Vector3.new(w, 0.78, 0.7), CFrame.new(0, y, -3.35 - (y - 9.8) * 0.2) * A(rad(-12), 0, 0), {
		material = Enum.Material.Neon,
		color = Color3.fromRGB(230, 216, 255),
		transparency = 0.2,
	})
end

-- ซี่โครงโค้งรอบอก
for i = 0, 4 do
	local y = 13.6 + i * 1.2
	local spread = 3.6 + math.sin(i / 4 * math.pi) * 0.9
	for _, s in ipairs({ -1, 1 }) do
		local a = Vector3.new(s * 1.9, y, -4.3)
		local b = Vector3.new(s * spread, y + 0.6, -3.1)
		local c = Vector3.new(s * (spread + 0.6), y + 1.1, -1.5)
		bar(torso, a, b, 0.42, CONFIG.AccentColor, 0.1)
		bar(torso, b, c, 0.36, CONFIG.AccentColor, 0.25)
	end
end

-- แนวหนามกลางหลัง
local RIDGE = { { 22.6, 1.8, 0.8 }, { 21.3, 3.6, 1.1 }, { 19.6, 4.3, 1.4 }, { 17.6, 3.9, 1.3 }, { 15.6, 3.8, 1.1 }, { 13.6, 3.9, 1 } }
for i, r in ipairs(RIDGE) do
	spike(torso, Vector3.new(0, r[1], r[2]), Vector3.new(0, 1, 1.1), 2.2 * r[3], 0.75 * r[3], i % 2 == 0 and CONFIG.AccentColor or CONFIG.GoldColor)
end
spike(hips, Vector3.new(0, 11.8, 5.1), Vector3.new(0, 0.8, 1.2), 2, 0.68)
spike(hips, Vector3.new(0, 9.8, 5.5), Vector3.new(0, 0.8, 1.2), 1.8, 0.6)

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
local NECK_WIDTH = { 3.1, 2.6, 2.2 }

for _, n in ipairs(NECKS) do
	local key = n.key
	local dir = n.dir.Unit
	local pos = n.base
	local prev = torso
	for j = 1, 3 do
		local w = NECK_WIDTH[j]
		local nextPos = pos + dir * 2.7
		local seg = bone("Neck" .. j .. "_" .. key, pos, nextPos, w, prev)
		voxels(seg, 6)
		-- เกล็ดใต้คอ + หนามหลังคอ
		decor(seg, "ThroatPlate", Vector3.new(w * 0.62, w * 0.2, 2.3), seg.CFrame * CFrame.new(0, -w * 0.48, 0), {
			material = Enum.Material.Neon,
			color = Color3.fromRGB(230, 216, 255),
			transparency = 0.3,
		})
		spike(seg, pt(seg.CFrame, 0, w * 0.45, 0), seg.CFrame:VectorToWorldSpace(Vector3.new(0, 1, 0.7)), 1.3, 0.5, j % 2 == 1 and CONFIG.GoldColor or CONFIG.AccentColor)
		prev = seg
		pos = nextPos
		dir = (dir + Vector3.new(0, 0, -0.22)).Unit
	end

	-- หัว
	local headCF = lookAt(pos, pos + Vector3.new(n.dir.X * 0.5, -0.15, -1))
	local head = ellipsoid("Head_" .. key, Vector3.new(2.8, 2.2, 4.2), headCF * CFrame.new(0, 0.3, -1.7))
	motor(prev, head, headCF)
	local hcf = head.CFrame
	decor(head, "Skull", Vector3.new(2.6, 2, 2.6), hcf * CFrame.new(0, 0.15, 0.3))
	voxels(head, 8)
	decor(head, "Snout", Vector3.new(2.1, 1.35, 2.8), hcf * CFrame.new(0, -0.15, -2.9))

	for _, s in ipairs({ -1, 1 }) do
		decorEllipsoid(head, "Eye", Vector3.new(0.65, 0.5, 0.75), hcf * CFrame.new(s * 1.12, 0.5, -1), {
			material = Enum.Material.Neon,
			color = CONFIG.EyeColor,
			transparency = 0,
		})
		decor(head, "Nostril", Vector3.new(0.32, 0.22, 0.32), hcf * CFrame.new(s * 0.55, 0.52, -4.1), {
			material = Enum.Material.SmoothPlastic,
			color = Color3.fromRGB(10, 5, 25),
			transparency = 0,
		})
		bar(head, pt(hcf, s * 0.55, 0.95, -2), pt(hcf, s * 1.35, 1.25, -0.3), 0.36, CONFIG.AccentColor) -- คิ้ว
		spike(head, pt(hcf, s * 1.25, -0.3, 0.6), hcf:VectorToWorldSpace(Vector3.new(s * 0.8, -0.1, 1)), 1.7, 0.42, CONFIG.AccentColor) -- แก้ม
		spike(head, pt(hcf, s * 1.05, 0.2, 1.3), hcf:VectorToWorldSpace(Vector3.new(s, 0.3, 0.8)), 1.2, 0.32)
		-- เขา 2 ท่อน
		local hornBase = pt(hcf, s * 0.9, 1.1, 1)
		local hornMid = hornBase + hcf:VectorToWorldSpace(Vector3.new(s * 0.5, 1.1, 1.4))
		local hornTip = hornMid + hcf:VectorToWorldSpace(Vector3.new(s * 0.2, 0.2, 1.3))
		claw(head, hornBase, hornMid, 0.55)
		claw(head, hornMid, hornTip, 0.35)
	end

	-- กราม (ขยับอ้าปากได้)
	local jawCF = headCF * CFrame.new(0, -0.6, -0.4)
	local jaw = newPart("Jaw_" .. key, Vector3.new(2.1, 0.7, 4.3), jawCF * CFrame.new(0, -0.35, -2.15))
	motor(head, jaw, jawCF)
	spike(jaw, pt(jaw.CFrame, 0, -0.3, 1.2), jaw.CFrame:VectorToWorldSpace(Vector3.new(0, -0.6, 1)), 1.1, 0.35, CONFIG.AccentColor)
	for t = 0, 4 do
		for _, s in ipairs({ -1, 1 }) do
			decor(jaw, "Tooth", Vector3.new(0.25, 0.45, 0.25), jaw.CFrame * CFrame.new(s * 0.8, 0.5, -1.9 + t * 0.6), {
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
	spike(fore, elbow, Vector3.new(s * 0.4, -0.2, 1), 1.5, 0.5)

	local handCF = lookAt(wrist, wrist + (wrist - elbow))
	local hand = newPart("Hand_" .. k, Vector3.new(2.2, 2.2, 2.2), handCF, { shape = Enum.PartType.Ball })
	motor(fore, hand, handCF)
	for f = 1, 3 do
		local x = (f - 2) * 0.65
		local finger = bone("Finger" .. f .. "_" .. k, pt(handCF, x, 0.3, -0.8), pt(handCF, x * 1.4, 1.1, -2.3), 0.5, hand)
		local fcf, hz = finger.CFrame, finger.Size.Z / 2
		claw(finger, pt(fcf, 0, 0, -hz), pt(fcf, 0, -0.2, -hz - 0.8), 0.3)
	end

	-- ปีก: ต้นปีก, ปลายปีก, ก้านปีก 4 ก้านแผ่จากข้อมือปีก, พังผืดขอบหยัก
	local wBase = Vector3.new(2.6 * s, 21.2, 2.6)
	local wElbow = wBase + Vector3.new(4.6 * s, 5.4, 2.6)
	local wWrist = wElbow + Vector3.new(4.6 * s, 2.6, 1.2)
	local boneOpts = { material = Enum.Material.Neon, color = CONFIG.AccentColor, transparency = 0.1 }
	local w1 = bone("WingArm_" .. k, wBase, wElbow, 1.3, torso, boneOpts)
	local w2 = bone("WingHand_" .. k, wElbow, wWrist, 1.0, w1, boneOpts)
	decor(w2, "WingKnuckle", Vector3.new(1.5, 1.5, 1.5), CFrame.new(wWrist), {
		shape = Enum.PartType.Ball, material = Enum.Material.Neon, color = CONFIG.GoldColor, transparency = 0,
	})
	claw(w2, wWrist, wWrist + Vector3.new(0.5 * s, 1.3, -1.3), 0.42)

	local tipOffsets = {
		Vector3.new(5 * s, 7, 0.8), Vector3.new(8.5 * s, 3, 1.8),
		Vector3.new(8.5 * s, -2.5, 2.8), Vector3.new(6 * s, -8, 3.4),
	}
	local tips, spars = {}, {}
	for i, o in ipairs(tipOffsets) do
		tips[i] = wWrist + o
		spars[i] = bone("WingFinger" .. i .. "_" .. k, wWrist, tips[i], 0.55 - (i - 1) * 0.05, w2, boneOpts)
		decor(spars[i], "WingTipCrystal", Vector3.new(0.75, 1.5, 0.75), CFrame.new(tips[i]) * A(0, 0, rad(45 * s)), {
			material = Enum.Material.Neon, color = Color3.fromRGB(160, 240, 255), transparency = 0,
		})
	end
	local edgeColor = Color3.fromRGB(243, 184, 255)
	for i = 1, 3 do
		local a, b = tips[i], tips[i + 1]
		local mid = a:Lerp(b, 0.5):Lerp(wWrist, 0.24)
		triangle(spars[i], wWrist, a, mid, 0.75)
		triangle(spars[i + 1], wWrist, mid, b, 0.75)
		bar(spars[i], a, mid, 0.2, edgeColor, 0.1)
		bar(spars[i + 1], mid, b, 0.2, edgeColor, 0.1)
	end
	local bodyRear = Vector3.new(2.2 * s, 12.5, 4.2)
	local midIn = tips[4]:Lerp(bodyRear, 0.5):Lerp(wWrist, 0.18)
	triangle(w1, wBase, wElbow, wWrist, 0.25)
	triangle(w1, wBase, wWrist, bodyRear, 0.35)
	triangle(w2, wWrist, tips[4], midIn, 0.7)
	triangle(w2, wWrist, midIn, bodyRear, 0.6)
	bar(w2, tips[4], midIn, 0.2, edgeColor, 0.1)
	bar(w2, midIn, bodyRear, 0.2, edgeColor, 0.1)

	-- ขาแบบมังกร: ต้นขา, หน้าแข้ง, ข้อเท้า, เท้า
	local hip = Vector3.new(3.6 * s, 9.6, 1.2)
	local knee = hip + Vector3.new(1 * s, -3.2, -2.6)
	local hock = knee + Vector3.new(0.2 * s, -2.6, 2.8)
	local ankle = hock + Vector3.new(0, -2.3, -0.8)
	local thigh = bone("Thigh_" .. k, hip, knee, 3.4, hips)
	voxels(decorEllipsoid(thigh, "Haunch", Vector3.new(4.6, 5.6, 6.2), CFrame.new(hip + Vector3.new(0.6 * s, -0.6, 0.2))), 10)
	local shin = bone("Shin_" .. k, knee, hock, 2.4, thigh)
	local meta = bone("Metatarsal_" .. k, hock, ankle, 1.8, shin)
	voxels(shin, 6)
	voxels(meta, 4)
	spike(meta, hock, Vector3.new(0, 0.3, 1.2), 1.4, 0.45)

	local footCF = CFrame.lookAt(ankle, ankle + Vector3.new(0, 0, -1))
	local foot = ellipsoid("Foot_" .. k, Vector3.new(2.8, 1.1, 3.4), footCF * CFrame.new(0, -0.3, -1.1))
	motor(meta, foot, footCF)
	for t = -1, 1 do
		local base = pt(foot.CFrame, t * 0.9, -0.1, -1.5)
		claw(foot, base, base + Vector3.new(t * 0.3, -0.35, -1.3), 0.38)
	end
	claw(foot, pt(foot.CFrame, 0, -0.1, 1.4), pt(foot.CFrame, 0, -0.4, 2.4), 0.32)
end

---------------------------------------------------------------------------
-- หาง 8 ท่อน + หนาม + ครีบปลายหาง
---------------------------------------------------------------------------

do
	local pos = Vector3.new(0, 8.5, 4.5)
	local dir = Vector3.new(0, -0.35, 1).Unit
	local prev = hips
	local count = 8
	for j = 1, count do
		local w = 3.4 - (j - 1) * (2.6 / (count - 1))
		local nextPos = pos + dir * 2.7
		local seg = bone("Tail" .. j, pos, nextPos, w, prev)
		voxels(seg, math.max(3, 9 - j))
		spike(seg, pt(seg.CFrame, 0, w * 0.45, 0), seg.CFrame:VectorToWorldSpace(Vector3.new(0, 1, 0.8)), 0.7 + w * 0.4, 0.3 + w * 0.13, j % 2 == 1 and CONFIG.GoldColor or CONFIG.AccentColor)
		prev = seg
		pos = nextPos
		dir = (dir + Vector3.new(0.12, 0.07, 0)).Unit
	end
	local sideDir = dir:Cross(Vector3.yAxis).Unit
	local back = pos - dir * 0.6
	local tipP = pos + dir * 3.4
	local left = pos + sideDir * 1.9 + dir * 0.5
	local right = pos - sideDir * 1.9 + dir * 0.5
	triangle(prev, back, left, tipP, 0.8)
	triangle(prev, back, tipP, right, 0.8)
	bar(prev, left, tipP, 0.2, Color3.fromRGB(243, 184, 255), 0.1)
	bar(prev, right, tipP, 0.2, Color3.fromRGB(243, 184, 255), 0.1)
	decor(prev, "TailCrystal", Vector3.new(1, 2.2, 1), CFrame.new(tipP) * A(rad(70), 0, rad(45)), {
		material = Enum.Material.Neon,
		color = Color3.fromRGB(120, 235, 255),
		transparency = 0.1,
	})
end

---------------------------------------------------------------------------
-- ผิวชั้นใน: ก็อปทุกชิ้นร่างใสเป็นชั้นทึบขนาด 97% ไว้ข้างใน
---------------------------------------------------------------------------

local PIX_BASE = Color3.fromRGB(91, 60, 214)
local PIX_LAV = Color3.fromRGB(200, 180, 255)
local PIX_WHITE = Color3.fromRGB(242, 237, 255)
local PIX_CYAN = Color3.fromRGB(127, 233, 255)
local LIGHT = Vector3.new(0.4, 0.8, -0.5).Unit
local NEIGHBORS = {
	Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 1, 0),
	Vector3.new(0, -1, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
}

-- เติมพิกเซลสี่เหลี่ยมบนผิวของชิ้นตามตาราง (เฉพาะชั้นนอกสุด)
local function pixelShell(part)
	local size, g = part.Size, CONFIG.PixelSize
	local nx = math.max(1, math.round(size.X / g))
	local ny = math.max(1, math.round(size.Y / g))
	local nz = math.max(1, math.round(size.Z / g))
	local cell = Vector3.new(size.X / nx, size.Y / ny, size.Z / nz)
	local h = size / 2
	local round = part.Shape == Enum.PartType.Ball or part:GetAttribute("Ellipsoid")
	local function inside(i, j, k)
		if i < 0 or j < 0 or k < 0 or i >= nx or j >= ny or k >= nz then
			return false
		end
		if not round then
			return true
		end
		local x = ((i + 0.5) * cell.X - h.X) / h.X
		local y = ((j + 0.5) * cell.Y - h.Y) / h.Y
		local z = ((k + 0.5) * cell.Z - h.Z) / h.Z
		return x * x + y * y + z * z <= 1
	end
	for i = 0, nx - 1 do
		for j = 0, ny - 1 do
			for k = 0, nz - 1 do
				if inside(i, j, k) then
					local nrm, exposed = Vector3.zero, false
					for _, o in ipairs(NEIGHBORS) do
						if not inside(i + o.X, j + o.Y, k + o.Z) then
							exposed = true
							nrm = nrm + o
						end
					end
					if exposed then
						local lp = Vector3.new((i + 0.5) * cell.X - h.X, (j + 0.5) * cell.Y - h.Y, (k + 0.5) * cell.Z - h.Z)
						if round then
							nrm = Vector3.new(lp.X / (h.X * h.X), lp.Y / (h.Y * h.Y), lp.Z / (h.Z * h.Z))
						end
						if nrm.Magnitude < 1e-3 then
							nrm = Vector3.yAxis
						end
						nrm = part.CFrame:VectorToWorldSpace(nrm.Unit)
						local roll = rng:NextNumber()
						local c = roll < 0.015 and PIX_CYAN or roll < 0.035 and PIX_WHITE or roll < 0.13 and PIX_LAV or PIX_BASE
						local lit = (0.38 + 0.72 * math.max(nrm:Dot(LIGHT), 0) + 0.18 * math.max(-nrm.Z, 0)) * rng:NextNumber(0.82, 1.12)
						local px = Instance.new("Part")
						px.Name = "Pixel"
						px.Size = cell * 0.84
						px.CFrame = part.CFrame * CFrame.new(lp)
						px.Material = roll < 0.035 and Enum.Material.Neon or Enum.Material.SmoothPlastic
						px.Color = Color3.new(math.min(1, c.R * lit), math.min(1, c.G * lit), math.min(1, c.B * lit))
						px.Transparency = 0.08
						px.Anchored = true
						px.CanCollide = false
						px.CanTouch = false
						px.CanQuery = false
						px.CastShadow = false
						px.Massless = true
						px.Parent = part
						weld(part, px)
					end
				end
			end
		end
	end
end

if CONFIG.PixelSkin then
	local bodyParts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Part") and d.Material == CONFIG.BodyMaterial and d.Transparency < 1
			and math.min(d.Size.X, d.Size.Y, d.Size.Z) >= 0.9 then
			table.insert(bodyParts, d)
		end
	end
	for _, d in ipairs(bodyParts) do
		pixelShell(d)
	end
elseif CONFIG.SkinEnabled then
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Part") and d.Material == CONFIG.BodyMaterial and d.Transparency < 1 then
			local skin = Instance.new("Part")
			skin.Name = "Skin"
			skin.Shape = d.Shape
			skin.Size = d.Size * 0.97
			skin.CFrame = d.CFrame
			skin.Material = CONFIG.SkinMaterial
			skin.Color = CONFIG.SkinColor
			skin.Transparency = CONFIG.SkinTransparency
			local mesh = d:FindFirstChildOfClass("SpecialMesh")
			if mesh then
				mesh:Clone().Parent = skin
			end
			skin.Anchored = true
			skin.CanCollide = false
			skin.CanTouch = false
			skin.CanQuery = false
			skin.Massless = true
			skin.CastShadow = false
			skin.Parent = d
			weld(d, skin)
		end
	end
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
	-- แกนลำตัว (หน้า-หลัง) ในกรอบของข้อต่อ ใช้กระพือปีกขึ้นลงรอบลำตัว
	local jointWorld = m.motor.Part0.CFrame * m.base
	m.axisZ = jointWorld:VectorToObjectSpace(Vector3.zAxis)
	m.axisY = jointWorld:VectorToObjectSpace(Vector3.yAxis)
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

	-- ปีกกระพือรอบแกนลำตัวทั้งแผง (ปีกท่อนนอกกับก้านปีกไม่ขยับแยก เพื่อไม่ให้พังผืดฉีก)
	local down = sin(t * 2.2)
	for _, side in ipairs({ { "L", -1 }, { "R", 1 } }) do
		local k, s = side[1], side[2]
		local wing = motors["WingArm_" .. k]
		if wing then
			wing.motor.C0 = wing.base
				* CFrame.fromAxisAngle(wing.axisZ, s * (down * 0.6 - 0.25))
				* CFrame.fromAxisAngle(wing.axisY, -s * down * 0.12)
		end
	end
	for _, side in ipairs({ { "L", 0 }, { "R", math.pi } }) do
		local k, ph = side[1], side[2]
		pose("UpperArm_" .. k, A(sin(t * 1.2 + ph) * 0.25, 0, sin(t * 0.9 + ph) * 0.2))
		pose("Forearm_" .. k, A(sin(t * 1.6 + ph) * 0.3, 0, 0))
		pose("Hand_" .. k, A(sin(t * 2 + ph) * 0.3, 0, sin(t * 1.3 + ph) * 0.4))
		for f = 1, 3 do
			pose("Finger" .. f .. "_" .. k, A((sin(t * 2.5 + f + ph) + 1) * 0.25, 0, 0))
		end
		pose("Thigh_" .. k, A(sin(t * 1.4 + ph) * 0.08, 0, 0))
		pose("Shin_" .. k, A(-sin(t * 1.4 + ph) * 0.1, 0, 0))
		pose("Metatarsal_" .. k, A(sin(t * 1.4 + ph) * 0.08, 0, 0))
		pose("Foot_" .. k, A(sin(t * 1.4 + ph) * 0.1, 0, 0))
	end

	for j = 1, 8 do
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
