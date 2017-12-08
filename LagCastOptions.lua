
-- Interesting variables:
--   LagCastOptionsExtraBufferSlider
--   LagCastOptionsExtraBufferEditBox
--   LagCastOptionsMinLagSlider
--   LagCastOptionsMinLagEditBox

LAG_CAST_OPTIONS_TEX_TMPL = "Interface\\Addons\\LagCast\\CastBars\\CastTexture (%d).tga"

--------------------------------------------------------------------------------------------------
-- Internal variables and functions
--------------------------------------------------------------------------------------------------

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

for i=1,1000 do
  -- this highlight offset bug pisses me off
  local button = getglobal("DropDownList1Button"..i.."Highlight")
  if not button then break end
  button:ClearAllPoints()
  button:SetPoint("TOPLEFT", -10, 0)
  button:SetPoint("BOTTOMRIGHT", -10, 0)
end

local lScrollData = {
  clickedTexture = nil;
  clickedIdx = nil;
}

local lOriginal_UIDropDownMenu_SetText
local function unhookUIDropDownMenu_SetText()
  if not lOriginal_UIDropDownMenu_SetText then return end
  UIDropDownMenu_SetText = lOriginal_UIDropDownMenu_SetText
  lOriginal_UIDropDownMenu_SetText = nil
end


local LagCastOptionsScroll_SetupScrolling

local function getBarType() return LagCastAccount and LagCastAccount.barType or 1 end

--------------------------------------------------------------------------------------------------
-- OnFoo functions
--------------------------------------------------------------------------------------------------

local lIgnoreEvents = false
local dummyCastBarMoved = false;

local function setDummyBarWH(isCustom)
  if isCustom then
    LagCastDummyBar:SetWidth(LagCastCustomFrame:GetWidth())
    LagCastDummyBar:SetHeight(LagCastCustomFrame:GetHeight())
  else
    LagCastDummyBar:SetWidth(195)
    LagCastDummyBar:SetHeight(18)
  end
end

function LagCastOptions_OnShow()
  dummyCastBarMoved = false
  LagCastDummyBar:Show()

  local conf = LagCastAccount
  
  local v, s, t = conf.bufferMs or LAG_CAST_INITIAL_BUFFER, LagCastOptionsExtraBufferSlider, LagCastOptionsExtraBufferEditBox
  local min, max = s:GetMinMaxValues()
  s:SetValue(math.max(min, math.min(max, v)))
  t:SetText(v)
  
  v, s, t = conf.minLag or LAG_CAST_MIN_LAG, LagCastOptionsMinLagSlider, LagCastOptionsMinLagEditBox
  min, max = s:GetMinMaxValues()
  s:SetValue(math.max(min, math.min(max, v)))
  t:SetText(v)
  -- this also calls setDummyBarWH(...)
  LagCastOptionsScroll_SetupScrolling()
end

function LagCastOptions_OnExtraBufferText()
  if lIgnoreEvents or not this:IsVisible() then return end
  lIgnoreEvents = true
  local slider = LagCastOptionsExtraBufferSlider
  
  local val = tonumber(this:GetText())
  if val ~= nil and slider:GetValue() ~= val then
    local min, max = slider:GetMinMaxValues()
    slider:SetValue(math.max(min, math.min(max, val)))
  end
  lIgnoreEvents = false
end

function LagCastOptions_OnExtraBuffer()
  if lIgnoreEvents or not this:IsVisible() then return end
  lIgnoreEvents = true
  LagCastOptionsExtraBufferEditBox:SetText(this:GetValue())
  lIgnoreEvents = false
end

function LagCastOptions_OnMinLagText()
  if lIgnoreEvents or not this:IsVisible() then return end
  lIgnoreEvents = true
  local slider = LagCastOptionsMinLagSlider
  
  local val = tonumber(this:GetText())
  if val ~= nil and slider:GetValue() ~= val then
    local min, max = slider:GetMinMaxValues()
    slider:SetValue(math.max(min, math.min(max, val)))
  end
  lIgnoreEvents = false
end

function LagCastOptions_OnMinLag()
  if lIgnoreEvents or not this:IsVisible() then return end
  lIgnoreEvents = true
  LagCastOptionsMinLagEditBox:SetText(this:GetValue())
  lIgnoreEvents = false
end

local newMode
function LagCastOptions_OnCancel()
  unhookUIDropDownMenu_SetText()
  LagCastDummyBar:Hide()
  LagCastOptions:Hide()
  newMode = nil
