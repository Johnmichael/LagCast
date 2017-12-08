--------------------------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------------------------

LAG_CAST_ALPHA_STEP = 0.05;
LAG_CAST_FLASH_STEP = 0.2;
LAG_CAST_HOLD_TIME = 1;
LAG_CAST_INITIAL_BUFFER = 60; -- 60ms in addition to network latency before SpellStopCasting() is issued
LAG_CAST_MIN_LAG = 0
LAG_CAST_BAR_TYPE = 1

LAG_CAST_SPARK_WIDTH=10 -- for custom sparks only

--------------------------------------------------------------------------------------------------
-- Internal variables and functions
--------------------------------------------------------------------------------------------------

local lCastBar
local lVars -- will be set to LagCastFrame

local function getSpark() return getglobal(lCastBar:GetName() .. "Spark") end
local function getFlash() return getglobal(lCastBar:GetName() .. "Flash") end
local function getCancelSpark() return getglobal(lCastBar:GetName() .. "CancelSpark") end
local function getCancelOverlay() return getglobal(lCastBar:GetName() .. "CancelOverlay") end
local function getText() return getglobal(lCastBar:GetName() .. "Text") end
local function getTextTimer() return getglobal(lCastBar:GetName() .. "TextTimer") end

local lOriginal_SpellStopCasting
local lOriginal_UIErrorsFrame_OnEvent
local lOriginal_UseAction
local lOriginal_GameTooltip_ClearMoney;

local lTooltipNames = { }
local lHelpDisplayed = nil

local function p(text, ...)
  local msg
  if getn(arg) == 0 then
    msg = format("LagCast [%.03f]: %s", GetTime(), text)
  else
    for i=1, getn(arg) do
      if arg[i] == nil then
        arg[i] = ""
      elseif type(arg[i]) == "table" or type(arg[i]) == "function" then
        arg[i] = "["..type(arg[i]).."]"
      end
    end
    msg = format("LagCast [%.03f]: "..text, GetTime(), unpack(arg))
  end
  DEFAULT_CHAT_FRAME:AddMessage(msg)
end

local lDebug

function LagCastFrame_DebugStart() lDebug = { }; lDebugIdx = nil; end
function LagCastFrame_DebugMark()
  if lDebug then
    table.insert(lDebug, format("[%.03f] INTERRUPTED", GetTime()))
  end
end
function LagCastFrame_DebugEnd() lDebug = nil end
function LagCastFrame_DebugPrint()
  if not lDebug then return end
  for i, v in lDebug do
    DEFAULT_CHAT_FRAME:AddMessage(format("LagCast %s", v))
  end
end

local function getAccount()
  if not LagCastAccount then LagCastAccount = { } end
  return LagCastAccount
end

local function getCharacter()
  if not LagCastCharacter then LagCastCharacter = { } end
  return LagCastCharacter
end

-- these need to be be appropriately namespaced global functions,
-- coordinate with LagCastOptions.lua for getting and setting
local function getMode() return getCharacter().mode or "disabled" end
local function setMode(m) getCharacter().mode = m end
local function getBufferMs() return getAccount().bufferMs or LAG_CAST_INITIAL_BUFFER end
local function getMinLag() return getAccount().minLag or LAG_CAST_MIN_LAG end
local function getBarType() return getAccount().barType or LAG_CAST_BAR_TYPE end
local function getBarDims() return getAccount().barDims end
local function getDisableSpamPrevention() return getAccount().disableSpamPrevention end
local function getDisableTimerDisplay() return getAccount().disableTimerDisplay end
local function setBufferMs(v) getAccount().bufferMs = v end
local function setMinLag(v) getAccount().minLag = v end
local function setBarType(v) getAccount().barType = v end
local function setBarDims(v) getAccount().barDims = v end

local function getLag()
  local _, _, lag_ms = GetNetStats()
  return max(getMinLag(), lag_ms)
end


