local _, addon = ...

local Compatibility = {}
addon.Compatibility = Compatibility

local Client = {}
Client.__index = Client

local function callMethod(object, methodName, ...)
    if object == nil then
        return false
    end

    local method = object[methodName]
    if type(method) ~= "function" then
        return false
    end

    local ok = pcall(method, object, ...)
    return ok
end

local function callFunction(callback, ...)
    if type(callback) ~= "function" then
        return false
    end

    return pcall(callback, ...)
end

function Compatibility.Create(environment)
    return setmetatable({
        databaseName = addon.Identity.databaseName,
        environment = environment or _G,
    }, Client)
end

function Client:GetClientProfile()
    if self.clientProfile == nil then
        self.clientProfile = addon.ClientProfile.Detect(
            self.environment,
            addon.Identity.addonName
        )
    end

    return self.clientProfile
end

function Client:CreateEventFrame()
    local createFrame = self.environment.CreateFrame
    if type(createFrame) ~= "function" then
        return nil
    end

    local ok, frame = pcall(createFrame, "Frame")
    if not ok then
        return nil
    end

    return frame
end

function Client:RegisterEvent(frame, eventName)
    return callMethod(frame, "RegisterEvent", eventName)
end

function Client:SetEventHandler(frame, handler)
    return callMethod(frame, "SetScript", "OnEvent", handler)
end

function Client:IsLoggedIn()
    local ok, loggedIn = callFunction(self.environment.IsLoggedIn)
    return ok and loggedIn ~= nil and loggedIn ~= false
end

local function withoutLeadingSlash(command)
    return string.gsub(command, "^/", "")
end

function Client:RegisterSlashCommand(command, alias, key, handler)
    if type(command) ~= "string"
        or type(alias) ~= "string"
        or type(key) ~= "string"
        or type(handler) ~= "function"
    then
        return false
    end

    local registerNewSlashCommand = self.environment.RegisterNewSlashCommand
    if type(registerNewSlashCommand) == "function" then
        local ok = pcall(
            registerNewSlashCommand,
            handler,
            withoutLeadingSlash(command),
            withoutLeadingSlash(alias)
        )
        if ok then
            return true
        end
    end

    local slashCommands = self.environment.SlashCmdList
    if type(slashCommands) ~= "table" then
        return false
    end

    self.environment["SLASH_" .. key .. "1"] = command
    self.environment["SLASH_" .. key .. "2"] = alias
    slashCommands[key] = handler
    return true
end

function Client:Print(message)
    local chatFrame = self.environment.DEFAULT_CHAT_FRAME
    if callMethod(chatFrame, "AddMessage", message) then
        return true
    end

    local printMessage = self.environment.print
    if type(printMessage) == "function" then
        local ok = pcall(printMessage, message)
        return ok
    end

    return false
end

function Client:GetCurrentCharacterIdentity()
    local ok, name, unitRealm = callFunction(self.environment.UnitName, "player")
    if not ok or type(name) ~= "string" or name == "" then
        return nil
    end

    -- Both clients report a placeholder name until the player is ready.
    local placeholder = self.environment.UNKNOWNOBJECT
    if name == (type(placeholder) == "string" and placeholder or "Unknown") then
        return nil
    end

    local realm = unitRealm
    if type(realm) ~= "string" or realm == "" then
        local realmOk, currentRealm = callFunction(self.environment.GetRealmName)
        if realmOk then
            realm = currentRealm
        end
    end

    if type(realm) ~= "string" or realm == "" then
        return nil
    end

    local stableId
    local guidOk, guid = callFunction(self.environment.UnitGUID, "player")
    if guidOk and type(guid) == "string" and guid ~= "" then
        stableId = guid
    end

    return {
        name = name,
        realm = realm,
        stableId = stableId,
    }
end

