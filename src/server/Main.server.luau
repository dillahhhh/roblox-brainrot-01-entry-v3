-- Pasar Brainrot (Brainrot Anomali Nusantara) — server utama
-- Membangun map pasar malam, menjalankan ekonomi, steal, banjir Pasar Tumpah,
-- dan menyimpan progres pemain di DataStore. Ditulis ulang dari pemahaman
-- atas source FIXED29: perilaku, angka, harga dan timing dipertahankan identik.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

-- DataStore progres pemain; dibungkus pcall supaya game tetap jalan kalau
-- DataStore tidak bisa diakses (misalnya di Studio tanpa izin API).
local PlayerDataStore = nil
pcall(function()
	PlayerDataStore = DataStoreService:GetDataStore("PasarNusantara_V5")
end)

-- Pencahayaan malam yang cerah: cukup terang supaya plaza terbaca, tapi
-- tetap terasa seperti pasar malam (jam 20.30, ambient hangat).
Lighting.Brightness = 2
Lighting.Ambient = Color3.fromRGB(115, 110, 100)
Lighting.OutdoorAmbient = Color3.fromRGB(125, 120, 105)
Lighting.ColorShift_Top = Color3.fromRGB(255, 235, 205)
Lighting.ClockTime = 20.5
Lighting.GlobalShadows = true
Lighting.EnvironmentDiffuseScale = 0.6
Lighting.EnvironmentSpecularScale = 0.3

-- Hapus efek cahaya bawaan yang bikin gambar terlalu kontras.
for _, effect in ipairs(Lighting:GetChildren()) do
	if effect:IsA("BloomEffect") or effect:IsA("SunRaysEffect") then
		effect:Destroy()
	end
end

-- Semua angka tuning game ada di sini, satu tempat.
local CONFIG = {
	MaxBases = 8,
	SlotsPerBase = 6,
	SellMultiplier = 0.5,
	SpawnInterval = 3.5,
	ConveyorSpeed = 16,
	BaseLockDuration = 30,
	RebirthBaseCost = 100000,
}

-- Warna label tiap tier kelangkaan.
local RARITY_COLORS = {
	Common = Color3.fromRGB(220, 220, 220),
	Uncommon = Color3.fromRGB(110, 220, 110),
	Rare = Color3.fromRGB(65, 165, 255),
	Epic = Color3.fromRGB(185, 85, 255),
	Legendary = Color3.fromRGB(255, 140, 40),
	Mythic = Color3.fromRGB(255, 65, 65),
	["Ultra Rare"] = Color3.fromRGB(255, 225, 0),
}

-- Katalog 7 anomali, satu per tier. Price = harga beli, Income = $/detik.
local BRAINROT_CATALOG = {
	{Id = "ayam_ikan", Name = "Ayam Ikan", Rarity = "Common", Price = 50, Income = 5, Color = Color3.fromRGB(210, 170, 110)},
	{Id = "babi_terbang", Name = "Babi Terbang", Rarity = "Uncommon", Price = 150, Income = 15, Color = Color3.fromRGB(255, 180, 200)},
	{Id = "anjing_es_teh", Name = "Anjing Es Teh", Rarity = "Rare", Price = 400, Income = 40, Color = Color3.fromRGB(180, 140, 90)},
	{Id = "kucing_rendang", Name = "Kucing Rendang", Rarity = "Epic", Price = 1000, Income = 100, Color = Color3.fromRGB(255, 170, 60)},
	{Id = "beruang_durian", Name = "Beruang Durian", Rarity = "Legendary", Price = 3000, Income = 300, Color = Color3.fromRGB(140, 95, 60)},
	{Id = "harimau_api", Name = "Harimau Api", Rarity = "Mythic", Price = 12000, Income = 1200, Color = Color3.fromRGB(255, 140, 40)},
	{Id = "gajah_gamelan", Name = "Gajah Gamelan", Rarity = "Ultra Rare", Price = 50000, Income = 10000, Color = Color3.fromRGB(255, 200, 60)},
}

-- Indeks katalog berdasarkan Id, supaya pencarian per Id cepat.
local CatalogById = {}
for _, item in ipairs(BRAINROT_CATALOG) do
	CatalogById[item.Id] = item
end

-- RemoteEvent server <-> client.
local Remotes = Instance.new("Folder")
Remotes.Name = "GameRemotes"
Remotes.Parent = ReplicatedStorage

local UpdateStateEvent = Instance.new("RemoteEvent")
UpdateStateEvent.Name = "UpdateState"
UpdateStateEvent.Parent = Remotes

local ActionEvent = Instance.new("RemoteEvent")
ActionEvent.Name = "PlayerAction"
ActionEvent.Parent = Remotes

local FloodEvent = Instance.new("RemoteEvent")
FloodEvent.Name = "FloodEvent"
FloodEvent.Parent = Remotes

local DebugFloodEvent = Instance.new("RemoteEvent")
DebugFloodEvent.Name = "DebugFlood"
DebugFloodEvent.Parent = Remotes

-- Hapus baseplate / spawn bawaan supaya map dibangun dari nol oleh script.
for _, obj in ipairs(workspace:GetChildren()) do
	if obj.Name == "Baseplate" or obj.Name == "SpawnLocation" or obj.Name == "GeneratedMap" then
		obj:Destroy()
	end
end

local MapFolder = Instance.new("Folder")
MapFolder.Name = "GeneratedMap"
MapFolder.Parent = workspace

-- Pembantu bikin Part yang sudah di-anchor; properti lain dilempar lewat tabel.
local function createPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = props.Parent or MapFolder
	return p
end

-- Tanah + jalan batu + sabuk conveyor di tengah map.
createPart({Name = "MainTerrain", Size = Vector3.new(340, 2, 420), Position = Vector3.new(0, -1, 0), Color = Color3.fromRGB(145, 135, 120), Material = Enum.Material.Cobblestone})
createPart({Name = "MainRoadStone", Size = Vector3.new(46, 0.4, 340), Position = Vector3.new(0, 0.2, 0), Color = Color3.fromRGB(145, 135, 120), Material = Enum.Material.Cobblestone})
createPart({Name = "ConveyorBelt", Size = Vector3.new(30, 0.5, 320), Position = Vector3.new(0, 0.3, 0), Color = Color3.fromRGB(165, 135, 95), Material = Enum.Material.WoodPlanks})
-- Pembatas dua jalur conveyor di tengah belt.
createPart({Name = "ConveyorDivider", Size = Vector3.new(1, 0.2, 320), Position = Vector3.new(0, 0.6, 0), Color = Color3.fromRGB(95, 65, 40), Material = Enum.Material.SmoothPlastic})

-- Pohon di tepi map supaya ujung map tidak langsung langit kosong.
local function plantTree(x, z)
	local trunkH = 5
	local leafSize = 6 + math.random() * 2
	createPart({Name = "PohonBatang", Size = Vector3.new(1.5, trunkH, 1.5), Position = Vector3.new(x, trunkH / 2, z), Color = Color3.fromRGB(120, 80, 45), Material = Enum.Material.Wood})
	createPart({Name = "PohonDaun", Shape = Enum.PartType.Ball, Size = Vector3.new(leafSize, leafSize, leafSize), Position = Vector3.new(x, trunkH + leafSize / 2 - 1, z), Color = Color3.fromRGB(60 + math.random(0, 30), 140, 70), Material = Enum.Material.SmoothPlastic})
end
for z = -180, 180, 30 do
	plantTree(-155, z)
	plantTree(155, z)
end
for x = -150, 150, 30 do
	plantTree(x, -195)
	plantTree(x, 195)
end

-- Tembok kota di tepi map: skyline gedung supaya ujung map terasa perkotaan.
local function plantCityBuilding(isXSide, fixedCoord, alongCoord)
	local w = 12 + math.random(0, 4)
	local h = 12 + math.random(0, 23)
	local shade = 35 + math.random(0, 25)
	local col = Color3.fromRGB(shade, shade + 10, shade + 30)
	if isXSide then
		createPart({Name = "KotaGedung", Size = Vector3.new(6, h, w), Position = Vector3.new(fixedCoord, h / 2, alongCoord), Color = col, Material = Enum.Material.SmoothPlastic})
	else
		createPart({Name = "KotaGedung", Size = Vector3.new(w, h, 6), Position = Vector3.new(alongCoord, h / 2, fixedCoord), Color = col, Material = Enum.Material.SmoothPlastic})
	end
end
for z = -190, 190, 20 do
	plantCityBuilding(true, -162, z)
	plantCityBuilding(true, 162, z)
end
for x = -150, 150, 20 do
	plantCityBuilding(false, -202, x)
	plantCityBuilding(false, 202, x)
end

-- Lampu malam: tiang + bola neon + PointLight hangat, biar malam tetap cerah.
local function plantLamp(x, z)
	createPart({Name = "LampuTiang", Size = Vector3.new(0.6, 7, 0.6), Position = Vector3.new(x, 3.5, z), Color = Color3.fromRGB(60, 55, 50), Material = Enum.Material.SmoothPlastic})
	local lamp = createPart({Name = "LampuKepala", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), Position = Vector3.new(x, 7.3, z), Color = Color3.fromRGB(255, 220, 130), Material = Enum.Material.Neon})
	local light = Instance.new("PointLight", lamp)
	light.Color = Color3.fromRGB(255, 215, 140)
	light.Range = 22
	light.Brightness = 1.2
end
for z = -160, 160, 80 do
	plantLamp(-20, z)
	plantLamp(20, z)
end
for _, lx in ipairs({-45, -15, 15, 45}) do
	plantLamp(lx, 150)
end

-- Area pasar di selatan map.
local PasarArea = Instance.new("Folder")
PasarArea.Name = "PasarNusantara"
PasarArea.Parent = MapFolder

createPart({Name = "PlazaPasar", Size = Vector3.new(110, 0.6, 55), Position = Vector3.new(0, 0.3, 155), Color = Color3.fromRGB(185, 165, 135), Material = Enum.Material.Sandstone, Parent = PasarArea})

-- Gapura pasar (selatan): dua menara candi meru + atap meru tiga tingkat + emblem emas.
local pasarStone = Color3.fromRGB(130, 115, 95)
local pasarStone2 = Color3.fromRGB(140, 125, 105)
local pasarRoof = Color3.fromRGB(95, 65, 40)
local pasarGold = Color3.fromRGB(255, 200, 60)
for _, sx in ipairs({-21, 21}) do
	local side = sx < 0 and "Kiri" or "Kanan"
	createPart({Name = "GapuraPasarMenaraDasar" .. side, Size = Vector3.new(12, 5, 12), Position = Vector3.new(sx, 2.5, 140), Color = pasarStone, Material = Enum.Material.Brick, Parent = PasarArea})
	createPart({Name = "GapuraPasarMenaraTengah1" .. side, Size = Vector3.new(10, 5, 10), Position = Vector3.new(sx, 7.5, 140), Color = pasarStone2, Material = Enum.Material.Brick, Parent = PasarArea})
	createPart({Name = "GapuraPasarMenaraAtap1" .. side, Size = Vector3.new(12, 1.5, 12), Position = Vector3.new(sx, 10.75, 140), Color = pasarRoof, Material = Enum.Material.Slate, Parent = PasarArea})
	createPart({Name = "GapuraPasarMenaraTengah2" .. side, Size = Vector3.new(8, 4, 8), Position = Vector3.new(sx, 13.5, 140), Color = pasarStone2, Material = Enum.Material.Brick, Parent = PasarArea})
	createPart({Name = "GapuraPasarMenaraAtap2" .. side, Size = Vector3.new(10, 1.5, 10), Position = Vector3.new(sx, 16.25, 140), Color = pasarRoof, Material = Enum.Material.Slate, Parent = PasarArea})
	createPart({Name = "GapuraPasarMenaraPuncak" .. side, Size = Vector3.new(6, 3, 6), Position = Vector3.new(sx, 18.5, 140), Color = pasarStone2, Material = Enum.Material.Brick, Parent = PasarArea})
	createPart({Name = "GapuraPasarMenaraAtap3" .. side, Size = Vector3.new(8, 1.5, 8), Position = Vector3.new(sx, 20.75, 140), Color = pasarRoof, Material = Enum.Material.Slate, Parent = PasarArea})
	createPart({Name = "GapuraPasarMenaraEmas" .. side, Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), Position = Vector3.new(sx, 22.3, 140), Color = pasarGold, Material = Enum.Material.SmoothPlastic, Parent = PasarArea})
