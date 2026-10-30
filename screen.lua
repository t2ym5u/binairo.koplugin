local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local T               = require("ffi/util").template
local _               = require("i18n")

local ScreenBase      = require("screen_base")
local MenuHelper      = require("menu_helper")

local BinairoBoard       = lrequire("board")
local BinairoBoardWidget = lrequire("board_widget")

local SIZES = {
    { id = "6",  text = "6×6"   },
    { id = "8",  text = "8×8"   },
    { id = "10", text = "10×10" },
    { id = "12", text = "12×12" },
}

local GAME_RULES_EN = [[
Fill every row and column with equal 0s and 1s.
• No three consecutive identical values in any row or column.
• Tap a cell to cycle: empty → 0 → 1 → empty.
• Tap Check to highlight wrong cells.
• Tap Reveal to show the solution.
]]

local GAME_RULES_FR = [[
Remplissez chaque ligne et colonne avec autant de 0 que de 1.
• Pas trois valeurs identiques consécutives sur une ligne ou colonne.
• Appuyez sur une case pour faire défiler : vide → 0 → 1 → vide.
• Appuyez sur Vérifier pour mettre en évidence les cases incorrectes.
• Appuyez sur Révéler pour afficher la solution.
]]

-- ---------------------------------------------------------------------------
-- BinairoScreen
-- ---------------------------------------------------------------------------

local BinairoScreen = ScreenBase:extend{}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function BinairoScreen:init()
    local state = self.plugin:loadState()
    self.board = BinairoBoard:new()
    if not self.board:load(state) then
        self.board:generate(
            tonumber(self.plugin:getSetting("grid_size", "8")),
            self.plugin:getSetting("difficulty", "easy")
        )
    end
    ScreenBase.init(self)
end

