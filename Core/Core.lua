local _, UUF = ...
local UnhaltedUnitFrames = LibStub("AceAddon-3.0"):NewAddon("UnhaltedUnitFrames", "AceConsole-3.0", "AceTimer-3.0", "AceBucket-3.0")

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

    -- Initialize EventBus for centralized event routing
    UUF._eventBus = UUF.Architecture.EventBus
    UUF.EventBus = UUF.Architecture.EventBus  -- Public alias for dashboard and other systems
    
    -- Register EventBus handlers for all game events
    UUF._eventBus:Register("PLAYER_SPECIALIZATION_CHANGED", "UUF_SpecChanged", function(unit)
        if unit == "player" then UUF:UpdateAllUnitFrames() end
    end)
    
    -- Register bucket events through EventBus
    UUF._eventBus:Register("PET_UPDATE_BATCH", "UUF_PetBatch", function()
        if UUF.PET then UUF:UpdateUnitFrame(UUF.PET, "pet") end
    end)
    
    UUF._eventBus:Register("GROUP_UPDATE_BATCH", "UUF_GroupBatch", function()
        if UUF.db.profile.Units.party.SortOrder == "ROLE" then
            UUF:LayoutPartyFrames()
        end
    end)
    
    UUF._eventBus:Register("PLAYER_REGEN_ENABLED", "UUF_SafeQueueFlush", function()
        if not UUF._safeQueue or #UUF._safeQueue == 0 then return end
        for i = 1, #UUF._safeQueue do
            local ok, err = pcall(UUF._safeQueue[i])
            if not ok then
                print("UnhaltedUnitFrames: error flushing safe queue - ", err)
            end
        end
        UUF._safeQueue = {}
    end)
    
    UUF._eventBus:Register("MINIMAP_PING", "UUF_MinimapPing", function(unit)
        UUF:ShowPingOnUnit(unit)
    end)
    
    -- Safe-queue for deferred protected calls during combat lockdown
    UUF._safeQueue = UUF._safeQueue or {}
    
    -- Set up frame-based event dispatch to EventBus (bridge from WoW events to EventBus)
    UUF:_SetupEventDispatcher()
end

function UUF:SetupEditModeHooks()
    if UUF._editModeHooked then return end
    if not EditModeManagerFrame then return end
    UUF._editModeHooked = true
    EditModeManagerFrame:HookScript("OnShow", function() UUF:ApplyFrameMovers() end)
    EditModeManagerFrame:HookScript("OnHide", function() UUF:ApplyFrameMovers() end)
    EditModeManagerFrame:HookScript("OnShow", function() UUF:ApplyEditModeLayout() end)
    EditModeManagerFrame:HookScript("OnHide", function() UUF:ApplyEditModeLayout() end)
end

