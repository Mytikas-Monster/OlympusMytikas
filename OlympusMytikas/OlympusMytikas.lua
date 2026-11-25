-- Olympus Mytikas - one window, two guild tools.
--
-- This file is only the shell. It builds a single window with two tabs and one
-- minimap button, then hands each tab its addon's existing window as a child.
-- It never changes either addon's rules, commands, guild protocol or data:
--   Recruit      = OlympusRecruit 1.6.5  (global OlympusRecruit_BuildUI)
--   Kill on Sight = KillOnSight 1.5.4     (global KillOnSight_BuildUI)
-- Both addon files still work on their own: every shell call is guarded, so
-- running either one without this file behaves exactly as it always did.

local ADDON = ...
OlympusMytikasLoaded = true

if type(OlympusMytikasDB) ~= "table" then OlympusMytikasDB = {} end
if type(OlympusMytikasDB.minimap) ~= "boolean" then OlympusMytikasDB.minimap = true end
if type(OlympusMytikasDB.minimapAngle) ~= "number" then OlympusMytikasDB.minimapAngle = 200 end
-- The button used to slide on a fixed 80 px ring (angle only). The distance is
-- saved too now, so it can be dragged into the middle of the minimap or out
-- past the rim. Old profiles without a radius keep the familiar 80.
if type(OlympusMytikasDB.minimapRadius) ~= "number" then OlympusMytikasDB.minimapRadius = 80 end
if OlympusMytikasDB.lastTab ~= "recruit" and OlympusMytikasDB.lastTab ~= "kos" then
	OlympusMytikasDB.lastTab = "recruit"
end
-- Saved with the addon's account-wide settings: the KoS half of this window can
-- be switched off without touching Recruit. Old profiles with no flag keep it on.
if type(OlympusMytikasDB.kosEnabled) ~= "boolean" then OlympusMytikasDB.kosEnabled = true end

-- Quiet the Olympus family's own local chat. Addon messages are printed straight
-- into the chat frame (they are not chat events), so the only reliable place to
-- stop them is AddMessage itself. Replies to a slash command are let through by
-- wrapping the command handlers: while one is running, commandDepth > 0.
local commandDepth = 0
local hiddenChat = {}
local HIDDEN_MAX = 50
local wrappedCommands = {}

local function IsSecret(value)
	return type(issecretvalue) == "function" and issecretvalue(value)
end

local function StripColors(s)
	return s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

local function IsOlympusLocal(text)
	if IsSecret(text) or type(text) ~= "string" then return false end
	local s = StripColors(text):gsub("^%s+", "")
	return s:match("^Olympus:") ~= nil
		or s:match("^Olympus%s") ~= nil
		or s:match("^%[Olympus") ~= nil
		or s:match("^%[KoS%]") ~= nil
		or s:match("^Montgomery's Tool Box:") ~= nil
		or s:match("^Bones:") ~= nil
		or s:match("^%[Arena") ~= nil
		or s:match("^%[Arène") ~= nil
		or s:match("^%[Арена") ~= nil
end