end
createPart({Name = "GapuraPasarAtap1", Size = Vector3.new(58, 1.5, 14), Position = Vector3.new(0, 24, 140), Color = pasarRoof, Material = Enum.Material.Slate, Parent = PasarArea})
createPart({Name = "GapuraPasarAtap2", Size = Vector3.new(48, 1.5, 12), Position = Vector3.new(0, 25.5, 140), Color = pasarRoof, Material = Enum.Material.Slate, Parent = PasarArea})
createPart({Name = "GapuraPasarAtap3", Size = Vector3.new(38, 1.5, 10), Position = Vector3.new(0, 27, 140), Color = pasarRoof, Material = Enum.Material.Slate, Parent = PasarArea})
createPart({Name = "GapuraPasarPuncak", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), Position = Vector3.new(0, 28.7, 140), Color = pasarGold, Material = Enum.Material.SmoothPlastic, Parent = PasarArea})
createPart({Name = "GapuraPasarEmblem", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 6, 6), CFrame = CFrame.new(0, 26, 147.5) * CFrame.Angles(0, math.rad(90), 0), Color = pasarGold, Material = Enum.Material.SmoothPlastic, Parent = PasarArea})
createPart({Name = "GapuraPasarPortal", Size = Vector3.new(30, 22, 0.5), Position = Vector3.new(0, 11, 140), Color = pasarGold, Material = Enum.Material.ForceField, Transparency = 0.55, CanCollide = false, Parent = PasarArea})

-- Titik spawn pemain di plaza selatan.
local SpawnLoc = Instance.new("SpawnLocation", PasarArea)
SpawnLoc.Size = Vector3.new(16, 1, 16)
SpawnLoc.Position = Vector3.new(0, 0.8, 168)
SpawnLoc.Anchored = true
SpawnLoc.Color = Color3.fromRGB(65, 175, 255)
SpawnLoc.Material = Enum.Material.Neon
SpawnLoc.Transparency = 0.3

-- Gerbang Nusantara (utara): sama seperti gapura pasar, di ujung utara map.
local gateStone = Color3.fromRGB(130, 115, 95)
local gateStone2 = Color3.fromRGB(140, 125, 105)
local gateRoof = Color3.fromRGB(95, 65, 40)
local gateGold = Color3.fromRGB(255, 200, 60)
for _, sx in ipairs({-21, 21}) do
	local side = sx < 0 and "Kiri" or "Kanan"
	createPart({Name = "GerbangMenaraDasar" .. side, Size = Vector3.new(12, 5, 12), Position = Vector3.new(sx, 2.5, -165), Color = gateStone, Material = Enum.Material.Brick})
	createPart({Name = "GerbangMenaraTengah1" .. side, Size = Vector3.new(10, 5, 10), Position = Vector3.new(sx, 7.5, -165), Color = gateStone2, Material = Enum.Material.Brick})
	createPart({Name = "GerbangMenaraAtap1" .. side, Size = Vector3.new(12, 1.5, 12), Position = Vector3.new(sx, 10.75, -165), Color = gateRoof, Material = Enum.Material.Slate})
	createPart({Name = "GerbangMenaraTengah2" .. side, Size = Vector3.new(8, 4, 8), Position = Vector3.new(sx, 13.5, -165), Color = gateStone2, Material = Enum.Material.Brick})
	createPart({Name = "GerbangMenaraAtap2" .. side, Size = Vector3.new(10, 1.5, 10), Position = Vector3.new(sx, 16.25, -165), Color = gateRoof, Material = Enum.Material.Slate})
	createPart({Name = "GerbangMenaraPuncak" .. side, Size = Vector3.new(6, 3, 6), Position = Vector3.new(sx, 18.5, -165), Color = gateStone2, Material = Enum.Material.Brick})
	createPart({Name = "GerbangMenaraAtap3" .. side, Size = Vector3.new(8, 1.5, 8), Position = Vector3.new(sx, 20.75, -165), Color = gateRoof, Material = Enum.Material.Slate})
	createPart({Name = "GerbangMenaraEmas" .. side, Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), Position = Vector3.new(sx, 22.3, -165), Color = gateGold, Material = Enum.Material.SmoothPlastic})
end
createPart({Name = "GerbangAtap1", Size = Vector3.new(58, 1.5, 14), Position = Vector3.new(0, 24, -165), Color = gateRoof, Material = Enum.Material.Slate})
createPart({Name = "GerbangAtap2", Size = Vector3.new(48, 1.5, 12), Position = Vector3.new(0, 25.5, -165), Color = gateRoof, Material = Enum.Material.Slate})
createPart({Name = "GerbangAtap3", Size = Vector3.new(38, 1.5, 10), Position = Vector3.new(0, 27, -165), Color = gateRoof, Material = Enum.Material.Slate})
createPart({Name = "GerbangPuncak", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), Position = Vector3.new(0, 28.7, -165), Color = gateGold, Material = Enum.Material.SmoothPlastic})
createPart({Name = "GerbangEmblem", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 6, 6), CFrame = CFrame.new(0, 26, -157.5) * CFrame.Angles(0, math.rad(90), 0), Color = gateGold, Material = Enum.Material.SmoothPlastic})
createPart({Name = "GerbangPortal", Size = Vector3.new(30, 22, 0.5), Position = Vector3.new(0, 11, -165), Color = gateGold, Material = Enum.Material.ForceField, Transparency = 0.55, CanCollide = false})

local PlayerStates = {}

-- Menempelkan satu part visual ke badan model brainrot (di-weld supaya ikut gerak).
local function addVisualPart(model, body, shape, size, color, offset, material, transparency)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.CanCollide = false
	p.Massless = true
	p.Anchored = false
	p.CFrame = body.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = body
	w.Part1 = p
	w.C0 = body.CFrame:Inverse() * p.CFrame
	w.C1 = CFrame.new()
	w.Parent = body
	p.Parent = model
	return p
end