function UnhaltedUnitFrames:OnEnable()
    UUF:Init()
    UUF:SetupEditModeHooks()
    UUF:CreatePositionController()
    
    -- Initialize debug system first (used by all other systems)
    if UUF.DebugOutput then
        UUF.DebugOutput:Init()
    end
    
    if UUF.DebugPanel then
        UUF.DebugPanel:Create()
        -- Debug panel only shows when explicitly requested via /uufdebug
        -- (not automatically on login/reload)
    end
    
    -- Initialize frame pooling system (must be before indicators)
    if UUF.FramePoolManager then
        UUF.FramePoolManager:Init()
    end
    
    -- Initialize enhanced systems (Phase 3+)
    if UUF.IndicatorPooling then
        UUF.IndicatorPooling:Init()
    end
    
    if UUF.ReactiveConfig then
        UUF.ReactiveConfig:Init()
    end
    
    -- Initialize event coalescing system
    if UUF.EventCoalescer then
        UUF.EventCoalescer:Init()
    end
    
    -- Initialize dirty flag manager
    if UUF.DirtyFlagManager then
        UUF.DirtyFlagManager:Init()
    end
    
    -- Initialize performance dashboard
    if UUF.PerformanceDashboard then
        UUF.PerformanceDashboard:Init()
    end
    
    -- Initialize advanced optimization systems
    if UUF.CoalescingIntegration then
        UUF.CoalescingIntegration:Init()
    end
    
    if UUF.DirtyPriorityOptimizer then
        UUF.DirtyPriorityOptimizer:Init()
    end
    
    if UUF.MLOptimizer then
        UUF.MLOptimizer:Init()
    end
    
    if UUF.PerformanceProfiler then
        UUF.PerformanceProfiler:Init()
    end
    
    if UUF.PerformancePresets then
        UUF.PerformancePresets:Init()
    end
    
    UUF:SpawnUnitFrame("player")
    UUF:SpawnUnitFrame("target")
    UUF:SpawnUnitFrame("targettarget")
    UUF:SpawnUnitFrame("focus")
    UUF:SpawnUnitFrame("focustarget")
    UUF:SpawnUnitFrame("pet")
    -- Force pet frame to be visible if enabled (critical for Warlock demons)
    if UUF.db.profile.Units.pet.Enabled and UUF.PET then
        UUF.PET:Show()
    end
    UUF:SpawnUnitFrame("party")
    UUF:SpawnUnitFrame("boss")
    
    -- Schedule pet frame visibility update to handle Warlock pets and other cases where RegisterUnitWatch may not work
    C_Timer.After(0.1, function()
        if UUF.UpdatePetFrameVisibility then
            UUF:UpdatePetFrameVisibility()
        end
        if UUF.UpdatePartyFrameVisibility then
            UUF:UpdatePartyFrameVisibility()
        end
    end)
    
    -- Start periodic pet/party frame visibility checker
    if not UUF._petVisibilityTimer then
        local tickCount = 0
        UUF._petVisibilityTimer = C_Timer.NewTicker(0.5, function()
            tickCount = tickCount + 1
            -- Log every 10 ticks (every 5 seconds) to avoid spam
            local shouldLog = (tickCount % 10 == 0)
            
            if UUF.UpdatePetFrameVisibility and UUF.db and UUF.db.profile then
                if shouldLog and UUF.DebugOutput then
                    UUF.DebugOutput:Output("Pet Timer", "Periodic timer tick - calling UpdatePetFrameVisibility", UUF.DebugOutput.TIER_DEBUG)
                end
                UUF:UpdatePetFrameVisibility()
            elseif shouldLog and UUF.DebugOutput then
                UUF.DebugOutput:Output("Pet Timer", "UpdatePetFrameVisibility not ready (db="..tostring(UUF.db ~= nil)..", profile="..tostring(UUF.db and UUF.db.profile ~= nil)..")", UUF.DebugOutput.TIER_DEBUG)
            end
            
            if UUF.UpdatePartyFrameVisibility and UUF.db and UUF.db.profile then
                UUF:UpdatePartyFrameVisibility()
            end
        end)
    end
    
    -- Validate architecture on load
    if UUF.Validator then
        C_Timer.After(2, function()
            if UUF.DebugOutput then
                UUF.DebugOutput:Output("Validator", "Running architecture validation...", UUF.DebugOutput.TIER_INFO)
            end
            UUF.Validator:RunFullValidation()
        end)
    end
    
    -- Merge castbar enhancement defaults after all systems are initialized
    C_Timer.After(0.5, function()
        if UUF.MergeCastBarDefaults then
            UUF:MergeCastBarDefaults()
        end
    end)
end

function UnhaltedUnitFrames:OnPetUpdate()
    -- Dispatch through EventBus for centralized handling
    if UUF._eventBus then
        UUF._eventBus:Dispatch("PET_UPDATE_BATCH")
    else
        if UUF.PET then
            UUF:UpdateUnitFrame(UUF.PET, "pet")
        end
    end
    -- Force pet frame visibility update for Warlocks and other classes
    if UUF.UpdatePetFrameVisibility then
        local success, result = pcall(UUF.UpdatePetFrameVisibility, UUF)
        if not success and UUF.DebugOutput then
            UUF.DebugOutput:Output("Pet Event Handler", "UpdatePetFrameVisibility error: " .. tostring(result), UUF.DebugOutput.TIER_CRITICAL)
        end
    end
end

function UnhaltedUnitFrames:OnGroupUpdate()
    -- Dispatch through EventBus for centralized handling
    if UUF._eventBus then
        UUF._eventBus:Dispatch("GROUP_UPDATE_BATCH")
    else
        if UUF.db and UUF.db.profile and UUF.db.profile.Units.party.SortOrder == "ROLE" then
            UUF:LayoutPartyFrames()
        end
    end
    -- Force party frame visibility update for Delves and other cases where RegisterUnitWatch may not work
    if UUF.UpdatePartyFrameVisibility then
        pcall(UUF.UpdatePartyFrameVisibility, UUF)
    end
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