-- Carried money in copper, or nil when the client cannot report it.
function Client:GetCarriedMoney()
    local ok, copper = callFunction(self.environment.GetMoney)
    if not ok or type(copper) ~= "number" or copper < 0 or copper ~= math.floor(copper) then
        return nil
    end

    return copper
end

-- true/false for guild membership, or nil when the client cannot report it.
function Client:IsInGuild()
    local ok, inGuild = callFunction(self.environment.IsInGuild)
    if not ok then
        return nil
    end

    return inGuild ~= nil and inGuild ~= false
end

-- Calls onChange() whenever the client reports that carried money changed.
-- Client event names stay here so Core modules only see the normalized call.
function Client:ObserveMoneyChanges(onChange)
    if type(onChange) ~= "function" or type(self.environment.GetMoney) ~= "function" then
        return false
    end

    local frame = self:CreateEventFrame()
    if frame == nil
        or not self:SetEventHandler(frame, function()
            onChange()
        end)
        or not self:RegisterEvent(frame, "PLAYER_MONEY")
    then
        return false
    end

    self.moneyFrame = frame
    return true
end

-- Seconds from the client's monotonic clock, or nil when unavailable.
function Client:Now()
    local ok, now = callFunction(self.environment.GetTime)
    if not ok or type(now) ~= "number" then
        return nil
    end

    return now
end

-- Runs callback once after `seconds`. Returns false when the client has no
-- timer, so callers can act immediately instead.
-- Wall-clock seconds for saved records; GetTime() restarts with the client.
function Client:Timestamp()
    local ok, now = callFunction(self.environment.GetServerTime)
    if not ok or type(now) ~= "number" then
        ok, now = callFunction(self.environment.time)
    end
    if not ok or type(now) ~= "number" then
        return nil
    end

    return now
end

function Client:After(seconds, callback)
    local timers = self.environment.C_Timer
    if type(timers) ~= "table" or type(timers.After) ~= "function" or type(callback) ~= "function" then
        return false
    end

    local ok = pcall(timers.After, seconds, callback)
    return ok
end

-- Client events that describe where the next money change came from, mapped
-- to normalized source context. "open"/"close" bracket an interaction;
-- "note" is a single corroborating message.
local CONTEXT_EVENTS = {
    CHAT_MSG_MONEY = { source = "loot", action = "note" },
    LOOT_CLOSED = { source = "loot", action = "close" },
    LOOT_OPENED = { source = "loot", action = "open" },
    MERCHANT_CLOSED = { source = "vendorSales", action = "close" },
    MERCHANT_SHOW = { source = "vendorSales", action = "open" },
    -- QUEST_TURNED_IN(questID, xpReward, moneyReward): the reward is the
    -- exact copper the next money change should add (seen in captured traces).
    QUEST_TURNED_IN = { source = "quests", action = "note", amountArgument = 3 },
    -- A completed trade adds money around TRADE_CLOSED; a cancelled trade
    -- adds none, so it never produces a gain to classify.
    TRADE_CLOSED = { source = "playerTrades", action = "close" },
    TRADE_SHOW = { source = "playerTrades", action = "open" },
    -- Money gained while the guild bank is open is a withdrawal (excluded).
    -- Guild-bank money update events are deliberately not used: they also
    -- fire for guild funds changes that never touch the player's money.
    GUILDBANKFRAME_CLOSED = { source = "guildBankWithdrawal", action = "close" },
    GUILDBANKFRAME_OPENED = { source = "guildBankWithdrawal", action = "open" },
}

-- Newer clients report interaction windows by Enum.PlayerInteractionType.
local INTERACTION_TYPES = {
    [1] = "playerTrades", -- TradePartner
    [10] = "guildBankWithdrawal", -- GuildBanker
}
local INTERACTION_ACTIONS = {
    PLAYER_INTERACTION_MANAGER_FRAME_HIDE = "close",
    PLAYER_INTERACTION_MANAGER_FRAME_SHOW = "open",
}