function BinairoScreen:serializeState()
    return self.board:serialize()
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function BinairoScreen:buildLayout()
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Binairo"), function()
        return {
            { text = _("New game"), callback = function() self:onNewGame() end },
            self:makeDailyButtonConfig(),
            { text = T(_("Size: %1"), self:_sizeLabel()),
              callback = function() self:_openSizeMenu() end },
            { text = T(_("Difficulty: %1"), self:_diffLabel()),
              callback = function() self:_openDiffMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    -- Controls first: the board is sized from whatever room they leave.
    self.status_text:setMaxWidth(self:getControlsWidth())
    local action_bar = self:buildActionBar({
        { id = "undo_btn", text = _("Undo"),   callback = function() self:onUndo() end },
        { text = _("Check"),                   callback = function() self:onCheck() end },
        { text = _("Hint"),                    callback = function() self:onHint() end },
        { text = _("Reveal"),                  callback = function() self:onReveal() end },
    })
    self.undo_btn = action_bar:getButtonById("undo_btn")
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        action_bar,
    }

    -- The widget draws its own thick outer border, so the frame only pads.
    local frame_pad   = Size.padding.large
    local frame_extra = 2 * frame_pad
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = BinairoBoardWidget:new{
        board          = self.board,
        max_size       = math.min(budget_w, budget_h) - frame_extra,
        onCellSelected = function(r, c) self:onCellSelected(r, c) end,
    }
    local board_frame = FrameContainer:new{
        padding    = frame_pad,
        margin     = 0,
        bordersize = 0,
        self.board_widget,
    }
    self:_updateUndoBtn()

    if is_landscape then
        local content = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Cell interaction
-- ---------------------------------------------------------------------------

function BinairoScreen:onCellSelected(r, c)
    if self.board.solved then return end
    local ok, msg = self.board:toggle(r, c)
    if not ok and msg then
        self:updateStatus(msg)
    else
        self:_updateUndoBtn()
        self.board_widget:refresh()
        self.plugin:saveState(self.board:serialize())
        if self.board.solved then
            self:updateStatus(T(_("Solved! Time: %1"), self.board.timer:format()))
            self.board.timer:stop()
        else
            self:updateStatus()
        end
        self:refreshActionBar()
    end
end

-- ---------------------------------------------------------------------------
-- Game actions
-- ---------------------------------------------------------------------------

function BinairoScreen:onNewGame()
    math.randomseed(os.time())
    self.board:generate(
        tonumber(self.plugin:getSetting("grid_size", "8")),
        self.plugin:getSetting("difficulty", "easy")
    )
    self.plugin:saveState(self.board:serialize())
    self:_rebuildBoardWidget()
    self:updateStatus(_("New game started."))
    self:refreshActionBar()
end

function BinairoScreen:_rebuildBoardWidget()
    if self.board_widget then
        self.board_widget.board = self.board
        self.board_widget.cols  = self.board.n
        self.board_widget.rows  = self.board.n
        self.board_widget:init()
    end
    self.board_widget:refresh()
    self:_updateUndoBtn()
end

function BinairoScreen:onUndo()
    local ok, msg = self.board:undoLast()
    if msg then self:updateStatus(msg) end
    if ok then
        self.board_widget:refresh()
        self.plugin:saveState(self.board:serialize())
    end
    self:_updateUndoBtn()
    self:refreshActionBar()
end

function BinairoScreen:onCheck()
    local errs = self.board:checkErrors()
    local count = 0
    for _, row in pairs(errs) do
        for _ in pairs(row) do count = count + 1 end
    end
    self.board_widget:refresh()
    if count == 0 then
        self:updateStatus(_("No errors found!"))
    else
        self:updateStatus(T(_("%1 error(s) highlighted."), count))
    end
end

function BinairoScreen:onReveal()
    self.board:revealSolution()
    self.board_widget:refresh()
    self.plugin:saveState(self.board:serialize())
    self:updateStatus(_("Solution revealed."))
    self:refreshActionBar()
end

function BinairoScreen:isRoundOver()
    return self.board.solved
end

-- A hint can place the last cell, so the round may end here.
function BinairoScreen:onHint()
    ScreenBase.onHint(self)
    self:refreshActionBar()
end

-- ---------------------------------------------------------------------------
-- Status bar
-- ---------------------------------------------------------------------------

function BinairoScreen:updateStatus(msg)
    local text
    if msg then
        text = msg
    elseif self.board.solved then
        text = T(_("Solved! Time: %1"), self.board.timer:format())
    else
        text = self:joinStatus(
            T("%1×%1", self.board.n),
            MenuHelper.DIFFICULTY_LABELS[self.board.difficulty] or self.board.difficulty,
            T(_("Empty: %1"), self.board:emptyCells()))
    end
    ScreenBase.updateStatus(self, text)
end

-- ---------------------------------------------------------------------------
-- Menu helpers
-- ---------------------------------------------------------------------------

function BinairoScreen:_sizeLabel()
    local sz = self.plugin:getSetting("grid_size", "8")
    return sz .. "×" .. sz
end

function BinairoScreen:_diffLabel()
    local d = self.plugin:getSetting("difficulty", "easy")
    return MenuHelper.DIFFICULTY_LABELS[d] or d
end

function BinairoScreen:_openSizeMenu()
    MenuHelper.openPickerMenu{
        title      = _("Select size"),
        current_id = self.plugin:getSetting("grid_size", "8"),
        parent     = self,
        items      = SIZES,
        on_select  = function(id)
            self.plugin:saveSetting("grid_size", id)
            self:onNewGame()
        end,
    }
end

function BinairoScreen:_openDiffMenu()
    MenuHelper.openDifficultyMenu{
        current   = self.plugin:getSetting("difficulty", "easy"),
        parent    = self,
        on_select = function(id)
            self.plugin:saveSetting("difficulty", id)
            self:onNewGame()
        end,
    }
end

function BinairoScreen:_updateUndoBtn()
    if self.undo_btn then
        self.undo_btn:enableDisable(self.board.undo:canUndo())
    end
end

return BinairoScreen
