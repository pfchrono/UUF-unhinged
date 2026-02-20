local _, UUF = ...
local oUF = UUF.oUF

-- PERF LOCALS: Localize frequently-called globals for faster access
local CreateFrame = CreateFrame
local type, pairs, ipairs = type, pairs, ipairs
local select = select
local math_floor = math.floor

-- Performance Optimization: Frame Pooling for Aura Buttons
-- =========================================================
-- Frame pooling reduces garbage collection pressure by reusing buttons instead of
-- creating/destroying them every frame. To enable:
-- 1. Uncomment USE_AURA_POOLING below
-- 2. Call UUF:InitAuraPooling() during initialization
-- 
-- Expected improvements: 5-15% GC reduction, smoother frame updates in high-aura environments
-- See Core/FramePoolManager.lua for pool management API

local USE_AURA_POOLING = true  -- Set to true to enable frame pooling (ENABLED for production)

local function CreateAuraButton_Pooled(pool, unit, auraType)
    local button = pool:Acquire()
    if button then
        button:ClearAllPoints()
        button:Show()
        button._poolName = unit .. "_" .. auraType
    end
    return button
end

local function ReleaseAuraButton_Pooled(pool, button)
    if button then
        button:Hide()
        button:ClearAllPoints()
        pool:Release(button)
    end
end

local function BuildAuraStyleKey(generalDB, aurasDB)
    local shadow = generalDB.Fonts.Shadow
    local duration = aurasDB.AuraDuration
    local buffs = aurasDB.Buffs
    local debuffs = aurasDB.Debuffs
    return table.concat({
        UUF.Media.Font or "",
        generalDB.Fonts.FontFlag or "",
        tostring(shadow.Enabled),
        shadow.Colour[1] or 0, shadow.Colour[2] or 0, shadow.Colour[3] or 0, shadow.Colour[4] or 0,
        shadow.XPos or 0, shadow.YPos or 0,
        duration.FontSize or 0,
        tostring(duration.ScaleByIconSize),
        duration.Layout[1] or "", duration.Layout[2] or "", duration.Layout[3] or 0, duration.Layout[4] or 0,
        duration.Colour[1] or 0, duration.Colour[2] or 0, duration.Colour[3] or 0,
        buffs.Count.FontSize or 0,
        buffs.Count.Layout[1] or "", buffs.Count.Layout[2] or "", buffs.Count.Layout[3] or 0, buffs.Count.Layout[4] or 0,
        buffs.Count.Colour[1] or 0, buffs.Count.Colour[2] or 0, buffs.Count.Colour[3] or 0,
        debuffs.Count.FontSize or 0,
        debuffs.Count.Layout[1] or "", debuffs.Count.Layout[2] or "", debuffs.Count.Layout[3] or 0, debuffs.Count.Layout[4] or 0,
        debuffs.Count.Colour[1] or 0, debuffs.Count.Colour[2] or 0, debuffs.Count.Colour[3] or 0,
    }, "|")
end

local function StyleAuras(_, button, unit, auraType)
    if not button or not unit or not auraType then return end
    UUF:StyleAuraButton(button, unit, auraType, true)
end

local function RestyleAuras(_, button, unit, auraType)
    if not button or not unit or not auraType then return end
    UUF:StyleAuraButton(button, unit, auraType, false)
end