local actionHooked
local function hookAction()
  -- Hook UseAction (code derived from Telo's Selfcast)
  if lOriginal_UseAction then return end
	lOriginal_UseAction = UseAction;
	UseAction = LagCast_UseAction;
  
  lOriginal_UIErrorsFrame_OnEvent = UIErrorsFrame_OnEvent
  UIErrorsFrame_OnEvent = function(event, message)
    if (this.casting or this.channeling) and event == "SPELL_FAILED_SPELL_IN_PROGRESS" then
      -- silently ignore, i hate this spammy worthless message
    else
      lOriginal_UIErrorsFrame_OnEvent(event, message)
    end
  end
end

local function unhookAction()
  if not lOriginal_UseAction then return end
  UseAction = lOriginal_UseAction
  UIErrorsFrame_OnEvent = lOriginal_UIErrorsFrame_OnEvent
  lOriginal_UseAction = nil
  lOriginal_UIErrorsFrame_OnEvent = nil
end

local lWrappedSpellStopCasting
local function customSpellStopCasting()
  local stopped = lOriginal_SpellStopCasting()
  -- sometimes the castbar lingers. if spellstopcasting was invoked (can be via Escape key)
  -- and it returned false, fake a spellcast_stop equivalent event
  --
  -- note: SpellStopCasting() does not cancel channeling
  if not stopped and not lWrappedSpellStopCasting and lVars and lVars.casting then
    --p("Sending fake hooked_stop event")
    local ev = event
    event = "hooked_stop"
    LagCastFrame_OnEvent(event)
    event = ev
    return true
  end
  return stopped
end

local function wrappedSpellStopCasting()
  lWrappedSpellStopCasting = true
  SpellStopCasting()
  lWrappedSpellStopCasting = nil
end

local function disableBlizzCastingBarFrame()
  CastingBarFrame:UnregisterAllEvents()
  if not lOriginal_SpellStopCasting then
    lOriginal_SpellStopCasting = SpellStopCasting
    SpellStopCasting = customSpellStopCasting
  end
end

local function enableBlizzCastingBarFrame()
  if lOriginal_SpellStopCasting then
    SpellStopCasting = lOriginal_SpellStopCasting
    lOriginal_SpellStopCasting = nil
  end
  local t = this
  this = CastingBarFrame
  CastingBarFrame_OnLoad()
  this = t
end

-- called via the UseAction intercepted call
function LagCast_StopCasting(dryRun)
  local this = lCastBar
  
  local lag_ms = getLag()
  local now = GetTime()
  
  if not getDisableSpamPrevention() then
    if lVars.spamPrevention and now - lVars.spamPrevention < ((lag_ms+getBufferMs())*2)/1000 then
      --p("spammy, ignoring")
      return false
    end
    
    if not lVars.casting then
      --p("Casting directly")
      if not dryRun then
        lVars.spamPrevention = now
      end
      return true
    end
  end

  if lVars.casting then
    local cancel_ok_time = lVars.endTime + (-lag_ms + getBufferMs())/1000
    if cancel_ok_time < now then
      --p("Cancelling and casting, start=%.03f  end=%.03f  cancel_ok=%.03f  now=%.03f", lVars.startTime, lVars.endTime, cancel_ok_time, now)
      if not dryRun then
        wrappedSpellStopCasting()
        lVars.spamPrevention = now
      end
      return true
    end
  end
  
  --p("Not yet ideal")
  return getDisableSpamPrevention();
end

-- global, /script LagCast("Fireball")
function LagCast(spellname)
  if LagCast_StopCasting(false) then
    CastSpellByName(spellname)
  end
end

local function markSpellcastStopped(event)
  lCastBar:SetValue(lVars.endTime);
  lCastBar:SetStatusBarColor(0.0, 1.0, 0.0);
  getSpark():Hide()
  getCancelSpark():Hide()
  getCancelOverlay():Hide()
  getFlash():SetAlpha(0.0);
  getFlash():Show();
  getTextTimer():Hide()
  if ( event == "SPELLCAST_STOP" ) then
    lVars.casting = nil;
  else
    lVars.channeling = nil;
  end
  lVars.flash = 1;
  lVars.fadeOut = 1;

  lVars.mode = "flash";
end

local function LagCast_MoneyToggle()
	if( lOriginal_GameTooltip_ClearMoney ) then
		GameTooltip_ClearMoney = lOriginal_GameTooltip_ClearMoney;
		lOriginal_GameTooltip_ClearMoney = nil;
	else
		lOriginal_GameTooltip_ClearMoney = GameTooltip_ClearMoney;
		GameTooltip_ClearMoney = LagCast_GameTooltip_ClearMoney;
	end
end

local cachedToolTips = { }
local cachedKnownSpells = { }
local function getSpellInfo(actionId)
  -- protect money frame while we set hidden tooltip
  LagCast_MoneyToggle();
  LagCastTooltip:SetOwner(UIParent, "ANCHOR_NONE");
  LagCastTooltip:SetAction(actionId)
  LagCast_MoneyToggle();
  
  local name = getglobal(lTooltipNames[1]):GetText()
  -- user is placing icon
  if (name == nil) then return end
  local inSpellbook = cachedKnownSpells[name]
  local isInstant = false
  
  for i=2, getn(lTooltipNames) do
    local ttframe = getglobal(lTooltipNames[i])
    if ttframe then
      local text = ttframe:GetText()
      if text == SPELL_CAST_TIME_INSTANT or text == SPELL_CAST_TIME_INSTANT_NO_MANA then
        isInstant = true
        break
      end
    end
  end
  
  if inSpellbook == nil then
    cachedKnownSpells[name] = false
    inSpellbook = false
    for tabIndex = 1, MAX_SKILLLINE_TABS do
      local tabName, tabTexture, tabSpellOffset, tabNumSpells = GetSpellTabInfo(tabIndex)
      if not tabName then break end
      
      for spellIndex = tabSpellOffset + 1, tabSpellOffset + tabNumSpells do
        local spellName, spellRank = GetSpellName(spellIndex, BOOKTYPE_SPELL)
        -- local spellTexture = GetSpellTexture(spellIndex)
        if name == spellName then
          --p("%s=%s idx=%d", name, spellName, spellIndex)
          inSpellbook = true
          cachedKnownSpells[name] = true
          break
        end
      end
    end
  end
  
  return name, inSpellbook, isInstant
end

-- leave this global, someone might want to call it? maybe?
function LagCast_UseAction(id, type, self)
  local spellName, spellInSpellbook, spellIsInstant = getSpellInfo(id)
  --p("LagCast_UseAction: name=%s  inbook=%s  instant=%s", spellName, spellInSpellbook, spellIsInstant)
  
  if spellInSpellbook then
    if LagCast_StopCasting() then
      lOriginal_UseAction(id, type, self)
    end
  else
    lOriginal_UseAction(id, type, self)
  end
end

local function formattedMode()
  local m = getMode()
  return
    m == "enabled" and "|cff00ff00enabled|r" or
    m == "bar_only" and "|cffff7f50bar_only|r" or
    m == "stop_only" and "|cffff7f50stop_only|r" or
    m == "disabled" and "|cffff0000disabled|r" or
    "|cffff0000"..m.." (UNKNOWN)|r"
end

local function showHelp()
  -- print usage here
  local function m(msg) DEFAULT_CHAT_FRAME:AddMessage(msg) end
  
  m("|cffffff00LagCast status:|r " .. formattedMode())
  m("|cffffffffhelp|r|cff00ff00: displays this message.|r")
  m("|cffffffffenable|r|cff00ff00: enables |cffffff00LagCast|cff00ff00 castbar and actionbar hooking|r")
  m("|cffffffffbar_only|r|cff00ff00: enables |cffffff00LagCast|cff00ff00 castbar but not actionbar hooking|r")
  m("|cffffffffstop_only|r|cff00ff00: enables |cffffff00LagCast|cff00ff00 actionbar hooking but not the custom castbar|r")
  m("|cffffffffdisable|r|cff00ff00: restores blizzard default castbar, disables actionbar hooking|r")
  m("|cffffffffconfig|r|cff00ff00: configure |cffffff00LagCast|r")
  m("|cffffffffreset|r|cff00ff00: reset frame locations|r")
end

local testTimers = { }
 function LagCastFrame_onSlashCommand(msg, editbox)
  for arg in string.gfind(string.lower(msg), "([%w_]+)") do
    if arg == "help" or arg == "usage" then
      showHelp()
      return
      
    elseif string.sub(arg, 1, 6) == "enable" then
      if getMode() == "disabled" or getMode() == "bar_only" then hookAction() end
      if getMode() == "disabled" or getMode() == "stop_only" then disableBlizzCastingBarFrame() end
      setMode("enabled")
      return
      
    elseif string.sub(arg, 1, 7) == "disable" then
      if getMode() == "enabled" or getMode() == "bar_only" then unhookAction() end
      if getMode() == "enabled" or getMode() == "stop_only" then enableBlizzCastingBarFrame() end
      setMode("disabled")
      return
    
    elseif arg == "bar_only" then
      if getMode() == "enabled" or getMode() == "stop_only" then unhookAction() end
      if getMode() == "disabled" or getMode() == "stop_only" then disableBlizzCastingBarFrame() end
      setMode("bar_only")
      return

    elseif arg == "stop_only" then
      if getMode() == "enabled" or getMode() == "bar_only" then enableBlizzCastingBarFrame() end
      if getMode() == "disabled" or getMode() == "bar_only" then hookAction() end
      setMode("stop_only")
      return
      
    elseif string.sub(arg, 1, 4) == "conf" then
      if getMode() ~= "enabled" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00LagCast|r mode is '"..formattedMode())
      end
      LagCastOptions:Show()
      return
      
    elseif arg == "reset" then
      if lCastBar:IsVisible() then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00LagCast|r |cffff0000cannot|r be reset while the cast bar is visible (|cff00ff00try again in 1sec|r)")
        PlaySound("RaidWarning")
        return
      end
      
      lCastBar = LagCastFrame
    
      LagCastAccount = { }
      LagCastCharacter = { mode = "enabled" }
      
      LagCastOptions:SetUserPlaced(false)
      LagCastOptions:ClearAllPoints()
      LagCastOptions:SetPoint("CENTER", UIParent)
      
      -- not really necessary, this is done always in LagCastOptions
      LagCastDummyBar:SetUserPlaced(false)
      LagCastDummyBar:ClearAllPoints()
      LagCastDummyBar:SetWidth(195)
      LagCastDummyBar:SetHeight(18)
      LagCastDummyBar:SetPoint("BOTTOM", UIParent, 0, 55)
      
      LagCastFrame:SetUserPlaced(false)
      LagCastFrame:ClearAllPoints()
      LagCastFrame:SetWidth(195)
      LagCastFrame:SetHeight(13)
      LagCastFrame:SetPoint("BOTTOM", UIParent, 0, 55)
      
      LagCastCustomFrame:SetUserPlaced(false)
      LagCastCustomFrame:ClearAllPoints()
      LagCastCustomFrame:SetWidth(300)
      LagCastCustomFrame:SetHeight(32)
      LagCastCustomFrame:SetPoint("BOTTOM", UIParent, 0, 55)
      
      LagCastCustomFrame_SetSparkSizes()
      
      return
      
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00LagCast:|r unknown option '|cffff0000"..arg.."|r'")
      return
    end
  end

  if not lHelpDisplayed then
    showHelp()
    lHelpDisplayed = true
  end
  
  LagCastOptions:Show()
end

function LagCastCustomFrame_SetSparkSizes()
  local old_lCastBar = lCastBar
  lCastBar = LagCastCustomFrame
  
  local dims = getBarDims()
  if dims and dims.w and dims.h then
    lCastBar:SetWidth(dims.w)
    lCastBar:SetHeight(dims.h)
  end

  local h = lCastBar:GetHeight()
  getSpark():SetHeight(h)
  getCancelSpark():SetHeight(h)
  
  lCastBar = old_lCastBar
end

function LagCastFrame_SetCustomWH(w, h)
  local f = LagCastCustomFrame
  setBarDims({ w = w; h = h })
  f:SetWidth(w)
  f:SetHeight(h)
end

--------------------------------------------------------------------------------------------------
-- OnFoo functions
--------------------------------------------------------------------------------------------------

function LagCastFrame_OnLoad()
  lCastBar = LagCastFrame
  lVars = LagCastFrame
  
  -- many of these events are necessary in 'stop_only' and 'disabled' mode,
  -- gonna leave them in place. dont disable them unless you're not using
  -- the mod, in which case...
	LagCastFrame:RegisterEvent("SPELLCAST_START");
	LagCastFrame:RegisterEvent("SPELLCAST_STOP");
	LagCastFrame:RegisterEvent("SPELLCAST_FAILED");
	LagCastFrame:RegisterEvent("SPELLCAST_INTERRUPTED");
	LagCastFrame:RegisterEvent("SPELLCAST_DELAYED");
	LagCastFrame:RegisterEvent("SPELLCAST_CHANNEL_START");
	LagCastFrame:RegisterEvent("SPELLCAST_CHANNEL_UPDATE");
	LagCastFrame:RegisterEvent("SPELLCAST_CHANNEL_STOP");
	-- LagCastFrame:RegisterEvent("ADDON_LOADED");
	LagCastFrame:RegisterEvent("VARIABLES_LOADED");
  
  lVars.spamPrevention = nil
  
	lVars.casting = nil
	lVars.holdTime = 0
  lVars.startTime = nil
  lVars.endTime = nil
end

function LagCastFrame_OnEvent()
  -- If SPELLCAST_STOP then arg1 is either nil (stopped because of movement or the spell
  -- naturally ended) or the command which invoked the stop (a button name, mouse name,
  -- full macro name eg '/script LagCast("Fireball")'
  --p("Got event %s [%s %s %s %s %s %s %s %s %s]", event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
  if lDebug then
    table.insert(lDebug, format("[%.03f] %s [%s %s %s %s %s %s %s %s %s]", GetTime(), event, arg1 or "", arg2 or "", arg3 or "", arg4 or "", arg5 or "", arg6 or "", arg7 or "", arg8 or "", arg9 or ""))
  end
  if string.sub(event, 1, 5) == "SPELL" then
    lVars.spamPrevention = nil
  end

  if (event == "VARIABLES_LOADED") then
    if not LagCastCharacter then setMode("enabled") end
    setBufferMs(getBufferMs())
    setMinLag(getMinLag())
    
    if getMode() == "enabled" or getMode() == "bar_only" then disableBlizzCastingBarFrame() end
    if getMode() == "enabled" or getMode() == "stop_only" then hookAction() end
    
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00LagCast status:|r " .. formattedMode() .. " [|cffffff00/lc|r or |cffffff00/lagcast|r for options]")
   
    if getBarType() ~= 1 then 
      LagCastFrame_changeBarType(getBarType(), true)
    end
  
	elseif ( event == "SPELLCAST_START" ) then
		lVars.startTime = GetTime();
		lVars.endTime = lVars.startTime + (arg2 / 1000);
		lVars.holdTime = 0;
		lVars.casting = 1;
		lVars.fadeOut = nil;

		lVars.mode = "casting";
    
    if getMode() == "enabled" or getMode() == "bar_only" then
      lCastBar:SetStatusBarColor(1.0, 0.7, 0.0);
      getSpark():Show();
      getCancelSpark():Show()
      do
        local co = getCancelOverlay()
        local point, _, relativePoint, xOffset, yOffset = co:GetPoint(1)
        co:ClearAllPoints()
        co:SetPoint("TOPRIGHT", -abs(xOffset), yOffset)
        co:Show()
      end
      lCastBar:SetMinMaxValues(lVars.startTime, lVars.endTime);
      lCastBar:SetValue(lVars.startTime);
      getText():SetText(arg1);
      if not getDisableTimerDisplay() then getTextTimer():Show() end
      lCastBar:SetAlpha(1.0);
      lCastBar:Show();
    end
    
	elseif ( event == "SPELLCAST_STOP" or event == "SPELLCAST_CHANNEL_STOP" ) then
    -- These events can cause a SPELLCAST_STOP. You don't know which spell caused the
    -- stop, nor do combatlog events get sent at reliable times letting you parse the
    -- info out...
    --   o) When a spell has successfully completed
    --   o) When you cancel a spell via SpellStopCast(), this event is generated
    --      immediately on the client before the server can acknowledge it
    --   o) When you move while casting
    --   o) When a mob hits you, and it gains a debuff (like Chilled from Frost Armor)
    --
    -- For example, if you start casting then immediately move, you will recieve in this order:
    --   1: SPELLCAST_STOP
    --   2: SPELLCAST_START
    --   3: SPELLCAST_INTERRUPTED
    --
    -- To deal with this madness, I will selectively SPELLCAST_STOP events.
    
    if event == "SPELLCAST_STOP" then
      -- if we move before the server gets the SPELLCAST_START event
      if not lVars.casting then return end
      
      local neverBefore = lVars.endTime - getBufferMs()/1000
      if GetTime() < neverBefore then
        -- We tend to get these when aggressively SpellStopCasting() or
        -- prematurely moving.
        --p("now=%.3f  neverBefore=%.3f", GetTime(), neverBefore)
        return
      end
    end
  
		if ( not lCastBar:IsVisible() ) then
			 lCastBar:Hide();
		end
		if ( lCastBar:IsShown() ) then
      markSpellcastStopped(event)
		end
  
	elseif ( event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED" or event == "hooked_stop" ) then
    if event == "SPELLCAST_FAILED" then
      --[[
        SPELLCAST_FAILED sometimes legitimately get interspersed between SPELLCAST_START
        and SPELLCAST_STOP events. it's annoying, we need to ignore those. But, we have to
        pay attention to them when our target dies.
       ]]
       --p("UnitExists=%s  UnitIsDead=%s", UnitExists("target"), UnitIsDead("target"))
       if UnitExists("target") and not UnitIsDead("target") and not UnitIsDead("player") then
        -- a dirty heuristic, i dont think it gets called!
        return
       end
    end
  
		if ( lCastBar:IsShown() and not lVars.channeling ) then
			lCastBar:SetValue(lVars.endTime);
			lCastBar:SetStatusBarColor(1.0, 0.0, 0.0);
			getSpark():Hide();
      getCancelSpark():Hide()
      getCancelOverlay():Hide()
      getTextTimer():Hide()
			if ( event == "SPELLCAST_FAILED" ) then
				getText():SetText(FAILED);
			else
				getText():SetText(INTERRUPTED);
			end
			lVars.casting = nil;
			lVars.fadeOut = 1;
			lVars.holdTime = GetTime() + CASTING_BAR_HOLD_TIME;
		end
	elseif ( event == "SPELLCAST_DELAYED" ) then
    if not lVars.casting then
      -- seems this happens more than i'd like, usually when being attacked
      -- so cast bar is being delayed
      --
      -- it happens always when wanding.
      --p("WARNING: DELAYED event yet not casting")
      return
    end
  
    local orig_delay = arg1/1000
    local now = GetTime()
    local delay = min(orig_delay, now-lVars.startTime)
    --p("Delay is %.03fs [was %.03fs]", delay, orig_delay)
    lVars.startTime = lVars.startTime + delay
    lVars.endTime = lVars.endTime + delay
  
		if( lCastBar:IsShown() ) then
			lCastBar:SetMinMaxValues(lVars.startTime, lVars.endTime)
		end
    
	elseif ( event == "SPELLCAST_CHANNEL_START" ) then
		lVars.startTime = GetTime();
		lVars.endTime = lVars.startTime + (arg1 / 1000);
		lVars.duration = arg1 / 1000;
		lVars.holdTime = 0;
		lVars.casting = nil;
		lVars.channeling = 1;
		lVars.fadeOut = nil;
    
    if getMode() == "enabled" or getMode() == "bar_only" then
      lCastBar:SetStatusBarColor(1.0, 0.7, 0.0);
      getSpark():Show();
      getCancelSpark():Show()
      do
        local co = getCancelOverlay()
        local point, _, relativePoint, xOffset, yOffset = co:GetPoint(1)
        co:ClearAllPoints()
        co:SetPoint("TOPLEFT", abs(xOffset), yOffset)
        co:Show()
      end
      lCastBar:SetMinMaxValues(lVars.startTime, lVars.endTime);
      lCastBar:SetValue(lVars.endTime);
      getText():SetText(arg2);
      if not getDisableTimerDisplay() then getTextTimer():Show() end
      lCastBar:SetAlpha(1.0);
      lCastBar:Show();
    end

	elseif ( event == "SPELLCAST_CHANNEL_UPDATE" ) then
    local origDuration = lVars.endTime - lVars.startTime
    lVars.endTime = GetTime() + (arg1 / 1000)
    lVars.startTime = lVars.endTime - origDuration
    --lVars.endTime = lVars.startTime + (arg1 / 1000);
		if ( lCastBar:IsShown() ) then
			lCastBar:SetMinMaxValues(lVars.startTime, lVars.endTime);
		end
    
	end
end

function LagCastFrame_OnUpdate()
	if ( lVars.casting ) then
    local lagMs = getLag()
		local time = GetTime();
		if ( time > lVars.endTime ) then
			--status = lVars.endTime
      --p("forcing bar to go away") -- this code path is extremely common
      markSpellcastStopped("SPELLCAST_STOP")
      LagCastFrame_OnUpdate()
      return
		end
    local cancelTime = lVars.endTime - (lagMs+getBufferMs())/1000
		lCastBar:SetValue(time);
		getFlash():Hide();
    
    local timeUntilCancel = cancelTime - time
    if not getDisableTimerDisplay() then
      if timeUntilCancel > 0 then
        getTextTimer():SetText(format("%.1fs", timeUntilCancel))
      else
        getTextTimer():Hide()
      end
    end
    
    local lcfw, lcfh = lCastBar:GetWidth(), lCastBar:GetHeight()
    
    local isCustom = string.find(lCastBar:GetName(), "Custom", 1, true)
    local sparkOffset = isCustom and 0 or 2

    local timePosition
    do
      local sparkPosition = math.max(0, ((time - lVars.startTime) / (lVars.endTime - lVars.startTime)) * lcfw)
      timePosition = sparkPosition
      local spark = getSpark()
      spark:ClearAllPoints()
      spark:SetPoint(isCustom and "RIGHT" or "CENTER", this, "LEFT", sparkPosition, sparkOffset)
      if isCustom and spark:GetWidth() ~= sparkOffset then
        local desiredSize = math.min(sparkPosition, LAG_CAST_SPARK_WIDTH)
        spark:SetWidth(desiredSize)
      end
    end

    do
      local sparkPosition = ((cancelTime - lVars.startTime) / (lVars.endTime - lVars.startTime)) * lcfw;
      sparkPosition = math.max(sparkPosition, timePosition)
      local spark = getCancelSpark()
      spark:ClearAllPoints()
      spark:SetPoint(isCustom and "LEFT" or "CENTER", this, "LEFT", sparkPosition, sparkOffset)
      if isCustom and spark:GetWidth() ~= sparkOffset then
        local desiredSize = math.min(lcfw - sparkPosition, LAG_CAST_SPARK_WIDTH)
        spark:SetWidth(desiredSize)
       end
      
      local cancelPos = math.max(0, (lcfw - sparkPosition) - sparkOffset)
      local overlay = getCancelOverlay()
      if overlay:GetNumPoints() ~= 1 then
        local pt, rt, rp, x, y = overlay:GetPoint(1)
        overlay:ClearAllPoints()
        overlay:SetPoint(pt, rt, rp, x, y)
      end
      overlay:SetWidth(cancelPos)
      if math.floor(overlay:GetHeight()+0.5) ~= math.floor(lcfh-2+0.5) then
        overlay:SetHeight(lcfh-sparkOffset)
      end
    end

	elseif ( lVars.channeling ) then
    local lagMs = getLag()
		local time = GetTime();
		if ( time > lVars.endTime ) then
			time = lVars.endTime
		end
		if ( time == lVars.endTime ) then
			lVars.channeling = nil;
			lVars.fadeOut = 1;
			return;
		end
    
    local cancelTime = (lagMs+getBufferMs())/1000
		local barValue = lVars.startTime + (lVars.endTime - time);
		lCastBar:SetValue( barValue );
		getFlash():Hide();
    
    local timeUntilCancel = cancelTime - time
    if not getDisableTimerDisplay() then
      if timeUntilCancel > 0 then
        getTextTimer():SetText(format("%.1fs", timeUntilCancel))
      else
        getTextTimer():Hide()
      end
    end
    
    local lcfw, lcfh = lCastBar:GetWidth(), lCastBar:GetHeight()
    
    local isCustom = string.find(lCastBar:GetName(), "Custom", 1, true)
    local sparkOffset = isCustom and 0 or 2
		-- local sparkPosition = ((barValue - lVars.startTime) / (lVars.endTime - lVars.startTime)) * lCastBar:GetWidth()
    -- local desiredSize = math.min(sparkPosition, LAG_CAST_SPARK_WIDTH)
		-- getSpark():SetPoint("CENTER", LagCastFrame, "LEFT", sparkPosition, sparkOffset)
    -- Since stuff is going in the opposite order, we'll switch around the sparks
    local timePosition
    do
      local sparkPosition = ((barValue - lVars.startTime) / (lVars.endTime - lVars.startTime)) * lcfw
      timePosition = sparkPosition
      local spark = getCancelSpark()
      spark:ClearAllPoints()
      spark:SetPoint(isCustom and "LEFT" or "CENTER", this, "LEFT", sparkPosition, sparkOffset)
      if isCustom and spark:GetWidth() ~= sparkOffset then
        local desiredSize = math.min(sparkPosition, LAG_CAST_SPARK_WIDTH)
        spark:SetWidth(desiredSize)
      end
    end

    do
      local sparkPosition = cancelTime / (lVars.endTime - lVars.startTime) * lcfw;
      sparkPosition = math.min(sparkPosition, timePosition)
      local spark = getSpark()
      spark:ClearAllPoints()
      spark:SetPoint(isCustom and "RIGHT" or "CENTER", this, "LEFT", sparkPosition, sparkOffset)
      if isCustom and spark:GetWidth() ~= sparkOffset then
        local desiredSize = math.min(sparkPosition, LAG_CAST_SPARK_WIDTH)
        spark:SetWidth(desiredSize)
       end
      
      local cancelPos = math.max(0, sparkPosition)
      local overlay = getCancelOverlay()
      if overlay:GetNumPoints() ~= 1 then
        local pt, rt, rp, x, y = overlay:GetPoint(1)
        overlay:ClearAllPoints()
        overlay:SetPoint(pt, rt, rp, x, y)
      end
      overlay:SetWidth(cancelPos)
      if math.floor(overlay:GetHeight()+0.5) ~= math.floor(lcfh-2+0.5) then
        overlay:SetHeight(lcfh-sparkOffset)
      end
    end
    
	elseif ( GetTime() < lVars.holdTime ) then
		return;
    
	elseif ( lVars.flash ) then
		local alpha = getFlash():GetAlpha() + CASTING_BAR_FLASH_STEP;
		if ( alpha < 1 ) then
			getFlash():SetAlpha(alpha);
		else
			getFlash():SetAlpha(1.0);
			lVars.flash = nil;
		end
    
	elseif ( lVars.fadeOut ) then
		local alpha = lCastBar:GetAlpha() - CASTING_BAR_ALPHA_STEP;
		if ( alpha > 0 ) then
			lCastBar:SetAlpha(alpha);
		else
			lVars.fadeOut = nil;
			lCastBar:Hide();
		end
    
	end
end

function LagCastFrame_changeBarType(idx, viaStartup)
  if (idx == 1 and viaStartup) then return end
  
  local shown = lCastBar:IsShown()
  if getBarType() == 1 or viaStartup then
    lCastBar:Hide()
    lCastBar = LagCastCustomFrame
    if shown then lCastBar:Show() end
    
  elseif idx == 1 then
    lCastBar:Hide()
    lCastBar = LagCastFrame
    if shown then lCastBar:Show() end
  end
  
  if not viaStartup then setBarType(idx) end
  
  if idx ~= 1 then
    LagCastCustomFrame_SetSparkSizes()
    lCastBar:SetStatusBarTexture(format(LAG_CAST_OPTIONS_TEX_TMPL, idx-1))
  end
end


--------------------------------------------------------------------------------------------------
-- Hooked functions
--------------------------------------------------------------------------------------------------

function LagCast_GameTooltip_ClearMoney()
	-- Intentionally empty; don't clear money while we use hidden tooltips
end

-----------------------------------------------------------------------------------------------
-- General initialisation
--------------------------------------------------------------------------------------------------

for i=1, 30 do
  table.insert(lTooltipNames, "LagCastTooltipTextLeft"..i)
  table.insert(lTooltipNames, "LagCastTooltipTextRight"..i)
end


SLASH_LAGCASTER1 = '/lagcast'
SLASH_LAGCASTER2 = '/lc'
SlashCmdList.LAGCASTER = LagCastFrame_onSlashCommand
