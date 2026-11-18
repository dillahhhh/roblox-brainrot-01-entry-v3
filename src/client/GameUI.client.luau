-- GameUIController — seluruh HUD dan kontrol client untuk Pasar Brainrot.
-- Berjalan dari StarterPlayerScripts; semua elemen UI dibuat lewat script di sini.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer

-- Indeks base milik pemain ini. Dipakai untuk membedakan prompt "Curi" di base orang lain.
local MyBaseIndex = nil

local Remotes = ReplicatedStorage:WaitForChild("GameRemotes")
local UpdateStateEvent = Remotes:WaitForChild("UpdateState")
local ActionEvent = Remotes:WaitForChild("PlayerAction")
local FloodEvent = Remotes:WaitForChild("FloodEvent")

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "PasarNusantaraUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = player:WaitForChild("PlayerGui")

-- FIXED28: skala UI responsif — di layar kecil (HP) semua UI mengecil supaya
-- tidak menutupi layar. Skala dihitung dari ukuran viewport terhadap acuan
-- 1100x700, dijepit antara 0.55 dan 1, dan dihitung ulang tiap viewport berubah.
local uiScale = Instance.new("UIScale")
uiScale.Parent = ScreenGui

local function refreshUIScale()
	local cam = workspace.CurrentCamera
	local vp = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
	uiScale.Scale = math.clamp(math.min(vp.X / 1100, vp.Y / 700), 0.55, 1)
end
refreshUIScale()
local viewportCamera = workspace.CurrentCamera
if viewportCamera then
	viewportCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshUIScale)
end

-- Pembantu kecil untuk sudut membulat dan garis tepi panel.
local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 10)
	corner.Parent = parent
end