local function RecordHidden(text)
	if text == nil or text == "" then return end
	hiddenChat[#hiddenChat + 1] = tostring(text)
	if #hiddenChat > HIDDEN_MAX then table.remove(hiddenChat, 1) end
end

local function ShouldWrapCommand(key)
	if type(key) ~= "string" then return false end
	if key:find("OLYMPUS", 1, true) or key:find("KOS", 1, true) then return true end
	for i = 1, 12 do
		local alias = _G["SLASH_" .. key .. i]
		if type(alias) ~= "string" then break end
		local a = alias:lower()
		if a:match("^/om") or a:match("^/kos") or a:match("^/mytikas") or a:match("^/oly") then
			return true
		end
	end
	return false
end

local function FinishCommand(ok, ...)
	commandDepth = commandDepth - 1
	if not ok then error((...), 0) end
	return ...
end

local function WrapCommand(key)
	if type(SlashCmdList) ~= "table" then return end
	local fn = SlashCmdList[key]
	if type(fn) ~= "function" or wrappedCommands[key] == fn then return end
	local original = fn
	SlashCmdList[key] = function(...)
		commandDepth = commandDepth + 1
		return FinishCommand(pcall(original, ...))
	end
	wrappedCommands[key] = SlashCmdList[key]
end

local function WrapCommands()
	if type(SlashCmdList) ~= "table" then return end
	for key in pairs(SlashCmdList) do
		if ShouldWrapCommand(key) then WrapCommand(key) end
	end
end

local realPrint = print
if type(realPrint) == "function" then
	print = function(...)
		local first = ...
		if commandDepth > 0 or IsSecret(first) or type(first) ~= "string" then return realPrint(...) end
		local n = select("#", ...)
		if not IsOlympusLocal(n > 1 and first .. " " or first) then return realPrint(...) end
		local parts = { first }
		for i = 2, n do
			local value = select(i, ...)
			if IsSecret(value) then return realPrint(...) end
			-- Objects may implement their own conversion in the game's print function.
			local kind = type(value)
			if kind ~= "string" and kind ~= "number" and kind ~= "boolean" and kind ~= "nil" then
				return realPrint(...)
			end
			parts[i] = tostring(value)
		end
		RecordHidden(table.concat(parts, " "))
	end
end

if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
	local realAddMessage = DEFAULT_CHAT_FRAME.AddMessage
	DEFAULT_CHAT_FRAME.AddMessage = function(self, text, ...)
		if commandDepth == 0 and IsOlympusLocal(text) then
			for i = 1, select("#", ...) do
				if IsSecret((select(i, ...))) then return realAddMessage(self, text, ...) end
			end
			RecordHidden(text)
			return
		end
		return realAddMessage(self, text, ...)
	end
end

OlympusMytikasChat = { hidden = hiddenChat, wrap = WrapCommands, isOlympus = IsOlympusLocal }
WrapCommands()

local GOLD  = { 0.95, 0.89, 0.62 }
local AMBER = { 0.79, 0.58, 0.33 }
local DIM   = { 0.70, 0.63, 0.54 }
local INK   = { 0.055, 0.032, 0.026 }

local WIN_W, WIN_H = 560, 850
local CONTENT_W, CONTENT_H = 540, 760

-- The one skin for BOTH tabs: the game art the kill board already used.
-- Recruit's own TGA backdrop and hand-drawn buttons are gone in the merged
-- addon, so nothing in either panel paints a competing window background.
local PAGE_ART = "Professions-QualityWindow-Background"
local INSET_ART = "heavybronze-frame-background"
local PORTRAIT  = "Interface\\AddOns\\OlympusMytikas\\Media\\olympus-logo"
local KOS_PORTRAIT = "Interface\\AddOns\\OlympusMytikas\\Media\\emblem"

local function HasAtlas(name)
	if type(C_Texture) ~= "table" or type(C_Texture.GetAtlasInfo) ~= "function" then return false end
	local ok, info = pcall(C_Texture.GetAtlasInfo, name)
	return ok and info ~= nil
end

local function ApplyPageArt(f)
	if not HasAtlas(PAGE_ART) then return end
	local anchor = type(f.Bg) == "table" and f.Bg or f
	if not f.koPage then f.koPage = f:CreateTexture(nil, "BACKGROUND", nil, 1) end
	f.koPage:SetAllPoints(anchor)
	if pcall(f.koPage.SetAtlas, f.koPage, PAGE_ART) then
		if type(f.Bg) == "table" then
			if not f.koFill then
				f.koFill = f:CreateTexture(nil, "BACKGROUND", nil, 0)
				f.koFill:SetAllPoints(f.Bg)
				f.koFill:SetColorTexture(0.082, 0.086, 0.059)
			end
			f.Bg:Hide()
		end
		if f.TopTileStreaks then pcall(function() f.TopTileStreaks:Hide() end) end
	end
end

local shell, content, tabRecruit, tabKos, kosToggle, mapBtn, dragging
local panels = {}
local active = nil

local function Say(msg, visible)
	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		if visible then commandDepth = commandDepth + 1 end
		pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, "|cffca9455Olympus|r: " .. tostring(msg))
		if visible then commandDepth = commandDepth - 1 end
	end
end

local function KosEnabled()
	return OlympusMytikasDB.kosEnabled ~= false
end

-- The button is the only control the player needs. Killing the KoS side here
-- also tells KillOnSight.lua to stop syncing, tracking deaths and drawing marks.
local function SetKosEnabled(on)
	on = on and true or false
	OlympusMytikasDB.kosEnabled = on
	if kosToggle then kosToggle:SetText(on and "KoS ON" or "KoS OFF") end
	if tabKos then tabKos:SetShown(on) end
	if not on and active == "kos" then OlympusMytikas_Show("recruit") end
	if type(KillOnSight_SetEnabled) == "function" then pcall(KillOnSight_SetEnabled, on) end
	Say("Kill on Sight is now " .. (on and "ON" or "OFF") .. ".", true)
	return on