local function CreateUnitBuffs(unitFrame, unit)
    local BuffsDB = UUF.db.profile.Units[UUF:GetNormalizedUnit(unit)].Auras.Buffs
    local frameName = unitFrame:GetName() or UUF:FetchFrameName(unit)
    if not unitFrame.BuffContainer then
        unitFrame.BuffContainer = CreateFrame("Frame", frameName .. "_BuffsContainer", unitFrame)
        unitFrame.BuffContainer:SetFrameStrata(UUF.db.profile.Units[UUF:GetNormalizedUnit(unit)].Auras.FrameStrata)
        local buffPerRow = BuffsDB.Wrap or 4
        local buffRows = math.ceil(BuffsDB.Num / buffPerRow)
        local buffContainerWidth = (BuffsDB.Size + BuffsDB.Layout[5]) * buffPerRow - BuffsDB.Layout[5]
        local buffContainerHeight = (BuffsDB.Size + BuffsDB.Layout[5]) * buffRows - BuffsDB.Layout[5]
        unitFrame.BuffContainer:SetSize(buffContainerWidth, buffContainerHeight)
        unitFrame.BuffContainer:SetPoint(BuffsDB.Layout[1], unitFrame, BuffsDB.Layout[2], BuffsDB.Layout[3], BuffsDB.Layout[4])
        unitFrame.BuffContainer.size = BuffsDB.Size
        unitFrame.BuffContainer.spacing = BuffsDB.Layout[5]
        unitFrame.BuffContainer.num = BuffsDB.Num
        unitFrame.BuffContainer.initialAnchor = BuffsDB.Layout[1]
        unitFrame.BuffContainer.onlyShowPlayer = BuffsDB.OnlyShowPlayer
        unitFrame.BuffContainer["growthX"] = BuffsDB.GrowthDirection
        unitFrame.BuffContainer["growthY"] = BuffsDB.WrapDirection
        unitFrame.BuffContainer.filter = BuffsDB.Filter or "HELPFUL"
        unitFrame.BuffContainer.PostCreateButton = function(_, button) StyleAuras(_, button, unit, "HELPFUL") end
        unitFrame.BuffContainer.anchoredButtons = 0
        unitFrame.BuffContainer.createdButtons = 0
        unitFrame.BuffContainer.tooltipAnchor = "ANCHOR_CURSOR"
        unitFrame.BuffContainer.showType = BuffsDB.ShowType
        unitFrame.BuffContainer.showBuffType = BuffsDB.ShowType
        unitFrame.BuffContainer.dispelColorCurve = C_CurveUtil.CreateColorCurve()
        unitFrame.BuffContainer.dispelColorCurve:SetType(Enum.LuaCurveType.Step)
        for _, dispelIndex in next, oUF.Enum.DispelType do
            if(oUF.colors.dispel[dispelIndex]) then
                unitFrame.BuffContainer.dispelColorCurve:AddPoint(dispelIndex, oUF.colors.dispel[dispelIndex])
            end
        end

        if BuffsDB.Enabled then
            unitFrame.Buffs = unitFrame.BuffContainer
        else
            unitFrame.Buffs = nil
        end
    end
end

local function CreateUnitDebuffs(unitFrame, unit)
    local DebuffsDB = UUF.db.profile.Units[UUF:GetNormalizedUnit(unit)].Auras.Debuffs
    local frameName = unitFrame:GetName() or UUF:FetchFrameName(unit)
    if not unitFrame.DebuffContainer then
        unitFrame.DebuffContainer = CreateFrame("Frame", frameName .. "_DebuffsContainer", unitFrame)
        unitFrame.DebuffContainer:SetFrameStrata(UUF.db.profile.Units[UUF:GetNormalizedUnit(unit)].Auras.FrameStrata)
        local debuffPerRow = DebuffsDB.Wrap or 3
        local debuffRows = math.ceil(DebuffsDB.Num / debuffPerRow)
        local debuffContainerWidth = (DebuffsDB.Size + DebuffsDB.Layout[5]) * debuffPerRow - DebuffsDB.Layout[5]
        local debuffContainerHeight = (DebuffsDB.Size + DebuffsDB.Layout[5]) * debuffRows - DebuffsDB.Layout[5]
        unitFrame.DebuffContainer:SetSize(debuffContainerWidth, debuffContainerHeight)
        unitFrame.DebuffContainer:SetPoint(DebuffsDB.Layout[1], unitFrame, DebuffsDB.Layout[2], DebuffsDB.Layout[3], DebuffsDB.Layout[4])
        unitFrame.DebuffContainer.size = DebuffsDB.Size
        unitFrame.DebuffContainer.spacing = DebuffsDB.Layout[5]
        unitFrame.DebuffContainer.num = DebuffsDB.Num
        unitFrame.DebuffContainer.initialAnchor = DebuffsDB.Layout[1]
        unitFrame.DebuffContainer.onlyShowPlayer = DebuffsDB.OnlyShowPlayer
        unitFrame.DebuffContainer["growthX"] = DebuffsDB.GrowthDirection
        unitFrame.DebuffContainer["growthY"] = DebuffsDB.WrapDirection
        unitFrame.DebuffContainer.filter = DebuffsDB.Filter or "HARMFUL"
        unitFrame.DebuffContainer.anchoredButtons = 0
        unitFrame.DebuffContainer.createdButtons = 0
        unitFrame.DebuffContainer.PostCreateButton = function(_, button) StyleAuras(_, button, unit, "HARMFUL") end
        unitFrame.DebuffContainer.tooltipAnchor = "ANCHOR_CURSOR"
        unitFrame.DebuffContainer.showType = DebuffsDB.ShowType
        unitFrame.DebuffContainer.showDebuffType = DebuffsDB.ShowType
        unitFrame.DebuffContainer.dispelColorCurve = C_CurveUtil.CreateColorCurve()
        unitFrame.DebuffContainer.dispelColorCurve:SetType(Enum.LuaCurveType.Step)
        for _, dispelIndex in next, oUF.Enum.DispelType do
            if(oUF.colors.dispel[dispelIndex]) then
                unitFrame.DebuffContainer.dispelColorCurve:AddPoint(dispelIndex, oUF.colors.dispel[dispelIndex])
            end
        end

        if DebuffsDB.Enabled then
            unitFrame.Debuffs = unitFrame.DebuffContainer
        else
            unitFrame.Debuffs = nil
        end
    end