local function copperAmount(value)
    if type(value) ~= "number" or value < 0 or value ~= math.floor(value) then
        return nil
    end
    return value
end

-- Calls onContext(source, action, amount) for each recognized context
-- event. Payloads are not trusted: the only value read is a documented
-- copper amount, and a malformed one is dropped (amount = nil).
function Client:ObserveIncomeContext(onContext)
    if type(onContext) ~= "function" then
        return false
    end

    local frame = self:CreateEventFrame()
    if frame == nil
        or not self:SetEventHandler(frame, function(_, eventName, ...)
            local context = CONTEXT_EVENTS[eventName]
            if context ~= nil then
                local amount
                if context.amountArgument ~= nil then
                    amount = copperAmount((select(context.amountArgument, ...)))
                end
                onContext(context.source, context.action, amount)
                return
            end

            local action = INTERACTION_ACTIONS[eventName]
            local source = action and INTERACTION_TYPES[(...)]
            if source ~= nil then
                onContext(source, action)
            end
        end)
    then
        return false
    end

    local registered = false
    local eventName
    for eventName in pairs(CONTEXT_EVENTS) do
        -- An event this client lacks is skipped; the others still work.
        registered = self:RegisterEvent(frame, eventName) or registered
    end
    for eventName in pairs(INTERACTION_ACTIONS) do
        registered = self:RegisterEvent(frame, eventName) or registered
    end

    self.contextFrame = frame
    self:ObserveMailCollection(onContext)
    self:ObserveTransferCalls(onContext)
    return registered
end

-- Copper the character paid for the refundable item in `bag`/`slot`, or nil.
function Client:ReadPurchasePrice(bag, slot, isEquipped)
    local containers = self.environment.C_Container
    if type(containers) == "table" then
        local ok, info = callFunction(containers.GetContainerItemPurchaseInfo, bag, slot, isEquipped)
        if ok and type(info) == "table" then
            return copperAmount(info.money)
        end
    end

    local ok, money = callFunction(self.environment.GetContainerItemPurchaseInfo, bag, slot, isEquipped)
    return ok and copperAmount(money) or nil
end

-- Hooks the calls that return money the player already had: withdrawing
-- from the guild bank and refunding a purchased item. Each becomes an
-- exclusion note carrying the exact amount when the client reports it.
function Client:ObserveTransferCalls(onContext)
    local hook = self.environment.hooksecurefunc
    if type(hook) ~= "function" or self.transfersHooked then
        return false
    end

    local hooked = false
    local function hookCall(owner, callName, handler)
        if type(owner) == "table" and type(owner[callName]) == "function" then
            local ok
            if owner == self.environment then
                ok = pcall(hook, callName, handler)
            else
                ok = pcall(hook, owner, callName, handler)
            end
            hooked = ok or hooked
        end
    end

    hookCall(self.environment, "WithdrawGuildBankMoney", function(copper)
        onContext("guildBankWithdrawal", "note", copperAmount(copper))
    end)

    local function onRefund(bag, slot, isEquipped)
        onContext("refund", "note", self:ReadPurchasePrice(bag, slot, isEquipped))
    end
    hookCall(self.environment.C_Container, "ContainerRefundItemPurchase", onRefund)
    hookCall(self.environment, "ContainerRefundItemPurchase", onRefund)

    self.transfersHooked = hooked
    return hooked
end

-- Reads what the client says about inbox mail `index`: its attached money,
-- whether it was returned to sender, and its auction invoice type.
function Client:ReadInboxMail(index)
    local headerOk, _, _, _, _, money, _, _, _, _, wasReturned =
        callFunction(self.environment.GetInboxHeaderInfo, index)
    if not headerOk or copperAmount(money) == nil then
        return nil
    end

    local invoiceOk, invoiceType = callFunction(self.environment.GetInboxInvoiceInfo, index)
    return {
        invoiceType = invoiceOk and invoiceType or nil,
        money = money,
        returned = wasReturned ~= nil and wasReturned ~= false and wasReturned ~= 0,
    }
