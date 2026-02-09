local _, UUF = ...
local UnhaltedUnitFrames = LibStub("AceAddon-3.0"):NewAddon("UnhaltedUnitFrames")

function UnhaltedUnitFrames:OnInitialize()
    UUF.db = LibStub("AceDB-3.0"):New("UUFDB", UUF:GetDefaultDB(), true)
    UUF.LDS:EnhanceDatabase(UUF.db, "UnhaltedUnitFrames")
    for k, v in pairs(UUF:GetDefaultDB()) do
        if UUF.db.profile[k] == nil then
            UUF.db.profile[k] = v
        end
    end
    UUF.TAG_UPDATE_INTERVAL = UUF.db.profile.General.TagUpdateInterval or 0.25
    UUF.SEPARATOR = UUF.db.profile.General.Separator or "||"
    UUF.TOT_SEPARATOR = UUF.db.profile.General.ToTSeparator or "»"
    if UUF.db.global.UseGlobalProfile then UUF.db:SetProfile(UUF.db.global.GlobalProfile or "Default") end
    UUF.db.RegisterCallback(UUF, "OnProfileChanged", function() UUF:UpdateAllUnitFrames() end)
    UUF.db.RegisterCallback(UUF, "OnProfileCopied", function() UUF:UpdateAllUnitFrames() end)
    UUF.db.RegisterCallback(UUF, "OnProfileReset", function() UUF:UpdateAllUnitFrames() end)

    local playerSpecalizationChangedEventFrame = CreateFrame("Frame")
    playerSpecalizationChangedEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    playerSpecalizationChangedEventFrame:SetScript("OnEvent", function(_, event, ...) if event == "PLAYER_SPECIALIZATION_CHANGED" then local unit = ... if unit == "player" then UUF:UpdateAllUnitFrames() end end end)

    local groupUpdateEventFrame = CreateFrame("Frame")
    groupUpdateEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    groupUpdateEventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    groupUpdateEventFrame:SetScript("OnEvent", function(_, event)
        if UUF.db.profile.Units.party.SortOrder == "ROLE" then
            UUF:CreateTestPartyFrames()
        end
    end)
    local tempGuardianFrame = CreateFrame("Frame")
    tempGuardianFrame:RegisterEvent("PLAYER_CONTROL_LOST")
    tempGuardianFrame:RegisterEvent("PLAYER_CONTROL_GAINED")
    tempGuardianFrame:RegisterEvent("COMPANION_UPDATE")
    tempGuardianFrame:RegisterEvent("UNIT_PET")
    tempGuardianFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    tempGuardianFrame:SetScript("OnEvent", function()
        -- Refresh pet frame when temporary guardians appear/disappear
        if UUF.PET then
            UUF:UpdateUnitFrame(UUF.PET, "pet")
        end
    end)
    -- Safe-queue for deferred protected calls during combat lockdown
    UUF._safeQueue = UUF._safeQueue or {}
    local safeQueueFrame = CreateFrame("Frame")
    safeQueueFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    safeQueueFrame:SetScript("OnEvent", function()
        if not UUF._safeQueue or #UUF._safeQueue == 0 then return end
        for i = 1, #UUF._safeQueue do
            local ok, err = pcall(UUF._safeQueue[i])
            if not ok then
                print("UnhaltedUnitFrames: error flushing safe queue - ", err)
            end
        end
        UUF._safeQueue = {}
    end)
end

function UnhaltedUnitFrames:OnEnable()
    UUF:Init()
    UUF:CreatePositionController()
    UUF:SpawnUnitFrame("player")
    UUF:SpawnUnitFrame("target")
    UUF:SpawnUnitFrame("targettarget")
    UUF:SpawnUnitFrame("focus")
    UUF:SpawnUnitFrame("focustarget")
    UUF:SpawnUnitFrame("pet")
    UUF:SpawnUnitFrame("party")
    UUF:SpawnUnitFrame("boss")
end

function UUF:GetUnitConfig(unit)
    local normalizedUnit = UUF:GetNormalizedUnit(unit)
    local unitConfig = UUF.db.profile.Units[normalizedUnit]
    return unitConfig
end

function UUF:GetUnitIndicatorConfig(unit, indicatorType)
    local unitConfig = UUF:GetUnitConfig(unit)
    if not unitConfig or not unitConfig.Indicators then
        return nil
    end
    return unitConfig.Indicators[indicatorType]
end

function UUF:QueueOrRun(fn)
    if type(fn) ~= "function" then return end
    if InCombatLockdown() then
        UUF._safeQueue = UUF._safeQueue or {}
        UUF._safeQueue[#UUF._safeQueue + 1] = fn
    else
        fn()
    end
end

-- In Core.lua, add NPC-specific event tracking
local questNpcFrame = CreateFrame("Frame")
questNpcFrame:RegisterEvent("QUEST_ACCEPTED")
questNpcFrame:RegisterEvent("QUEST_TURNED_IN")
questNpcFrame:RegisterEvent("QUEST_LOG_UPDATE")
questNpcFrame:SetScript("OnEvent", function(_, event)
    -- Handle NPC party joins/leaves tied to specific quests
    UUF:UpdatePartyFrames()
end)

-- Listen for unit changes that might affect party composition
local unitEventFrame = CreateFrame("Frame")
unitEventFrame:RegisterEvent("UNIT_FACTION")  -- NPC faction changes
unitEventFrame:SetScript("OnEvent", function(_, event)
    UUF:UpdatePartyFrames()
end)

-- Track temporary guardian/pet changes
local guardianEventFrame = CreateFrame("Frame")
guardianEventFrame:RegisterEvent("PLAYER_CONTROL_LOST")     -- When taking controlled pet
guardianEventFrame:RegisterEvent("PLAYER_CONTROL_GAINED")   -- When releasing controlled pet
guardianEventFrame:RegisterEvent("UNIT_PET")                -- Pet appearance/disappearance
guardianEventFrame:RegisterEvent("COMPANION_UPDATE")        -- Companion gained/lost
guardianEventFrame:SetScript("OnEvent", function(_, event)
    -- Update player frame and pet frame when guardians change
    UUF:UpdateUnitFrame(UUF.PLAYER, "player")
    if UUF.PET then UUF:UpdateUnitFrame(UUF.PET, "pet") end
end)