-- Membangun model 3D seekor brainrot dari part-part sederhana.
-- scale 2.0 dipakai di pedestal/conveyor, 1.4 saat dibawa, 1.6 di atas peti.
local function createBrainrotVisualModel(itemInfo, scale)
	scale = scale or 1
	local s = scale
	local model = Instance.new("Model")
	model.Name = "BrainrotVisual"
	local body = Instance.new("Part", model)
	body.Name = "PrimaryBody"
	body.CanCollide = false
	body.Massless = true
	body.Anchored = false
	local function V(x, y, z) return Vector3.new(x * s, y * s, z * s) end
	local function CF(x, y, z) return CFrame.new(x * s, y * s, z * s) end
	local function add(shape, size, color, offset, material, transparency)
		return addVisualPart(model, body, shape, size, color, offset, material, transparency)
	end
	local id = itemInfo.Id
	if id == "ayam_ikan" then
		-- Common: Ayam Kampung berkepala IKAN (badan ayam + kepala ikan + sirip).
		body.Size = Vector3.new(1.6 * s, 1.0 * s, 1.0 * s)
		body.Color = Color3.fromRGB(210, 170, 110)
		add(Enum.PartType.Block, V(0.7, 0.7, 0.7), Color3.fromRGB(100, 160, 200), CF(0.95, 0.55, 0))
		add(Enum.PartType.Block, V(0.5, 0.7, 0.15), Color3.fromRGB(100, 160, 200), CF(-0.9, 0.5, 0) * CFrame.Angles(0, 0, math.rad(25)))
		add(Enum.PartType.Block, V(0.5, 0.5, 0.1), Color3.fromRGB(80, 140, 190), CF(0.2, 0.8, 0))
		add(Enum.PartType.Block, V(0.3, 0.15, 0.2), Color3.fromRGB(40, 40, 40), CF(1.3, 0.45, 0))
		add(Enum.PartType.Block, V(0.9, 0.6, 0.15), Color3.fromRGB(190, 150, 95), CF(-0.1, 0.1, 0.55))
		add(Enum.PartType.Block, V(0.9, 0.6, 0.15), Color3.fromRGB(190, 150, 95), CF(-0.1, 0.1, -0.55))
		add(Enum.PartType.Block, V(0.15, 0.7, 0.15), Color3.fromRGB(255, 160, 40), CF(0.4, -0.8, 0.3))
		add(Enum.PartType.Block, V(0.15, 0.7, 0.15), Color3.fromRGB(255, 160, 40), CF(0.4, -0.8, -0.3))
		add(Enum.PartType.Ball, V(0.16, 0.16, 0.16), Color3.fromRGB(20, 20, 20), CF(1.2, 0.65, 0.25))
		add(Enum.PartType.Ball, V(0.16, 0.16, 0.16), Color3.fromRGB(20, 20, 20), CF(1.2, 0.65, -0.25))
	elseif id == "babi_terbang" then
		-- Uncommon: Babi BERSAYAP (badan babi + sayap putih besar).
		body.Shape = Enum.PartType.Cylinder
		body.Size = Vector3.new(1.9 * s, 1.2 * s, 1.2 * s)
		body.Color = Color3.fromRGB(255, 180, 200)
		add(Enum.PartType.Block, V(0.9, 0.9, 0.9), Color3.fromRGB(255, 180, 200), CF(1.25, 0.35, 0))
		add(Enum.PartType.Cylinder, V(0.35, 0.55, 0.55), Color3.fromRGB(240, 150, 175), CF(1.75, 0.35, 0))
		add(Enum.PartType.Block, V(0.3, 0.5, 0.4), Color3.fromRGB(255, 180, 200), CF(1.2, 1.0, 0.35) * CFrame.Angles(0, 0, math.rad(-15)))
		add(Enum.PartType.Block, V(0.3, 0.5, 0.4), Color3.fromRGB(255, 180, 200), CF(1.2, 1.0, -0.35) * CFrame.Angles(0, 0, math.rad(15)))
		add(Enum.PartType.Block, V(1.2, 0.7, 0.15), Color3.fromRGB(245, 245, 245), CF(-0.2, 0.6, 0.7) * CFrame.Angles(math.rad(20), 0, math.rad(15)))
		add(Enum.PartType.Block, V(1.2, 0.7, 0.15), Color3.fromRGB(245, 245, 245), CF(-0.2, 0.6, -0.7) * CFrame.Angles(math.rad(-20), 0, math.rad(-15)))
		add(Enum.PartType.Block, V(0.3, 0.7, 0.3), Color3.fromRGB(255, 180, 200), CF(0.6, -0.85, 0.35))
		add(Enum.PartType.Block, V(0.3, 0.7, 0.3), Color3.fromRGB(255, 180, 200), CF(0.6, -0.85, -0.35))
		add(Enum.PartType.Block, V(0.3, 0.7, 0.3), Color3.fromRGB(255, 180, 200), CF(-0.6, -0.85, 0.35))
		add(Enum.PartType.Block, V(0.3, 0.7, 0.3), Color3.fromRGB(255, 180, 200), CF(-0.6, -0.85, -0.35))
		add(Enum.PartType.Cylinder, V(0.5, 0.15, 0.15), Color3.fromRGB(255, 180, 200), CF(-1.1, 0.2, 0) * CFrame.Angles(0, 0, math.rad(40)))
		add(Enum.PartType.Ball, V(0.16, 0.16, 0.16), Color3.fromRGB(20, 20, 20), CF(1.7, 0.5, 0.25))
		add(Enum.PartType.Ball, V(0.16, 0.16, 0.16), Color3.fromRGB(20, 20, 20), CF(1.7, 0.5, -0.25))
	elseif id == "anjing_es_teh" then
		-- Rare: Anjing bawa GELAS ES TEH di punggung (gelas + teh + sedotan + es batu).
		body.Size = Vector3.new(1.7 * s, 0.9 * s, 0.9 * s)
		body.Color = Color3.fromRGB(180, 140, 90)
		add(Enum.PartType.Block, V(0.85, 0.8, 0.8), Color3.fromRGB(180, 140, 90), CF(1.1, 0.4, 0))
		add(Enum.PartType.Block, V(0.5, 0.4, 0.5), Color3.fromRGB(200, 165, 110), CF(1.7, 0.25, 0))
		add(Enum.PartType.Ball, V(0.22, 0.22, 0.22), Color3.fromRGB(30, 30, 30), CF(1.95, 0.35, 0))
		add(Enum.PartType.Block, V(0.25, 0.6, 0.4), Color3.fromRGB(160, 120, 75), CF(1.0, 0.95, 0.35) * CFrame.Angles(0, 0, math.rad(-20)))
		add(Enum.PartType.Block, V(0.25, 0.6, 0.4), Color3.fromRGB(160, 120, 75), CF(1.0, 0.95, -0.35) * CFrame.Angles(0, 0, math.rad(20)))
		add(Enum.PartType.Cylinder, V(0.7, 0.5, 0.5), Color3.fromRGB(180, 220, 240), CF(0, 0.8, 0), Enum.Material.Glass, 0.3)
		add(Enum.PartType.Cylinder, V(0.5, 0.4, 0.4), Color3.fromRGB(160, 110, 60), CF(0, 0.75, 0))
		add(Enum.PartType.Cylinder, V(0.9, 0.08, 0.08), Color3.fromRGB(220, 60, 60), CF(0.1, 1.2, 0) * CFrame.Angles(0, 0, math.rad(20)))
		add(Enum.PartType.Block, V(0.2, 0.2, 0.2), Color3.fromRGB(240, 250, 255), CF(-0.1, 1.0, 0.15))
		add(Enum.PartType.Block, V(0.2, 0.2, 0.2), Color3.fromRGB(240, 250, 255), CF(0.1, 1.0, -0.15))
		add(Enum.PartType.Block, V(0.28, 0.75, 0.28), Color3.fromRGB(180, 140, 90), CF(0.6, -0.8, 0.3))
		add(Enum.PartType.Block, V(0.28, 0.75, 0.28), Color3.fromRGB(180, 140, 90), CF(0.6, -0.8, -0.3))
		add(Enum.PartType.Block, V(0.28, 0.75, 0.28), Color3.fromRGB(180, 140, 90), CF(-0.6, -0.8, 0.3))
		add(Enum.PartType.Block, V(0.28, 0.75, 0.28), Color3.fromRGB(180, 140, 90), CF(-0.6, -0.8, -0.3))
		add(Enum.PartType.Block, V(0.7, 0.2, 0.2), Color3.fromRGB(180, 140, 90), CF(-1.05, 0.45, 0) * CFrame.Angles(0, 0, math.rad(30)))
		add(Enum.PartType.Ball, V(0.15, 0.15, 0.15), Color3.fromRGB(20, 20, 20), CF(1.5, 0.55, 0.25))
		add(Enum.PartType.Ball, V(0.15, 0.15, 0.15), Color3.fromRGB(20, 20, 20), CF(1.5, 0.55, -0.25))
	elseif id == "kucing_rendang" then
		-- Epic: Kucing bawa MANGKOK RENDANG di kepala (mangkok + rendang + cabai).
		body.Size = Vector3.new(1.5 * s, 0.85 * s, 0.85 * s)
		body.Color = Color3.fromRGB(255, 170, 60)
		add(Enum.PartType.Ball, V(0.75, 0.75, 0.75), Color3.fromRGB(255, 170, 60), CF(1.0, 0.45, 0))
		add(Enum.PartType.Block, V(0.3, 0.45, 0.15), Color3.fromRGB(255, 170, 60), CF(0.9, 1.0, 0.3) * CFrame.Angles(0, 0, math.rad(-15)))
		add(Enum.PartType.Block, V(0.3, 0.45, 0.15), Color3.fromRGB(255, 170, 60), CF(0.9, 1.0, -0.3) * CFrame.Angles(0, 0, math.rad(15)))
		add(Enum.PartType.Cylinder, V(0.4, 0.6, 0.6), Color3.fromRGB(245, 245, 240), CF(1.0, 1.0, 0))
		add(Enum.PartType.Ball, V(0.5, 0.4, 0.5), Color3.fromRGB(120, 70, 30), CF(1.0, 1.2, 0))
		add(Enum.PartType.Block, V(0.15, 0.3, 0.15), Color3.fromRGB(220, 40, 40), CF(1.0, 1.4, 0.2))
		add(Enum.PartType.Ball, V(0.16, 0.16, 0.16), Color3.fromRGB(80, 200, 100), CF(1.35, 0.5, 0.22))
		add(Enum.PartType.Ball, V(0.16, 0.16, 0.16), Color3.fromRGB(80, 200, 100), CF(1.35, 0.5, -0.22))
		add(Enum.PartType.Ball, V(0.12, 0.12, 0.12), Color3.fromRGB(255, 150, 170), CF(1.4, 0.35, 0))
		add(Enum.PartType.Block, V(0.25, 0.7, 0.25), Color3.fromRGB(255, 170, 60), CF(0.55, -0.75, 0.28))
		add(Enum.PartType.Block, V(0.25, 0.7, 0.25), Color3.fromRGB(255, 170, 60), CF(0.55, -0.75, -0.28))
		add(Enum.PartType.Block, V(0.25, 0.7, 0.25), Color3.fromRGB(255, 170, 60), CF(-0.55, -0.75, 0.28))
		add(Enum.PartType.Block, V(0.25, 0.7, 0.25), Color3.fromRGB(255, 170, 60), CF(-0.55, -0.75, -0.28))
		add(Enum.PartType.Cylinder, V(1.1, 0.18, 0.18), Color3.fromRGB(255, 170, 60), CF(-0.95, 0.5, 0) * CFrame.Angles(0, 0, math.rad(35)))
	elseif id == "beruang_durian" then
		-- Legendary: Beruang bawa DURIAN di punggung (durian + duri).
		body.Size = Vector3.new(1.9 * s, 1.2 * s, 1.1 * s)
		body.Color = Color3.fromRGB(140, 95, 60)
		add(Enum.PartType.Ball, V(0.9, 0.9, 0.9), Color3.fromRGB(140, 95, 60), CF(1.2, 0.5, 0))
		add(Enum.PartType.Block, V(0.5, 0.4, 0.5), Color3.fromRGB(170, 120, 75), CF(1.7, 0.35, 0))
		add(Enum.PartType.Ball, V(0.2, 0.2, 0.2), Color3.fromRGB(30, 30, 30), CF(1.95, 0.45, 0))
		add(Enum.PartType.Ball, V(0.3, 0.3, 0.3), Color3.fromRGB(140, 95, 60), CF(1.1, 1.05, 0.35))
		add(Enum.PartType.Ball, V(0.3, 0.3, 0.3), Color3.fromRGB(140, 95, 60), CF(1.1, 1.05, -0.35))
		add(Enum.PartType.Ball, V(0.8, 0.8, 0.8), Color3.fromRGB(180, 200, 80), CF(-0.2, 0.9, 0))
		add(Enum.PartType.Block, V(0.15, 0.35, 0.15), Color3.fromRGB(200, 220, 100), CF(-0.2, 1.4, 0))
		add(Enum.PartType.Block, V(0.15, 0.35, 0.15), Color3.fromRGB(200, 220, 100), CF(-0.6, 1.1, 0.3))
		add(Enum.PartType.Block, V(0.15, 0.35, 0.15), Color3.fromRGB(200, 220, 100), CF(-0.6, 1.1, -0.3))
		add(Enum.PartType.Block, V(0.15, 0.35, 0.15), Color3.fromRGB(200, 220, 100), CF(0.2, 1.1, 0.3))
		add(Enum.PartType.Block, V(0.15, 0.35, 0.15), Color3.fromRGB(200, 220, 100), CF(0.2, 1.1, -0.3))
		add(Enum.PartType.Block, V(0.35, 0.8, 0.35), Color3.fromRGB(140, 95, 60), CF(0.7, -0.9, 0.35))
		add(Enum.PartType.Block, V(0.35, 0.8, 0.35), Color3.fromRGB(140, 95, 60), CF(0.7, -0.9, -0.35))
		add(Enum.PartType.Block, V(0.35, 0.8, 0.35), Color3.fromRGB(140, 95, 60), CF(-0.7, -0.9, 0.35))
		add(Enum.PartType.Block, V(0.35, 0.8, 0.35), Color3.fromRGB(140, 95, 60), CF(-0.7, -0.9, -0.35))
		add(Enum.PartType.Ball, V(0.16, 0.16, 0.16), Color3.fromRGB(20, 20, 20), CF(1.6, 0.65, 0.25))
		add(Enum.PartType.Ball, V(0.16, 0.16, 0.16), Color3.fromRGB(20, 20, 20), CF(1.6, 0.65, -0.25))
	elseif id == "harimau_api" then
		-- Mythic: Harimau API (belang + surai api Neon oren/merah/kuning).
		body.Size = Vector3.new(1.8 * s, 1.0 * s, 0.95 * s)
		body.Color = Color3.fromRGB(255, 140, 40)
		add(Enum.PartType.Block, V(0.15, 1.0, 1.0), Color3.fromRGB(20, 20, 20), CF(-0.5, 0, 0))
		add(Enum.PartType.Block, V(0.15, 1.0, 1.0), Color3.fromRGB(20, 20, 20), CF(0, 0, 0))
		add(Enum.PartType.Block, V(0.15, 1.0, 1.0), Color3.fromRGB(20, 20, 20), CF(0.5, 0, 0))
		add(Enum.PartType.Ball, V(0.85, 0.85, 0.85), Color3.fromRGB(255, 140, 40), CF(1.15, 0.45, 0))
		add(Enum.PartType.Block, V(0.3, 0.45, 0.15), Color3.fromRGB(255, 140, 40), CF(1.05, 1.0, 0.3) * CFrame.Angles(0, 0, math.rad(-15)))
		add(Enum.PartType.Block, V(0.3, 0.45, 0.15), Color3.fromRGB(255, 140, 40), CF(1.05, 1.0, -0.3) * CFrame.Angles(0, 0, math.rad(15)))
		add(Enum.PartType.Block, V(0.5, 0.8, 0.5), Color3.fromRGB(255, 120, 20), CF(0.8, 1.1, 0), Enum.Material.Neon)
		add(Enum.PartType.Block, V(0.4, 0.6, 0.4), Color3.fromRGB(255, 60, 20), CF(0.4, 1.0, 0.3), Enum.Material.Neon)
		add(Enum.PartType.Block, V(0.4, 0.6, 0.4), Color3.fromRGB(255, 60, 20), CF(0.4, 1.0, -0.3), Enum.Material.Neon)
		add(Enum.PartType.Block, V(0.4, 0.7, 0.4), Color3.fromRGB(255, 200, 40), CF(1.2, 1.0, 0), Enum.Material.Neon)
		add(Enum.PartType.Block, V(0.45, 0.35, 0.45), Color3.fromRGB(255, 180, 90), CF(1.65, 0.3, 0))
		add(Enum.PartType.Ball, V(0.18, 0.18, 0.18), Color3.fromRGB(30, 30, 30), CF(1.9, 0.4, 0))
		add(Enum.PartType.Ball, V(0.16, 0.16, 0.16), Color3.fromRGB(80, 200, 100), CF(1.5, 0.6, 0.25))
		add(Enum.PartType.Ball, V(0.16, 0.16, 0.16), Color3.fromRGB(80, 200, 100), CF(1.5, 0.6, -0.25))
		add(Enum.PartType.Block, V(0.3, 0.75, 0.3), Color3.fromRGB(255, 140, 40), CF(0.65, -0.85, 0.32))
		add(Enum.PartType.Block, V(0.3, 0.75, 0.3), Color3.fromRGB(255, 140, 40), CF(0.65, -0.85, -0.32))
		add(Enum.PartType.Block, V(0.3, 0.75, 0.3), Color3.fromRGB(255, 140, 40), CF(-0.65, -0.85, 0.32))
		add(Enum.PartType.Block, V(0.3, 0.75, 0.3), Color3.fromRGB(255, 140, 40), CF(-0.65, -0.85, -0.32))
		add(Enum.PartType.Cylinder, V(1.0, 0.18, 0.18), Color3.fromRGB(255, 140, 40), CF(-1.05, 0.4, 0) * CFrame.Angles(0, 0, math.rad(35)))
	elseif id == "gajah_gamelan" then
		-- Ultra Rare: Gajah EMAS bawa GONG GAMELAN emas di punggung + perhiasan emas.
		body.Size = Vector3.new(2.4 * s, 1.7 * s, 1.5 * s)
		body.Color = Color3.fromRGB(255, 200, 60)
		body.Material = Enum.Material.Metal
		add(Enum.PartType.Ball, V(1.3, 1.3, 1.3), Color3.fromRGB(255, 200, 60), CF(1.5, 0.6, 0), Enum.Material.Metal)
		add(Enum.PartType.Cylinder, V(1.4, 0.35, 0.35), Color3.fromRGB(255, 200, 60), CF(2.1, -0.3, 0) * CFrame.Angles(0, 0, math.rad(55)), Enum.Material.Metal)
		add(Enum.PartType.Ball, V(0.35, 0.35, 0.35), Color3.fromRGB(255, 200, 60), CF(2.35, -0.85, 0), Enum.Material.Metal)
		add(Enum.PartType.Block, V(0.2, 1.3, 1.0), Color3.fromRGB(255, 200, 60), CF(1.2, 0.7, 0.65), Enum.Material.Metal)
		add(Enum.PartType.Block, V(0.2, 1.3, 1.0), Color3.fromRGB(255, 200, 60), CF(1.2, 0.7, -0.65), Enum.Material.Metal)
		add(Enum.PartType.Cylinder, V(0.8, 0.18, 0.18), Color3.fromRGB(245, 245, 240), CF(2.0, 0.1, 0.4) * CFrame.Angles(0, math.rad(90), 0))
		add(Enum.PartType.Cylinder, V(0.8, 0.18, 0.18), Color3.fromRGB(245, 245, 240), CF(2.0, 0.1, -0.4) * CFrame.Angles(0, math.rad(90), 0))
		add(Enum.PartType.Cylinder, V(0.2, 1.2, 1.2), Color3.fromRGB(255, 200, 60), CF(-0.2, 1.3, 0), Enum.Material.Metal)
		add(Enum.PartType.Block, V(0.25, 0.6, 0.25), Color3.fromRGB(255, 200, 60), CF(-0.2, 0.8, 0.5), Enum.Material.Metal)
		add(Enum.PartType.Block, V(0.25, 0.6, 0.25), Color3.fromRGB(255, 200, 60), CF(-0.2, 0.8, -0.5), Enum.Material.Metal)
		add(Enum.PartType.Ball, V(0.3, 0.3, 0.3), Color3.fromRGB(255, 200, 60), CF(1.5, 1.4, 0), Enum.Material.Metal)
		add(Enum.PartType.Ball, V(0.18, 0.18, 0.18), Color3.fromRGB(20, 20, 20), CF(1.95, 0.85, 0.35))
		add(Enum.PartType.Ball, V(0.18, 0.18, 0.18), Color3.fromRGB(20, 20, 20), CF(1.95, 0.85, -0.35))
		add(Enum.PartType.Block, V(0.45, 0.7, 0.45), Color3.fromRGB(255, 200, 60), CF(0.9, -0.9, 0.45), Enum.Material.Metal)
		add(Enum.PartType.Block, V(0.45, 0.7, 0.45), Color3.fromRGB(255, 200, 60), CF(0.9, -0.9, -0.45), Enum.Material.Metal)
		add(Enum.PartType.Block, V(0.45, 0.7, 0.45), Color3.fromRGB(255, 200, 60), CF(-0.9, -0.9, 0.45), Enum.Material.Metal)
		add(Enum.PartType.Block, V(0.45, 0.7, 0.45), Color3.fromRGB(255, 200, 60), CF(-0.9, -0.9, -0.45), Enum.Material.Metal)
		add(Enum.PartType.Cylinder, V(0.8, 0.15, 0.15), Color3.fromRGB(255, 200, 60), CF(-1.35, 0.3, 0) * CFrame.Angles(0, 0, math.rad(30)), Enum.Material.Metal)
	else
		-- Fallback: kotak + aksen neon supaya model tidak pernah kosong.
		body.Size = Vector3.new(2.4 * s, 2.4 * s, 2.4 * s)
		body.Color = itemInfo.Color
		body.Material = Enum.Material.SmoothPlastic
		local topPart = Instance.new("Part", model)
		topPart.Name = "TopAccent"
		topPart.Size = Vector3.new(1.6 * s, 0.7 * s, 1.6 * s)
		topPart.Color = RARITY_COLORS[itemInfo.Rarity] or Color3.new(1, 1, 1)
		topPart.Material = Enum.Material.Neon
		topPart.CanCollide = false
		topPart.Massless = true
		topPart.CFrame = body.CFrame * CFrame.new(0, 1.45 * s, 0)
		local weldTop = Instance.new("Weld", body)
		weldTop.Part0 = body
		weldTop.Part1 = topPart
		weldTop.C0 = body.CFrame:Inverse() * topPart.CFrame
		weldTop.C1 = CFrame.new()
	end
	-- Aura + partikel berkilau untuk tier Rare ke atas (makin langka makin terang).
	local auraColor = nil
	local auraRange = 0
	local auraBright = 0
	if itemInfo.Rarity == "Rare" then auraColor = Color3.fromRGB(65, 165, 255); auraRange = 7; auraBright = 1.2
	elseif itemInfo.Rarity == "Epic" then auraColor = Color3.fromRGB(185, 85, 255); auraRange = 8; auraBright = 1.5
	elseif itemInfo.Rarity == "Legendary" then auraColor = Color3.fromRGB(255, 140, 40); auraRange = 9; auraBright = 1.8
	elseif itemInfo.Rarity == "Mythic" then auraColor = Color3.fromRGB(255, 65, 65); auraRange = 10; auraBright = 2
	elseif itemInfo.Rarity == "Ultra Rare" then auraColor = Color3.fromRGB(255, 225, 0); auraRange = 16; auraBright = 3 end
	if auraColor then
		local pl = Instance.new("PointLight", body)
		pl.Color = auraColor
		pl.Range = auraRange
		pl.Brightness = auraBright
		local pe = Instance.new("ParticleEmitter", body)
		pe.Color = ColorSequence.new(auraColor)
		pe.Size = NumberSequence.new(itemInfo.Rarity == "Ultra Rare" and 0.35 or 0.25)
		pe.Rate = itemInfo.Rarity == "Ultra Rare" and 25 or 12
		pe.Lifetime = NumberRange.new(0.6, 1.2)
		pe.Speed = NumberRange.new(1, 2)
		pe.SpreadAngle = Vector2.new(360, 360)
		pe.LightEmission = 1
	end
	model.PrimaryPart = body
	return model
