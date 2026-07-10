local UndoStack = require("undo_stack")
local Timer     = require("timer")
local _         = require("i18n")

-- ---------------------------------------------------------------------------
-- BinairoBoard — game logic
--
-- Rules:
--   1. Each row and each column contains exactly n/2 zeros and n/2 ones.
--   2. No three consecutive identical values in any row or column.
--   3. All rows are distinct and all columns are distinct (soft — not enforced
--      in the generator for simplicity, very rare violation on small grids).
--
-- Cell values: nil (empty), 0, or 1.
-- ---------------------------------------------------------------------------

local BinairoBoard = {}
BinairoBoard.__index = BinairoBoard

local REVEAL = { easy = 0.55, medium = 0.45, hard = 0.35 }

function BinairoBoard:new(opts)
    opts = opts or {}
    return setmetatable({
        n          = opts.n or 8,
        difficulty = opts.difficulty or "easy",
        solution   = {},
        cells      = {},
        given      = {},
        errors     = {},
        solved     = false,
        undo       = UndoStack:new(),
        timer      = Timer:new(),
    }, self)
end

-- ---------------------------------------------------------------------------
-- Generator
-- ---------------------------------------------------------------------------

local function copy2d(src, n)
    local dst = {}
    for i = 1, n do
        dst[i] = {}
        for j = 1, n do dst[i][j] = src[i][j] end
    end
    return dst
end

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

function BinairoBoard:_canPlace(grid, r, c, v)
    local n = self.n
    -- no 3 consecutive in row
    local left = 0
    for j = c-1, math.max(1, c-2), -1 do
        if grid[r][j] == v then left = left + 1 else break end
    end
    local right = 0
    for j = c+1, math.min(n, c+2) do
        if grid[r][j] == v then right = right + 1 else break end
    end
    if left + right >= 2 then return false end
    -- no 3 consecutive in column
    local up = 0
    for i = r-1, math.max(1, r-2), -1 do
        if grid[i][c] == v then up = up + 1 else break end
    end
    local down = 0
    for i = r+1, math.min(n, r+2) do
        if grid[i][c] == v then down = down + 1 else break end
    end
    if up + down >= 2 then return false end
    -- row balance
    local rc = 0
    for j = 1, n do if grid[r][j] == v then rc = rc + 1 end end
    if rc >= n/2 then return false end
    -- column balance
    local cc = 0
    for i = 1, n do if grid[i][c] == v then cc = cc + 1 end end
    if cc >= n/2 then return false end
    return true
end

function BinairoBoard:_fill(grid, pos)
    local n = self.n
    if pos > n * n then return true end
    local r = math.ceil(pos / n)
    local c = ((pos - 1) % n) + 1
    local vals = math.random(2) == 1 and {0, 1} or {1, 0}
    for _, v in ipairs(vals) do
        if self:_canPlace(grid, r, c, v) then
            grid[r][c] = v
            if self:_fill(grid, pos + 1) then return true end
            grid[r][c] = nil
        end
    end
    return false
end

function BinairoBoard:generate(n, difficulty)
    self.n          = n or self.n
    self.difficulty = difficulty or self.difficulty
    self.solved     = false
    self.errors     = {}
    self.undo:clear()
    self.timer:reset()
    self.timer:start()

    -- Build a complete valid board.
    local grid = {}
    for i = 1, self.n do grid[i] = {} end
    self:_fill(grid, 1)
    self.solution = copy2d(grid, self.n)

    -- Create puzzle by masking cells.
    local ratio = REVEAL[self.difficulty] or 0.5
    local positions = {}
    for i = 1, self.n do
        for j = 1, self.n do positions[#positions+1] = {i, j} end
    end
    shuffle(positions)
    local to_give = math.floor(self.n * self.n * ratio)

    self.cells = {}
    self.given = {}
    for i = 1, self.n do
        self.cells[i] = {}
        self.given[i] = {}
        for j = 1, self.n do
            self.cells[i][j] = nil
            self.given[i][j] = false
        end
    end
    for k = 1, math.min(to_give, #positions) do
        local r, c = positions[k][1], positions[k][2]
        self.cells[r][c] = self.solution[r][c]
        self.given[r][c] = true
    end
end

-- ---------------------------------------------------------------------------
-- Player moves
-- ---------------------------------------------------------------------------

-- Cycle nil→0→1→nil. Returns ok, msg.
function BinairoBoard:toggle(r, c)
    if self.given[r] and self.given[r][c] then
        return false, _("Cannot edit a given cell.")
    end
    if self.solved then return false end
    local cur = self.cells[r] and self.cells[r][c]
    local new = cur == nil and 0 or (cur == 0 and 1 or nil)
    self.undo:push({ r = r, c = c, old = cur, new = new })
    self.cells[r][c] = new
    self.errors = {}
    self.solved = self:_isComplete()
    return true
end

function BinairoBoard:undoLast()
    local move = self.undo:pop()
    if not move then return false, _("Nothing to undo.") end
    self.cells[move.r][move.c] = move.old
    self.errors = {}
    self.solved = false
    return true
end

-- ---------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------

-- Mark wrong cells (cells that differ from solution).
function BinairoBoard:checkErrors()
    self.errors = {}
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            local v = self.cells[r] and self.cells[r][c]
            if v ~= nil and v ~= self.solution[r][c] then
                self.errors[r] = self.errors[r] or {}
                self.errors[r][c] = true
            end
        end
    end
    return self.errors
end

function BinairoBoard:_isComplete()
    local n = self.n
    for r = 1, n do
        for c = 1, n do
            local v = self.cells[r] and self.cells[r][c]
            if v == nil or v ~= self.solution[r][c] then return false end
        end
    end
    return true
end

function BinairoBoard:emptyCells()
    local count = 0
    for r = 1, self.n do
        for c = 1, self.n do
            if not self.cells[r] or self.cells[r][c] == nil then count = count + 1 end
        end
    end
    return count
end

function BinairoBoard:revealSolution()
    local n = self.n
    for r = 1, n do
        for c = 1, n do self.cells[r][c] = self.solution[r][c] end
    end
    self.solved = true
    self.errors = {}
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

function BinairoBoard:serialize()
    return {
        n          = self.n,
        difficulty = self.difficulty,
        solution   = self.solution,
        cells      = self.cells,
        given      = self.given,
        solved     = self.solved,
        timer      = self.timer:serialize(),
        undo       = self.undo:serialize(),
    }
end

function BinairoBoard:load(data)
    if type(data) ~= "table" then return false end
    self.n          = data.n or 8
    self.difficulty = data.difficulty or "easy"
    self.solution   = data.solution or {}
    self.cells      = data.cells or {}
    self.given      = data.given or {}
    self.solved     = data.solved or false
    self.errors     = {}
    self.timer:load(data.timer)
    self.undo:load(data.undo)
    return true
end

return BinairoBoard
