local UndoStack = require("undo_stack")
local Timer     = require("timer")
local _         = require("i18n")
local Hint       = require("hint")

-- ---------------------------------------------------------------------------
-- BinairoBoard — game logic
--
-- Rules:
--   1. Each row and each column contains exactly n/2 zeros and n/2 ones.
--   2. No three consecutive identical values in any row or column.
--   3. All rows are distinct and all columns are distinct (enforced by
--      `_fill` since 2026-07-22 — a violation here previously meant the
--      stored solution could be one of several valid completions for a
--      given clue set, undetectable by the old flat-ratio clue reveal; see
--      docs/generator_robustness_audit.md's Tier 2 table).
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

-- Rows/columns must all be pairwise distinct (see the module doc comment):
-- this was previously "soft — not enforced", which meant `self.solution`
-- could itself violate its own genre rule, making the uniqueness-check
-- fixed into `generate()` below (added 2026-07-22) find that even the
-- stored solution didn't qualify as valid. Enforcing it here too keeps
-- `_fill` and the uniqueness counter consistent about what "a valid
-- completion" means.
function BinairoBoard:_rowsDistinctSoFar(grid, r, n)
    for r2 = 1, r - 1 do
        local same = true
        for c = 1, n do if grid[r2][c] ~= grid[r][c] then same = false; break end end
        if same then return false end
    end
    return true
end

function BinairoBoard:_colsAllDistinct(grid, n)
    for c1 = 1, n do
        for c2 = c1 + 1, n do
            local same = true
            for r = 1, n do if grid[r][c1] ~= grid[r][c2] then same = false; break end end
            if same then return false end
        end
    end
    return true
end

function BinairoBoard:_fill(grid, pos)
    local n = self.n
    if pos > n * n then
        return self:_colsAllDistinct(grid, n)
    end
    local r = math.ceil(pos / n)
    local c = ((pos - 1) % n) + 1
    local vals = math.random(2) == 1 and {0, 1} or {1, 0}
    for _, v in ipairs(vals) do
        if self:_canPlace(grid, r, c, v) then
            grid[r][c] = v
            local row_ok = (c < n) or self:_rowsDistinctSoFar(grid, r, n)
            if row_ok and self:_fill(grid, pos + 1) then return true end
            grid[r][c] = nil
        end
    end
    return false
end

-- Counts solutions (up to `limit`) of the Binairo instance given the
-- current `given`/`cells` fixed values, using MRV cell ordering. Returns
-- (solutions_found, exhausted); exhausted=true means node_budget was hit
-- before the search concluded, so the count isn't proof. Mirrors
-- sudokukiller.koplugin/board.lua's countCageSolutions.
local NODE_BUDGET_UNIQUENESS = 200000

local function countSolutions(cells, given, n, limit, node_budget)
    local grid = {}
    for r = 1, n do
        grid[r] = {}
        for c = 1, n do grid[r][c] = given[r][c] and cells[r][c] or -1 end
    end

    local solutions, nodes, exhausted = 0, 0, false

    local function canPlace(r, c, v)
        local left = 0
        for j = c - 1, math.max(1, c - 2), -1 do
            if grid[r][j] == v then left = left + 1 else break end
        end
        local right = 0
        for j = c + 1, math.min(n, c + 2) do
            if grid[r][j] == v then right = right + 1 else break end
        end
        if left + right >= 2 then return false end
        local up = 0
        for i = r - 1, math.max(1, r - 2), -1 do
            if grid[i][c] == v then up = up + 1 else break end
        end
        local down = 0
        for i = r + 1, math.min(n, r + 2) do
            if grid[i][c] == v then down = down + 1 else break end
        end
        if up + down >= 2 then return false end
        local rc = 0
        for j = 1, n do if grid[r][j] == v then rc = rc + 1 end end
        if rc >= n / 2 then return false end
        local cc = 0
        for i = 1, n do if grid[i][c] == v then cc = cc + 1 end end
        if cc >= n / 2 then return false end
        return true
    end

    local empties = {}
    for r = 1, n do for c = 1, n do if grid[r][c] == -1 then empties[#empties + 1] = { r = r, c = c } end end end

    local function candidatesFor(r, c)
        local cands = {}
        for _, v in ipairs({ 0, 1 }) do if canPlace(r, c, v) then cands[#cands + 1] = v end end
        return cands
    end

    -- Rows/columns must also all be pairwise distinct (a real Binairo rule
    -- -- see the module doc comment -- not enforced by `_fill`'s solution
    -- construction, but still a constraint on which grids count as valid
    -- completions here: checkErrors/_isComplete compare a player's answer
    -- directly against the stored solution, so any OTHER grid satisfying
    -- every rule would wrongly read as "incorrect" if it existed).
    local function rowFull(r) for c = 1, n do if grid[r][c] == -1 then return false end end return true end
    local function colFull(c) for r = 1, n do if grid[r][c] == -1 then return false end end return true end
    local function rowDistinct(r)
        for r2 = 1, r - 1 do
            local same = true
            for c = 1, n do if grid[r2][c] ~= grid[r][c] then same = false; break end end
            if same then return false end
        end
        return true
    end
    local function colDistinct(c)
        for c2 = 1, c - 1 do
            local same = true
            for r = 1, n do if grid[r][c2] ~= grid[r][c] then same = false; break end end
            if same then return false end
        end
        return true
    end

    local function search(depth)
        if solutions >= limit or exhausted then return end
        nodes = nodes + 1
        if nodes > node_budget then exhausted = true; return end
        if depth > #empties then solutions = solutions + 1; return end
        local best_idx, best_cands, best_len = nil, nil, 3
        for i, cell in ipairs(empties) do
            if grid[cell.r][cell.c] == -1 then
                local cands = candidatesFor(cell.r, cell.c)
                if #cands < best_len then
                    best_len, best_cands, best_idx = #cands, cands, i
                    if best_len <= 1 then break end
                end
            end
        end
        if best_idx == nil then solutions = solutions + 1; return end
        if best_len == 0 then return end
        local cell = empties[best_idx]
        for _, v in ipairs(best_cands) do
            grid[cell.r][cell.c] = v
            local ok = true
            if rowFull(cell.r) and not rowDistinct(cell.r) then ok = false end
            if ok and colFull(cell.c) and not colDistinct(cell.c) then ok = false end
            if ok then search(depth + 1) end
            grid[cell.r][cell.c] = -1
            if solutions >= limit or exhausted then return end
        end
    end
    search(1)
    return solutions, exhausted
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

    -- Dig cells one at a time (like sudoku-common's hole-digging), starting
    -- fully revealed and verifying with countSolutions after each tentative
    -- removal, putting the cell back if that broke uniqueness -- the old
    -- "mask a flat ratio of cells" approach never checked this (see
    -- docs/generator_robustness_audit.md's Tier 2 table: measured 0%
    -- unique at every size/difficulty tested).
    local ratio = REVEAL[self.difficulty] or 0.5
    local positions = {}
    for i = 1, self.n do
        for j = 1, self.n do positions[#positions + 1] = { i, j } end
    end
    shuffle(positions)
    local total        = self.n * self.n
    local target_hide  = total - math.floor(total * ratio)

    self.cells = {}
    self.given = {}
    for i = 1, self.n do
        self.cells[i] = {}
        self.given[i] = {}
        for j = 1, self.n do
            self.cells[i][j] = self.solution[i][j]
            self.given[i][j] = true
        end
    end

    local hidden = 0
    for _, pos in ipairs(positions) do
        if hidden >= target_hide then break end
        local r, c = pos[1], pos[2]
        self.given[r][c] = false
        local solutions, exhausted = countSolutions(self.cells, self.given, self.n, 2, NODE_BUDGET_UNIQUENESS)
        if not exhausted and solutions == 1 then
            self.cells[r][c] = nil
            hidden = hidden + 1
        else
            self.given[r][c] = true
        end
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

-- Like toggle(), but goes straight to a value instead of cycling. Used by the
-- Hint button, and undoable through the same stack as any hand-made move.
function BinairoBoard:setCellValue(r, c, v)
    if self.given[r] and self.given[r][c] then return false end
    if self.solved then return false end
    local cur = self.cells[r] and self.cells[r][c]
    if cur == v then return true end
    self.undo:push({ r = r, c = c, old = cur, new = v })
    self.cells[r][c] = v
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

-- 0 is a real value here, not an empty cell, so the default "empty" test
-- (nil/0/false) would read every placed zero as a blank.
Hint.install(BinairoBoard, {
    isEmpty     = function(v) return v == nil end,
    getUser     = function(b, r, c) return b.cells[r] and b.cells[r][c] end,
    getSolution = function(b, r, c) return b.solution[r][c] end,
    isGiven     = function(b, r, c) return b.given[r] and b.given[r][c] end,
    setCell     = function(b, r, c, v) return b:setCellValue(r, c, v) end,
})

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
