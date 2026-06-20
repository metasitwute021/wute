#!/usr/bin/env python3
"""
Add furniture / details to modern-house.obj.

Coordinate system (Y up):
  Ground / floor level  Y = 0,  ceiling of ground floor ~ Y = 200
  Interior footprint    X[-1042,-36]  Z[-348,238]
    - Kitchen  : west room   X[-1035,-780]
    - Living   : east-south  X[-740,-60]  Z[-340,-50]
    - Bedroom  : east-north  X[-740,-60]  Z[  0, 225]
  Front yard (open, Y=0)     X[-200,360]  Z[300,860]
"""
import math

OBJ_IN  = "modern-house.obj"
OBJ_OUT = "modern-house.obj"
MTL_OUT = "modern-house.mtl"

# ---- count existing vertices so new face indices are absolute ----
base_v = 0
with open(OBJ_IN) as f:
    for ln in f:
        if ln.startswith("v "):
            base_v += 1
print("existing verts:", base_v)

OUT = []                 # appended obj lines
V = base_v               # running absolute vertex count

def emit(s): OUT.append(s)

def add_v(x, y, z):
    global V
    emit(f"v {x:.3f} {y:.3f} {z:.3f}")
    V += 1
    return V             # absolute index of this vertex

def obj(name, mat):
    emit(f"o {name}")
    emit(f"usemtl {mat}")