local function addStroke(parent, color, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Color3.fromRGB(255, 200, 70)
	stroke.Thickness = thickness or 2
	stroke.Parent = parent
end

-- 1. UANG — bawah tengah, tanpa bar, kecil.
local MoneyPanel = Instance.new("Frame")
MoneyPanel.Size = UDim2.new(0, 260, 0, 50)
MoneyPanel.Position = UDim2.new(0.5, -130, 1, -55)
MoneyPanel.BackgroundTransparency = 1
MoneyPanel.Parent = ScreenGui

local MoneyLabel = Instance.new("TextLabel")
MoneyLabel.Size = UDim2.new(1, 0, 0, 28)
MoneyLabel.Position = UDim2.new(0, 0, 0, 0)
MoneyLabel.BackgroundTransparency = 1
MoneyLabel.Text = "$200"
MoneyLabel.TextColor3 = Color3.fromRGB(255, 220, 70)
MoneyLabel.Font = Enum.Font.FredokaOne
MoneyLabel.TextXAlignment = Enum.TextXAlignment.Center
MoneyLabel.TextSize = 30
MoneyLabel.TextStrokeTransparency = 0
MoneyLabel.Parent = MoneyPanel

local IncomeLabel = Instance.new("TextLabel")
IncomeLabel.Size = UDim2.new(1, 0, 0, 20)
IncomeLabel.Position = UDim2.new(0, 0, 0, 28)
IncomeLabel.BackgroundTransparency = 1
IncomeLabel.Text = "+$0/s - Rebirth 0x"
IncomeLabel.TextColor3 = Color3.fromRGB(110, 245, 130)
IncomeLabel.Font = Enum.Font.GothamBold
IncomeLabel.TextXAlignment = Enum.TextXAlignment.Center
IncomeLabel.TextSize = 17
IncomeLabel.TextStrokeTransparency = 0
IncomeLabel.Parent = MoneyPanel

-- 2. PANEL BASE-KU — judul saja (6 baris slot dihapus).
local BasePanel = Instance.new("Frame")
BasePanel.Size = UDim2.new(0, 208, 0, 34)
BasePanel.Position = UDim2.new(0, 16, 0, 16)
BasePanel.BackgroundColor3 = Color3.fromRGB(25, 22, 20)
BasePanel.BackgroundTransparency = 0.15
BasePanel.Parent = ScreenGui
addCorner(BasePanel, 12)
addStroke(BasePanel, Color3.fromRGB(120, 180, 255), 2)

local BaseTitle = Instance.new("TextLabel")
BaseTitle.Size = UDim2.new(1, -12, 0, 24)
BaseTitle.Position = UDim2.new(0, 6, 0, 5)
BaseTitle.BackgroundTransparency = 1
BaseTitle.Text = "Base-ku (0/6) - Klik Jual 50%"
BaseTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
BaseTitle.Font = Enum.Font.GothamBold
BaseTitle.TextScaled = true
BaseTitle.Parent = BasePanel

-- 2b. BANNER PASAR TUMPAH — atas tengah, paling atas (FIXED29: y=8).
local FloodBanner = Instance.new("Frame")
FloodBanner.Size = UDim2.new(0, 520, 0, 44)
FloodBanner.Position = UDim2.new(0.5, -260, 0, 8)
FloodBanner.BackgroundColor3 = Color3.fromRGB(25, 22, 20)
FloodBanner.BackgroundTransparency = 0.15
FloodBanner.Parent = ScreenGui
addCorner(FloodBanner, 12)
addStroke(FloodBanner, Color3.fromRGB(120, 180, 255), 2)

local FloodBannerLabel = Instance.new("TextLabel")
FloodBannerLabel.Size = UDim2.new(1, -12, 1, 0)
FloodBannerLabel.Position = UDim2.new(0, 6, 0, 0)
FloodBannerLabel.BackgroundTransparency = 1
FloodBannerLabel.Text = "Pasar Tumpah: --:--"
FloodBannerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
FloodBannerLabel.Font = Enum.Font.GothamBold
FloodBannerLabel.TextScaled = true
FloodBannerLabel.Parent = FloodBanner

-- 3. PANEL SEDANG MEMEGANG BRAINROT — tengah bawah.
local CarryPanel = Instance.new("Frame")
CarryPanel.Size = UDim2.new(0, 340, 0, 82)
CarryPanel.Position = UDim2.new(0.5, -170, 1, -160)
CarryPanel.BackgroundColor3 = Color3.fromRGB(30, 25, 20)
CarryPanel.BackgroundTransparency = 0.1
CarryPanel.Visible = false
CarryPanel.Parent = ScreenGui
addCorner(CarryPanel, 12)
addStroke(CarryPanel, Color3.fromRGB(255, 210, 60), 2)

local CarryTitle = Instance.new("TextLabel")
CarryTitle.Size = UDim2.new(1, -16, 0, 28)
CarryTitle.Position = UDim2.new(0, 8, 0, 6)
CarryTitle.BackgroundTransparency = 1
CarryTitle.Text = "Memegang: Es Teh Manis (+$8/s)"
CarryTitle.TextColor3 = Color3.fromRGB(255, 230, 100)
CarryTitle.Font = Enum.Font.FredokaOne
CarryTitle.TextScaled = true
CarryTitle.Parent = CarryPanel

local PlaceBtn = Instance.new("TextButton")
PlaceBtn.Size = UDim2.new(0.47, 0, 0, 36)
PlaceBtn.Position = UDim2.new(0.02, 0, 0, 38)
PlaceBtn.BackgroundColor3 = Color3.fromRGB(45, 165, 85)
PlaceBtn.Text = "Taruh ke Base"
PlaceBtn.TextColor3 = Color3.new(1, 1, 1)
PlaceBtn.Font = Enum.Font.GothamBold
PlaceBtn.TextScaled = true
PlaceBtn.Parent = CarryPanel
addCorner(PlaceBtn, 8)

PlaceBtn.MouseButton1Click:Connect(function()
	ActionEvent:FireServer("PlaceCarriedAuto")
end)

local SellCarryBtn = Instance.new("TextButton")
SellCarryBtn.Size = UDim2.new(0.47, 0, 0, 36)
SellCarryBtn.Position = UDim2.new(0.51, 0, 0, 38)
SellCarryBtn.BackgroundColor3 = Color3.fromRGB(205, 65, 55)
SellCarryBtn.Text = "Jual ($40)"
SellCarryBtn.TextColor3 = Color3.new(1, 1, 1)
SellCarryBtn.Font = Enum.Font.GothamBold
SellCarryBtn.TextScaled = true
SellCarryBtn.Parent = CarryPanel
addCorner(SellCarryBtn, 8)

SellCarryBtn.MouseButton1Click:Connect(function()
	ActionEvent:FireServer("SellCarried")
end)

-- 4. TOMBOL KUNCI BASE & REBIRTH
local LockBtn = Instance.new("TextButton")
LockBtn.Size = UDim2.new(0, 210, 0, 46)
LockBtn.Position = UDim2.new(0, 16, 1, -62)
LockBtn.BackgroundColor3 = Color3.fromRGB(215, 130, 30)
LockBtn.Text = "Kunci Base (30 dtk)"
LockBtn.TextColor3 = Color3.new(1, 1, 1)
LockBtn.Font = Enum.Font.FredokaOne
LockBtn.TextScaled = true
LockBtn.Parent = ScreenGui
addCorner(LockBtn, 10)
addStroke(LockBtn, Color3.fromRGB(255, 220, 120), 2)

LockBtn.MouseButton1Click:Connect(function()
	ActionEvent:FireServer("LockBase")
end)

local RebirthBtn = Instance.new("TextButton")
RebirthBtn.Size = UDim2.new(0, 230, 0, 46)
RebirthBtn.Position = UDim2.new(1, -246, 1, -62)
RebirthBtn.BackgroundColor3 = Color3.fromRGB(130, 55, 210)
RebirthBtn.Text = "Rebirth ($100.000)"
RebirthBtn.TextColor3 = Color3.new(1, 1, 1)
RebirthBtn.Font = Enum.Font.FredokaOne
RebirthBtn.TextScaled = true
RebirthBtn.Parent = ScreenGui
addCorner(RebirthBtn, 10)
addStroke(RebirthBtn, Color3.fromRGB(210, 150, 255), 2)

RebirthBtn.MouseButton1Click:Connect(function()
	ActionEvent:FireServer("Rebirth")
end)

-- 5. UPDATE TAMPILAN REAL-TIME dari server.
UpdateStateEvent.OnClientEvent:Connect(function(data)
	MyBaseIndex = data.BaseIndex
	MoneyLabel.Text = "$" .. tostring(data.Money)
	IncomeLabel.Text = "+$" .. data.Income .. "/s - Rebirth " .. data.Rebirths .. "x"
	RebirthBtn.Text = "Rebirth ($" .. data.RebirthCost .. ")"

	if data.IsLocked then
		LockBtn.Text = "Terkunci (" .. data.LockRemaining .. " dtk)"
		LockBtn.BackgroundColor3 = Color3.fromRGB(180, 45, 45)
	else
		LockBtn.Text = "Kunci Base (30 dtk)"
		LockBtn.BackgroundColor3 = Color3.fromRGB(215, 130, 30)
	end

	if data.CarriedItem then
		CarryPanel.Visible = true
		CarryTitle.Text = "Memegang: " .. data.CarriedItem.Name .. " (+$" .. data.CarriedItem.Income .. "/s)"
		SellCarryBtn.Text = "Jual ($" .. data.CarriedItem.SellPrice .. ")"
	else
		CarryPanel.Visible = false
	end

	BaseTitle.Text = "Base " .. tostring(data.BaseIndex or "-") .. " (" .. #data.Slots .. "/6) - Klik Jual 50%"
end)

-- 6. MUSIK LATAR (BGM) + TOMBOL MUTE
local BGM_PLAYLIST = {
	"rbxassetid://9043887091"
}

local bgmSound = Instance.new("Sound")
bgmSound.Name = "PasarNusantaraBGM"
bgmSound.Volume = 0.35
bgmSound.Looped = false
bgmSound.Parent = SoundService

local isMuted = false
local currentTrackIndex = 1

local function playNextTrack()
	if currentTrackIndex > #BGM_PLAYLIST then
		currentTrackIndex = 1
	end
	bgmSound.SoundId = BGM_PLAYLIST[currentTrackIndex]
	bgmSound:Play()
	currentTrackIndex += 1
end

bgmSound.Ended:Connect(playNextTrack)
playNextTrack()

-- Penjaga lagu: kalau lagu mati mendadak (asset gagal load / Ended tidak jalan), nyalakan lagi.
local lastPlayAttempt = os.clock()
local origPlayNext = playNextTrack
playNextTrack = function()
	lastPlayAttempt = os.clock()
	origPlayNext()
end
task.spawn(function()
	while true do
		task.wait(5)
		if not isMuted and not bgmSound.IsPlaying and (os.clock() - lastPlayAttempt) > 3 then
			playNextTrack()
		end
	end
end)

local MuteBtn = Instance.new("TextButton")
MuteBtn.Size = UDim2.new(0, 125, 0, 38)
MuteBtn.Position = UDim2.new(1, -141, 0, 16)
MuteBtn.BackgroundColor3 = Color3.fromRGB(25, 22, 20)
MuteBtn.BackgroundTransparency = 0.15
MuteBtn.Text = "Musik: ON"
MuteBtn.TextColor3 = Color3.fromRGB(255, 220, 90)
MuteBtn.Font = Enum.Font.GothamBold
MuteBtn.TextScaled = true
MuteBtn.Parent = ScreenGui
addCorner(MuteBtn, 10)
addStroke(MuteBtn, Color3.fromRGB(255, 195, 50), 2)

MuteBtn.MouseButton1Click:Connect(function()
	isMuted = not isMuted
	bgmSound.Volume = isMuted and 0 or 0.35
	MuteBtn.Text = isMuted and "Musik: OFF" or "Musik: ON"
	MuteBtn.TextColor3 = isMuted and Color3.fromRGB(180, 180, 180) or Color3.fromRGB(255, 220, 90)
end)

-- 7. SISTEM LARI (SPRINT) PC & MOBILE — tombol Shift di PC, tombol di layar sentuh.
-- Lari menaikkan WalkSpeed dan melebarkan FOV; kembali normal saat dilepas.
local WALK_SPEED = 16
local SPRINT_SPEED = 28
local NORMAL_FOV = 70
local SPRINT_FOV = 80

local isSprinting = false
local camera = workspace.CurrentCamera

local SprintBtn = Instance.new("TextButton")
SprintBtn.Size = UDim2.new(0, 145, 0, 44)
SprintBtn.Position = UDim2.new(1, -161, 1, -116)
SprintBtn.BackgroundColor3 = Color3.fromRGB(45, 135, 225)
SprintBtn.Text = "Lari [Shift]"
SprintBtn.TextColor3 = Color3.new(1, 1, 1)
SprintBtn.Font = Enum.Font.FredokaOne
SprintBtn.TextScaled = true
SprintBtn.Parent = ScreenGui
addCorner(SprintBtn, 10)
addStroke(SprintBtn, Color3.fromRGB(140, 210, 255), 2)

local function setSprint(active)
	isSprinting = active
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = isSprinting and SPRINT_SPEED or WALK_SPEED
	end

	local targetFov = isSprinting and SPRINT_FOV or NORMAL_FOV
	TweenService:Create(camera, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = targetFov
	}):Play()

	if isSprinting then
		SprintBtn.Text = "Sedang Lari"
		SprintBtn.BackgroundColor3 = Color3.fromRGB(235, 145, 30)
	else
		SprintBtn.Text = "Lari [Shift]"
		SprintBtn.BackgroundColor3 = Color3.fromRGB(45, 135, 225)
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setSprint(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setSprint(false)
	end
end)