end

-- Menghapus model brainrot yang sedang dibawa pemain + mengembalikan pose bahu.
local function clearCarriedBrainrotVisual(player)
	local char = player.Character
	if char then
		local existing = char:FindFirstChild("CarriedBrainrotModel")
		if existing then existing:Destroy() end
		local rightShoulder = char:FindFirstChild("RightShoulder", true) or char:FindFirstChild("Right Shoulder", true)
		local leftShoulder = char:FindFirstChild("LeftShoulder", true) or char:FindFirstChild("Left Shoulder", true)
		if rightShoulder and rightShoulder:GetAttribute("OrigC0") then pcall(function() rightShoulder.C0 = rightShoulder:GetAttribute("OrigC0") end) end
		if leftShoulder and leftShoulder:GetAttribute("OrigC0") then pcall(function() leftShoulder.C0 = leftShoulder:GetAttribute("OrigC0") end) end
	end
end

-- Menempelkan brainrot ke tangan pemain (diangkat di depan dada, bahu diangkat).
local function attachBrainrotToPlayer(player, itemId)
	clearCarriedBrainrotVisual(player)
	if not itemId or not CatalogById[itemId] then return end
	local char = player.Character
	if not char then return end
	local itemInfo = CatalogById[itemId]
	local model = createBrainrotVisualModel(itemInfo, 1.4)
	model.Name = "CarriedBrainrotModel"
	local primary = model.PrimaryPart
	primary.Anchored = false
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	local rightShoulder = char:FindFirstChild("RightShoulder", true) or char:FindFirstChild("Right Shoulder", true)
	local leftShoulder = char:FindFirstChild("LeftShoulder", true) or char:FindFirstChild("Left Shoulder", true)
	if not torso then model:Destroy() return end
	if rightShoulder then
		if not rightShoulder:GetAttribute("OrigC0") then rightShoulder:SetAttribute("OrigC0", rightShoulder.C0) end
		pcall(function() rightShoulder.C0 = rightShoulder:GetAttribute("OrigC0") * CFrame.Angles(math.rad(65), 0, math.rad(-18)) end)
	end
	if leftShoulder then
		if not leftShoulder:GetAttribute("OrigC0") then leftShoulder:SetAttribute("OrigC0", leftShoulder.C0) end
		pcall(function() leftShoulder.C0 = leftShoulder:GetAttribute("OrigC0") * CFrame.Angles(math.rad(65), 0, math.rad(18)) end)
	end
	model.Parent = char
	local holdOffset = CFrame.new(0, 0.15, -1.75)
	primary.CFrame = torso.CFrame * holdOffset
	local motor = Instance.new("Motor6D", primary)
	motor.Name = "CarryMotor"
	motor.Part0 = torso
	motor.Part1 = primary
	motor.C0 = holdOffset
end

local Bases = {}
local BaseZPositions = {90, 25, -40, -105}

