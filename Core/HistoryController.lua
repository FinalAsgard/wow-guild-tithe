local _, addon = ...

-- Presents the donation ledger: lifetime totals and a newest-first list of
-- donations, a page of rows at a time. It only reads the ledger; nothing
-- here can add, change, or remove a donation.
local HistoryController = {
    TITLE = "Donation History",
    -- Rows shown at once; scrolling moves through the rest.
    ROWS = 12,
    -- Rows moved per mouse-wheel step.
    WHEEL_STEP = 3,
    -- Guild totals listed before the rest are summarized.
    GUILD_LINES = 5,
    EMPTY_TEXT = "No donations yet. Donations confirmed at the guild bank will appear here.",
    UNAVAILABLE_TEXT = "Donation history is unavailable right now.",
}
addon.HistoryController = HistoryController

local Controller = {}
Controller.__index = Controller

-- Add-on deposits share one label; the exact method stays in the ledger.
local METHOD_LABELS = {
    automatic = "Guild Tithe",
    button = "Guild Tithe",
    manual = "Manual",
}

function HistoryController.MethodLabel(method)
    return METHOD_LABELS[method] or tostring(method)
end

function HistoryController.Create(client, ledger, formatter)
    return setmetatable({
        client = client,
        formatter = formatter or addon.MoneyFormatter,
        ledger = ledger,
        offset = 0,
    }, Controller)
end

function Controller:Money(copper)
    return self.formatter.Format(copper) or tostring(copper)
end

local function characterText(character)
    local name = character.name or character.key
    if character.realm ~= nil then
        return name .. "-" .. character.realm
    end
    return name
end

-- The page's contents for the current scroll position.
function Controller:View()
    local ledger = self.ledger
    local view = {
        title = HistoryController.TITLE,
        guilds = {},
        rows = {},
    }
    if not ledger:IsAvailable() then
        view.message = HistoryController.UNAVAILABLE_TEXT
        view.overall = "Lifetime given: -"
        return view
    end

    local totals = ledger:Totals()
    view.overall = "Lifetime given: " .. self:Money(totals.overall)
    local index
    for index = 1, math.min(#totals.guilds, HistoryController.GUILD_LINES) do
        local guild = totals.guilds[index]
        table.insert(view.guilds, guild.name .. " (" .. guild.realm .. "): " ..
            self:Money(guild.amount))
    end
    local hidden = #totals.guilds - HistoryController.GUILD_LINES
    if hidden > 0 then
        table.insert(view.guilds, "and " .. hidden .. " more " ..
            (hidden == 1 and "guild" or "guilds"))
    end

    local count = ledger:Count()
    if count == 0 then
        self.offset = 0
        view.message = HistoryController.EMPTY_TEXT
        return view
    end

    self.offset = math.max(0, math.min(self.offset, count - HistoryController.ROWS))
    local entries = ledger:Entries(self.offset, HistoryController.ROWS)
    for index = 1, #entries do
        local entry = entries[index]
        table.insert(view.rows, {
            date = self.client:FormatDate(entry.timestamp) or "-",
            guild = entry.guild.name,
            character = characterText(entry.character),
            amount = self:Money(entry.amount),
            method = HistoryController.MethodLabel(entry.method),
        })
    end
    view.range = (self.offset + 1) .. "-" .. (self.offset + #entries) .. " of " .. count
    view.canNewer = self.offset > 0
    view.canOlder = self.offset + #entries < count
    return view
end

function Controller:Render()
    if self.page ~= nil then
        self.page:Render(self:View())
    end
end

-- Moves the list by `rows` (positive is older) and redraws it.
function Controller:Scroll(rows)
    self.offset = math.max(0, self.offset + (tonumber(rows) or 0))
    self:Render()
end

-- Page dimensions the client builds the layout from.
function Controller:Layout()
    return {
        guildLines = HistoryController.GUILD_LINES + 1,
        rows = HistoryController.ROWS,
        wheelStep = HistoryController.WHEEL_STEP,
    }
end

function Controller:BindPage(page)
    if page == nil then
        return false
    end
    self:Start()
    self.page = page
    page:SetScrollHandler(function(rows)
        self:Scroll(rows)
    end)
    self:Render()
    return true
end

-- Adds the history tab under the add-on's settings entry. Without it, a
-- standalone window is used when history is opened.
function Controller:RegisterSettingsPage(parentCategory)
    if self.page ~= nil then
        return true
    end
    return self:BindPage(self.client:RegisterHistorySettingsPage(parentCategory,
        HistoryController.TITLE, self:Layout()))
end

function Controller:Start()
    if self.started then
        return
    end
    self.started = true
    -- Redraw after each new donation so an open page is always current.
    self.ledger:OnAppend(function()
        self:Render()
    end)
end

function Controller:Open()
    self:Start()
    if self.page == nil then
        self:BindPage(self.client:CreateHistoryWindow(HistoryController.TITLE, self:Layout()))
    end
    if self.page == nil then
        self.client:Print(addon.Identity.chatPrefix ..
            " Donation history is unavailable on this client.")
        return false
    end
    self.offset = 0
    self:Render()
    if not self.client:OpenHistoryPage(self.page) then
        self.client:Print(addon.Identity.chatPrefix ..
            " Donation history could not be opened.")
        return false
    end
    return true
end

function Controller:RegisterCommands(router)
    return router:Register("history", "open donation history", function()
        self:Open()
    end)
end
