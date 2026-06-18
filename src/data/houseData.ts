// ─────────────────────────────────────────────────────────────────────────
//  RH-CT.2124  —  Authoritative data
//  Source of truth:
//   • Architectural floor plans  (RH-CT.2124.jpg)
//   • Exterior rendering         (RH-CT.2124(1).jpg)
//   • Royal House "Premium (P)" material specification  (eff. 20 Sep 2023)
//  All room names & dimensions are transcribed directly from the drawings.
// ─────────────────────────────────────────────────────────────────────────

export type Room = {
  name: string
  /** width in metres */
  w: number
  /** length in metres */
  l: number
  /** optional note */
  note?: string
}

export type Floor = {
  id: string
  label: string
  title: string
  /** imported image module path resolved in component */
  rooms: Room[]
}

const area = (r: Room) => +(r.w * r.l).toFixed(2)
export const roomArea = area

export const MODEL = {
  code: 'RH-CT.2124',
  builder: 'Royal House Co., Ltd.',
  standard: 'Premium (P)',
  effective: '20 September 2023',
  plot: { w: 19.0, l: 16.0 }, // metres (from Ground Floor Plan)
}

// ── Floors & rooms (verbatim from the plan) ────────────────────────────────
export const GROUND_ROOMS: Room[] = [
  { name: 'Foyer', w: 3.1, l: 3.525 },
  { name: 'Family Hall', w: 3.225, l: 4.05 },
  { name: 'Dining', w: 3.2, l: 4.0 },
  { name: 'Kitchen', w: 1.6, l: 4.0 },
  { name: 'Pantry', w: 2.625, l: 3.9 },
  { name: 'Bedroom 1', w: 3.2, l: 3.6 },
  { name: 'Hall', w: 2.45, l: 2.65 },
  { name: 'Maid’s Room', w: 2.275, l: 1.925 },
  { name: 'Washing Yard', w: 1.85, l: 5.75 },
  { name: 'W.C. 1', w: 1.825, l: 0.975 },
  { name: 'W.C. 2', w: 2.7, l: 1.45 },
  { name: 'Terrace', w: 3.2, l: 1.5 },
  { name: 'Parking', w: 5.55, l: 5.35, note: '2 cars' },
]

export const SECOND_ROOMS: Room[] = [
  { name: 'Master Bedroom', w: 7.025, l: 3.9 },
  { name: 'Bedroom 2', w: 3.25, l: 5.05 },
  { name: 'Family', w: 3.1, l: 3.55 },
  { name: 'Hall', w: 2.4, l: 2.65 },
  { name: 'W.C. 3', w: 2.8, l: 1.975 },
  { name: 'W.C. 4', w: 2.8, l: 1.825 },
  { name: 'Balcony', w: 2.95, l: 0.975 },
]

export const THIRD_ROOMS: Room[] = [
  { name: 'Bedroom 4', w: 5.2, l: 3.9 },
  { name: 'Bedroom 3', w: 3.2, l: 3.975 },
  { name: 'Buddha / Prayer Room', w: 3.1, l: 3.55 },
  { name: 'Walk-in Closet 1', w: 1.825, l: 1.975 },
  { name: 'Walk-in Closet 2', w: 1.725, l: 1.875 },
  { name: 'Hall', w: 2.45, l: 3.15 },
  { name: 'W.C. 5', w: 2.8, l: 1.975 },
  { name: 'W.C. 6', w: 2.8, l: 1.925 },
  { name: 'Balcony (East)', w: 0.875, l: 8.95 },
  { name: 'Balcony (North)', w: 3.25, l: 0.975 },
  { name: 'Balcony (South)', w: 3.2, l: 1.4 },
  { name: 'Balcony (Rear)', w: 3.2, l: 0.825 },
]