-- Membangun 8 base (4 baris x 2 sisi). Tiap base: lantai, dinding, kaca kunci,
-- gapura, rumah Nusantara, papan nama, lampu, dan 6 pedestal (2 baris x 3 kolom).
for row = 1, 4 do
	for side = 1, 2 do
		local baseIndex = (row - 1) * 2 + side
		local isLeft = (side == 1)
		local xCenter = isLeft and -68 or 68
		local zCenter = BaseZPositions[row]
		local BaseFolder = Instance.new("Folder", MapFolder)
		BaseFolder.Name = "Base_" .. baseIndex
		createPart({Name = "BaseFloor", Size = Vector3.new(56, 0.8, 46), Position = Vector3.new(xCenter, 0.4, zCenter), Color = Color3.fromRGB(185, 135, 75), Material = Enum.Material.WoodPlanks, Parent = BaseFolder})
		createPart({Name = "BaseBorder", Size = Vector3.new(58, 0.8, 48), Position = Vector3.new(xCenter, 0.375, zCenter), Color = Color3.fromRGB(100, 70, 45), Material = Enum.Material.Wood, Parent = BaseFolder})
		local wallColor = Color3.fromRGB(145, 95, 55)
		createPart({Size = Vector3.new(2, 4, 46), Position = Vector3.new(xCenter + (isLeft and -27 or 27), 2.4, zCenter), Color = wallColor, Material = Enum.Material.Wood, Parent = BaseFolder})
		createPart({Size = Vector3.new(56, 4, 2), Position = Vector3.new(xCenter, 2.4, zCenter - 22), Color = wallColor, Material = Enum.Material.Wood, Parent = BaseFolder})
		createPart({Size = Vector3.new(56, 4, 2), Position = Vector3.new(xCenter, 2.4, zCenter + 22), Color = wallColor, Material = Enum.Material.Wood, Parent = BaseFolder})
		local capColor = Color3.fromRGB(120, 80, 50)
		createPart({Name = "WallCapLuar", Size = Vector3.new(2.5, 0.6, 46), Position = Vector3.new(xCenter + (isLeft and -27 or 27), 4.6, zCenter), Color = capColor, Material = Enum.Material.Wood, Parent = BaseFolder})
		createPart({Name = "WallCapKiri", Size = Vector3.new(56, 0.6, 2.5), Position = Vector3.new(xCenter, 4.6, zCenter - 22), Color = capColor, Material = Enum.Material.Wood, Parent = BaseFolder})
		createPart({Name = "WallCapKanan", Size = Vector3.new(56, 0.6, 2.5), Position = Vector3.new(xCenter, 4.6, zCenter + 22), Color = capColor, Material = Enum.Material.Wood, Parent = BaseFolder})
		local DoorX = xCenter + (isLeft and 27 or -27)
		local LockBarrier = createPart({Name = "LockBarrier", Size = Vector3.new(1.5, 12, 42), Position = Vector3.new(DoorX, 6, zCenter), Color = Color3.fromRGB(255, 50, 50), Material = Enum.Material.ForceField, Transparency = 1, CanCollide = false, Parent = BaseFolder})
		-- Kaca di semua sisi: pintu, belakang, kiri, kanan. Saat terkunci jadi
		-- dinding (transparan 0.5 + bisa ditabrak); saat terbuka tembus pandang.
		local LockGlass = {}
		local glassDoor = createPart({Name = "LockGlassDoor", Size = Vector3.new(2, 12, 42), Position = Vector3.new(DoorX, 6, zCenter), Color = Color3.fromRGB(200, 230, 255), Material = Enum.Material.Glass, Transparency = 1, CanCollide = false, Parent = BaseFolder})
		local backX = xCenter + (isLeft and -25 or 25)
		local glassB = createPart({Name = "LockGlassBack", Size = Vector3.new(2, 12, 46), Position = Vector3.new(backX, 6, zCenter), Color = Color3.fromRGB(200, 230, 255), Material = Enum.Material.Glass, Transparency = 1, CanCollide = false, Parent = BaseFolder})
		table.insert(LockGlass, glassB)
		local glassL = createPart({Name = "LockGlassLeft", Size = Vector3.new(56, 12, 2), Position = Vector3.new(xCenter, 6, zCenter - 20), Color = Color3.fromRGB(200, 230, 255), Material = Enum.Material.Glass, Transparency = 1, CanCollide = false, Parent = BaseFolder})
		table.insert(LockGlass, glassL)
		local glassR = createPart({Name = "LockGlassRight", Size = Vector3.new(56, 12, 2), Position = Vector3.new(xCenter, 6, zCenter + 20), Color = Color3.fromRGB(200, 230, 255), Material = Enum.Material.Glass, Transparency = 1, CanCollide = false, Parent = BaseFolder})
		table.insert(LockGlass, glassR)
		-- Pintu cuma trigger: pemilik lewat bebas, non-pemilik diteleport keluar
		-- kalau base sedang terkunci.
		LockBarrier.CanTouch = true
		LockBarrier.Touched:Connect(function(hit)
			local baseData = Bases[baseIndex]
			if not baseData or not baseData.IsLocked then return end
			local char = hit.Parent
			local plr = Players:GetPlayerFromCharacter(char)
			if not plr or baseData.Owner == plr then return end
			local root = char:FindFirstChild("HumanoidRootPart")
			if not root then return end
			local outX = DoorX + (isLeft and 6 or -6)
			root.CFrame = CFrame.new(outX, 4, root.Position.Z)
		end)
		-- Pagar menutup celah antara pilar gapura dan dinding samping.
		createPart({Name = "PagarKiri", Size = Vector3.new(2.2, 4, 10.4), Position = Vector3.new(DoorX, 2.4, zCenter - 16), Color = wallColor, Material = Enum.Material.Wood, Parent = BaseFolder})
		createPart({Name = "PagarKanan", Size = Vector3.new(2.2, 4, 10.4), Position = Vector3.new(DoorX, 2.4, zCenter + 16), Color = wallColor, Material = Enum.Material.Wood, Parent = BaseFolder})
		-- Gapura base: dua menara candi + atap dua tingkat + emblem emas.
		local pillarColor = Color3.fromRGB(130, 115, 95)
		local pillarColor2 = Color3.fromRGB(140, 125, 105)
		local roofColor = Color3.fromRGB(95, 65, 40)
		local goldColor = Color3.fromRGB(255, 200, 60)
		for _, zo in ipairs({-9, 9}) do
			local side = zo < 0 and "Kiri" or "Kanan"
			local tz = zCenter + zo
			createPart({Name = "GapuraMenaraDasar" .. side, Size = Vector3.new(2, 4, 4), Position = Vector3.new(DoorX, 2, tz), Color = pillarColor, Material = Enum.Material.Brick, Parent = BaseFolder})
			createPart({Name = "GapuraMenaraTengah" .. side, Size = Vector3.new(2, 3, 3.5), Position = Vector3.new(DoorX, 5.5, tz), Color = pillarColor2, Material = Enum.Material.Brick, Parent = BaseFolder})
			createPart({Name = "GapuraMenaraAtap1" .. side, Size = Vector3.new(2.5, 1, 4.5), Position = Vector3.new(DoorX, 7.5, tz), Color = roofColor, Material = Enum.Material.Slate, Parent = BaseFolder})
			createPart({Name = "GapuraMenaraPuncak" .. side, Size = Vector3.new(2, 2, 3), Position = Vector3.new(DoorX, 9, tz), Color = pillarColor2, Material = Enum.Material.Brick, Parent = BaseFolder})
			createPart({Name = "GapuraMenaraAtap2" .. side, Size = Vector3.new(2.5, 1, 4), Position = Vector3.new(DoorX, 10.5, tz), Color = roofColor, Material = Enum.Material.Slate, Parent = BaseFolder})
			createPart({Name = "GapuraMenaraEmas" .. side, Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2), Position = Vector3.new(DoorX, 11.8, tz), Color = goldColor, Material = Enum.Material.SmoothPlastic, Parent = BaseFolder})
		end
		createPart({Name = "GapuraAtap1", Size = Vector3.new(2, 1.2, 24), Position = Vector3.new(DoorX, 12.5, zCenter), Color = roofColor, Material = Enum.Material.Slate, Parent = BaseFolder})
		createPart({Name = "GapuraAtap2", Size = Vector3.new(2, 1.2, 20), Position = Vector3.new(DoorX, 13.7, zCenter), Color = roofColor, Material = Enum.Material.Slate, Parent = BaseFolder})
		createPart({Name = "GapuraPuncak", Shape = Enum.PartType.Ball, Size = Vector3.new(1.5, 1.5, 1.5), Position = Vector3.new(DoorX, 14.8, zCenter), Color = goldColor, Material = Enum.Material.SmoothPlastic, Parent = BaseFolder})
		createPart({Name = "GapuraEmblem", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 3, 3), Position = Vector3.new(DoorX + (isLeft and 1.5 or -1.5), 12.5, zCenter), Color = goldColor, Material = Enum.Material.SmoothPlastic, Parent = BaseFolder})
		-- Papan nama pemilik di pintu (dua sisi), default "make.fun".
		local NameBeam = createPart({Name = "OwnerBoard", Size = Vector3.new(1, 3.5, 14), Position = Vector3.new(DoorX, 9.5, zCenter), Color = Color3.fromRGB(45, 35, 30), Material = Enum.Material.Wood, Parent = BaseFolder})
		local OwnerGui = Instance.new("SurfaceGui", NameBeam)
		OwnerGui.Face = isLeft and Enum.NormalId.Right or Enum.NormalId.Left
		local OwnerLabel = Instance.new("TextLabel", OwnerGui)
		OwnerLabel.Size = UDim2.new(1, 0, 1, 0)
		OwnerLabel.BackgroundTransparency = 1
		OwnerLabel.Text = "make.fun"
		OwnerLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
		OwnerLabel.Font = Enum.Font.FredokaOne
		OwnerLabel.TextScaled = true
		local OwnerGuiDalam = Instance.new("SurfaceGui", NameBeam)
		OwnerGuiDalam.Face = isLeft and Enum.NormalId.Left or Enum.NormalId.Right
		local OwnerLabelDalam = Instance.new("TextLabel", OwnerGuiDalam)
		OwnerLabelDalam.Size = UDim2.new(1, 0, 1, 0)
		OwnerLabelDalam.BackgroundTransparency = 1
		OwnerLabelDalam.Text = "make.fun"
		OwnerLabelDalam.TextColor3 = Color3.fromRGB(255, 220, 100)
		OwnerLabelDalam.Font = Enum.Font.FredokaOne
		OwnerLabelDalam.TextScaled = true

		-- Rumah Nusantara: 4 pilar + atap dua tingkat + karpet merah + lampu.
		for _, px in ipairs({xCenter - 26, xCenter + 26}) do
			for _, pz in ipairs({zCenter - 21, zCenter + 21}) do
				createPart({Name = "PilarRumah", Size = Vector3.new(2, 14, 2), Position = Vector3.new(px, 7, pz), Color = Color3.fromRGB(130, 95, 60), Material = Enum.Material.Wood, Parent = BaseFolder})
			end
		end
		createPart({Name = "AtapRumah1", Size = Vector3.new(58, 1, 48), Position = Vector3.new(xCenter, 15.5, zCenter), Color = Color3.fromRGB(95, 65, 40), Material = Enum.Material.Slate, Parent = BaseFolder})
		createPart({Name = "AtapRumah2", Size = Vector3.new(40, 1, 30), Position = Vector3.new(xCenter, 17, zCenter), Color = Color3.fromRGB(80, 55, 35), Material = Enum.Material.Slate, Parent = BaseFolder})
		createPart({Name = "AtapPuncak", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), Position = Vector3.new(xCenter, 18.3, zCenter), Color = Color3.fromRGB(255, 200, 60), Material = Enum.Material.SmoothPlastic, Parent = BaseFolder})
		-- Papan atap: foto profil + nama pemilik, di atas rumah.
		local roofAnchor = createPart({Name = "RoofSignAnchor", Size = Vector3.new(0.5, 0.5, 0.5), Position = Vector3.new(xCenter, 20.5, zCenter), Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.SmoothPlastic, Transparency = 1, CanCollide = false, Parent = BaseFolder})
		local roofSign = Instance.new("BillboardGui", roofAnchor)
		roofSign.Size = UDim2.new(0, 200, 0, 110)
		roofSign.StudsOffset = Vector3.new(0, 0, 0)
		roofSign.MaxDistance = 120
		roofSign.AlwaysOnTop = true
		local roofFace = Instance.new("ImageLabel", roofSign)
		roofFace.Size = UDim2.new(0, 64, 0, 64)
		roofFace.Position = UDim2.new(0.5, -32, 0, 0)
		roofFace.BackgroundTransparency = 1
		roofFace.Visible = false
		local roofLabel = Instance.new("TextLabel", roofSign)
		roofLabel.Size = UDim2.new(1, 0, 0, 32)
		roofLabel.Position = UDim2.new(0, 0, 0, 70)
		roofLabel.BackgroundTransparency = 1
		roofLabel.Text = "BASE " .. baseIndex
		roofLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		roofLabel.Font = Enum.Font.FredokaOne
		roofLabel.TextScaled = true
		roofLabel.TextStrokeTransparency = 0
		createPart({Name = "KarpetMerah", Size = Vector3.new(10, 0.15, 30), Position = Vector3.new(DoorX + (isLeft and -5 or 5), 0.85, zCenter), Color = Color3.fromRGB(200, 40, 40), Material = Enum.Material.SmoothPlastic, Parent = BaseFolder})
		local baseLamp = createPart({Name = "LampuBase", Shape = Enum.PartType.Ball, Size = Vector3.new(1.5, 1.5, 1.5), Position = Vector3.new(xCenter, 12, zCenter), Color = Color3.fromRGB(255, 220, 130), Material = Enum.Material.Neon, Parent = BaseFolder})
		local baseLight = Instance.new("PointLight", baseLamp)
		baseLight.Color = Color3.fromRGB(255, 215, 140)
		baseLight.Range = 30
		baseLight.Brightness = 1.5

		-- 6 pedestal per base (2 baris x 3 kolom). Prompt-nya beda perilaku
		-- untuk pemilik (taruh/jual) dan bukan pemilik (curi).
		local Slots = {}
		local colOffsets = {-14, 0, 14}
		local rowOffsets = {-9, 9}
		local slotCounter = 0
		for r = 1, 2 do
			for c = 1, 3 do
				slotCounter += 1
				local sx = xCenter + colOffsets[c]
				local sz = zCenter + rowOffsets[r]
				local Pedestal = createPart({Name = "Slot_" .. slotCounter, Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 8.5, 8.5), CFrame = CFrame.new(sx, 1.1, sz) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(60, 150, 95), Material = Enum.Material.SmoothPlastic, Parent = BaseFolder})
				local Prompt = Instance.new("ProximityPrompt", Pedestal)
				Prompt.ObjectText = "Slot " .. slotCounter .. " (Kosong)"
				Prompt.ActionText = "Taruh Brainrot"
				Prompt.HoldDuration = 0.25
				Prompt.MaxActivationDistance = 12
				local currentSlotIdx = slotCounter
				Prompt.Triggered:Connect(function(player)
					local baseData = Bases[baseIndex]
					local state = PlayerStates[player.UserId]
					if not baseData or not state then return end
					local slotObj = baseData.Slots[currentSlotIdx]
					if baseData.Owner == player then
						if slotObj.ItemId == nil and state.CarriedItemId ~= nil then
							slotObj.ItemId = state.CarriedItemId
							state.CarriedItemId = nil
							clearCarriedBrainrotVisual(player)
							renderSlotVisual(baseIndex, currentSlotIdx)
							syncClient(player)
						elseif slotObj.ItemId ~= nil then
							SellBrainrotFromSlot(player, baseIndex, currentSlotIdx)
						end
					else
						-- Bukan pemilik: coba curi brainrot dari pedestal ini.
						StealBrainrotFromSlot(player, baseIndex, currentSlotIdx)
					end
				end)
				Slots[slotCounter] = {Index = slotCounter, Pedestal = Pedestal, Prompt = Prompt, ItemId = nil, VisualModel = nil}
			end
		end
		Bases[baseIndex] = {Index = baseIndex, Owner = nil, OwnerLabel = OwnerLabel, OwnerLabelDalam = OwnerLabelDalam, LockBarrier = LockBarrier, LockGlassDoor = glassDoor, LockGlass = LockGlass, RoofFace = roofFace, RoofLabel = roofLabel, IsLocked = false, LockEndTime = 0, SpawnPos = Vector3.new(xCenter, 4, zCenter), Slots = Slots}
	end
