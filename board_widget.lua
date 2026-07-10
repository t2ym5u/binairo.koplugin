local Blitbuffer = require("ffi/blitbuffer")
local common     = require("grid_widget_base")

local GridWidgetBase   = common.GridWidgetBase
local drawLine         = common.drawLine
local drawCenteredText = common.drawCenteredText

-- Gray levels (e-ink palette)
local BG_GIVEN  = Blitbuffer.COLOR_GRAY_E   -- very light gray for given cells
local BG_ERROR  = Blitbuffer.COLOR_GRAY_A   -- medium gray for wrong cells
local FG_GIVEN  = Blitbuffer.COLOR_BLACK
local FG_PLAYER = Blitbuffer.COLOR_GRAY_4   -- darker gray for player-entered values
local FG_ERROR  = Blitbuffer.COLOR_WHITE

-- ---------------------------------------------------------------------------
-- BinairoBoardWidget
-- ---------------------------------------------------------------------------

local BinairoBoardWidget = GridWidgetBase:extend{
    -- board: BinairoBoard (set by caller)
}

function BinairoBoardWidget:init()
    self.cols = self.board and self.board.n or 8
    self.rows = self.cols
    GridWidgetBase.init(self)
end

function BinairoBoardWidget:onCellTap(row, col)
    if self.onCellSelected then self.onCellSelected(row, col) end
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

function BinairoBoardWidget:paintTo(bb, x, y)
    local rect   = self.paint_rect
    rect.x = x
    rect.y = y

    local board  = self.board
    local n      = board.n
    local cw     = self.cell_w
    local ch     = self.cell_h
    local cw_px  = self.cell_w_px
    local ch_px  = self.cell_h_px
    local face   = self.number_face

    -- White background
    bb:paintRect(x, y, rect.w, rect.h, Blitbuffer.COLOR_WHITE)

    -- Cells
    for r = 1, n do
        for c = 1, n do
            local cx = x + math.floor((c - 1) * cw)
            local cy = y + math.floor((r - 1) * ch)

            local val      = board.cells[r] and board.cells[r][c]
            local is_given = board.given[r] and board.given[r][c]
            local is_error = board.errors[r] and board.errors[r][c]

            -- Background fill
            if is_error then
                bb:paintRect(cx + 1, cy + 1, cw_px - 1, ch_px - 1, BG_ERROR)
            elseif is_given then
                bb:paintRect(cx + 1, cy + 1, cw_px - 1, ch_px - 1, BG_GIVEN)
            end

            -- Value text
            if val ~= nil then
                local text  = tostring(val)
                local color = is_error and FG_ERROR
                           or is_given and FG_GIVEN
                           or              FG_PLAYER
                local tcx = cx + math.floor(cw_px / 2)
                local tcy = cy + math.floor(ch_px / 2)
                drawCenteredText(bb, text, face, tcx, tcy, color)
            end
        end
    end

    -- Grid lines
    for c = 0, n do
        local lx = x + math.floor(c * cw)
        drawLine(bb, lx, y, 1, rect.h, Blitbuffer.COLOR_BLACK)
    end
    for r = 0, n do
        local ly = y + math.floor(r * ch)
        drawLine(bb, x, ly, rect.w, 1, Blitbuffer.COLOR_BLACK)
    end
end

return BinairoBoardWidget