end

function LagCastOptions_OnOkay()
  unhookUIDropDownMenu_SetText()

  local buf = tonumber(LagCastOptionsExtraBufferEditBox:GetText()) or LagCastOptionsExtraBufferSlider:GetValue()
  local lag = tonumber(LagCastOptionsMinLagEditBox:GetText()) or LagCastOptionsMinLagSlider:GetValue()

  -- refactor
  LagCastAccount.bufferMs = buf
  LagCastAccount.minLag = lag
  LagCastAccount.disableSpamPrevention = not(LagCastOptionsPreventSpam:GetChecked())
  LagCastAccount.disableTimerDisplay = not(LagCastOptionsTimerDisplay:GetChecked())
  -- dontDisplayTimer
  
  local o = LagCastDummyBar
  
  if dummyCastBarMoved then
    if lScrollData.clickedIdx == 1 and (math.floor(o:GetWidth()+0.5) ~= 195 or math.floor(o:GetHeight()+0.5) ~= 18) then
      message("Please be aware; only non-Blizzard cast bars can have custom sizes")
    end
  
    local n = LagCastFrame
    local point, _, relativePoint, xOffset, yOffset = o:GetPoint()
    
    n:SetUserPlaced(true)
    n:ClearAllPoints()
    n:SetPoint(point, UIParent, relativePoint, xOffset, yOffset-5)
    
    n = LagCastCustomFrame
    n:SetUserPlaced(true)
    n:ClearAllPoints()
    LagCastFrame_SetCustomWH(o:GetWidth(), o:GetHeight())
    n:SetPoint(point, UIParent, relativePoint, xOffset, yOffset)
    LagCastCustomFrame_SetSparkSizes()
  end
  
  if newMode then
    LagCastFrame_onSlashCommand(newMode)
  end

  if lScrollData.selected ~= lScrollData.clickedIdx then
    LagCastFrame_changeBarType(lScrollData.clickedIdx)
  end
  
  LagCastDummyBar:Hide()
  LagCastOptions:Hide()
  newMode = nil
end

local prevLagVal
function LagCastOptions_Latency_OnUpdate()
  local _, _, lag = GetNetStats()
  if (lag == prevLagVal) then return end
  prevLagVal = lag
  LagCastOptionsCurrentLatencyLabel:SetText("Current Latency: "..lag.."ms")
end

function LagCastOptions_barMoved()
  dummyCastBarMoved = true
end

function LagCastOptionsMode_Layout()
  local py = this:GetParent():GetTop()
  local y = LagCastOptionsCurrentLatency:GetTop()
  this:ClearAllPoints()
  this:SetPoint("TOPLEFT", 10, y-py+3)
end

function LagCastOptionsMode_Populate()
  local modeFrame = this
  local items = {
    { mode="enabled",   text="Enabled",           r=0,  g=1,    b=0 },
    { mode="bar_only",  text="Bar Only",          r=1,  g=0.5,  b=0.3125 },
    { mode="stop_only", text="StopCasting Only",  r=1,  g=0.5,  b=0.3125 },
    { mode="disabled",  text= "Disabled",         r=1,  g=0,    b=0 }
  }
  lOriginal_UIDropDownMenu_SetText = UIDropDownMenu_SetText
  
  UIDropDownMenu_SetText = function(text, frame)
    lOriginal_UIDropDownMenu_SetText(text, frame)
    if frame ~= modeFrame then return end
    for k, v in items do
      if v.text == text then
        local filterText = getglobal(frame:GetName().."Text")
        filterText:SetTextColor(v.r, v.g, v.b)
        return
      end
    end
  end
    
  local selectedIdx = 1
  UIDropDownMenu_Initialize(this, function()
    local onClick = function(opt)
      newMode = opt
      UIDropDownMenu_SetSelectedID(modeFrame, this:GetID())
    end
  
    local currMode = LagCastCharacter.mode
    for k,v in pairs(items) do
      local info = { }
      info.text = v.text
      info.value = v.text
      info.func = onClick
      info.arg1 = v.mode
      info.textR = v.r
      info.textG = v.g
      info.textB = v.b
      if currMode == v.mode then selectedIdx = k end
      -- info.checked = currMode == k and 1 or nil
      --info.tooltipTitle = "Yo this is title";
      --info.toottipText = "Yo this is text";
      UIDropDownMenu_AddButton(info)
    end
  end)
  UIDropDownMenu_SetWidth(130);
  UIDropDownMenu_SetButtonWidth(124)
  UIDropDownMenu_JustifyText("LEFT")
  UIDropDownMenu_SetSelectedID(this, selectedIdx)