end

-- Biaya rebirth: 100rb x 2^jumlah rebirth yang sudah dilakukan.
local function getRebirthCost(rebirthCount) return CONFIG.RebirthBaseCost * (2 ^ rebirthCount) end

-- Pendapatan $/detik satu base = jumlah income slot x pengali rebirth pemilik.
local function calculateIncome(baseIndex)
	local base = Bases[baseIndex]
	if not base then return 0 end
	local total = 0
	for _, slot in ipairs(base.Slots) do
		if slot.ItemId and CatalogById[slot.ItemId] then total += CatalogById[slot.ItemId].Income end
	end
	local owner = base.Owner
	local mult = (owner and PlayerStates[owner.UserId]) and (1 + PlayerStates[owner.UserId].Rebirths * 0.5) or 1
	return math.floor(total * mult)
end

-- Mengirim state terbaru ke satu client (uang, income, slot, barang dibawa, kunci).
function syncClient(player)
	local state = PlayerStates[player.UserId]
	if not state then return end
	local base = Bases[state.BaseIndex]
	local slotList = {}
	if base then
		for i, slot in ipairs(base.Slots) do
			if slot.ItemId then
				local info = CatalogById[slot.ItemId]
				table.insert(slotList, {SlotIndex = i, Id = info.Id, Name = info.Name, Rarity = info.Rarity, Income = info.Income, SellPrice = math.floor(info.Price * CONFIG.SellMultiplier)})
			end
		end
	end
	local carriedInfo = nil
	if state.CarriedItemId and CatalogById[state.CarriedItemId] then
		local cInfo = CatalogById[state.CarriedItemId]
		carriedInfo = {Id = cInfo.Id, Name = cInfo.Name, Rarity = cInfo.Rarity, Income = cInfo.Income, SellPrice = math.floor(cInfo.Price * CONFIG.SellMultiplier)}
	end
	UpdateStateEvent:FireClient(player, {
		Money = state.Money, Rebirths = state.Rebirths, RebirthCost = getRebirthCost(state.Rebirths),
		Income = calculateIncome(state.BaseIndex), BaseIndex = state.BaseIndex, Slots = slotList,
		CarriedItem = carriedInfo, IsLocked = base and base.IsLocked or false,
		LockRemaining = base and math.max(0, math.ceil(base.LockEndTime - os.clock())) or 0
	})
end