def box(x0, x1, y0, y1, z0, z1):
    """Axis-aligned box -> 6 quad faces."""
    i = [
        add_v(x0, y0, z0), add_v(x1, y0, z0), add_v(x1, y1, z0), add_v(x0, y1, z0),
        add_v(x0, y0, z1), add_v(x1, y0, z1), add_v(x1, y1, z1), add_v(x0, y1, z1),
    ]
    q = [(0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(0,1,5,4),(3,7,6,2)]
    for a,b,c,d in q:
        emit(f"f {i[a]} {i[b]} {i[c]} {i[d]}")

def cyl(cx, cy, cz, r, h, axis="y", seg=14, r2=None):
    """Prism/cylinder. r2 lets it taper (top radius)."""
    if r2 is None: r2 = r
    bot, top = [], []
    for k in range(seg):
        a = 2*math.pi*k/seg
        c, s = math.cos(a), math.sin(a)
        if axis == "y":
            bot.append(add_v(cx + r*c,  cy,     cz + r*s))
        elif axis == "x":
            bot.append(add_v(cx,        cy + r*c, cz + r*s))
        else:
            bot.append(add_v(cx + r*c,  cy + r*s, cz))
    for k in range(seg):
        a = 2*math.pi*k/seg
        c, s = math.cos(a), math.sin(a)
        if axis == "y":
            top.append(add_v(cx + r2*c, cy + h,  cz + r2*s))
        elif axis == "x":
            top.append(add_v(cx + h,    cy + r2*c, cz + r2*s))
        else:
            top.append(add_v(cx + r2*c, cy + r2*s, cz + h))
    for k in range(seg):
        n = (k+1) % seg
        emit(f"f {bot[k]} {bot[n]} {top[n]} {top[k]}")
    emit("f " + " ".join(str(x) for x in bot))
    emit("f " + " ".join(str(x) for x in reversed(top)))

def quad(p0, p1, p2, p3):
    a = add_v(*p0); b = add_v(*p1); c = add_v(*p2); d = add_v(*p3)
    emit(f"f {a} {b} {c} {d}")

# =====================================================================
#  MATERIALS  (plain colour, no texture maps -> no vt needed)
# =====================================================================
NEW_MATS = """
# ---- furniture / detail materials (added) ----
newmtl Furn_Wood
Kd 0.45 0.30 0.17
Ks 0.2 0.2 0.2
Ns 30
newmtl Furn_WoodLight
Kd 0.74 0.58 0.39
Ks 0.2 0.2 0.2
Ns 30
newmtl Furn_WoodDark
Kd 0.26 0.17 0.10
Ks 0.2 0.2 0.2
Ns 30
newmtl Fabric_Cream
Kd 0.90 0.87 0.79
newmtl Fabric_Sofa
Kd 0.27 0.40 0.52
newmtl Fabric_Red
Kd 0.66 0.16 0.16
newmtl Fabric_Teal
Kd 0.18 0.52 0.50
newmtl Pillow_White
Kd 0.95 0.95 0.93
newmtl Metal_Steel
Kd 0.74 0.76 0.79
Ks 0.6 0.6 0.6
Ns 80
newmtl Glass_Win
Kd 0.55 0.70 0.80
newmtl Black_Mat
Kd 0.05 0.05 0.05
newmtl White_Mat
Kd 0.93 0.93 0.93
newmtl Skin_Light
Kd 0.86 0.67 0.53
newmtl Skin_Tan
Kd 0.66 0.47 0.33
newmtl Hair_Dark
Kd 0.16 0.11 0.07
newmtl Cloth_Green
Kd 0.20 0.50 0.28
newmtl Cloth_Blue
Kd 0.18 0.30 0.62
newmtl Cloth_Orange
Kd 0.82 0.42 0.12
newmtl Cloth_Plum
Kd 0.45 0.20 0.40
newmtl Book_Red
Kd 0.70 0.15 0.13
newmtl Book_Green
Kd 0.16 0.45 0.22
newmtl Book_Blue
Kd 0.15 0.32 0.58
newmtl Book_Yellow
Kd 0.84 0.70 0.18
newmtl Book_Teal
Kd 0.12 0.46 0.50
newmtl Grass_Green
Kd 0.30 0.55 0.20
newmtl Grass_Dark
Kd 0.22 0.42 0.16
newmtl Car_Red
Kd 0.72 0.09 0.09
Ks 0.7 0.7 0.7
Ns 90
newmtl Car_Glass
Kd 0.16 0.21 0.27
newmtl Tire_Black
Kd 0.04 0.04 0.04
newmtl Plant_Green
Kd 0.18 0.42 0.16
newmtl Plant_Pot
Kd 0.55 0.30 0.20
newmtl Vase_Ceramic
Kd 0.86 0.83 0.76
newmtl Frame_Gold
Kd 0.72 0.57 0.22
Ks 0.5 0.5 0.5
Ns 60
newmtl Frame_Wood
Kd 0.35 0.22 0.12
newmtl Art_A
Kd 0.30 0.55 0.70
newmtl Art_B
Kd 0.80 0.55 0.35
newmtl Art_C
Kd 0.55 0.65 0.40
newmtl Lamp_Shade
Kd 0.96 0.90 0.68
newmtl Carpet_Grey
Kd 0.55 0.55 0.58
newmtl Carpet_Warm
Kd 0.62 0.45 0.34
"""

# =====================================================================
#  REUSABLE PIECES
# =====================================================================
def chair(cx, cz, face=+1, seat_y=46, mat="Furn_Wood", w=46, d=46):
    """Simple chair. `face` direction of back along Z (+1 back at -z)."""
    obj(f"Chair_{cx:.0f}_{cz:.0f}", mat)
    x0, x1 = cx-w/2, cx+w/2
    z0, z1 = cz-d/2, cz+d/2
    t = 5
    # seat
    box(x0, x1, seat_y, seat_y+t, z0, z1)
    # 4 legs
    for lx in (x0, x1-6):
        for lz in (z0, z1-6):
            box(lx, lx+6, 0, seat_y, lz, lz+6)
    # backrest
    if face >= 0:
        box(x0, x1, seat_y+t, seat_y+t+50, z0, z0+6)
    else:
        box(x0, x1, seat_y+t, seat_y+t+50, z1-6, z1)

def book_row(x0, y, z0, z1, n, height=26, mat_cycle=None):
    """A row of books standing along X."""
    mats = mat_cycle or ["Book_Red","Book_Green","Book_Blue","Book_Yellow","Book_Teal"]
    w = (z1 - z0)
    bw = 7
    x = x0
    for k in range(n):
        m = mats[k % len(mats)]
        obj(f"Book_{x:.0f}_{z0:.0f}_{k}", m)
        h = height + (k % 3)*4 - 4
        box(x, x+bw, y, y+h, z0, z1)
        x += bw + 1.5

def picture(cx, cy, wall_x=None, wall_z=None, w=70, h=50, mat="Art_A"):
    """Framed picture hung flat on a wall. Provide wall_x OR wall_z."""
    obj(f"Picture_{cx:.0f}_{cy:.0f}", "Frame_Gold")
    fr = 4
    if wall_z is not None:           # wall runs along X, picture faces +/-Z
        zt = wall_z
        box(cx-w/2-fr, cx+w/2+fr, cy-h/2-fr, cy+h/2+fr, zt-2, zt)     # frame slab
        obj(f"PictureArt_{cx:.0f}_{cy:.0f}", mat)
        box(cx-w/2, cx+w/2, cy-h/2, cy+h/2, zt-3, zt-2)
    else:
        xt = wall_x
        box(xt, xt+2, cy-h/2-fr, cy+h/2+fr, cx-w/2-fr, cx+w/2+fr)
        obj(f"PictureArt_{cx:.0f}_{cy:.0f}", mat)
        box(xt+2, xt+3, cy-h/2, cy+h/2, cx-w/2, cx+w/2)

def rug(cx, cz, w, d, mat="Carpet_Grey"):
    obj(f"Rug_{cx:.0f}_{cz:.0f}", mat)
    box(cx-w/2, cx+w/2, 0.3, 1.2, cz-d/2, cz+d/2)

def vase(cx, cy, cz, r=9, h=34, mat="Vase_Ceramic"):
    obj(f"Vase_{cx:.0f}_{cz:.0f}", mat)
    cyl(cx, cy, cz, r*0.7, h*0.45, r2=r, seg=12)
    cyl(cx, cy+h*0.45, cz, r, h*0.55, r2=r*0.6, seg=12)

def potted_plant(cx, cy, cz, scale=1.0):
    obj(f"Pot_{cx:.0f}_{cz:.0f}", "Plant_Pot")
    cyl(cx, cy, cz, 12*scale, 22*scale, r2=15*scale, seg=12)
    obj(f"Plant_{cx:.0f}_{cz:.0f}", "Plant_Green")
    # foliage = stacked tapered blobs
    cyl(cx, cy+22*scale, cz, 20*scale, 26*scale, r2=14*scale, seg=10)
    cyl(cx, cy+44*scale, cz, 16*scale, 24*scale, r2=4*scale, seg=10)

def person(cx, cz, cy=0, facing=0.0, shirt="Cloth_Blue", pants="Furn_WoodDark",
           skin="Skin_Light", scale=1.0, sitting=False, name="Person"):
    """Stylised low-poly human, standing or sitting, ~170cm-ish in model units."""
    s = scale
    obj(f"{name}_legs_{cx:.0f}_{cz:.0f}", pants)
    if sitting:
        # thighs forward + shins down
        for dx in (-7*s, 1*s):
            box(cx+dx, cx+dx+6*s, 46*s, 52*s, cz-2*s, cz+22*s)   # thigh
            box(cx+dx, cx+dx+6*s, 0, 46*s, cz+16*s, cz+22*s)     # shin
        torso_y0 = 52*s
    else:
        for dx in (-8*s, 2*s):
            box(cx+dx, cx+dx+6*s, 0, 52*s, cz-3*s, cz+3*s)
        torso_y0 = 52*s
    th = 40*s
    obj(f"{name}_torso_{cx:.0f}_{cz:.0f}", shirt)
    box(cx-9*s, cx+9*s, torso_y0, torso_y0+th, cz-5*s, cz+5*s)
    # arms
    for dx in (-13*s, 9*s):
        box(cx+dx, cx+dx+4*s, torso_y0-2*s, torso_y0+th, cz-4*s, cz+4*s)
    # neck + head
    neck = torso_y0+th
    obj(f"{name}_head_{cx:.0f}_{cz:.0f}", skin)
    box(cx-2.5*s, cx+2.5*s, neck, neck+5*s, cz-2.5*s, cz+2.5*s)
    cyl(cx, neck+5*s, cz, 8*s, 0, r2=8*s, seg=10)   # flat-ish, skip
    box(cx-7*s, cx+7*s, neck+5*s, neck+20*s, cz-7*s, cz+7*s)
    obj(f"{name}_hair_{cx:.0f}_{cz:.0f}", "Hair_Dark")
    box(cx-7.5*s, cx+7.5*s, neck+15*s, neck+22*s, cz-7.5*s, cz+7.5*s)

# =====================================================================
#  KITCHEN ZONE  (โซนห้องครัว)  west room
# =====================================================================
def build_kitchen():
    wx = -1035            # west wall inner face ~ -1042
    # --- run of base cabinets + counter along west wall (depth in +X) ---
    cab_x0, cab_x1 = wx, wx+58
    obj("Kitchen_BaseCab", "Furn_WoodLight")
    box(cab_x0, cab_x1, 0, 86, -330, 150)
    obj("Kitchen_Counter", "Metal_Steel")
    box(cab_x0-2, cab_x1+4, 86, 92, -332, 154)
    # cabinet door seams (thin dark insets)
    obj("Kitchen_CabDoors", "Furn_Wood")
    z = -322
    while z < 140:
        box(cab_x1-1, cab_x1+1, 8, 80, z, z+44)
        z += 52
    # --- sink ---
    obj("Kitchen_Sink", "Metal_Steel")
    box(wx+10, wx+46, 80, 86, -60, 10)
    obj("Kitchen_SinkBasin", "Black_Mat")
    box(wx+14, wx+42, 70, 84, -56, 6)
    obj("Kitchen_Faucet", "Chrome")
    cyl(wx+28, 86, -52, 2.5, 26, seg=8)
    box(wx+28, wx+50, 110, 114, -54, -50)
    # --- stove / hob ---
    obj("Kitchen_Stove", "Black_Mat")
    box(wx+6, wx+52, 86, 90, 60, 130)
    obj("Kitchen_Burners", "Metal_Steel")
    for bz in (75, 110):
        cyl(wx+20, 90, bz, 7, 1.5, seg=10)
        cyl(wx+40, 90, bz, 7, 1.5, seg=10)
    # --- upper wall cabinets ---
    obj("Kitchen_UpperCab", "Furn_WoodLight")
    box(wx, wx+34, 130, 188, -320, 40)
    box(wx, wx+34, 130, 188, 70, 150)
    # --- range hood over stove ---
    obj("Kitchen_Hood", "Metal_Steel")
    box(wx, wx+50, 150, 188, 58, 132)
    # --- tall fridge (north end) ---
    obj("Kitchen_Fridge", "White_Mat")
    box(wx, wx+62, 0, 188, 165, 232)
    obj("Kitchen_FridgeHandle", "Chrome")
    box(wx+62, wx+66, 60, 150, 170, 174)
    obj("Kitchen_FridgeSeam", "Metal_Steel")
    box(wx, wx+62, 96, 99, 165, 232)
    # --- kitchen island ---
    ix, iz = -880, -110
    obj("Kitchen_Island", "Furn_Wood")
    box(ix-70, ix+70, 0, 88, iz-45, iz+45)
    obj("Kitchen_IslandTop", "Furn_WoodDark")
    box(ix-78, ix+78, 88, 94, iz-52, iz+52)
    # stools at island
    for sx in (ix-40, ix, ix+40):
        obj(f"Stool_{sx}", "Metal_Steel")
        cyl(sx, 0, iz+78, 4, 62, seg=8)
        obj(f"StoolSeat_{sx}", "Furn_WoodDark")
        cyl(sx, 62, iz+78, 16, 6, seg=12)
    # --- items on counter ---
    obj("Kitchen_Pot", "Metal_Steel")
    cyl(wx+30, 92, 95, 13, 16, seg=14)
    obj("Kitchen_Bottles", "Glass_Win")
    cyl(wx+24, 92, -120, 4, 30, seg=8)
    cyl(wx+38, 92, -110, 5, 24, seg=8)
    obj("Kitchen_CuttingBoard", "Furn_WoodLight")
    box(wx+8, wx+44, 92, 95, -200, -150)
    # fruit bowl on island
    obj("Island_Bowl", "Vase_Ceramic")
    cyl(ix, 94, iz, 14, 8, r2=18, seg=14)
    for fx,fz,fm in [(-6,-4,"Book_Red"),(6,2,"Book_Yellow"),(0,6,"Book_Green")]:
        obj(f"Fruit_{fx}_{fz}", fm); cyl(ix+fx, 100, iz+fz, 5, 8, r2=5, seg=8)
    # dining set near kitchen
    dx, dz = -870, 120
    obj("Dining_Table", "Furn_Wood")
    box(dx-85, dx+85, 72, 78, dz-55, dz+55)
    for lx in (dx-78, dx+72):
        for lz in (dz-48, dz+42):
            box(lx, lx+6, 0, 72, lz, lz+6)
    chair(dx-50, dz-80, face=-1, mat="Furn_WoodDark")
    chair(dx+50, dz-80, face=-1, mat="Furn_WoodDark")
    chair(dx-50, dz+80, face=+1, mat="Furn_WoodDark")
    chair(dx+50, dz+80, face=+1, mat="Furn_WoodDark")
    # a person cooking at the counter
    person(wx+95, 40, facing=math.pi, shirt="Cloth_Orange", pants="Furn_WoodDark",
           name="Cook")

# =====================================================================
#  LIVING ROOM  east-south
# =====================================================================
def build_living():
    # rug centre
    cx, cz = -380, -200
    rug(cx, cz, 320, 200, "Carpet_Grey")
    # --- sofa against east wall (x ~ -60), facing -X ---
    sx0, sx1 = -150, -90
    obj("Sofa_Base", "Fabric_Sofa")
    box(sx0, sx1, 0, 38, -320, -90)
    obj("Sofa_Seat", "Fabric_Sofa")
    box(sx0, sx1+4, 38, 50, -320, -90)
    obj("Sofa_Back", "Fabric_Sofa")
    box(sx1-8, sx1, 38, 95, -320, -90)
    obj("Sofa_ArmL", "Fabric_Sofa")
    box(sx0-6, sx1, 38, 70, -320, -306)
    box(sx0-6, sx1, 38, 70, -104, -90)
    # cushions
    for i,pz in enumerate((-280,-205,-130)):
        obj(f"Sofa_Cushion_{i}", "Pillow_White")
        box(sx0-4, sx1-14, 50, 66, pz-28, pz+28)
    # --- coffee table on rug ---
    obj("Coffee_Table", "Furn_WoodDark")
    box(cx-70, cx+70, 34, 40, cz-45, cz+45)
    for lx in (cx-66, cx+58):
        for lz in (cz-40, cz+32):
            box(lx, lx+8, 0, 34, lz, lz+8)
    obj("Coffee_Books", "Book_Blue")
    box(cx-30, cx+10, 40, 48, cz-20, cz+18)
    book_row(cx+18, 40, cz-22, cz+18, 3, height=16)
    # --- tv unit against south wall (z ~ -345) ---
    tvx = -480
    obj("TV_Stand", "Furn_WoodDark")
    box(tvx-130, tvx+130, 0, 44, -342, -300)
    obj("TV_Screen", "Black_Mat")
    box(tvx-110, tvx+110, 52, 150, -344, -338)
    obj("TV_Frame", "Metal_Steel")
    box(tvx-114, tvx+114, 48, 154, -345, -344)
    # decor on tv stand
    vase(tvx+95, 44, -320, r=8, h=30, mat="Vase_Ceramic")
    book_row(tvx-110, 44, -322, -304, 4, height=20)
    # --- bookshelf against west partition (x ~ -740) ---
    bx = -738
    obj("Bookshelf", "Furn_Wood")
    box(bx, bx+40, 0, 185, -300, -150)
    for sy in (40, 80, 120, 160):
        obj(f"Shelf_{sy}", "Furn_WoodLight")
        box(bx, bx+40, sy-3, sy, -300, -150)
        book_row(bx+6, sy, -296, -158, 9, height=30)
    # --- armchair ---
    acx, acz = -640, -250
    obj("Armchair_Base", "Fabric_Red")
    box(acx-28, acx+28, 0, 40, acz-28, acz+28)
    box(acx-28, acx+28, 40, 52, acz-28, acz+28)
    obj("Armchair_Back", "Fabric_Red")
    box(acx-28, acx+28, 40, 92, acz+18, acz+28)
    obj("Armchair_Arms", "Fabric_Red")
    box(acx-34, acx-28, 40, 64, acz-28, acz+28)
    box(acx+28, acx+34, 40, 64, acz-28, acz+28)
    # floor lamp
    obj("Floor_Lamp_Pole", "Metal_Steel")
    cyl(-700, 0, -120, 3, 150, seg=8)
    obj("Floor_Lamp_Shade", "Lamp_Shade")
    cyl(-700, 150, -120, 20, 26, r2=14, seg=12)
    # potted plant in corner
    potted_plant(-90, 0, -130, scale=1.2)
    # pictures on south wall
    picture(-650, 110, wall_z=-346, w=70, h=50, mat="Art_A")
    picture(-560, 110, wall_z=-346, w=50, h=60, mat="Art_B")
    picture(-300, 115, wall_z=-346, w=80, h=55, mat="Art_C")
    # person sitting on sofa
    person(-118, 50, shirt="Cloth_Green", pants="Furn_WoodDark", sitting=True,
           name="Sitter")

# =====================================================================
#  BEDROOM  east-north
# =====================================================================
def build_bedroom():
    # rug
    rug(-300, 110, 260, 200, "Carpet_Warm")
    # --- bed, headboard against east wall (x ~ -60) ---
    hx = -70                      # headboard near east wall
    bx0, bx1 = -300, hx           # length along X
    bz0, bz1 = 30, 180            # width along Z
    obj("Bed_Frame", "Furn_WoodDark")
    box(bx0, bx1, 0, 26, bz0, bz1)
    obj("Bed_Mattress", "White_Mat")
    box(bx0+4, bx1-4, 26, 50, bz0+4, bz1-4)
    obj("Bed_Blanket", "Fabric_Teal")
    box(bx0+2, bx1-50, 48, 58, bz0+2, bz1-2)
    obj("Bed_BlanketFold", "Fabric_Teal")
    box(bx0+2, bx1-50, 50, 56, bz0+2, bz1-2)
    obj("Bed_Headboard", "Furn_Wood")
    box(hx-6, hx+4, 0, 95, bz0-4, bz1+4)
    # pillows
    for pz in (bz0+40, bz1-40):
        obj(f"Pillow_{pz:.0f}", "Pillow_White")
        box(hx-46, hx-12, 50, 66, pz-26, pz+26)
    # --- nightstands ---
    for nz in (bz0-22, bz1+22):
        obj(f"Nightstand_{nz:.0f}", "Furn_Wood")
        box(hx-44, hx-6, 0, 48, nz-18, nz+18)
        obj(f"NS_Drawer_{nz:.0f}", "Furn_WoodLight")
        box(hx-46, hx-44, 8, 40, nz-15, nz+15)
    # lamp on right nightstand
    obj("Bed_Lamp_Base", "Metal_Steel")
    cyl(hx-25, 48, bz1+22, 4, 30, seg=8)
    obj("Bed_Lamp_Shade", "Lamp_Shade")
    cyl(hx-25, 78, bz1+22, 14, 18, r2=10, seg=12)
    # books on left nightstand
    obj("Bed_Books", "Book_Red")
    box(hx-40, hx-14, 48, 56, bz0-28, bz0-12)
    box(hx-40, hx-14, 56, 62, bz0-26, bz0-14)
    # --- wardrobe against north wall (z ~ 225) ---
    obj("Wardrobe", "Furn_WoodLight")
    box(-680, -540, 0, 188, 175, 222)
    obj("Wardrobe_Doors", "Furn_Wood")
    box(-680, -610, 6, 182, 173, 175)
    box(-610, -540, 6, 182, 173, 175)
    obj("Wardrobe_Handles", "Chrome")
    box(-616, -612, 80, 110, 171, 173)
    box(-608, -604, 80, 110, 171, 173)
    # --- dresser + mirror ---
    obj("Dresser", "Furn_WoodDark")
    box(-470, -330, 0, 70, 198, 232)
    obj("Dresser_Mirror", "Glass_Win")
    box(-440, -360, 70, 165, 226, 230)
    obj("Dresser_MirrorFrame", "Furn_Wood")
    box(-446, -354, 66, 169, 230, 233)
    # decor on dresser
    vase(-360, 70, 215, r=7, h=26, mat="Vase_Ceramic")
    potted_plant(-450, 70, 214, scale=0.6)
    # --- desk + chair ---
    obj("Bed_Desk", "Furn_Wood")
    box(-720, -600, 70, 76, 30, 90)
    for lx in (-716, -608):
        box(lx, lx+6, 0, 70, 34, 40)
        box(lx, lx+6, 0, 70, 80, 86)
    chair(-660, 120, face=+1, seat_y=44, mat="Furn_WoodDark", w=40, d=40)
    book_row(-710, 76, 34, 86, 5, height=24)
    obj("Desk_Lamp", "Metal_Steel")
    cyl(-612, 76, 78, 2.5, 34, seg=6)
    # pictures over bed / on wall
    picture(110, 130, wall_x=-30, w=70, h=50, mat="Art_B")  # east wall (x=-23 inner)
    picture(150, 60, wall_z=234, w=60, h=45, mat="Art_C")
    # window curtains hint on east wall not needed
    # person standing by wardrobe
    person(-610, 0, shirt="Cloth_Plum", pants="Furn_WoodDark", skin="Skin_Tan",
           name="Resident")

# =====================================================================
#  EXTERIOR  — front yard: grass, car, people, tree
# =====================================================================
def build_yard():
    # lawn slab (slightly above floor plane to avoid z-fight)
    obj("Lawn", "Grass_Green")
    box(-200, 360, 0.5, 2.0, 320, 860)
    # scattered grass tufts (crossed quads)
    import random
    random.seed(7)
    n = 160
    for k in range(n):
        gx = random.uniform(-190, 350)
        gz = random.uniform(330, 850)
        # keep tufts off the driveway strip
        if 40 < gx < 300 and 360 < gz < 580:
            continue
        h = random.uniform(10, 22)
        w = 5
        m = "Grass_Green" if k % 2 else "Grass_Dark"
        obj(f"Tuft_{k}", m)
        quad((gx-w,1.5,gz),(gx+w,1.5,gz),(gx+w*0.3,h,gz+1),(gx-w*0.7,h,gz-1))
        quad((gx,1.5,gz-w),(gx,1.5,gz+w),(gx+1,h,gz+w*0.3),(gx-1,h,gz-w*0.7))
    # driveway slab
    obj("Driveway", "Carpet_Grey")
    box(40, 300, 0.6, 1.5, 360, 580)
    # ---- CAR (รถ) on driveway, length along X ----
    car_build(cx=170, cz=470)
    # ---- tree ----
    obj("Tree_Trunk", "Plant_Pot")
    cyl(-130, 0, 700, 14, 110, r2=10, seg=10)
    obj("Tree_Canopy", "Plant_Green")
    cyl(-130, 100, 700, 70, 60, r2=55, seg=12)
    cyl(-130, 150, 700, 60, 55, r2=20, seg=12)
    # bushes
    for bx, bz in [(300, 360),(-180, 360),(330, 800),(-150, 820)]:
        obj(f"Bush_{bx}_{bz}", "Grass_Dark")
        cyl(bx, 0, bz, 26, 34, r2=18, seg=10)
    # ---- people in yard ----
    person(60, 0, shirt="Cloth_Blue", pants="Furn_WoodDark", name="Yard1")
    person(-40, 0, shirt="Cloth_Orange", pants="Furn_WoodDark", skin="Skin_Tan",
           name="Yard2")
    person(250, 0, shirt="Cloth_Green", pants="Furn_WoodDark", name="Yard3")

def car_build(cx, cz):
    L, W = 230, 96            # length(X), width(Z)
    x0, x1 = cx-L/2, cx+L/2
    z0, z1 = cz-W/2, cz+W/2
    # lower body
    obj("Car_Body", "Car_Red")
    box(x0+18, x1-18, 28, 64, z0, z1)
    box(x0, x1, 34, 58, z0+6, z1-6)        # main mass with rounded-ish ends
    # cabin
    obj("Car_Cabin", "Car_Red")
    box(cx-58, cx+40, 64, 96, z0+8, z1-8)
    # windows
    obj("Car_Glass", "Car_Glass")
    box(cx-56, cx+38, 68, 92, z0+5, z0+7)   # left side glass
    box(cx-56, cx+38, 68, 92, z1-7, z1-5)   # right side glass
    box(cx-60, cx-56, 68, 92, z0+8, z1-8)   # windshield
    box(cx+38, cx+42, 68, 92, z0+8, z1-8)   # rear glass
    # bumpers / lights
    obj("Car_Bumper", "Metal_Steel")
    box(x0-2, x0+4, 30, 50, z0+6, z1-6)
    box(x1-4, x1+2, 30, 50, z0+6, z1-6)
    obj("Car_Lights", "Lamp_Shade")
    box(x0, x0+4, 44, 54, z0+10, z0+26)
    box(x0, x0+4, 44, 54, z1-26, z1-10)
    obj("Car_TailLights", "Fabric_Red")
    box(x1-4, x1, 44, 54, z0+10, z0+26)
    box(x1-4, x1, 44, 54, z1-26, z1-10)
    # wheels (axis along Z)
    obj("Car_Wheels", "Tire_Black")
    for wx in (cx-70, cx+70):
        cyl(wx, 26, z0-3, 26, 14, axis="z", seg=14)
        cyl(wx, 26, z1-11, 26, 14, axis="z", seg=14)
    obj("Car_Hubcaps", "Metal_Steel")
    for wx in (cx-70, cx+70):
        cyl(wx, 26, z0-4, 10, 2, axis="z", seg=10)
        cyl(wx, 26, z1+2, 10, 2, axis="z", seg=10)

# =====================================================================
build_kitchen()
build_living()
build_bedroom()
build_yard()

# ---- write outputs ----
with open(OBJ_OUT, "a") as f:
    f.write("\n# ===== added detail geometry (furniture, people, yard, car) =====\n")
    f.write("\n".join(OUT))
    f.write("\n")

with open(MTL_OUT, "a") as f:
    f.write(NEW_MATS)

added = V - base_v
print("added verts:", added, " total now:", V)
print("appended obj lines:", len(OUT))