end

function LagCastOptionsScroll_LoadTextures()
  local chld = LagCastOptionsBarsScrollChildFrame
  local ntex = 0
  
  local numRows, rowsPerPage, rowHeight = 109, 6, 35
  
  local textures = { }
  local onClicked = function(idx, clicked)
    if lScrollData.clickedIdx == idx then return end

    setDummyBarWH(idx ~= 1)
    
    clicked:Show()
    if lScrollData.clickedTexture then lScrollData.clickedTexture:Hide() end
    lScrollData.clickedIdx = idx
    lScrollData.clickedTexture = clicked
  end
  
  LagCastOptionsScroll_SetupScrolling = function()
    lScrollData.clickedTexture = nil
    lScrollData.clickedIdx = nil
    lScrollData.selected = getBarType()
    for i, v in textures do
      if i == lScrollData.selected then
        onClicked(i, v.clicked)
      else
        v.clicked:Hide()
        v.highlight:Hide()
      end
    end
    
    local old_this, old_arg1 = this, arg1
    this, arg1 = LagCastOptionsBars, (math.min(numRows - rowsPerPage, math.max(0, lScrollData.selected-3))) * rowHeight
    FauxScrollFrame_OnVerticalScroll(rowHeight, function() end)
    this, arg1 = old_this, old_arg1
  end
  
  local function InsertCastTexture(textureName)
    local b = CreateFrame("Button", nil, chld)
    b:SetHeight(32)
    b:SetPoint("TOPLEFT", 0, -35*ntex)
    b:SetPoint("TOPRIGHT", 0, -35*ntex)
    b:EnableMouse(true)
    
    local f
    if textureName then
      f = CreateFrame("StatusBar", nil, b)
      f:SetAllPoints()
      f:SetStatusBarColor(1, 1, 1)
      f:SetStatusBarTexture(textureName)
      f:SetStatusBarColor(1, 0.7, 0)
      f:SetMinMaxValues(0, 10)
      f:SetBackdrop({ bgFile = textureName, tile = false })
      f:SetBackdropColor(0, 1, 0)
      
      -- doing this adds more confusion imho
      --f:SetValue(mod(ntex-1, 7) + 2)
      
      -- this sets the initial piss-yellow colour to the green graphs
      f:SetValue(3)
      
    else
      f = CreateFrame("StatusBar", "LagCastOptionsScrollBlizzlike", b, "LagCastTemplate")
      f:SetPoint("CENTER", 0, 0)
      LagCastOptionsScrollBlizzlikeCancelOverlay:Hide()
      f:SetHeight(13)
      f:SetMinMaxValues(0, 10)
      f:SetValue(5)

    end

    local hframe = CreateFrame("Frame", nil, b)
    hframe:SetAllPoints(true)
    
    local highlight = hframe:CreateTexture("OVERLAY")
    highlight:SetAllPoints()
    highlight:SetTexture(1, 1, 1, 0.3)
    highlight:SetBlendMode("BLEND")
    highlight:Hide()
    
    local clicked = hframe:CreateTexture("OVERLAY")
    clicked:SetPoint("TOPLEFT", 0, 0)
    clicked:SetPoint("BOTTOMRIGHT", 20, 0)
    clicked:SetTexture(1, 1, 1, 0.5)
    clicked:SetBlendMode("BLEND")
    clicked:SetGradientAlpha("HORIZONTAL", 1,1,1,0,  1,1,1,1)
    clicked:Hide()
    
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnEnter", function() highlight:Show() end)
    b:SetScript("OnLeave", function() highlight:Hide() end)
    local idx = ntex+1
    b:SetScript("OnClick", function() onClicked(idx, clicked) end)
    
    table.insert(textures, { clicked = clicked, highlight=highlight })
    
    ntex = ntex + 1
    
  end
  
  InsertCastTexture()
  for i=1,numRows-1 do
    InsertCastTexture(format(LAG_CAST_OPTIONS_TEX_TMPL, i))
  end
  -- this method still gets called if config is closed and reopened, so mark it as a noop
  LagCastOptionsScroll_LoadTextures = function() end
  FauxScrollFrame_Update(this, numRows, rowsPerPage, rowHeight)
end