end

function Client:SnapshotInbox()
    local ok, count = callFunction(self.environment.GetInboxNumItems)
    local snapshot = {}
    if ok and type(count) == "number" then
        local index
        for index = 1, count do
            snapshot[index] = self:ReadInboxMail(index)
        end
    end
    self.inboxSnapshot = snapshot
end

-- Collecting mail money is a function call rather than an event, so the
-- collect calls are hooked. The inbox is snapshotted whenever it updates,
-- because the client may clear a mail's money as soon as it is collected.
-- Money from returned mail is reported as a return, auction sale proceeds
-- (a "seller" invoice) as auctions, and anything else as ordinary mail.
local MAIL_COLLECT_CALLS = { "TakeInboxMoney", "AutoLootMailItem" }

function Client:ObserveMailCollection(onContext)
    local hook = self.environment.hooksecurefunc
    if type(hook) ~= "function" or self.mailHooked then
        return false
    end

    local frame = self:CreateEventFrame()
    if frame == nil
        or not self:SetEventHandler(frame, function()
            self:SnapshotInbox()
        end)
    then
        return false
    end
    self:RegisterEvent(frame, "MAIL_SHOW")
    self:RegisterEvent(frame, "MAIL_INBOX_UPDATE")
    self.mailFrame = frame

    local hooked = false
    local index
    for index = 1, #MAIL_COLLECT_CALLS do
        local callName = MAIL_COLLECT_CALLS[index]
        if type(self.environment[callName]) == "function" then
            hooked = pcall(hook, callName, function(mailIndex)
                -- Prefer the live mail; fall back to the snapshot if the
                -- client already cleared its money. A stale snapshot entry
                -- carries the wrong amount, so it cannot match the gain.
                local mail = self:ReadInboxMail(mailIndex)
                if (mail == nil or mail.money <= 0) and self.inboxSnapshot ~= nil then
                    mail = self.inboxSnapshot[mailIndex]
                end
                if mail == nil or mail.money <= 0 then
                    return
                end
                local source = "mailbox"
                if mail.returned then
                    source = "returnedMail"
                elseif mail.invoiceType == "seller" then
                    source = "auctions"
                end
                onContext(source, "note", mail.money)
            end) or hooked
        end
    end

    self.mailHooked = hooked
    return hooked
end

-- The player's current guild as { name, realm }, or nil when guildless or
-- unknown. GetGuildInfo reports no realm for a guild on the player's realm.
function Client:GetGuildIdentity()
    local ok, name, _, _, realm = callFunction(self.environment.GetGuildInfo, "player")
    if not ok or type(name) ~= "string" or name == "" then
        return nil
    end

    if type(realm) ~= "string" or realm == "" then
        local realmOk, currentRealm = callFunction(self.environment.GetRealmName)
        realm = realmOk and currentRealm or nil
    end
    if type(realm) ~= "string" or realm == "" then
        return nil
    end

    -- Newer clients expose a stable guild club id; the realm-qualified name
    -- is the fallback identity everywhere else.
    local identity = { name = name, realm = realm }
    local clubs = self.environment.C_Club
    if type(clubs) == "table" then
        local idOk, clubId = callFunction(clubs.GetGuildClubId)
        if idOk and (type(clubId) == "string" or type(clubId) == "number") then
            identity.id = tostring(clubId)
        end
    end
    return identity
end

-- Calls onOpen() / onClose() when the guild bank window opens or closes.
-- Newer clients report it through the interaction manager (GuildBanker = 10).
local GUILD_BANK_INTERACTION = 10