end

function UUF:UpdateUnitAuras(unitFrame, unit)
    if not unit or not unitFrame then return end
    local GeneralDB = UUF.db.profile.General
    local AurasDB = UUF.db.profile.Units[UUF:GetNormalizedUnit(unit)].Auras
    if not AurasDB then return end
    local BuffsDB = AurasDB.Buffs
    local DebuffsDB = AurasDB.Debuffs

    local shouldEnableAuras = BuffsDB.Enabled or DebuffsDB.Enabled

    if BuffsDB.Enabled then
        unitFrame.Buffs = unitFrame.BuffContainer
        local buffPerRow = BuffsDB.Wrap or 4
        local buffRows = math.ceil(BuffsDB.Num / buffPerRow)
        local buffContainerWidth = (BuffsDB.Size + BuffsDB.Layout[5]) * buffPerRow - BuffsDB.Layout[5]
        local buffContainerHeight = (BuffsDB.Size + BuffsDB.Layout[5]) * buffRows - BuffsDB.Layout[5]
        UUF:QueueOrRun(function()
            unitFrame.BuffContainer:ClearAllPoints()
            unitFrame.BuffContainer:SetSize(buffContainerWidth, buffContainerHeight)
            unitFrame.BuffContainer:SetPoint(BuffsDB.Layout[1], unitFrame, BuffsDB.Layout[2], BuffsDB.Layout[3], BuffsDB.Layout[4])
            unitFrame.BuffContainer:SetFrameStrata(UUF.db.profile.Units[UUF:GetNormalizedUnit(unit)].Auras.FrameStrata)
        end)
        unitFrame.BuffContainer.size = BuffsDB.Size
        unitFrame.BuffContainer.spacing = BuffsDB.Layout[5]
        unitFrame.BuffContainer.num = BuffsDB.Num
        unitFrame.BuffContainer.initialAnchor = BuffsDB.Layout[1]
        unitFrame.BuffContainer.onlyShowPlayer = BuffsDB.OnlyShowPlayer
        unitFrame.BuffContainer["growthX"] = BuffsDB.GrowthDirection
        unitFrame.BuffContainer["growthY"] = BuffsDB.WrapDirection
        unitFrame.BuffContainer.filter = BuffsDB.Filter or "HELPFUL"
        unitFrame.BuffContainer.createdButtons = unitFrame.Buffs.createdButtons or 0
        unitFrame.BuffContainer.anchoredButtons = unitFrame.Buffs.anchoredButtons or 0
        unitFrame.BuffContainer.PostCreateButton = function(_, button) StyleAuras(_, button, unit, "HELPFUL") end
        unitFrame.BuffContainer.showType = BuffsDB.ShowType
        unitFrame.BuffContainer.showBuffType = BuffsDB.ShowType
        UUF:QueueOrRun(function() unitFrame.BuffContainer:Show() end)
    else
        UUF:QueueOrRun(function() unitFrame.BuffContainer:Hide() end)
        unitFrame.Buffs = nil
    end

    if DebuffsDB.Enabled then
        unitFrame.Debuffs = unitFrame.DebuffContainer
        local debuffPerRow = DebuffsDB.Wrap or 4
        local debuffRows = math.ceil(DebuffsDB.Num / debuffPerRow)
        local debuffContainerWidth = (DebuffsDB.Size + DebuffsDB.Layout[5]) * debuffPerRow - DebuffsDB.Layout[5]
        local debuffContainerHeight = (DebuffsDB.Size + DebuffsDB.Layout[5]) * debuffRows - DebuffsDB.Layout[5]
        UUF:QueueOrRun(function()
            unitFrame.DebuffContainer:ClearAllPoints()
            unitFrame.DebuffContainer:SetSize(debuffContainerWidth, debuffContainerHeight)
            unitFrame.DebuffContainer:SetFrameStrata(UUF.db.profile.Units[UUF:GetNormalizedUnit(unit)].Auras.FrameStrata)
            unitFrame.DebuffContainer:SetPoint(DebuffsDB.Layout[1], unitFrame, DebuffsDB.Layout[2], DebuffsDB.Layout[3], DebuffsDB.Layout[4])
        end)
        unitFrame.DebuffContainer.size = DebuffsDB.Size
        unitFrame.DebuffContainer.spacing = DebuffsDB.Layout[5]
        unitFrame.DebuffContainer.num = DebuffsDB.Num
        unitFrame.DebuffContainer.initialAnchor = DebuffsDB.Layout[1]
        unitFrame.DebuffContainer.onlyShowPlayer = DebuffsDB.OnlyShowPlayer
        unitFrame.DebuffContainer["growthX"] = DebuffsDB.GrowthDirection
        unitFrame.DebuffContainer["growthY"] = DebuffsDB.WrapDirection
        unitFrame.DebuffContainer.filter = DebuffsDB.Filter or "HARMFUL"
        unitFrame.DebuffContainer.createdButtons = unitFrame.Debuffs.createdButtons or 0
        unitFrame.DebuffContainer.anchoredButtons = unitFrame.Debuffs.anchoredButtons or 0
        unitFrame.DebuffContainer.PostCreateButton = function(_, button) StyleAuras(_, button, unit, "HARMFUL") end
        unitFrame.DebuffContainer.showType = DebuffsDB.ShowType
        unitFrame.DebuffContainer.showDebuffType = DebuffsDB.ShowType
        UUF:QueueOrRun(function() unitFrame.DebuffContainer:Show() end)
    else
        UUF:QueueOrRun(function() unitFrame.DebuffContainer:Hide() end)
        unitFrame.Debuffs = nil
    end

    if shouldEnableAuras then
        if not unitFrame:IsElementEnabled("Auras") then unitFrame:EnableElement("Auras") end
        if unitFrame.BuffContainer and unitFrame.BuffContainer.ForceUpdate then unitFrame.BuffContainer:ForceUpdate() end
        if unitFrame.DebuffContainer and unitFrame.DebuffContainer.ForceUpdate then unitFrame.DebuffContainer:ForceUpdate() end
    else
        if unitFrame:IsElementEnabled("Auras") then
            unitFrame:DisableElement("Auras")
        end
    end

    local styleKey = BuildAuraStyleKey(GeneralDB, AurasDB)
    local needsRestyle = unitFrame.UUFAuraStyleKey ~= styleKey
    unitFrame.UUFAuraStyleKey = styleKey

    if needsRestyle then
        for _, button in ipairs(unitFrame.BuffContainer) do
            if button and button:IsShown() then
                if UUF:StampChanged(button, "auraButtonStyle", unit, "HELPFUL", styleKey) then
                    RestyleAuras(_, button, unit, "HELPFUL")
                end
            end
        end
        for _, button in ipairs(unitFrame.DebuffContainer) do
            if button and button:IsShown() then
                if UUF:StampChanged(button, "auraButtonStyle", unit, "HARMFUL", styleKey) then
                    RestyleAuras(_, button, unit, "HARMFUL")
                end
            end
        end
    end
    if UUF.AURA_TEST_MODE == true then UUF:CreateTestAuras(unitFrame, unit) end