SprintBtn.MouseButton1Click:Connect(function()
	setSprint(not isSprinting)
end)

player.CharacterAdded:Connect(function(char)
	local hum = char:WaitForChild("Humanoid")
	hum.WalkSpeed = isSprinting and SPRINT_SPEED or WALK_SPEED
end)

-- 8. PASAR TUMPAH — banner peringatan + hitung mundur (dari server).
local FloodPhase = "Idle"
local FloodSeconds = 0

local function formatFloodTime(sec)
	local m = math.floor(sec / 60)
	local s = sec % 60
	return string.format("%d:%02d", m, s)
end

local function refreshFloodBanner()
	if FloodPhase == "Warning" then
		FloodBannerLabel.Text = "PASAR TUMPAH! Banjir dalam " .. FloodSeconds .. " dtk - yang di luar base bisa hanyut!"
		FloodBannerLabel.TextColor3 = Color3.fromRGB(255, 90, 60)
	elseif FloodPhase == "Flooding" then
		FloodBannerLabel.Text = "BANJIR! Lari ke base!"
		FloodBannerLabel.TextColor3 = Color3.fromRGB(90, 170, 255)
	elseif FloodPhase == "Scramble" then
		FloodBannerLabel.Text = "Peti bermunculan! Rebut peti sebelum hilang! (" .. formatFloodTime(FloodSeconds) .. ")"
		FloodBannerLabel.TextColor3 = Color3.fromRGB(255, 220, 90)
	else
		FloodBannerLabel.Text = "Pasar Tumpah: " .. formatFloodTime(FloodSeconds)
		FloodBannerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	end
end

FloodEvent.OnClientEvent:Connect(function(phase, seconds)
	FloodPhase = phase
	FloodSeconds = seconds or 0
	refreshFloodBanner()
end)

task.spawn(function()
	while true do
		task.wait(1)
		if FloodSeconds > 0 then
			FloodSeconds -= 1
			refreshFloodBanner()
		end
	end
end)

-- FIXED26 STEAL: prompt pedestal di base orang lain tampil "Curi Brainrot"
-- (bukan "Jual $X") supaya pemain tahu dia bisa mencuri. Perubahan properti
-- prompt di client hanya berlaku lokal untuk pemain itu sendiri.
ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
	if MyBaseIndex == nil then return end
	local pedestal = prompt.Parent
	if not pedestal or not pedestal:IsA("BasePart") then return end
	local baseFolder = pedestal.Parent
	if not baseFolder or not baseFolder.Name:match("^Base_%d+$") then return end
	local baseIndex = tonumber(baseFolder.Name:match("Base_(%d+)"))
	if not baseIndex or baseIndex == MyBaseIndex then return end
	if prompt.ObjectText:find("Kosong") then return end
	prompt.ActionText = "Curi Brainrot"
end)