function Client:ObserveGuildBank(onOpen, onClose)
    if type(onOpen) ~= "function" or type(onClose) ~= "function" then
        return false
    end

    local frame = self:CreateEventFrame()
    if frame == nil
        or not self:SetEventHandler(frame, function(_, eventName, interactionType)
            if eventName == "GUILDBANKFRAME_OPENED"
                or (eventName == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
                    and interactionType == GUILD_BANK_INTERACTION)
            then
                onOpen()
            elseif eventName == "GUILDBANKFRAME_CLOSED"
                or (eventName == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE"
                    and interactionType == GUILD_BANK_INTERACTION)
            then
                onClose()
            end
        end)
    then
        return false
    end

    local registered = false
    local index
    local events = {
        "GUILDBANKFRAME_OPENED",
        "GUILDBANKFRAME_CLOSED",
        "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
        "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    }
    for index = 1, #events do
        registered = self:RegisterEvent(frame, events[index]) or registered
    end

    self.guildBankFrame = frame
    return registered
end

-- Calls onBlocked(functionName) when the client refuses a protected call
-- made by this add-on (ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN).
function Client:ObserveActionBlocked(onBlocked)
    if type(onBlocked) ~= "function" then
        return false
    end

    local frame = self:CreateEventFrame()
    if frame == nil
        or not self:SetEventHandler(frame, function(_, _, addonName, functionName)
            if addonName == addon.Identity.addonName then
                onBlocked(functionName)
            end
        end)
    then
        return false
    end

    local blocked = self:RegisterEvent(frame, "ADDON_ACTION_BLOCKED")
    local forbidden = self:RegisterEvent(frame, "ADDON_ACTION_FORBIDDEN")
    return blocked or forbidden
end

-- Calls onDeposit(copper) after every guild-bank money deposit request,
-- including ones made from Blizzard's own guild-bank window.
function Client:ObserveGuildBankDeposits(onDeposit)
    local hook = self.environment.hooksecurefunc
    if type(onDeposit) ~= "function"
        or type(hook) ~= "function"
        or type(self.environment.DepositGuildBankMoney) ~= "function"
        or self.depositsHooked
    then
        return false
    end

    self.depositsHooked = pcall(hook, "DepositGuildBankMoney", function(copper)
        onDeposit(copperAmount(copper))
    end)
    return self.depositsHooked
end

-- Asks the client to move `copper` from the player into the guild bank.
-- Returns true when the request was made; completion is confirmed later by
-- the player's carried money dropping by that amount.
function Client:DepositGuildBankMoney(copper)
    if copperAmount(copper) == nil or copper <= 0 then
        return false
    end
    local ok = callFunction(self.environment.DepositGuildBankMoney, copper)
    return ok == true
end

-- The tithe offer shown with the guild bank. Returns nil when the client
-- cannot create frames. It exposes Show(lines, onDeposit), Hide(), and
-- IsShown(). When the guild bank window's Withdraw button can be found, the
-- offer is a "Give Tithe" button just left of it, with the lines in its
-- tooltip; otherwise it is a small panel beside the bank. The pay button
-- only works when onDeposit is given.
function Client:CreatePaymentPanel(title)
    local createFrame = self.environment.CreateFrame
    if type(createFrame) ~= "function" then
        return nil
    end

    local environment = self.environment
    local ok, panel = pcall(function()
        -- Newer clients need BackdropTemplate for a frame to take a backdrop.
        local template = environment.BackdropTemplateMixin ~= nil and "BackdropTemplate" or nil
        local frame = createFrame("Frame", nil, environment.UIParent, template)
        frame:SetSize(260, 96)
        frame:SetPoint("CENTER")
        -- Above the guild bank window, which would otherwise cover it.
        pcall(frame.SetFrameStrata, frame, "DIALOG")
        pcall(frame.SetBackdrop, frame, {
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })

        local heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        heading:SetPoint("TOPLEFT", 10, -10)
        heading:SetText(title)

        local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        body:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -6)
        body:SetJustifyH("LEFT")

        local button = createFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(120, 22)
        button:SetPoint("BOTTOMLEFT", 10, 10)
        button:SetText("Deposit")

        frame:Hide()
        return { body = body, button = button, frame = frame }
    end)
    if not ok then
        return nil
    end

    -- The game's Withdraw button, under its current or older name.
    local function findWithdrawButton()
        local bank = environment.GuildBankFrame
        if type(bank) ~= "table" then
            return nil
        end
        return bank.WithdrawButton or environment.GuildBankFrameWithdrawButton
    end

    local function showTooltip(owner)
        local tooltip = environment.GameTooltip
        if type(tooltip) ~= "table" or type(panel.lines) ~= "table" then
            return
        end
        pcall(function()
            tooltip:SetOwner(owner, "ANCHOR_TOP")
            tooltip:SetText(title)
            local index
            for index = 1, #panel.lines do
                tooltip:AddLine(panel.lines[index], 1, 1, 1)
            end
            tooltip:Show()
        end)
    end

    -- The pay button inside the guild bank window, or nil when the window's
    -- Withdraw button cannot be found.
    function panel:Inline()
        local withdraw = findWithdrawButton()
        if withdraw == nil then
            return nil
        end
        if self.inlineButton ~= nil and self.inlineAnchor == withdraw then
            return self.inlineButton
        end
        local created, button = pcall(function()
            local inline = createFrame("Button", nil, environment.GuildBankFrame,
                "UIPanelButtonTemplate")
            inline:SetSize(100, 22)
            inline:SetPoint("RIGHT", withdraw, "LEFT", -4, 0)
            -- Disabled buttons ignore the mouse unless told otherwise, and
            -- the tooltip is how a disabled Give Tithe explains itself.
            pcall(inline.SetMotionScriptsWhileDisabled, inline, true)
            inline:SetScript("OnEnter", showTooltip)
            inline:SetScript("OnLeave", function()
                local tooltip = environment.GameTooltip
                if type(tooltip) == "table" then
                    pcall(tooltip.Hide, tooltip)
                end
            end)
            return inline
        end)
        if not created then
            return nil
        end
        if self.inlineButton ~= nil then
            self.inlineButton:Hide()
        end
        self.inlineButton = button
        self.inlineAnchor = withdraw
        return button
    end

    -- The guild bank window loads on demand, after this panel is created, so
    -- the panel attaches beside it each time it is shown.
    function panel:Attach()
        local bank = environment.GuildBankFrame
        if bank == nil or self.attachedTo == bank then
            return
        end
        local frame = self.frame
        local attached = pcall(function()
            frame:SetParent(bank)
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", bank, "TOPRIGHT", 4, 0)
            frame:SetFrameStrata("DIALOG")
        end)
        if attached then
            self.attachedTo = bank
        end
    end

    function panel:Show(lines, onDeposit)
        self.lines = lines
        self.body:SetText(table.concat(lines, "\n"))
        local inline = self:Inline()
        if inline ~= nil then
            self.frame:Hide()
            inline:SetText(onDeposit ~= nil and "Give Tithe" or "Depositing...")
            inline:SetScript("OnClick", onDeposit)
            if onDeposit ~= nil then
                pcall(inline.Enable, inline)
            else
                pcall(inline.Disable, inline)
            end
            inline:Show()
            self.inlineShown = true
            return
        end
        self.inlineShown = false
        self:Attach()
        self.button:SetScript("OnClick", onDeposit)
        if onDeposit ~= nil then
            self.button:Show()
        else
            self.button:Hide()
        end
        self.frame:Show()
    end

    -- Nothing can be given now. The in-bank button stays, disabled, with
    -- `lines` in its tooltip; the side panel is simply hidden.
    function panel:ShowUnavailable(lines)
        local inline = self:Inline()
        if inline == nil then
            self:Hide()
            return
        end
        self.lines = lines
        self.body:SetText(table.concat(lines, "\n"))
        self.frame:Hide()
        inline:SetText("Give Tithe")
        inline:SetScript("OnClick", nil)
        pcall(inline.Disable, inline)
        inline:Show()
        self.inlineShown = true
    end

    function panel:Hide()
        self.button:SetScript("OnClick", nil)
        self.frame:Hide()
        if self.inlineButton ~= nil then
            self.inlineButton:SetScript("OnClick", nil)
            self.inlineButton:Hide()
        end
        self.inlineShown = false
    end

    function panel:IsShown()
        if self.inlineShown then
            return self.inlineButton:IsShown() == true
        end
        return self.frame:IsShown() == true
    end

    return panel