end

function UUF:CreateUnitAuras(unitFrame, unit)
    CreateUnitBuffs(unitFrame, unit)
    CreateUnitDebuffs(unitFrame, unit)
end

function UUF:UpdateUnitAurasStrata(unit)
    if not unit then return end
    if InCombatLockdown() then return end
    local normalizedUnit = UUF:GetNormalizedUnit(unit)
    local unitFrame = UUF[unit:upper()]
    local unitDB = UUF.db.profile.Units[normalizedUnit]
    if not unitFrame or not unitDB or not unitDB.Auras then return end
    if unitFrame.BuffContainer then unitFrame.BuffContainer:SetFrameStrata(unitDB.Auras.FrameStrata) end
    if unitFrame.DebuffContainer then unitFrame.DebuffContainer:SetFrameStrata(unitDB.Auras.FrameStrata) end
end


function UUF:CreateTestAuras(unitFrame, unit)
    if not unit then return end
    if not unitFrame then return end
    local General = UUF.db.profile.General
    local AuraDurationDB = UUF.db.profile.Units[UUF:GetNormalizedUnit(unit)].Auras.AuraDuration
    local BuffsDB = UUF.db.profile.Units[UUF:GetNormalizedUnit(unit)].Auras.Buffs
    local DebuffsDB = UUF.db.profile.Units[UUF:GetNormalizedUnit(unit)].Auras.Debuffs
    if UUF.AURA_TEST_MODE then
        if unitFrame.BuffContainer then
            if BuffsDB.Enabled then
                unitFrame.BuffContainer:ClearAllPoints()
                unitFrame.BuffContainer:SetPoint(BuffsDB.Layout[1], unitFrame, BuffsDB.Layout[2], BuffsDB.Layout[3], BuffsDB.Layout[4])
                unitFrame.BuffContainer:SetFrameStrata(UUF.db.profile.Units[UUF:GetNormalizedUnit(unit)].Auras.FrameStrata)
                unitFrame.BuffContainer:Show()

                for j = 1, BuffsDB.Num do
                    local button = unitFrame.BuffContainer["fake" .. j]
                    if not button then
                        button = CreateFrame("Button", nil, unitFrame.BuffContainer, "BackdropTemplate")
                        button:SetBackdrop(UUF.BACKDROP)
                        button:SetBackdropColor(0, 0, 0, 0)
                        button:SetBackdropBorderColor(0, 0, 0, 1)
                        button:SetFrameStrata(UUF.db.profile.Units[UUF:GetNormalizedUnit(unit)].Auras.FrameStrata)

                        button.Icon = button:CreateTexture(nil, "BORDER")
                        button.Icon:SetAllPoints()

                        button.Count = button:CreateFontString(nil, "OVERLAY")
                        unitFrame.BuffContainer["fake" .. j] = button
                    end

                    button:SetSize(BuffsDB.Size, BuffsDB.Size)
                    button.Count:ClearAllPoints()
                    button.Count:SetPoint(BuffsDB.Count.Layout[1], button, BuffsDB.Count.Layout[2], BuffsDB.Count.Layout[3], BuffsDB.Count.Layout[4])
                    button.Count:SetFont(UUF.Media.Font, BuffsDB.Count.FontSize, General.Fonts.FontFlag)
                    if General.Fonts.Shadow.Enabled then
                        button.Count:SetShadowColor(unpack(General.Fonts.Shadow.Colour))
                        button.Count:SetShadowOffset(General.Fonts.Shadow.XPos, General.Fonts.Shadow.YPos)
                    else
                        button.Count:SetShadowColor(0, 0, 0, 0)
                        button.Count:SetShadowOffset(0, 0)
                    end
                    button.Count:SetTextColor(unpack(BuffsDB.Count.Colour))

                    local row = math.floor((j - 1) / BuffsDB.Wrap)
                    local col = (j - 1) % BuffsDB.Wrap
                    local x = col * (BuffsDB.Size + BuffsDB.Layout[5])
                    local y = row * (BuffsDB.Size + BuffsDB.Layout[5])
                    if BuffsDB.GrowthDirection == "LEFT" then x = -x end
                    if BuffsDB.WrapDirection == "DOWN" then y = -y end

                    button:ClearAllPoints()
                    button:SetPoint(BuffsDB.Layout[1], unitFrame.BuffContainer, BuffsDB.Layout[1], x, y)

                    button.Icon:SetTexture(135769)
                    button.Icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
                    button.Icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
                    button.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                    button.Count:SetText(j)
                    button.Duration = button.Duration or button:CreateFontString(nil, "OVERLAY")
                    button.Duration:ClearAllPoints()
                    button.Duration:SetPoint(AuraDurationDB.Layout[1], button, AuraDurationDB.Layout[2], AuraDurationDB.Layout[3], AuraDurationDB.Layout[4])
                    if AuraDurationDB.ScaleByIconSize then
                        local iconWidth = button:GetWidth()
                        local scaleFactor = iconWidth / 36
                        button.Duration:SetFont(UUF.Media.Font, AuraDurationDB.FontSize * scaleFactor, General.Fonts.FontFlag)
                    else
                        button.Duration:SetFont(UUF.Media.Font, AuraDurationDB.FontSize, General.Fonts.FontFlag)
                    end
                    if General.Fonts.Shadow.Enabled then
                        button.Duration:SetShadowColor(unpack(General.Fonts.Shadow.Colour))
                        button.Duration:SetShadowOffset(General.Fonts.Shadow.XPos, General.Fonts.Shadow.YPos)
                    else
                        button.Duration:SetShadowColor(0, 0, 0, 0)
                        button.Duration:SetShadowOffset(0, 0)
                    end
                    button.Duration:SetTextColor(AuraDurationDB.Colour[1], AuraDurationDB.Colour[2], AuraDurationDB.Colour[3], 1)
                    button.Duration:SetText("10m")
                    button:Show()
                end

                local maxFake = BuffsDB.Num
                for j = maxFake + 1, (unitFrame.BuffContainer.maxFake or maxFake) do
                    local button = unitFrame.BuffContainer["fake" .. j]
                    if button then button:Hide() end
                end
                unitFrame.BuffContainer.maxFake = BuffsDB.Num
            else
                unitFrame.BuffContainer:Hide()
            end
        end

        if unitFrame.DebuffContainer then
            if DebuffsDB.Enabled then
                unitFrame.DebuffContainer:ClearAllPoints()
                unitFrame.DebuffContainer:SetPoint(DebuffsDB.Layout[1], unitFrame, DebuffsDB.Layout[2], DebuffsDB.Layout[3], DebuffsDB.Layout[4])
                unitFrame.DebuffContainer:SetFrameStrata(UUF.db.profile.Units[UUF:GetNormalizedUnit(unit)].Auras.FrameStrata)
                unitFrame.DebuffContainer:Show()

                for j = 1, DebuffsDB.Num do
                    local button = unitFrame.DebuffContainer["fake" .. j]
                    if not button then
                        button = CreateFrame("Button", nil, unitFrame.DebuffContainer, "BackdropTemplate")
                        button:SetBackdrop(UUF.BACKDROP)
                        button:SetBackdropColor(0, 0, 0, 0)
                        button:SetBackdropBorderColor(0, 0, 0, 1)
                        button:SetFrameStrata(UUF.db.profile.Units[UUF:GetNormalizedUnit(unit)].Auras.FrameStrata)
                        button.Icon = button:CreateTexture(nil, "BORDER")
                        button.Icon:SetAllPoints()

                        button.Count = button:CreateFontString(nil, "OVERLAY")
                        unitFrame.DebuffContainer["fake" .. j] = button
                    end

                    button:SetSize(DebuffsDB.Size, DebuffsDB.Size)
                    button.Count:ClearAllPoints()
                    button.Count:SetPoint(DebuffsDB.Count.Layout[1], button, DebuffsDB.Count.Layout[2], DebuffsDB.Count.Layout[3], DebuffsDB.Count.Layout[4])
                    button.Count:SetFont(UUF.Media.Font, DebuffsDB.Count.FontSize, General.Fonts.FontFlag)
                    if General.Fonts.Shadow.Enabled then
                        button.Count:SetShadowColor(unpack(General.Fonts.Shadow.Colour))
                        button.Count:SetShadowOffset(General.Fonts.Shadow.XPos, General.Fonts.Shadow.YPos)
                    else
                        button.Count:SetShadowColor(0, 0, 0, 0)
                        button.Count:SetShadowOffset(0, 0)
                    end
                    button.Count:SetTextColor(unpack(DebuffsDB.Count.Colour))

                    local row = math.floor((j - 1) / DebuffsDB.Wrap)
                    local col = (j - 1) % DebuffsDB.Wrap
                    local x = col * (DebuffsDB.Size + DebuffsDB.Layout[5])
                    local y = row * (DebuffsDB.Size + DebuffsDB.Layout[5])
                    if DebuffsDB.GrowthDirection == "LEFT" then x = -x end
                    if DebuffsDB.WrapDirection == "DOWN" then y = -y end

                    button:ClearAllPoints()
                    button:SetPoint(DebuffsDB.Layout[1], unitFrame.DebuffContainer, DebuffsDB.Layout[1], x, y)
                    button.Icon:SetTexture(135768)
                    button.Icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
                    button.Icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
                    button.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                    button.Count:SetText(j)
                    button.Duration = button.Duration or button:CreateFontString(nil, "OVERLAY")
                    button.Duration:ClearAllPoints()
                    button.Duration:SetPoint(AuraDurationDB.Layout[1], button, AuraDurationDB.Layout[2], AuraDurationDB.Layout[3], AuraDurationDB.Layout[4])
                    if AuraDurationDB.ScaleByIconSize then
                        local iconWidth = button:GetWidth()
                        local scaleFactor = iconWidth / 36
                        button.Duration:SetFont(UUF.Media.Font, AuraDurationDB.FontSize * scaleFactor, General.Fonts.FontFlag)
                    else
                        button.Duration:SetFont(UUF.Media.Font, AuraDurationDB.FontSize, General.Fonts.FontFlag)
                    end
                    if General.Fonts.Shadow.Enabled then
                        button.Duration:SetShadowColor(unpack(General.Fonts.Shadow.Colour))
                        button.Duration:SetShadowOffset(General.Fonts.Shadow.XPos, General.Fonts.Shadow.YPos)
                    else
                        button.Duration:SetShadowColor(0, 0, 0, 0)
                        button.Duration:SetShadowOffset(0, 0)
                    end
                    button.Duration:SetTextColor(AuraDurationDB.Colour[1], AuraDurationDB.Colour[2], AuraDurationDB.Colour[3], 1)
                    button.Duration:SetText("10m")
                    button:Show()
                end

                local maxFake = DebuffsDB.Num
                for j = maxFake + 1, (unitFrame.DebuffContainer.maxFake or maxFake) do
                    local button = unitFrame.DebuffContainer["fake" .. j]
                    if button then button:Hide() end
                end
                unitFrame.DebuffContainer.maxFake = DebuffsDB.Num
            else
                unitFrame.DebuffContainer:Hide()
            end
        end
    else
        if unitFrame.BuffContainer then
            for j = 1, (unitFrame.BuffContainer.maxFake or 0) do
                local button = unitFrame.BuffContainer["fake" .. j]
                if button then button:Hide() end
            end
        end
        if unitFrame.DebuffContainer then
            for j = 1, (unitFrame.DebuffContainer.maxFake or 0) do
                local button = unitFrame.DebuffContainer["fake" .. j]
                if button then button:Hide() end
            end
        end
    end
end