end

OlympusMytikas_KoS = { enabled = KosEnabled, set = SetKosEnabled }

-- The game's own portrait frame, like the kill board uses, so the merged window
-- reads as part of Forever. Fallbacks keep it working on any interface version.
local function MyVersion()
	local v
	if type(C_AddOns) == "table" and type(C_AddOns.GetAddOnMetadata) == "function" then
		v = C_AddOns.GetAddOnMetadata(ADDON, "Version")
	end
	if (type(v) ~= "string" or v == "") and type(GetAddOnMetadata) == "function" then
		v = GetAddOnMetadata(ADDON, "Version")
	end
	if type(v) ~= "string" or v == "" then v = "1.1.4" end
	return v
end

local function BuildShell()
	if shell then return shell end
	local f
	if pcall(function() f = CreateFrame("Frame", "OlympusMytikasFrame", UIParent, "PortraitFrameTemplate") end)
		and f and f.CloseButton then
		-- the template gave us chrome
	elseif pcall(function() f = CreateFrame("Frame", "OlympusMytikasFrame", UIParent, "BasicFrameTemplateWithInset") end)
		and f then
		-- a simpler game frame
	else
		f = CreateFrame("Frame", "OlympusMytikasFrame", UIParent)
	end
	f:SetSize(WIN_W, WIN_H)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
	f:SetFrameStrata("DIALOG")
	if f.SetToplevel then pcall(f.SetToplevel, f, true) end
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

	if f.SetTitle then
		pcall(f.SetTitle, f, "Olympus Mytikas")
	elseif f.TitleText then
		f.TitleText:SetText("Olympus Mytikas")
	end
	if f.CloseButton then
		f.CloseButton:SetScript("OnClick", function() f:Hide() end)
	elseif f.closeBox then
		f.closeBox:SetScript("OnClick", function() f:Hide() end)
	end

	-- The one portrait: Olympus' white mountain on navy, not the kill-board emblem.
	if f.SetPortraitToAsset then pcall(f.SetPortraitToAsset, f, PORTRAIT) end

	-- This is the only window art in the addon: both tabs sit on top of it.
	ApplyPageArt(f)

	-- A plain backing for the no-template case; one flat fill, no sliced art.
	if not f.Bg and not f.koPage then
		local edge = f:CreateTexture(nil, "BORDER")
		edge:SetColorTexture(0.62, 0.42, 0.24, 0.90)
		edge:SetAllPoints(f)
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetColorTexture(INK[1], INK[2], INK[3], 0.96)
		bg:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -3)
		bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
	end

	local bar = CreateFrame("Frame", nil, f)
	bar:SetSize(CONTENT_W, 28)
	bar:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -44)

	local function MakeTab(label, x, width, key)
		local b = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
		b:SetSize(width, 24)
		b:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
		b:SetText(label)
		b:SetScript("OnClick", function() OlympusMytikas_Show(key) end)
		return b
	end
	tabRecruit = MakeTab("Recruit", 0, 74, "recruit")
	tabKos = MakeTab("Kill on Sight", 78, 96, "kos")
	tabKos:SetShown(KosEnabled())

	-- Right of the two tabs: a plain on/off switch for the KoS half. Recruit is
	-- always available; this only stops the kill board, its chat and its syncing.
	kosToggle = CreateFrame("Button", "OlympusMytikasKosToggle", bar, "UIPanelButtonTemplate")
	kosToggle:SetSize(78, 24)
	kosToggle:SetPoint("TOPLEFT", bar, "TOPLEFT", 178, 0)
	kosToggle:SetText(KosEnabled() and "KoS ON" or "KoS OFF")
	kosToggle:SetScript("OnClick", function() SetKosEnabled(not KosEnabled()) end)
	kosToggle:SetScript("OnEnter", function(self)
		if type(GameTooltip) ~= "table" then return end
		pcall(function()
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:AddLine("Kill on Sight: " .. (KosEnabled() and "ON" or "OFF"), GOLD[1], GOLD[2], GOLD[3])
			GameTooltip:AddLine("Click to turn it " .. (KosEnabled() and "off" or "on") .. ".", 1, 1, 1)
			GameTooltip:AddLine("Off = no kill notices, no board sync, no badges or pins. Recruit keeps working.", DIM[1], DIM[2], DIM[3])
			GameTooltip:Show()
		end)
	end)
	kosToggle:SetScript("OnLeave", function()
		if type(GameTooltip) == "table" then pcall(function() GameTooltip:Hide() end) end
	end)

	local version = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	version:SetPoint("LEFT", kosToggle, "RIGHT", 8, 0)
	version:SetText("v" .. MyVersion())
	local url = CreateFrame("EditBox", nil, bar, "InputBoxTemplate")
	url:SetPoint("LEFT", version, "RIGHT", 10, 0)
	url:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
	url:SetHeight(22)
	url:SetAutoFocus(false)
	local memberHome = "https://app.mytikas.monster/account.html"
	url:SetText(memberHome)
	url:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	url:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	url:SetScript("OnEditFocusLost", function(self) self:SetText(memberHome) end)

	content = CreateFrame("Frame", nil, f)
	content:SetSize(CONTENT_W, CONTENT_H)
	content:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -76)

	if type(UISpecialFrames) == "table" then
		local exists = false
		for i = 1, #UISpecialFrames do
			if UISpecialFrames[i] == "OlympusMytikasFrame" then exists = true end
		end
		if not exists then UISpecialFrames[#UISpecialFrames + 1] = "OlympusMytikasFrame" end
	end

	shell = f
	return f
end

-- Neither panel is allowed to bring its own window: the shell above is the
-- only frame with art, a title or a close button.
local function HideChrome(child)
	if not child then return end
	if child.CloseButton then child.CloseButton:Hide() end
	if child.closeBox then child.closeBox:Hide() end
	if child.TitleText then child.TitleText:Hide() end
	if child.titleText then child.titleText:Hide() end
	if child.koPage then child.koPage:Hide() end
	if child.koFill then child.koFill:Hide() end
	if child.art then child.art:Hide() end
	if child.glow then child.glow:Hide() end
	-- Portrait art stays: the KoS page keeps its own emblem in its own circle.
end

-- Take an addon's already-built window and make it a page of our window.
local function Embed(key, child)
	if not child or panels[key] == child then return end
	HideChrome(child)
	child:SetParent(content)
	child:ClearAllPoints()
	if key == "recruit" then
		child:SetPoint("TOPLEFT", content, "TOPLEFT", 30, -8)
		if child.closeBox then child.closeBox:Hide() end
	else
		child:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
		if child.CloseButton then child.CloseButton:Hide() end
		if child.closeBox then child.closeBox:Hide() end
	end
	-- Re-apply after embedding: this is the KoS circle's picture.
	if key == "kos" and child.SetPortraitToAsset then
		pcall(child.SetPortraitToAsset, child, KOS_PORTRAIT)
	end
	-- Tabs and the shell's own close button own the window now.
	child:SetMovable(false)
	if child.RegisterForDrag then pcall(child.RegisterForDrag, child) end
	if type(UISpecialFrames) == "table" then
		local name = child.GetName and child:GetName() or nil
		for i = #UISpecialFrames, 1, -1 do
			if name and UISpecialFrames[i] == name then table.remove(UISpecialFrames, i) end
		end
	end
	panels[key] = child
end

local function EnsurePanel(key)
	if panels[key] then return panels[key] end
	local builder = key == "recruit" and OlympusRecruit_BuildUI or KillOnSight_BuildUI
	if type(builder) ~= "function" then return nil end
	local ok, child = pcall(builder)
	if not ok or not child then return nil end
	Embed(key, child)
	return child
end

-- Open the merged window, optionally on a named tab. Addon windows are passed
-- in by their own toggle functions so they are only built when first needed.
OlympusMytikas_Show = function(tab, child)
	if tab ~= "recruit" and tab ~= "kos" then tab = OlympusMytikasDB.lastTab end
	if tab ~= "recruit" and tab ~= "kos" then tab = "recruit" end
	if tab == "kos" and not KosEnabled() then tab = "recruit" end
	local f = BuildShell()
	if child then Embed(tab, child) end
	EnsurePanel(tab)
	OlympusMytikasDB.lastTab = tab
	active = tab
	for key, panel in pairs(panels) do panel:SetShown(key == tab) end
	tabRecruit:SetAlpha(tab == "recruit" and 1 or 0.55)
	tabKos:SetAlpha(tab == "kos" and 1 or 0.55)
	f:Show()
	if panels[tab] then panels[tab]:Show() end
	return f
end

-- One button for both addons. The addons skip building their own while the
-- shell is loaded; this removes any that are already there from an old reload.
local function HideAddonButtons()
	for _, name in ipairs({ "OlympusRecruitMinimapButton", "KillOnSightMinimap" }) do
		local b = _G[name]
		if b and b.Hide then pcall(b.Hide, b) end
	end
end

-- Distance from the minimap's centre: 0 = dead centre, 120 = well outside the
-- rim. The old fixed-ring value was 80.
local MAP_R_MIN, MAP_R_MAX = 0, 120

local function PlaceMapButton()
	if not mapBtn then return end
	local a = math.rad(tonumber(OlympusMytikasDB.minimapAngle) or 200)
	local r = tonumber(OlympusMytikasDB.minimapRadius) or 80
	mapBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function BuildMapButton()
	-- No type(Minimap) gate: some Forever builds expose global frames as
	-- userdata, and that check used to make the whole button vanish silently.
	if mapBtn or not Minimap then return mapBtn end
	-- Direct child of Minimap: OneForAll and other button collectors scan
	-- Minimap's children. The invisible-button bug was the missing first
	-- anchor (fixed below), not the parent, so both setups work now.
	local b = CreateFrame("Button", "OlympusMytikasMinimap", Minimap)
	-- The game's own minimap-button chrome, the same geometry Olympus uses,
	-- plus a solid plate so it is visible even before any texture loads.
	local k = 32 / 31
	b:SetSize(32, 32)
	b:SetFrameStrata("HIGH")
	b:SetFrameLevel(100)
	b:SetClampedToScreen(true)
	b:RegisterForDrag("LeftButton")
	-- Without this the client never delivers "RightButton" to OnClick.
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	local plate = b:CreateTexture(nil, "BACKGROUND")
	plate:SetColorTexture(0.055, 0.032, 0.026, 0.96)
	plate:SetSize(24 * k, 24 * k)
	plate:SetPoint("TOPLEFT", 4 * k, -4 * k)

	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20 * k, 20 * k)
	bg:SetPoint("TOPLEFT", 6 * k, -6 * k)

	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\AddOns\\OlympusMytikas\\Media\\minimap")
	icon:SetSize(18 * k, 18 * k)
	icon:SetPoint("TOPLEFT", 7 * k, -7 * k)
	if icon.SetMask then pcall(icon.SetMask, icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask") end

	local ring = b:CreateTexture(nil, "OVERLAY")
	ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	ring:SetSize(53 * k, 53 * k)
	ring:SetPoint("TOPLEFT")
	if b.SetHighlightTexture then
		pcall(b.SetHighlightTexture, b, "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	end
	b.icon = icon

	b:SetScript("OnEnter", function(self)
		if self.icon then self.icon:SetVertexColor(1, 0.93, 0.72) end
		if type(GameTooltip) ~= "table" then return end
		pcall(function()
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:AddLine("Olympus Mytikas", GOLD[1], GOLD[2], GOLD[3])
			GameTooltip:AddLine("Recruit + Kill on Sight in one window", 1, 1, 1)
			GameTooltip:AddLine("Click: open the window", DIM[1], DIM[2], DIM[3])
			GameTooltip:AddLine("Right click: post a random ad to /1 and /2", DIM[1], DIM[2], DIM[3])
			GameTooltip:AddLine("Drag: move me anywhere in or around the minimap", DIM[1], DIM[2], DIM[3])
			GameTooltip:Show()
		end)
	end)
	b:SetScript("OnLeave", function(self)
		if self.icon then self.icon:SetVertexColor(1, 1, 1) end
		if type(GameTooltip) == "table" then pcall(function() GameTooltip:Hide() end) end
	end)
	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			-- Exactly the old Recruit right click: one ad to /1 and /2.
			if type(SlashCmdList) == "table" and type(SlashCmdList.OLYMPUSRECRUIT) == "function" then
				pcall(SlashCmdList.OLYMPUSRECRUIT, "")
			elseif type(OlympusRecruit_Post) == "function" then
				pcall(OlympusRecruit_Post)
			end
		else
			OlympusMytikas_Show(OlympusMytikasDB.lastTab)
		end
	end)
	b:SetScript("OnDragStart", function() dragging = true end)
	b:SetScript("OnDragStop", function() dragging = false end)
	b:SetScript("OnUpdate", function(self, dt)
		if not dragging then return end
		local mx, my = Minimap:GetCenter()
		local cx, cy = GetCursorPosition()
		if not (mx and my and cx and cy) then return end
		local scale = Minimap.GetEffectiveScale and Minimap:GetEffectiveScale() or 1
		if scale and scale ~= 0 then cx, cy = cx / scale, cy / scale end
		local dx, dy = cx - mx, cy - my
		-- Full 360 degrees, and the distance is saved as well as the angle, so
		-- the button can be dragged in towards the centre or out past the rim.
		OlympusMytikasDB.minimapAngle = math.deg(math.atan2(dy, dx))
		local r = math.sqrt(dx * dx + dy * dy)
		if r < MAP_R_MIN then r = MAP_R_MIN elseif r > MAP_R_MAX then r = MAP_R_MAX end
		OlympusMytikasDB.minimapRadius = r
		PlaceMapButton()
	end)
	-- Set the global BEFORE placing: PlaceMapButton() bails out while mapBtn is
	-- nil, so the old order left this freshly built frame with no anchor at all
	-- (built + shown, GetCenter() nil, nothing on screen).
	mapBtn = b
	PlaceMapButton()
	return b
end

local function ShowMapButton(on)
	OlympusMytikasDB.minimap = on and true or false
	if on then
		if not mapBtn then BuildMapButton() end
		if mapBtn and mapBtn.Show then pcall(mapBtn.Show, mapBtn) end
	elseif mapBtn and mapBtn.Hide then
		pcall(mapBtn.Hide, mapBtn)
	end
	return true
end

-- /om minimap and /kos minimap both drive this one button in the merged addon.
OlympusMytikas_Minimap = ShowMapButton

-- Re-assert the one button on every entry path. Some Forever clients fire
-- PLAYER_ENTERING_WORLD before the minimap is ready during PLAYER_LOGIN, so
-- building on both (and again on a short timer) is safer than one event.
local function EnsureMapButton()
	if OlympusMytikasDB.minimap == false then return nil end
	local existed = mapBtn ~= nil
	local b = BuildMapButton()
	if not b then return nil end
	-- If OneForAll has already collected the button into its bar, do not
	-- re-anchor or re-show it on a later tick; its bar owns the position now.
	local stillOnMinimap = false
	if b.GetParent then
		local ok, p = pcall(b.GetParent, b)
		stillOnMinimap = ok and p == Minimap
	end
	if stillOnMinimap and b.GetPoint then
		-- Heal a button built by an older version: shown but with no point.
		local ok, point = pcall(b.GetPoint, b, "CENTER")
		if not ok or not point then PlaceMapButton() end
	end
	if not existed then
		if b.SetAlpha then pcall(b.SetAlpha, b, 1) end
		if b.Show then pcall(b.Show, b) end
	end
	return b
end

local function CenterOf(f)
	if not f or not f.GetCenter then return nil end
	local ok, x, y = pcall(f.GetCenter, f)
	if ok then return x, y end
end

-- Written into the saved variables so a /reload leaves behind hard evidence of
-- what the client actually saw, even if the chat line scrolls away.
local function RecordMinimapCheck(tag)
	local shown = "unknown"
	if mapBtn and mapBtn.IsShown then
		local ok, v = pcall(mapBtn.IsShown, mapBtn)
		if ok then shown = tostring(v) end
	end
	local mx, my = CenterOf(Minimap)
	local bx, by = CenterOf(mapBtn)
	local parentName = "none"
	if mapBtn and mapBtn.GetParent then
		local p = mapBtn:GetParent()
		if p and p.GetName then parentName = tostring(p:GetName()) end
	end
	OlympusMytikasDB.minimapCheck = {
		tag = tag,
		at = type(time) == "function" and time() or 0,
		minimapType = type(Minimap),
		built = mapBtn ~= nil,
		shown = shown,
		setting = OlympusMytikasDB.minimap == false and "OFF" or "ON",
		angle = OlympusMytikasDB.minimapAngle,
		radius = OlympusMytikasDB.minimapRadius or 80,
		mapCenter = mx and string.format("%.1f,%.1f", mx, my) or "nil",
		buttonCenter = bx and string.format("%.1f,%.1f", bx, by) or "nil",
		parent = parentName,
		strata = mapBtn and mapBtn.GetFrameStrata and tostring(mapBtn:GetFrameStrata()) or "?",
	}
end

local function TidyMapButtons()
	HideAddonButtons()
	EnsureMapButton()
	RecordMinimapCheck("auto")
end

-- ============================================================== version check
-- The same idea the other guild addons use: ask the guild (and group) on login
-- which build everyone runs. Anyone on a newer build answers once, and we print
-- a single yellow note. Addon messages are allowed from timers on Forever,
-- unlike chat sends, so this stays silent and cannot trip the click rule.
local VER_PREFIX = "OMVER"
local VER_ASK_AFTER = 15
local VER_LOGIN_WINDOW = 180

local function VerNow()
	if type(GetTime) == "function" then return GetTime() end
	return 0
end

local function ParseVersion(v)
	if type(v) ~= "string" then return nil end
	if #v > 26 then return nil end
	local major, minor, patch = v:match("^(%d+)%.(%d+)%.(%d+)$")
	if major then return { tonumber(major), tonumber(minor), tonumber(patch) } end
end

local function NewerVersion(a, b)
	for i = 1, math.max(#a, #b) do
		local x, y = a[i] or 0, b[i] or 0
		if x ~= y then return x > y end
	end
	return false
end

local myVersion = MyVersion()
local myNums = ParseVersion(myVersion) or { 0 }
local verLoginAt, verLastSeen
local verTold, verAnsweredAt, verLastAnswer = {}, {}, {}

local function VersionEnabled()
	return OlympusMytikasDB.versionNotice ~= false
end

local function AnnounceVersion(v)
	if verTold[v] then return end
	verTold[v] = true
	Say("|cffffd100A newer Olympus Mytikas version is available: " .. tostring(v)
		.. " (you have " .. myVersion .. ").|r", true)
end

local function ConfirmVersion(v)
	if not VersionEnabled() then return end
	if verLoginAt and VerNow() - verLoginAt <= VER_LOGIN_WINDOW then
		AnnounceVersion(v)
		return
	end
	-- Too late in the session: remember the biggest newer build for next login.
	local old = ParseVersion(OlympusMytikasDB.pendingNewVersion)
	local t = ParseVersion(v)
	if t and (not old or NewerVersion(t, old)) then
		OlympusMytikasDB.pendingNewVersion = v
	end
end

local function SendVersion(msg, dist)
	if type(C_ChatInfo) ~= "table" or type(C_ChatInfo.SendAddonMessage) ~= "function" then return end
	pcall(C_ChatInfo.SendAddonMessage, VER_PREFIX, msg, dist)
end

local function AskVersion()
	local q = "Q\t" .. myVersion
	if type(IsInGuild) == "function" and IsInGuild() then SendVersion(q, "GUILD") end
	if type(IsInRaid) == "function" and IsInRaid() then
		SendVersion(q, "RAID")
	elseif type(IsInGroup) == "function" and IsInGroup() then
		SendVersion(q, "PARTY")
	end
end

local function AnswerVersion(dist)
	if not dist then return end
	local t = VerNow()
	if verLastAnswer[dist] and t - verLastAnswer[dist] < 60 then return end
	verLastAnswer[dist] = t
	local function go()
		if verAnsweredAt[dist] and VerNow() - verAnsweredAt[dist] < 30 then return end
		SendVersion("V\t" .. myVersion, dist)
	end
	if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
		pcall(C_Timer.After, 1 + math.random() * 5, go)
	else
		go()
	end
end

local function OnVersionMessage(prefix, msg, dist)
	if IsSecret(prefix) or IsSecret(msg) or IsSecret(dist) then return end
	if prefix ~= VER_PREFIX or type(msg) ~= "string" then return end
	if dist ~= "GUILD" and dist ~= "PARTY" and dist ~= "RAID" then return end
	local kind, v = msg:match("^([QV])\t(.+)$")
	local reported = ParseVersion(v)
	if not reported then return end
	if kind == "V" and v == myVersion then verAnsweredAt[dist] = VerNow() end
	if NewerVersion(reported, myNums) then
		local previous = ParseVersion(verLastSeen)
		if not previous or NewerVersion(reported, previous) then verLastSeen = v end
		if not verTold[v] then ConfirmVersion(v) end
	elseif kind == "Q" and NewerVersion(myNums, reported) then
		AnswerVersion(dist)
	end
end

local function RegisterVersionPrefix()
	if type(C_ChatInfo) == "table" and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function" then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, VER_PREFIX)
	end
end

local function StartVersionCheck()
	verLoginAt = VerNow()
	RegisterVersionPrefix()
	if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return end
	pcall(C_Timer.After, 8, function()
		if VersionEnabled() then
			Say("|cffffd100Olympus Mytikas " .. myVersion .. " loaded.|r")
		end
		local p = OlympusMytikasDB.pendingNewVersion
		OlympusMytikasDB.pendingNewVersion = nil
		local t = ParseVersion(p)
		if t and NewerVersion(t, myNums) and VersionEnabled() then AnnounceVersion(p) end
	end)
	pcall(C_Timer.After, VER_ASK_AFTER, AskVersion)
end

-- /om is Recruit's slash command, not ours, so Recruit's handler calls this
-- with the text after "/om". Keep one copy of the logic for both entry points.
local function VersionCommand(arg)
	arg = tostring(arg or ""):lower()
	if arg == "off" then
		OlympusMytikasDB.versionNotice = false
		Say("new-version notice OFF")
	elseif arg == "on" then
		OlympusMytikasDB.versionNotice = true
		Say("new-version notice ON")
	else
		Say("version " .. myVersion .. "; newest seen: " .. (verLastSeen or "none")
			.. "; notice " .. (VersionEnabled() and "ON" or "OFF"))
		AskVersion()
	end
end

OlympusMytikasVersion = {
	prefix = VER_PREFIX,
	mine = myVersion,
	ask = AskVersion,
	onMessage = OnVersionMessage,
	announce = AnnounceVersion,
	command = VersionCommand,
}

-- /mytikas is a shortcut; /om ui and /kos still do what they always did.
SLASH_OLYMPUSMYTIKAS1 = "/mytikas"
SLASH_OLYMPUSMYTIKAS2 = "/omg"
SlashCmdList["OLYMPUSMYTIKAS"] = function(msg)
	local full = tostring(msg or ""):lower()
	local cmd = full:match("^%s*(%S*)") or ""
	local arg = full:match("^%s*%S+%s+(%S*)") or ""
	if cmd == "recruit" or cmd == "om" then
		OlympusMytikas_Show("recruit")
	elseif cmd == "kos" or cmd == "board" then
		OlympusMytikas_Show("kos")
	elseif cmd == "version" or cmd == "ver" then
		VersionCommand(arg)
	elseif cmd == "hidden" or cmd == "chat" then
		Say("hidden Olympus addon messages (oldest first):")
		if #hiddenChat == 0 then
			Say("(none)")
		else
			for i = 1, #hiddenChat do Say(hiddenChat[i]) end
		end
	elseif cmd == "minimap" or cmd == "map" then
		Say("minimap button setting: " .. (OlympusMytikasDB.minimap == false and "OFF" or "ON"))
		Say("button frame: " .. (mapBtn and "built" or "not built"))
		if mapBtn then
			local shown = "unknown"
			if mapBtn.IsShown then
				local ok, v = pcall(mapBtn.IsShown, mapBtn)
				if ok then shown = tostring(v) end
			end
			Say("button shown: " .. shown)
		end
		Say("position: angle " .. tostring(OlympusMytikasDB.minimapAngle)
			.. ", radius " .. tostring(OlympusMytikasDB.minimapRadius or 80))
		local mx, my = CenterOf(Minimap)
		local bx, by = CenterOf(mapBtn)
		Say("map centre: " .. (mx and string.format("%.1f,%.1f", mx, my) or "nil"))
		Say("button centre: " .. (bx and string.format("%.1f,%.1f", bx, by) or "nil"))
		EnsureMapButton()
		RecordMinimapCheck("command")
	else
		OlympusMytikas_Show(OlympusMytikasDB.lastTab)
	end
end

-- Recruit and KoS register their slash commands after this file loads, so wrap
-- them again once PLAYER_LOGIN has seen every addon in the folder.
WrapCommands()

local ev = CreateFrame("Frame")
OlympusMytikasEventFrame = ev   -- exposed for the harness; the game never needs it
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:SetScript("OnEvent", function(_, event, ...)
	local a1, a2, a3, a4 = ...
	if event == "ADDON_LOADED" and a1 ~= ADDON then return end
	if event == "CHAT_MSG_ADDON" then
		pcall(OnVersionMessage, a1, a2, a3, a4)
		return
	end
	if event == "PLAYER_LOGIN" then pcall(StartVersionCheck) end
	if event == "ADDON_LOADED" or event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
		WrapCommands()
		RegisterVersionPrefix()
		TidyMapButtons()
	end
end)

-- A reload can leave the old buttons alive for a moment; put them away quietly
-- and make sure ours is really there once the minimap has settled.
if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
	for _, delay in ipairs({ 1, 3, 8 }) do
		pcall(C_Timer.After, delay, TidyMapButtons)
	end
end

Say("loaded - /om ui and /kos open the same window; /mytikas opens it directly.")