end

function Client:GetAccountDatabase()
    return self.environment[self.databaseName]
end

function Client:SetAccountDatabase(database)
    self.environment[self.databaseName] = database
    return true
end

local function validBinding(options)
    return type(options) == "table"
        and type(options.getValue) == "function"
        and type(options.setValue) == "function"
end

function Client:RegisterSettingsCategory(options)
    local settings = self.environment.Settings
    local createSectionHeader = self.environment.CreateSettingsListSectionHeaderInitializer
    if type(options) ~= "table"
        or not validBinding(options.percentage)
        or type(options.checkboxSections) ~= "table"
        or type(options.balanceText) ~= "string"
        or type(createSectionHeader) ~= "function"
        or type(settings) ~= "table"
        or type(settings.RegisterVerticalLayoutCategory) ~= "function"
        or type(settings.RegisterProxySetting) ~= "function"
        or type(settings.CreateSliderOptions) ~= "function"
        or type(settings.CreateSlider) ~= "function"
        or type(settings.CreateCheckbox) ~= "function"
        or type(settings.RegisterAddOnCategory) ~= "function"
        or type(settings.VarType) ~= "table"
        or settings.VarType.Number == nil
        or settings.VarType.Boolean == nil
    then
        return nil
    end

    local sectionIndex, checkboxIndex
    for sectionIndex = 1, #options.checkboxSections do
        local section = options.checkboxSections[sectionIndex]
        if type(section) ~= "table"
            or type(section.heading) ~= "string"
            or section.heading == ""
            or type(section.checkboxes) ~= "table"
        then
            return nil
        end

        for checkboxIndex = 1, #section.checkboxes do
            if not validBinding(section.checkboxes[checkboxIndex]) then
                return nil
            end
        end
    end

    local ok, category, balanceInitializer, lifetimeInitializer = pcall(function()
        local percentage = options.percentage
        local registeredCategory, layout = settings.RegisterVerticalLayoutCategory(
            options.categoryName
        )
        if registeredCategory == nil
            or type(layout) ~= "table"
            or type(layout.AddInitializer) ~= "function"
        then
            error("settings category was not created")
        end

        local balanceInitializer = createSectionHeader("Tithe - Current balance: " ..
            options.balanceText)
        if balanceInitializer == nil then
            error("balance display was not created")
        end
        layout:AddInitializer(balanceInitializer)

        local lifetimeInitializer
        if type(options.lifetimeText) == "string" then
            lifetimeInitializer = createSectionHeader("Tithe - Lifetime given: " ..
                options.lifetimeText)
            if lifetimeInitializer == nil then
                error("lifetime display was not created")
            end
            layout:AddInitializer(lifetimeInitializer)
        end

        local setting = settings.RegisterProxySetting(
            registeredCategory,
            percentage.variable,
            settings.VarType.Number,
            percentage.label,
            percentage.defaultValue,
            percentage.getValue,
            percentage.setValue
        )
        if setting == nil then
            error("percentage setting was not created")
        end

        local sliderOptions = settings.CreateSliderOptions(
            percentage.minimum,
            percentage.maximum,
            percentage.step
        )
        if sliderOptions == nil then
            error("percentage slider options were not created")
        end

        local sliderMixin = self.environment.MinimalSliderWithSteppersMixin
        if type(sliderOptions.SetLabelFormatter) ~= "function"
            or type(sliderMixin) ~= "table"
            or type(sliderMixin.Label) ~= "table"
            or sliderMixin.Label.Right == nil
        then
            error("percentage slider formatter is unavailable")
        end
        sliderOptions:SetLabelFormatter(
            sliderMixin.Label.Right,
            function(value)
                return string.format("%.0f%%", value)
            end
        )

        local slider = settings.CreateSlider(
            registeredCategory,
            setting,
            sliderOptions,
            percentage.tooltip
        )
        if slider == nil then
            error("percentage slider was not created")
        end

        for sectionIndex = 1, #options.checkboxSections do
            local section = options.checkboxSections[sectionIndex]
            local sectionInitializer = createSectionHeader(section.heading)
            if sectionInitializer == nil then
                error("settings section was not created")
            end
            layout:AddInitializer(sectionInitializer)

            for checkboxIndex = 1, #section.checkboxes do
                local checkbox = section.checkboxes[checkboxIndex]
                local checkboxSetting = settings.RegisterProxySetting(
                    registeredCategory,
                    checkbox.variable,
                    settings.VarType.Boolean,
                    checkbox.label,
                    checkbox.defaultValue,
                    checkbox.getValue,
                    checkbox.setValue
                )
                if checkboxSetting == nil then
                    error("checkbox setting was not created")
                end

                local checkboxControl = settings.CreateCheckbox(
                    registeredCategory,
                    checkboxSetting,
                    checkbox.tooltip
                )
                if checkboxControl == nil then
                    error("checkbox control was not created")
                end
            end
        end

        settings.RegisterAddOnCategory(registeredCategory)
        return registeredCategory, balanceInitializer, lifetimeInitializer
    end)

    if not ok then
        return nil
    end

    self.balanceInitializers = self.balanceInitializers or {}
    self.balanceInitializers[category] = balanceInitializer
    self.lifetimeInitializers = self.lifetimeInitializers or {}
    self.lifetimeInitializers[category] = lifetimeInitializer
    return category