// Sum of enclosed interior spaces (excludes parking, terrace & balconies)
const OUTDOOR = new Set([
  'Parking',
  'Terrace',
  'Balcony',
  'Balcony (East)',
  'Balcony (North)',
  'Balcony (South)',
  'Balcony (Rear)',
])
const sumInterior = (rooms: Room[]) =>
  rooms.filter((r) => !OUTDOOR.has(r.name)).reduce((s, r) => s + area(r), 0)

export const LIVING_AREA = Math.round(
  sumInterior(GROUND_ROOMS) + sumInterior(SECOND_ROOMS) + sumInterior(THIRD_ROOMS),
)

// ── Headline statistics (counted from the plans) ───────────────────────────
export const STATS = [
  { value: '3', label: 'Storeys', sub: 'Ground · Second · Third' },
  { value: '5', label: 'Bedrooms', sub: 'incl. 27.4 m² Master Suite' },
  { value: '6', label: 'Bathrooms', sub: 'American Standard fittings' },
  { value: '2', label: 'Car Parking', sub: 'Covered carport' },
  { value: `${LIVING_AREA}`, label: 'Living Area (m²)', sub: 'Enclosed interior' },
  { value: '19×16', label: 'Plot (m)', sub: '304 m² land parcel' },
]

// ── Interior narrative (grounded in the actual layout) ──────────────────────
export const INTERIOR_SPACES = [
  {
    title: 'Living & Family Hall',
    area: '13.06 m²',
    body: 'A double-volume family hall opens directly off the foyer, framed by full-height green-tinted glazing that draws the garden indoors. The ground floor flows uninterrupted from arrival to gathering.',
  },
  {
    title: 'Dining Area',
    area: '12.80 m²',
    body: 'Positioned between the family hall and the kitchen, the 3.20 × 4.00 m dining room is the social spine of the home — laid over SPC flooring with a seamless line of sight to the rear garden.',
  },
  {
    title: 'Kitchen & Pantry',
    area: '6.40 + 10.24 m²',
    body: 'A dedicated Thai-style working kitchen pairs with a generous Western pantry, separated for ventilation and finished with Granito-tiled wet zones and a DOS grease-trap system.',
  },
  {
    title: 'Master Suite',
    area: '27.40 m²',
    body: 'The entire western wing of the second floor is given to the master bedroom — 7.025 × 3.90 m — with twin walk-through wardrobes, a private balcony, and a spa-grade ensuite plumbed for an American Standard bathtub.',
  },
  {
    title: 'Bathrooms',
    area: '6 in total',
    body: 'Every bathroom is fitted with American Standard sanitary ware, Kohler accessories and 60 × 60 cm Granito tiling carried full-height to the ceiling, with moisture-resistant gypsum soffits.',
  },
  {
    title: 'Staircase',
    area: 'Full-height',
    body: 'A reinforced-concrete staircase rises through all three storeys, topped with redwood treads and a stainless-steel balustrade hand-finished in three coats of gloss B-52 urethane.',
  },
]

// ── Specification accordion (Royal House Premium P) ─────────────────────────
export type SpecGroup = { category: string; items: { k: string; v: string }[] }