-- Menggambar / menghapus model brainrot di atas pedestal + label harganya.
function renderSlotVisual(baseIndex, slotIndex)
	local base = Bases[baseIndex]
	local slot = base.Slots[slotIndex]
	if slot.VisualModel then slot.VisualModel:Destroy() slot.VisualModel = nil end
	if not slot.ItemId then
		slot.Pedestal.Color = Color3.fromRGB(60, 150, 95)
		slot.Prompt.ObjectText = "Slot " .. slotIndex .. " (Kosong)"
		slot.Prompt.ActionText = "Taruh Brainrot dari Tangan"
		return
	end
	local info = CatalogById[slot.ItemId]
	slot.Pedestal.Color = Color3.fromRGB(90, 215, 135)
	local model = createBrainrotVisualModel(info, 2.0)
	model.Name = "PedestalBrainrot"
	local primary = model.PrimaryPart
	primary.Anchored = true
	model:PivotTo(CFrame.new(slot.Pedestal.Position.X, 1.7 + (2.4 * 2.0 * 0.5), slot.Pedestal.Position.Z))
	for _, p in ipairs(model:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = true end end
	model.Parent = slot.Pedestal
	local bb = Instance.new("BillboardGui", primary)
	bb.Size = UDim2.new(0, 150, 0, 50)
	bb.StudsOffset = Vector3.new(0, 5.2, 0)
	bb.MaxDistance = 45
	local lbl = Instance.new("TextLabel", bb)
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = info.Name .. " (+$" .. info.Income .. "/s)"
	lbl.TextColor3 = info.Rarity == "Ultra Rare" and Color3.new(1, 1, 1) or (RARITY_COLORS[info.Rarity] or Color3.new(1, 1, 1))
	lbl.TextStrokeTransparency = 0
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	slot.VisualModel = model
	slot.Prompt.ObjectText = info.Name
	slot.Prompt.ActionText = "Jual $" .. math.floor(info.Price * CONFIG.SellMultiplier)
end

-- Menjual brainrot dari satu slot: pemilik saja, dapat 50% harga beli.
function SellBrainrotFromSlot(player, baseIndex, slotIndex)
	local state = PlayerStates[player.UserId]
	local base = Bases[baseIndex]
	if not state or not base or base.Owner ~= player then return end
	local slot = base.Slots[slotIndex]
	if not slot or not slot.ItemId then return end
	local info = CatalogById[slot.ItemId]
	local refund = math.floor(info.Price * CONFIG.SellMultiplier)
	slot.ItemId = nil
	renderSlotVisual(baseIndex, slotIndex)
	state.Money += refund
	syncClient(player)
end

-- Mencuri brainrot dari slot base orang lain. Server yang memutuskan:
-- ditolak kalau base terkunci, slot kosong, tangan pencuri penuh, atau
-- pencuri ternyata pemilik base. Korban ikut di-sync supaya HUD-nya update.
function StealBrainrotFromSlot(player, baseIndex, slotIndex)
	local state = PlayerStates[player.UserId]
	local base = Bases[baseIndex]
	if not state or not base or base.Owner == player then return end
	if base.IsLocked then return end
	local slot = base.Slots[slotIndex]
	if not slot or not slot.ItemId then return end
	if state.CarriedItemId ~= nil then return end
	local stolenId = slot.ItemId
	slot.ItemId = nil
	renderSlotVisual(baseIndex, slotIndex)
	state.CarriedItemId = stolenId
	attachBrainrotToPlayer(player, stolenId)
	syncClient(player)
	if base.Owner then syncClient(base.Owner) end
end

-- Gacha tier brainrot: roll 1-1000 (Common 45%, Uncommon 25%, Rare 18%,
-- Epic 8%, Legendary 2.8%, Mythic 1%, Ultra Rare 0.2%).
local function pickRandomBrainrot()
	local roll = math.random(1, 1000)
	if roll <= 450 then return BRAINROT_CATALOG[1]
	elseif roll <= 700 then return BRAINROT_CATALOG[2]
	elseif roll <= 880 then return BRAINROT_CATALOG[3]
	elseif roll <= 960 then return BRAINROT_CATALOG[4]
	elseif roll <= 988 then return BRAINROT_CATALOG[5]
	elseif roll <= 998 then return BRAINROT_CATALOG[6]
	else return BRAINROT_CATALOG[7] end
end

-- Conveyor: tiap 3.5 detik muncul satu brainrot, jalan di atas belt lalu
-- hilang di ujung. Dua jalur (x = -7.5 / +7.5) bergantian. Saat Pasar
-- Tumpah warning, spawn dijeda.
local nextLaneX = -7.5
local ConveyorPaused = false
local ConveyorDirection = 1 -- 1: spawn z=130 jalan ke -155; -1: kebalikannya (dibalik tiap banjir)
task.spawn(function()
	while true do
		task.wait(CONFIG.SpawnInterval)
		while ConveyorPaused do task.wait(0.5) end
		local item = pickRandomBrainrot()
		local part = Instance.new("Part", MapFolder)
		part.Name = "MarketBrainrot"
		part:SetAttribute("BrainrotId", item.Id)
		part.Size = Vector3.new(5.5, 0.5, 5.5)
		part.Position = Vector3.new(nextLaneX, 0.85, 130 * ConveyorDirection)
		nextLaneX = -nextLaneX
		part.Anchored = true
		part.CanCollide = false
		part.Color = Color3.fromRGB(140, 100, 55)
		part.Material = Enum.Material.WoodPlanks
		part.Transparency = 0
		local visual = createBrainrotVisualModel(item, 2.0)
		visual.Parent = part
		visual:PivotTo(part.CFrame * CFrame.new(0, 2.6, 0))
		local vw = Instance.new("Weld")
		vw.Part0 = part
		vw.Part1 = visual.PrimaryPart
		vw.C0 = part.CFrame:Inverse() * visual.PrimaryPart.CFrame
		vw.C1 = CFrame.new()
		vw.Parent = part
		local bb = Instance.new("BillboardGui", part)
		bb.Size = UDim2.new(0, 170, 0, 58)
		bb.StudsOffset = Vector3.new(0, 6.8, 0)
		bb.MaxDistance = 55
		local txt = Instance.new("TextLabel", bb)
		txt.Size = UDim2.new(1, 0, 1, 0)
		txt.BackgroundTransparency = 1
		txt.Text = item.Name .. " [" .. item.Rarity .. "] $" .. item.Price
		txt.TextColor3 = item.Rarity == "Ultra Rare" and Color3.new(1, 1, 1) or RARITY_COLORS[item.Rarity]
		txt.TextStrokeTransparency = 0
		txt.Font = Enum.Font.FredokaOne
		txt.TextScaled = true
		local prompt = Instance.new("ProximityPrompt", part)
		prompt.ObjectText = item.Name .. " ($" .. item.Income .. "/s)"
		prompt.ActionText = "Beli dan Angkat $" .. item.Price
		prompt.MaxActivationDistance = 16
		local purchased = false
		prompt.Triggered:Connect(function(player)
			if purchased then return end
			local state = PlayerStates[player.UserId]
			if not state or state.CarriedItemId ~= nil or state.Money < item.Price then return end
			purchased = true
			part:SetAttribute("Purchased", true)
			state.Money -= item.Price
			state.CarriedItemId = item.Id
			attachBrainrotToPlayer(player, item.Id)
			syncClient(player)
			part:Destroy()
		end)
		local tween = TweenService:Create(part, TweenInfo.new(285 / CONFIG.ConveyorSpeed, Enum.EasingStyle.Linear), {Position = Vector3.new(part.Position.X, 0.85, -155 * ConveyorDirection)})
		tween:Play()
		tween.Completed:Connect(function() if part and part.Parent then part:Destroy() end end)
	end
end)

-- =====================================================================
-- PASAR TUMPAH: tiap 3 menit, sirene -> hitung mundur 10 dtk -> gelombang
-- banjir menyapu plaza -> brainrot yang belum aman hanyut jadi peti di
-- scramble zone -> peti bisa direbut (siapa cepat dia dapat).
-- Yang AMAN: brainrot di slot base + brainrot yang dibawa pemain yang sudah
-- sampai di dalam base-nya sendiri. Ini banjir pasar (hujan deras), bukan
-- tsunami: debris cuma BAJU + PINTU + JENDELA. Semua state di server.
-- =====================================================================
local FLOOD = {
	Interval = 180,      -- tiap 3 menit
	FirstDelay = 120,    -- banjir pertama 2 menit setelah server jalan
	WarningTime = 10,    -- hitung mundur sirene
	ScrambleTime = 60,   -- peti hidup 60 detik lalu hilang
	WaveTime = 6,        -- gelombang melintas plaza ~6 detik
}

local FloodPhase = "Idle" -- Idle | Warning | Flooding | Scramble
local FloodTimeLeft = FLOOD.FirstDelay
local FloodDebugTrigger = false
local FloodCrates = {}

-- Sirene banjir: bunyi saat Warning 10 detik. Sound di SoundService =
-- global, terdengar semua pemain dengan volume sama. Asset "Tornado Siren"
-- (rbxassetid://792323017, public domain, gratis). Looped supaya menutupi
-- 10 detik Warning; BGM tidak terganggu (Sound terpisah).
local FloodSiren = Instance.new("Sound")
FloodSiren.Name = "FloodSiren"
FloodSiren.SoundId = "rbxassetid://792323017"
FloodSiren.Volume = 0.6
FloodSiren.Looped = true
FloodSiren.Parent = SoundService

local CRATE_CLASSES = {
	Pasar = {Name = "Peti Pasar", Color = Color3.fromRGB(60, 200, 110)},
	Pedagang = {Name = "Peti Pedagang", Color = Color3.fromRGB(255, 200, 60)},
	Tumpah = {Name = "Peti Tumpah", Color = Color3.fromRGB(185, 85, 255)},
}

-- Kelas peti dari tier brainrot yang hanyut (1 brainrot = 1 peti).
-- Peti Tumpah dari tier menengah cuma peluang kecil (Epic 25%).
local function rollCrateClass(rarity)
	if rarity == "Common" or rarity == "Uncommon" then return "Pasar" end
	if rarity == "Rare" then return (math.random() < 0.4) and "Pedagang" or "Pasar" end
	if rarity == "Epic" then return (math.random() < 0.25) and "Tumpah" or "Pedagang" end
	if rarity == "Legendary" then return (math.random() < 0.5) and "Tumpah" or "Pedagang" end
	return "Tumpah" -- Mythic, Ultra Rare
end

-- Posisi peti per kelas: Pasar dekat base, Pedagang tengah plaza,
-- Tumpah di ujung utara (risiko tertinggi).
local function randomCratePosition(crateClass)
	if crateClass == "Pasar" then
		local side = math.random() < 0.5 and -1 or 1
		return Vector3.new(side * (44 + math.random() * 10), 0.8, -120 + math.random() * 240)
	elseif crateClass == "Tumpah" then
		return Vector3.new(-28 + math.random() * 56, 0.8, -158 + math.random() * 20)
	else
		return Vector3.new(-28 + math.random() * 56, 0.8, -120 + math.random() * 240)
	end
end

local function clampToPlaza(pos)
	local x = math.max(-75, math.min(75, pos.X))
	local z = math.max(-160, math.min(165, pos.Z))
	return Vector3.new(x, 0.8, z)
end

-- Apakah pemain sedang berdiri di dalam base-nya sendiri (batas +-28 x, +-23 z).
local function isInsideOwnBase(player)
	local state = PlayerStates[player.UserId]
	if not state or not state.BaseIndex then return false end
	local base = Bases[state.BaseIndex]
	if not base then return false end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local p = root.Position
	return math.abs(p.X - base.SpawnPos.X) <= 28 and math.abs(p.Z - base.SpawnPos.Z) <= 23
end

-- Satu peti loot: kotak kayu + model brainrot di atasnya + label + cahaya
-- (khusus Tumpah) + prompt "Buka Peti" (0.5 dtk, siapa cepat dia dapat).
local function spawnCrate(itemId, crateClass, position)
	local info = CatalogById[itemId]
	if not info then return end
	local classInfo = CRATE_CLASSES[crateClass]
	local crate = Instance.new("Part")
	crate.Name = "FloodCrate"
	crate.Size = Vector3.new(4, 3, 4)
	crate.Position = position + Vector3.new(0, 1.5, 0)
	crate.Anchored = true
	crate.CanCollide = false
	crate.Color = classInfo.Color
	crate.Material = Enum.Material.WoodPlanks
	crate:SetAttribute("BrainrotId", itemId)
	crate:SetAttribute("CrateClass", crateClass)
	-- Tampilkan brainrot di atas peti (pola sama seperti conveyor):
	-- visual di-parent ke crate, PivotTo di atas tutup peti, di-Weld.
	local visual = createBrainrotVisualModel(info, 1.6)
	visual.Parent = crate
	visual:PivotTo(crate.CFrame * CFrame.new(0, 3.6, 0))
	local vw = Instance.new("Weld")
	vw.Part0 = crate
	vw.Part1 = visual.PrimaryPart
	vw.C0 = crate.CFrame:Inverse() * visual.PrimaryPart.CFrame
	vw.C1 = CFrame.new()
	vw.Parent = crate
	local bb = Instance.new("BillboardGui", crate)
	bb.Size = UDim2.new(0, 170, 0, 58)
	bb.StudsOffset = Vector3.new(0, 7.0, 0)
	bb.MaxDistance = 55
	local txt = Instance.new("TextLabel", bb)
	txt.Size = UDim2.new(1, 0, 1, 0)
	txt.BackgroundTransparency = 1
	txt.Text = classInfo.Name .. " - " .. info.Name .. " [$" .. info.Income .. "/s]"
	txt.TextColor3 = RARITY_COLORS[info.Rarity] or Color3.new(1, 1, 1)
	txt.TextStrokeTransparency = 0
	txt.Font = Enum.Font.FredokaOne
	txt.TextScaled = true
	if crateClass == "Tumpah" then
		local pl = Instance.new("PointLight", crate)
		pl.Color = Color3.fromRGB(255, 225, 0)
		pl.Range = 12
		pl.Brightness = 2
		local pe = Instance.new("ParticleEmitter", crate)
		pe.Color = ColorSequence.new(Color3.fromRGB(255, 225, 0))
		pe.Size = NumberSequence.new(0.3)
		pe.Rate = 20
		pe.Lifetime = NumberRange.new(0.6, 1.2)
		pe.Speed = NumberRange.new(1, 2)
		pe.SpreadAngle = Vector2.new(360, 360)
		pe.LightEmission = 1
	end
	local prompt = Instance.new("ProximityPrompt", crate)
	prompt.ObjectText = classInfo.Name .. " - " .. info.Name .. " ($" .. info.Income .. "/s)"
	prompt.ActionText = "Buka Peti"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	local claimed = false
	prompt.Triggered:Connect(function(player)
		if claimed then return end
		local state = PlayerStates[player.UserId]
		if not state or state.CarriedItemId ~= nil then return end
		claimed = true
		state.CarriedItemId = itemId
		attachBrainrotToPlayer(player, itemId)
		syncClient(player)
		crate:Destroy()
	end)
	crate.Parent = MapFolder
	table.insert(FloodCrates, crate)
end

local function clearFloodCrates()
	for _, crate in ipairs(FloodCrates) do
		if crate and crate.Parent then crate:Destroy() end
	end
	FloodCrates = {}
end

-- Visual gelombang: dinding air kaca biru menyapu utara -> selatan,
-- genangan di plaza, dan debris (baju/pintu/jendela) yang ikut hanyut.
local function spawnWaveVisual()
	local wave = Instance.new("Part")
	wave.Name = "FloodWave"
	wave.Size = Vector3.new(70, 9, 4)
	wave.Position = Vector3.new(0, 4.5, -170)
	wave.Anchored = true
	wave.CanCollide = false
	wave.Color = Color3.fromRGB(65, 140, 255)
	wave.Material = Enum.Material.Glass
	wave.Transparency = 0.35
	wave.Parent = MapFolder
	local foam = Instance.new("ParticleEmitter", wave)
	foam.Color = ColorSequence.new(Color3.fromRGB(230, 245, 255))
	foam.Size = NumberSequence.new(1.2)
	foam.Rate = 60
	foam.Lifetime = NumberRange.new(0.5, 1)
	foam.Speed = NumberRange.new(2, 4)
	foam.SpreadAngle = Vector2.new(360, 360)
	foam.LightEmission = 0.5
	local waveTween = TweenService:Create(wave, TweenInfo.new(FLOOD.WaveTime, Enum.EasingStyle.Linear), {Position = Vector3.new(0, 4.5, 175)})
	waveTween:Play()
	task.delay(FLOOD.WaveTime + 0.5, function() if wave.Parent then wave:Destroy() end end)
	-- Genangan air di plaza (lantai base lebih tinggi, jadi base tetap kering).
	local sheet = Instance.new("Part")
	sheet.Name = "FloodWater"
	sheet.Size = Vector3.new(130, 0.2, 330)
	sheet.Position = Vector3.new(0, 0.65, 0)
	sheet.Anchored = true
	sheet.CanCollide = false
	sheet.Color = Color3.fromRGB(65, 140, 255)
	sheet.Material = Enum.Material.Glass
	sheet.Transparency = 1
	sheet.Parent = MapFolder
	TweenService:Create(sheet, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Transparency = 0.45}):Play()
	task.delay(3.5, function()
		if not sheet.Parent then return end
		TweenService:Create(sheet, TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Transparency = 1}):Play()
		task.delay(2.2, function() if sheet.Parent then sheet:Destroy() end end)
	end)
	-- Debris: cuma BAJU + PINTU + JENDELA (tembok kota TIDAK hanyut, tanpa mobil).
	local debrisFolder = Instance.new("Folder")
	debrisFolder.Name = "FloodDebris"
	debrisFolder.Parent = MapFolder
	local clothesColors = {
		Color3.fromRGB(220, 60, 60), Color3.fromRGB(255, 200, 60), Color3.fromRGB(65, 140, 255),
		Color3.fromRGB(80, 200, 110), Color3.fromRGB(255, 150, 200), Color3.fromRGB(255, 140, 40),
	}
	for i = 1, 14 do
		local kind = ({"baju", "pintu", "jendela"})[(i - 1) % 3 + 1]
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		if kind == "baju" then
			p.Size = Vector3.new(2, 0.3, 1.5)
			p.Color = clothesColors[math.random(#clothesColors)]
			p.Material = Enum.Material.Fabric
			p.Position = Vector3.new(math.random(-28, 28), 1, -165 + math.random(-5, 5))
		elseif kind == "pintu" then
			p.Size = Vector3.new(2.5, 5, 0.3)
			p.Color = Color3.fromRGB(140, 95, 55)
			p.Material = Enum.Material.Wood
			p.Position = Vector3.new(math.random(-28, 28), 2.5, -165 + math.random(-5, 5))
		else
			p.Size = Vector3.new(2, 2, 0.3)
			p.Color = Color3.fromRGB(180, 220, 245)
			p.Material = Enum.Material.Glass
			p.Transparency = 0.25
			p.Position = Vector3.new(math.random(-28, 28), 2, -165 + math.random(-5, 5))
		end
		p.CFrame = CFrame.new(p.Position) * CFrame.Angles(0, math.rad(math.random(-30, 30)), 0)
		p.Parent = debrisFolder
	end
	task.spawn(function()
		for _ = 1, 60 do
			task.wait(0.1)
			for _, p in ipairs(debrisFolder:GetChildren()) do
				if p:IsA("BasePart") then
					p.CFrame = p.CFrame * CFrame.new(0, 0, 5.7) * CFrame.Angles(0.02, 0.01, 0)
				end
			end
		end
		debrisFolder:Destroy()
	end)
end

-- Dorongan ringan ke pemain yang masih di luar base saat gelombang datang.
local function applyWaveKnockback()
	for _, player in ipairs(Players:GetPlayers()) do
		if not isInsideOwnBase(player) then
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				root.AssemblyLinearVelocity = Vector3.new(0, 8, 18)
			end
		end
	end
end

-- Satu gelombang banjir penuh: kumpulkan yang hanyut, balik arah conveyor,
-- tampilkan gelombang, lalu jatuhkan peti dari yang hanyut.
local function runFloodWave()
	-- 1. Brainrot di conveyor yang belum dibeli ikut hanyut.
	local washed = {}
	for _, child in ipairs(MapFolder:GetChildren()) do
		if child.Name == "MarketBrainrot" and child.Parent and not child:GetAttribute("Purchased") then
			local id = child:GetAttribute("BrainrotId")
			if id and CatalogById[id] then
				table.insert(washed, {ItemId = id})
			end
			child:Destroy()
		end
	end
	-- 2. Brainrot yang dibawa pemain yang belum sampai base ikut hanyut.
	for _, player in ipairs(Players:GetPlayers()) do
		local state = PlayerStates[player.UserId]
		if state and state.CarriedItemId and not isInsideOwnBase(player) then
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local pos = root and root.Position or Vector3.new(0, 4, 0)
			table.insert(washed, {ItemId = state.CarriedItemId, DropPos = pos})
			state.CarriedItemId = nil
			clearCarriedBrainrotVisual(player)
			syncClient(player)
		end
	end
	-- 3. Arah conveyor dibalik untuk ronde berikutnya.
	ConveyorDirection = -ConveyorDirection
	-- 4. Gelombang + debris + genangan.
	spawnWaveVisual()
	-- 5. Knockback ringan buat yang di luar base.
	applyWaveKnockback()
	-- 6. Tunggu gelombang lewat, baru peti muncul dari yang hanyut.
	task.wait(FLOOD.WaveTime + 0.5)
	-- Spawn peti dibungkus pcall supaya satu spawn yang gagal tidak
	-- membatalkan peti lainnya.
	local function safeSpawnCrate(itemId, crateClass, position)
		pcall(spawnCrate, itemId, crateClass, position)
	end
	-- Kalau conveyor kosong saat banjir (brainrot sudah sampai ujung dan
	-- di-destroy selama Warning), event tetap harus ada loot: 3 peti acak,
	-- satu per kelas.
	if #washed == 0 then
		safeSpawnCrate(BRAINROT_CATALOG[math.random(1, 2)].Id, "Pasar", randomCratePosition("Pasar"))
		safeSpawnCrate(BRAINROT_CATALOG[math.random(3, 4)].Id, "Pedagang", randomCratePosition("Pedagang"))
		safeSpawnCrate(BRAINROT_CATALOG[math.random(5, 7)].Id, "Tumpah", randomCratePosition("Tumpah"))
	end
	for _, w in ipairs(washed) do
		local info = CatalogById[w.ItemId]
		if info then
			local class = rollCrateClass(info.Rarity)
			local pos
			if w.DropPos then
				pos = clampToPlaza(w.DropPos)
			else
				pos = randomCratePosition(class)
			end
			safeSpawnCrate(w.ItemId, class, pos)
		end
	end
	-- Jaminan peti selalu muncul: kalau semua spawn di atas gagal dan tidak
	-- ada satu pun peti, paksa 3 peti fallback.
	if #FloodCrates == 0 then
		safeSpawnCrate(BRAINROT_CATALOG[math.random(1, 2)].Id, "Pasar", randomCratePosition("Pasar"))
		safeSpawnCrate(BRAINROT_CATALOG[math.random(3, 4)].Id, "Pedagang", randomCratePosition("Pedagang"))
		safeSpawnCrate(BRAINROT_CATALOG[math.random(5, 7)].Id, "Tumpah", randomCratePosition("Tumpah"))
	end
end

-- Debug (Studio saja): tembak RemoteEvent ini dari command bar Studio untuk
-- memicu banjir langsung tanpa menunggu timer:
--   game.ReplicatedStorage.GameRemotes.DebugFlood:FireServer()
DebugFloodEvent.OnServerEvent:Connect(function(player)
	if RunService:IsStudio() and FloodPhase == "Idle" then
		FloodDebugTrigger = true
	end
end)

-- State machine event: Idle -> Warning 10 dtk -> Flooding -> Scramble 60 dtk -> Idle.
task.spawn(function()
	task.wait(1)
	local nextDelay = FLOOD.FirstDelay
	while true do
		-- Idle: hitung mundur ke banjir berikutnya.
		FloodPhase = "Idle"
		FloodSiren:Stop()
		FloodTimeLeft = nextDelay
		FloodEvent:FireAllClients("Idle", FloodTimeLeft)
		local waited = 0
		while waited < nextDelay do
			task.wait(1)
			waited += 1
			FloodTimeLeft = nextDelay - waited
			if waited % 10 == 0 then FloodEvent:FireAllClients("Idle", FloodTimeLeft) end
			if FloodDebugTrigger then FloodDebugTrigger = false break end
		end
		-- Warning: sirene + hitung mundur 10 dtk, conveyor berhenti spawn.
		FloodPhase = "Warning"
		ConveyorPaused = true
		FloodSiren:Play()
		for t = FLOOD.WarningTime, 1, -1 do
			FloodTimeLeft = t
			FloodEvent:FireAllClients("Warning", t)
			task.wait(1)
		end
		-- Flooding: gelombang menyapu plaza.
		FloodPhase = "Flooding"
		FloodTimeLeft = 0
		FloodEvent:FireAllClients("Flooding", 0)
		FloodSiren:Stop()
		runFloodWave()
		-- Scramble: peti bisa direbut 60 dtk.
		FloodPhase = "Scramble"
		for t = FLOOD.ScrambleTime, 1, -1 do
			FloodTimeLeft = t
			if t == FLOOD.ScrambleTime or t % 5 == 0 then FloodEvent:FireAllClients("Scramble", t) end
			task.wait(1)
		end
		clearFloodCrates()
		ConveyorPaused = false
		nextDelay = FLOOD.Interval
	end
end)

-- Aksi dari client: jual slot, jual barang bawaan, taruh otomatis, kunci base, rebirth.
ActionEvent.OnServerEvent:Connect(function(player, action, payload)
	local state = PlayerStates[player.UserId]
	if not state then return end
	local base = Bases[state.BaseIndex]
	if not base then return end
	if action == "SellSlot" and type(payload) == "number" then
		SellBrainrotFromSlot(player, state.BaseIndex, payload)
	elseif action == "SellCarried" then
		if state.CarriedItemId and CatalogById[state.CarriedItemId] then
			local info = CatalogById[state.CarriedItemId]
			state.CarriedItemId = nil
			clearCarriedBrainrotVisual(player)
			state.Money += math.floor(info.Price * CONFIG.SellMultiplier)
			syncClient(player)
		end
	elseif action == "PlaceCarriedAuto" then
		if state.CarriedItemId then
			for i = 1, CONFIG.SlotsPerBase do
				if base.Slots[i].ItemId == nil then
					base.Slots[i].ItemId = state.CarriedItemId
					state.CarriedItemId = nil
					clearCarriedBrainrotVisual(player)
					renderSlotVisual(state.BaseIndex, i)
					syncClient(player)
					break
				end
			end
		end
	elseif action == "LockBase" then
		if not base.IsLocked then
			base.IsLocked = true
			base.LockEndTime = os.clock() + CONFIG.BaseLockDuration
			base.LockGlassDoor.Transparency = 0.5
			for _, p in ipairs(base.LockGlass) do p.Transparency = 0.5 p.CanCollide = true end
			syncClient(player)
			task.delay(CONFIG.BaseLockDuration, function()
				if base.Owner == player then
					base.IsLocked = false
					base.LockGlassDoor.Transparency = 1
					for _, p in ipairs(base.LockGlass) do p.Transparency = 1 p.CanCollide = false end
					syncClient(player)
				end
			end)
		end
	elseif action == "Rebirth" then
		local cost = getRebirthCost(state.Rebirths)
		if state.Money >= cost then
			state.Money = 100
			state.Rebirths += 1
			state.CarriedItemId = nil
			clearCarriedBrainrotVisual(player)
			for i = 1, CONFIG.SlotsPerBase do
				base.Slots[i].ItemId = nil
				renderSlotVisual(state.BaseIndex, i)
			end
			syncClient(player)
		end
	end
end)

-- Pemain masuk: beri base kosong, muat simpanan DataStore (uang, rebirth,
-- slot, barang bawaan), teleport ke base, pasang ulang visual bawaan.
Players.PlayerAdded:Connect(function(player)
	local assignedBase = nil
	for i = 1, CONFIG.MaxBases do
		if Bases[i].Owner == nil then
			assignedBase = i
			Bases[i].Owner = player
			Bases[i].OwnerLabel.Text = "make.fun"
			Bases[i].OwnerLabelDalam.Text = "make.fun"
			Bases[i].RoofLabel.Text = player.Name
			Bases[i].RoofFace.Visible = true
			task.spawn(function()
				local ok, thumb = pcall(function()
					return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
				end)
				if ok and thumb and Bases[i].RoofFace then Bases[i].RoofFace.Image = thumb end
			end)
			break
		end
	end
	local savedData = nil
	if PlayerDataStore then
		pcall(function() savedData = PlayerDataStore:GetAsync("User_" .. player.UserId) end)
	end
	PlayerStates[player.UserId] = {Money = savedData and savedData.Money or 200, Rebirths = savedData and savedData.Rebirths or 0, BaseIndex = assignedBase, CarriedItemId = savedData and savedData.Carried or nil}
	if assignedBase and savedData and savedData.Slots then
		for slotIdx, itemId in pairs(savedData.Slots) do
			local idx = tonumber(slotIdx)
			if idx and CatalogById[itemId] and Bases[assignedBase].Slots[idx] then
				Bases[assignedBase].Slots[idx].ItemId = itemId
				renderSlotVisual(assignedBase, idx)
			end
		end
	end
	player.CharacterAdded:Connect(function(char)
		task.wait(0.2)
		if assignedBase and char:FindFirstChild("HumanoidRootPart") then
			char.HumanoidRootPart.CFrame = CFrame.new(Bases[assignedBase].SpawnPos + Vector3.new(0, 3, 0))
		end
		local st = PlayerStates[player.UserId]
		if st and st.CarriedItemId then attachBrainrotToPlayer(player, st.CarriedItemId) end
	end)
	syncClient(player)
	FloodEvent:FireClient(player, FloodPhase, FloodTimeLeft)
end)

-- Menyimpan progres satu pemain: uang, rebirth, isi slot (kunci string),
-- dan barang yang sedang dibawa. Dipanggil saat pemain keluar dan saat
-- server ditutup.
local function savePlayerData(player)
	local state = PlayerStates[player.UserId]
	if not state then return end
	local slotsToSave = {}
	local base = Bases[state.BaseIndex]
	if base then
		for i, slot in ipairs(base.Slots) do
			if slot.ItemId then slotsToSave[tostring(i)] = slot.ItemId end
		end
	end
	if PlayerDataStore then
		pcall(function() PlayerDataStore:SetAsync("User_" .. player.UserId, {Money = state.Money, Rebirths = state.Rebirths, Slots = slotsToSave, Carried = state.CarriedItemId}) end)
	end
end

-- Pemain keluar: SIMPAN DULU, baru bersihkan slot dan kembalikan base.
-- Urutan ini penting: kalau slot dibersihkan dulu, simpanan jadi kosong.
Players.PlayerRemoving:Connect(function(player)
	local state = PlayerStates[player.UserId]
	if state then
		savePlayerData(player)
		local base = Bases[state.BaseIndex]
		if base then
			for i, slot in ipairs(base.Slots) do
				slot.ItemId = nil
				renderSlotVisual(state.BaseIndex, i)
			end
			base.Owner = nil
			base.IsLocked = false
			base.LockGlassDoor.Transparency = 1
			for _, p in ipairs(base.LockGlass) do p.Transparency = 1 p.CanCollide = false end
			base.OwnerLabel.Text = "make.fun"
			base.OwnerLabelDalam.Text = "make.fun"
			base.RoofLabel.Text = "BASE " .. state.BaseIndex
			base.RoofFace.Visible = false
			base.RoofFace.Image = ""
		end
		PlayerStates[player.UserId] = nil
	end
end)

-- Saat server ditutup, simpan semua pemain yang masih online.
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		savePlayerData(player)
	end
end)

-- Loop pendapatan: tiap detik, tiap pemain dapat income dari base-nya.
task.spawn(function()
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			local state = PlayerStates[player.UserId]
			if state and state.BaseIndex then
				local inc = calculateIncome(state.BaseIndex)
				if inc > 0 then state.Money += inc end
				syncClient(player)
			end
		end
	end
end)