end

-- Updates a settings header's text and repaints it if it is on screen.
function Client:RefreshSettingsHeader(initializers, category, text)
    if type(text) ~= "string" or type(initializers) ~= "table" then
        return false
    end

    local initializer = initializers[category]
    if type(initializer) ~= "table"
        or type(initializer.GetData) ~= "function"
    then
        return false
    end

    local ok, data = pcall(initializer.GetData, initializer)
    if not ok or type(data) ~= "table" then
        return false
    end

    data.name = text
    -- The header only reads its text when drawn, so repaint it if the
    -- settings page is showing it right now.
    local settingsPanel = self.environment.SettingsPanel
    if type(settingsPanel) == "table" then
        pcall(function()
            settingsPanel:GetSettingsList().ScrollBox:ForEachFrame(function(frame)
                if frame:GetElementData() == initializer and frame.Title ~= nil then
                    frame.Title:SetText(data.name)
                end
            end)
        end)
    end
    return true
end

function Client:RefreshSettingsBalance(category, balanceText)
    if type(balanceText) ~= "string" then
        return false
    end
    return self:RefreshSettingsHeader(self.balanceInitializers, category,
        "Tithe - Current balance: " .. balanceText)
end

function Client:RefreshSettingsLifetime(category, lifetimeText)
    if type(lifetimeText) ~= "string" then
        return false
    end
    return self:RefreshSettingsHeader(self.lifetimeInitializers, category,
        "Tithe - Lifetime given: " .. lifetimeText)
end

function Client:OpenSettingsCategory(category)
    local settings = self.environment.Settings
    if type(settings) ~= "table"
        or type(settings.OpenToCategory) ~= "function"
        or type(category) ~= "table"
        or type(category.GetID) ~= "function"
    then
        return false
    end

    local idOk, categoryID = pcall(category.GetID, category)
    if not idOk or categoryID == nil then
        return false
    end

    local openOk = pcall(settings.OpenToCategory, categoryID)
    return openOk
end