export const SPECIFICATIONS: SpecGroup[] = [
  {
    category: 'Structure',
    items: [
      { k: 'Piles', v: 'Prestressed concrete I-piles 0.22 × 0.22 m, 16–21 m (2-section welded)' },
      { k: 'Footings · Columns · Beams', v: 'Reinforced concrete' },
      { k: 'Floor slabs', v: 'Prestressed Solid-Plank with concrete topping on ø4 mm wire mesh @ 20 cm' },
      { k: 'Walls', v: 'Autoclaved Aerated Concrete (AAC) lightweight block, 7.5 cm + skim-coat plaster' },
      { k: 'Structural warranty', v: '20 years' },
    ],
  },
  {
    category: 'Roofing',
    items: [
      { k: 'Roof tile (this model)', v: 'Prestige tile — Horizon colour group' },
      { k: 'Roof structure', v: 'High-strength galvanized steel, rust-inhibited' },
      { k: 'Heat barrier', v: 'Good Foil under-roof reflective sheet' },
      { k: 'Fascia', v: 'Conwood, TOA 4 Seasons paint' },
      { k: 'Valley gutter', v: 'Stainless steel No.28' },
      { k: 'Roof warranty', v: '5 years' },
    ],
  },
  {
    category: 'Doors & Windows',
    items: [
      { k: 'Exterior frames', v: 'Powder-coated aluminium (white)' },
      { k: 'Exterior glazing', v: '5 mm green heat-cut glass' },
      { k: 'Interior frames', v: 'Redwood 2"×4" or synthetic timber, dark-oak finish' },
      { k: 'Bathroom doors', v: 'Louvered teak (B-52 urethane) or ventilated laminate' },
      { k: 'Hardware', v: 'Hafele / VECO lever handles & hinges' },
    ],
  },
  {
    category: 'Flooring',
    items: [
      { k: 'Living areas & bedrooms', v: 'SPC flooring 6 mm or laminate 12 mm + PVC skirting' },
      { k: 'Bathrooms', v: 'Granito tile 60 × 60 cm, full-height' },
      { k: 'Garage · Terrace · Balcony', v: 'Tiled, on Solid-Plank slab' },
      { k: 'Ceilings', v: 'Gypsum board 9 mm, TOA matte; Smart Wood at eaves & carport' },
    ],
  },
  {
    category: 'Electrical',
    items: [
      { k: 'Main / meter', v: 'Single 35 mm² main · 30/100 A 2-wire meter (80 A main)' },
      { k: 'Wiring', v: 'Thai Yazaki in PVC conduit, concealed' },
      { k: 'Switches & sockets', v: 'Panasonic (TIS standard)' },
      { k: 'Distribution board', v: '30 A, 18-way steel enclosure' },
      { k: 'Provisions', v: '5 A/C points · 3 water-heater · 3 TV · 2 LAN · 40 downlights' },
    ],
  },
  {
    category: 'Plumbing',
    items: [
      { k: 'Main supply', v: 'PVC ø 6 hun, class 13.5' },
      { k: 'Supply / drainage', v: 'PVC ø 4 hun (supply) · ø 3" class 5 (waste)' },
      { k: 'Wastewater treatment', v: 'DOS Ultra ULT 800' },
      { k: 'Grease trap', v: 'DOS G-TK-15 (kitchen)' },
    ],
  },
  {
    category: 'Sanitary Ware',
    items: [
      { k: 'Brand', v: 'American Standard, Kohler accessories' },
      { k: 'Master W.C.', v: 'STD TF-2307SC-WT' },
      { k: 'General W.C.', v: 'STD MILANO TF-2327SC-WT' },
      { k: 'Basins', v: 'Ceros counter basin TF-0477 · wall-hung TF-0948' },
      { k: 'Master bathtub', v: 'STD TF-8150-WT with A-0711-200 mixer & shower set' },
    ],
  },
]

// ── Signature materials ─────────────────────────────────────────────────────
export const MATERIALS = [
  { name: 'SPC Flooring', spec: '6 mm rigid-core, with PVC skirting', tag: 'Floors' },
  { name: 'Prestige Roof Tile', spec: 'Horizon colour group, galvanized steel frame', tag: 'Roof' },
  { name: 'American Standard', spec: 'Complete sanitary suite + Kohler', tag: 'Sanitary' },
  { name: 'TOA 4 Seasons 5-in-1', spec: 'Exterior & interior paint system, 3-coat', tag: 'Finish' },
  { name: 'Granito Tile 60×60', spec: 'Full-height bathroom walls & floors', tag: 'Tiling' },
  { name: 'AAC Lightweight Block', spec: '7.5 cm autoclaved, skim-coat plaster', tag: 'Walls' },
  { name: 'Powder-Coated Aluminium', spec: 'Exterior frames, 5 mm tinted glazing', tag: 'Openings' },
  { name: 'Hafele / VECO', spec: 'Architectural door & window hardware', tag: 'Hardware' },
]