-- Timer management via AceTimer-3.0
function UUF:ScheduleTimer(timername, delay, func, ...)
    return UnhaltedUnitFrames:ScheduleTimer(func, delay, ...)
end

function UUF:CancelTimer(handle)
    if handle then
        UnhaltedUnitFrames:CancelTimer(handle, true)
    end
end

-- Merge castbar enhancement defaults into all unit configs
function UUF:MergeCastBarDefaults()
    if not UUF.db or not UUF.CastBarDefaults then return end
    if UUF._castbarDefaultsMerged then return end  -- Only merge once
    
    UUF._castbarDefaultsMerged = true
    
    -- Simple table copy function (handles non-table values)
    local function CopyTable(src)
        if type(src) ~= "table" then
            return src  -- Return non-table values as-is
        end
        local result = {}
        for k, v in pairs(src) do
            if type(v) == "table" then
                result[k] = CopyTable(v)
            else
                result[k] = v
            end
        end
        return result
    end
    
    -- Merge into all unit types
    local units = {"player", "target", "targettarget", "focus", "focustarget", "pet", "party", "boss"}
    for _, unit in ipairs(units) do
        if UUF.db.profile.Units[unit] and UUF.db.profile.Units[unit].CastBar then
            -- Merge new feature tables from CastBarDefaults, preserving existing values
            for featureKey, featureConfig in pairs(UUF.CastBarDefaults) do
                if UUF.db.profile.Units[unit].CastBar[featureKey] == nil then
                    UUF.db.profile.Units[unit].CastBar[featureKey] = CopyTable(featureConfig)
                end
            end
        end
    end
end

function UUF:_SetupEventDispatcher()
    -- Create a single event dispatcher frame that bridges WoW events to the EventBus
    if UUF._eventDispatcherFrame then return end
    
    UUF._eventDispatcherFrame = CreateFrame("Frame")
    UUF._eventDispatcherFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    UUF._eventDispatcherFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    UUF._eventDispatcherFrame:RegisterEvent("PLAYER_LEVEL_UP")
    UUF._eventDispatcherFrame:RegisterEvent("UNIT_LEVEL")
    
    -- Register bucket events with AceBucket
    UnhaltedUnitFrames:RegisterBucketEvent(
        {"PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "COMPANION_UPDATE", "UNIT_PET", "UNIT_SPELLCAST_SUCCEEDED"},
        0.25, "OnPetUpdate"
    )
    UnhaltedUnitFrames:RegisterBucketEvent(
        {"GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED"},
        0.5, "OnGroupUpdate"
    )
    
    -- Try to register MINIMAP_PING if available
    local ok = pcall(UUF._eventDispatcherFrame.RegisterEvent, UUF._eventDispatcherFrame, "MINIMAP_PING")
    
    -- Event dispatcher script
    UUF._eventDispatcherFrame:SetScript("OnEvent", function(frame, event, ...)
        if event == "PLAYER_LEVEL_UP" then
            -- Player leveled up - update all tags showing player info
            C_Timer.After(0.1, function()
                UUF:UpdateAllUnitFrames()
            end)
        elseif event == "UNIT_LEVEL" then
            -- Specific unit level changed - update that frame
            local unit = ...
            if unit and UUF[unit:upper()] then
                C_Timer.After(0.1, function()
                    UUF:UpdateUnitFrame(UUF[unit:upper()], unit)
                end)
            end
        end
        
        if UUF._eventBus then
            UUF._eventBus:Dispatch(event, ...)
        end
    end)
end

local minimapPingFrame = CreateFrame("Frame")
do
    local ok = pcall(minimapPingFrame.RegisterEvent, minimapPingFrame, "MINIMAP_PING")
    if ok then
        minimapPingFrame:SetScript("OnEvent", function(_, _, unit)
            if UUF._eventBus then
                UUF._eventBus:Dispatch("MINIMAP_PING", unit)
            else
                UUF:ShowPingOnUnit(unit)
            end
        end)
    end
end



