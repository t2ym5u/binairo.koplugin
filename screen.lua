local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonDialog    = require("ui/widget/buttondialog")
local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local TitleBar        = require("ui/widget/titlebar")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local T               = require("ffi/util").template
local _               = require("i18n")

local ScreenBase      = require("screen_base")
local MenuHelper      = require("menu_helper")

local BinairoBoard       = lrequire("board")
local BinairoBoardWidget = lrequire("board_widget")

local DeviceScreen = Device.screen

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
    self.board_widget = BinairoBoardWidget:new{
        board          = self.board,
        onCellSelected = function(r, c) self:onCellSelected(r, c) end,
    }

    local is_landscape = self:isLandscape()
    local sw = DeviceScreen:getWidth()
    local sh = DeviceScreen:getHeight()

    -- Title bar (full width, pinned to top)
    local title_bar = TitleBar:new{
        width                  = sw,
        title                  = _("Binairo"),
        left_icon              = "appbar.menu",
        left_icon_tap_callback = function() self:openOptionsMenu() end,
        close_callback         = function() self:closeScreen() end,
        with_bottom_line       = true,
    }
    local tb_h = title_bar:getSize().h

    local board_frame = FrameContainer:new{
        padding = Size.padding.large,
        margin  = Size.margin.default,
        self.board_widget,
    }
    local board_sz = self.board_widget.size
        + (Size.padding.large + Size.margin.default) * 2
    local btn_w = is_landscape
        and math.max(sw - board_sz - Size.span.horizontal_default, 100)
        or  math.floor(sw * 0.9)

    -- Footer: game-specific actions
    local footer = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = btn_w,
        buttons = {{
            { id = "undo_btn", text = _("Undo"),   callback = function() self:onUndo() end },
            { text = _("Check"),                   callback = function() self:onCheck() end },
            { text = _("Reveal"),                  callback = function() self:onReveal() end },
        }},
    }
    self.undo_btn = footer:getButtonById("undo_btn")
    self:_updateUndoBtn()

    if is_landscape then
        local avail_h = sh - tb_h
        local right = VerticalGroup:new{
            align = "center",
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            footer,
        }
        local game_row = HorizontalGroup:new{
            align  = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            right,
        }
        local game_h   = game_row:getSize().h
        local top_span = math.max(0, math.floor((avail_h - game_h) / 2))
        local bot_span = math.max(0, avail_h - top_span - game_h)
        self.layout = VerticalGroup:new{
            title_bar,
            VerticalSpan:new{ width = top_span },
            game_row,
            VerticalSpan:new{ width = bot_span },
        }
        self[1] = self.layout
    else
        local content = VerticalGroup:new{
            align = "center",
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
        }
        self:buildPortraitLayout(title_bar, content, footer)
    end
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- Options menu
-- ---------------------------------------------------------------------------

function BinairoScreen:openOptionsMenu()
    local dlg
    dlg = ButtonDialog:new{
        title = _("Binairo"),
        buttons = {
            {{ text = _("New game"), callback = function()
                UIManager:close(dlg)
                self:onNewGame()
            end }},
            {{ text = T(_("Grid: %1"), self:_sizeLabel()),
               callback = function()
                UIManager:close(dlg)
                self:_openSizeMenu()
            end }},
            {{ text = T(_("Difficulty: %1"), self:_diffLabel()),
               callback = function()
                UIManager:close(dlg)
                self:_openDiffMenu()
            end }},
            {{ text = _("Rules"), callback = function()
                UIManager:close(dlg)
                self:showRules(_.lang() == "fr" and GAME_RULES_FR or GAME_RULES_EN)
            end }},
        },
    }
    UIManager:show(dlg)
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
        local empty = self.board:emptyCells()
        text = T(_("Empty: %1"), empty)
                .. "  \xC2\xB7  "
                .. T(_("Diff: %1"), MenuHelper.DIFFICULTY_LABELS[self.board.difficulty]
                                    or self.board.difficulty)
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
        title     = _("Select grid size"),
        current   = self.plugin:getSetting("grid_size", "8"),
        parent    = self,
        values    = SIZES,
        on_select = function(id)
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
