local UndoStack = require("undo_stack")
local Timer     = require("timer")
local _         = require("i18n")
local Hint       = require("hint")
local bit        = require("bit")

-- ---------------------------------------------------------------------------
-- BinairoBoard — game logic
--
-- Rules:
--   1. Each row and each column contains exactly n/2 zeros and n/2 ones.
--   2. No three consecutive identical values in any row or column.
--   3. All rows are distinct and all columns are distinct (enforced by
--      `_fillRows` (since 2026-07-22) — a violation here previously meant the
--      stored solution could be one of several valid completions for a
--      given clue set, undetectable by the old flat-ratio clue reveal; see
--      docs/generator_robustness_audit.md's Tier 2 table).
--
-- Cell values: nil (empty), 0, or 1.
-- ---------------------------------------------------------------------------

local BinairoBoard = {}
BinairoBoard.__index = BinairoBoard


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

-- Every row pattern a solution may use (n/2 ones, n/2 zeros, no three
-- identical values in a row), each stored as a bitmask: bit c-1 holds the
-- value of column c. Cached per size (n = 12 has 208 patterns).
local ROW_PATTERNS = {}

local function rowPatterns(n)
    if ROW_PATTERNS[n] then return ROW_PATTERNS[n] end
    local list = {}
    local function rec(c, ones, mask, prev1, prev2)
        if c > n then
            if ones == n / 2 then list[#list + 1] = mask end
            return
        end
        for v = 0, 1 do
            local ones2 = ones + v
            if ones2 <= n / 2 and c - ones2 <= n / 2
                and not (prev1 == v and prev2 == v) then
                rec(c + 1, ones2, mask + v * 2 ^ (c - 1), v, prev1)
            end
        end
    end
    rec(1, 0, 0, -1, -1)
    ROW_PATTERNS[n] = list
    return list
end

-- Builds a complete valid grid one whole row at a time. For each row, the
-- column rules (balance, no three in a column) force some cells; only
-- patterns agreeing with those forced cells are tried, from a random
-- starting point in a shuffled pattern list. The previous cell-by-cell fill
-- only noticed most column problems much later, so its backtracking had a
-- heavy tail (12x12: 2 million nodes on 1 seed in 100, 30 million at worst,
-- i.e. seconds on a desktop). Returns false when the node cap is hit; the
-- caller then starts over (still deterministic for a given seed).
local FILL_NODE_CAP = 2000

function BinairoBoard:_fillRows(grid)
    local n, half = self.n, self.n / 2
    local all = rowPatterns(n)
    local np = #all
    local patterns = {}
    for i = 1, np do patterns[i] = all[i] end
    shuffle(patterns)
    local ones, used = {}, {}
    for c = 1, n do ones[c] = 0 end
    local rows = {}   -- chosen pattern per row
    local nodes = 0

    local function colsDistinct()
        for c1 = 1, n do
            for c2 = c1 + 1, n do
                local same = true
                for r = 1, n do if grid[r][c1] ~= grid[r][c2] then same = false; break end end
                if same then return false end
            end
        end
        return true
    end

    local function rec(r)
        if r > n then return colsDistinct() end
        nodes = nodes + 1
        if nodes > FILL_NODE_CAP then return false end
        -- Cells of this row forced by the column rules.
        local mask, val, bitc = 0, 0, 1
        for c = 1, n do
            local o, z = ones[c], (r - 1) - ones[c]
            local force
            if o >= half then force = 0 elseif z >= half then force = 1 end
            if r > 2 and grid[r - 1][c] == grid[r - 2][c] then
                local opp = 1 - grid[r - 1][c]
                if force and force ~= opp then return false end
                force = opp
            end
            if force then
                mask = mask + bitc
                if force == 1 then val = val + bitc end
            end
            bitc = bitc * 2
        end
        local start = math.random(np)
        for k = 0, np - 1 do
            local p = patterns[(start + k - 1) % np + 1]
            if not used[p] and bit.band(p, mask) == val then
                used[p] = true
                rows[r] = p
                local row, x = grid[r], p
                for c = 1, n do
                    local v = x % 2
                    x = (x - v) / 2
                    row[c] = v
                    ones[c] = ones[c] + v
                end
                if rec(r + 1) then return true end
                for c = 1, n do ones[c] = ones[c] - row[c]; row[c] = nil end
                used[p] = nil
                if nodes > FILL_NODE_CAP then return false end
            end
        end
        return false
    end

    return rec(1)
end

-- Counts solutions (up to `limit`) of the Binairo instance given the
-- current `given`/`cells` fixed values, using MRV cell ordering. Returns
-- (solutions_found, exhausted); exhausted=true means node_budget was hit
-- before the search concluded, so the count isn't proof. Mirrors
-- sudokukiller.koplugin/board.lua's countCageSolutions.
-- Since 1.5.0 the generator digs with logicSolve (below), which proves
-- uniqueness by itself; this counter and hasOtherSolution stay as
-- independent checks for the specs.

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
    -- -- see the module doc comment -- not enforced by the old `_fill`'s solution
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

-- Removing a clue from a uniquely solvable grid keeps it unique exactly
-- when no completion puts the OTHER value in that cell (any second
-- solution must differ from the stored one there, since the grid with that
-- cell given was unique). So instead of counting solutions up to 2 --
-- rebuilding the stored solution first, then looking for another -- this
-- forces the opposite value and only has to refute it, with incremental
-- row/column counts and forced-cell propagation. Several times faster on
-- 12x12 Hard. Returns (found, exhausted). countSolutions is kept for the
-- specs, which cross-check the two.
--
-- Unlike countSolutions, an alternative completion counts even if two of
-- its rows or columns are identical: the in-game rules only state balance
-- and no-three-in-a-row, so a puzzle must be unique without the
-- distinct-lines rule. (countSolutions applied that rule only partially --
-- a full row was compared with the rows above it, never with full rows
-- below -- so this is at least as strict.)
local function hasOtherSolution(cells, given, n, r0, c0, node_budget, solution)
    local half = n / 2
    local grid, rc, cc = {}, {}, {}
    for r = 1, n do
        grid[r] = {}
        rc[r] = { [0] = 0, [1] = 0 }
        cc[r] = { [0] = 0, [1] = 0 }
    end
    local empties = {}
    for r = 1, n do
        for c = 1, n do
            local v = given[r][c] and cells[r][c] or -1
            grid[r][c] = v
            if v == -1 then
                empties[#empties + 1] = r * 64 + c
            else
                rc[r][v] = rc[r][v] + 1
                cc[c][v] = cc[c][v] + 1
            end
        end
    end
    local ne = #empties
    local nodes, exhausted = 0, false

    local function canPlace(r, c, v)
        if rc[r][v] >= half or cc[c][v] >= half then return false end
        local g = grid[r]
        local l1, l2, r1, r2 = g[c - 1], g[c - 2], g[c + 1], g[c + 2]
        if l1 == v and (l2 == v or r1 == v) then return false end
        if r1 == v and r2 == v then return false end
        local u1 = r > 1 and grid[r - 1][c]
        local d1 = r < n and grid[r + 1][c]
        if u1 == v and ((r > 2 and grid[r - 2][c] == v) or d1 == v) then return false end
        if d1 == v and r < n - 1 and grid[r + 2][c] == v then return false end
        return true
    end

    -- Assignments are recorded on a trail so a branch can be undone in one
    -- go. Placing (r, c) can only change the candidates of cells in row r
    -- and column c, so propagation re-examines just those.
    local trail, tn = {}, 0
    local function set(r, c, v)
        grid[r][c] = v
        rc[r][v] = rc[r][v] + 1
        cc[c][v] = cc[c][v] + 1
        tn = tn + 1
        trail[tn] = r * 64 + c
    end
    local function undoTo(mark)
        while tn > mark do
            local e = trail[tn]
            local r, c = (e - e % 64) / 64, e % 64
            local v = grid[r][c]
            grid[r][c] = -1
            rc[r][v] = rc[r][v] - 1
            cc[c][v] = cc[c][v] - 1
            tn = tn - 1
        end
    end

    -- Returns false on a contradiction (a cell left with no candidate).
    local function check(r, c)
        if grid[r][c] ~= -1 then return true end
        local p0, p1 = canPlace(r, c, 0), canPlace(r, c, 1)
        if p0 and p1 then return true end
        if not (p0 or p1) then return false end
        set(r, c, p0 and 0 or 1)
        return true
    end
    local function propagate(from)
        local i = from
        while i <= tn do
            local e = trail[i]
            local r, c = (e - e % 64) / 64, e % 64
            for j = 1, n do
                if not check(r, j) then return false end
                if not check(j, c) then return false end
            end
            i = i + 1
        end
        return true
    end

    local function search()
        nodes = nodes + 1
        if nodes > node_budget then exhausted = true; return false end
        -- Branch on the open cell whose row and column are fullest.
        local cell, best = nil, -1
        for i = 1, ne do
            local e = empties[i]
            local er, ec = (e - e % 64) / 64, e % 64
            if grid[er][ec] == -1 then
                local f = rc[er][0] + rc[er][1] + cc[ec][0] + cc[ec][1]
                if f > best then cell, best = e, f end
            end
        end
        if not cell then return true end
        local r, c = (cell - cell % 64) / 64, cell % 64
        local mark = tn
        -- A second solution, when there is one, mostly agrees with the
        -- stored one: trying the stored value first finds it sooner.
        local v1 = solution and solution[r][c] or 0
        for k = 0, 1 do
            local v = k == 0 and v1 or 1 - v1
            if canPlace(r, c, v) then
                set(r, c, v)
                local ok = propagate(mark + 1) and search()
                undoTo(mark)
                if ok or exhausted then return ok end
            end
        end
        return false
    end

    -- Force the opposite value into the cell being removed.
    local v0 = 1 - cells[r0][c0]
    if not canPlace(r0, c0, v0) then return false, false end
    set(r0, c0, v0)
    if not propagate(1) then return false, false end
    local found = search()
    return found, exhausted
end
BinairoBoard._hasOtherSolution = hasOtherSolution
BinairoBoard._countSolutions = countSolutions

-- ---------------------------------------------------------------------------
-- Human-style solver (1.5.0), used to grade and dig puzzles
-- ---------------------------------------------------------------------------
--
-- Works one line (row or column) at a time, never by trial and error:
--   tier 1  the basic rules a beginner applies at a glance:
--           - a pair "x x" is closed by the other value on both sides;
--           - a gap "x _ x" is filled with the other value;
--           - a line that already holds n/2 of a value gets the other
--             value in every empty cell.
--   tier 2  whole-line reasoning: of all the ways to finish this one line
--           (balanced, no three in a row), every one puts the same value
--           in some empty cell, so that cell is settled. This is how a
--           player sees "the last two 0s cannot both go there".
-- Tier 2 is only used when tier 1 is stuck, and every tier-2 step is
-- counted: that count is what tells the levels apart.
--
-- logicSolve(grid, n, max_tier) works on a COPY of grid (rows of nil/0/1)
-- and returns solved, t2_steps, and the cells it filled (flat array,
-- (r-1)*n+c, -1 where still empty). A puzzle it solves has exactly one
-- solution, since every deduction only follows from the rules.
local function logicSolve(grid, n, max_tier)
    local half = n / 2
    local patterns = rowPatterns(n)
    local np = #patterns
    -- Flat cell array (-1 = empty) and the cell indices of every line.
    local v = {}
    for r = 1, n do
        for c = 1, n do
            local x = grid[r][c]
            v[(r - 1) * n + c] = x == nil and -1 or x
        end
    end
    local lines = {}
    for k = 1, n do
        local row, col = {}, {}
        for i = 1, n do
            row[i] = (k - 1) * n + i
            col[i] = (i - 1) * n + k
        end
        lines[#lines + 1] = row
        lines[#lines + 1] = col
    end
    local open = 0
    for i = 1, n * n do if v[i] == -1 then open = open + 1 end end
    local seen = {}   -- cells already accounted for in `dirty`

    -- Tier 1 on one line; returns true if it placed anything.
    local function tier1(L)
        local placed = false
        local cnt0, cnt1 = 0, 0
        for i = 1, n do
            local x = v[L[i]]
            if x == 0 then cnt0 = cnt0 + 1 elseif x == 1 then cnt1 = cnt1 + 1 end
        end
        if cnt0 + cnt1 == n then return false end
        for i = 1, n do
            if v[L[i]] == -1 then
                local a1 = i > 1 and v[L[i - 1]] or -2
                local a2 = i > 2 and v[L[i - 2]] or -2
                local b1 = i < n and v[L[i + 1]] or -2
                local b2 = i < n - 1 and v[L[i + 2]] or -2
                local put
                for x = 0, 1 do
                    if (a1 == x and a2 == x) or (b1 == x and b2 == x) or (a1 == x and b1 == x) then
                        put = 1 - x
                    end
                end
                if not put then
                    if cnt0 >= half then put = 1 elseif cnt1 >= half then put = 0 end
                end
                if put then
                    v[L[i]] = put
                    if put == 0 then cnt0 = cnt0 + 1 else cnt1 = cnt1 + 1 end
                    open = open - 1
                    placed = true
                end
            end
        end
        return placed
    end

    -- Tier 2 on one line: intersect every completion of the line.
    local function tier2(L)
        local mask, val, bitc, empty = 0, 0, 1, false
        for i = 1, n do
            local x = v[L[i]]
            if x == -1 then empty = true
            else
                mask = mask + bitc
                if x == 1 then val = val + bitc end
            end
            bitc = bitc * 2
        end
        if not empty then return false end
        local all_and, all_or, any = -1, 0, false
        for k = 1, np do
            local p = patterns[k]
            if bit.band(p, mask) == val then
                all_and = bit.band(all_and, p)
                all_or = bit.bor(all_or, p)
                any = true
            end
        end
        if not any then return false end
        local placed = false
        bitc = 1
        for i = 1, n do
            if v[L[i]] == -1 then
                if bit.band(all_and, bitc) ~= 0 then
                    v[L[i]] = 1; open = open - 1; placed = true
                elseif bit.band(all_or, bitc) == 0 then
                    v[L[i]] = 0; open = open - 1; placed = true
                end
            end
            bitc = bitc * 2
        end
        return placed
    end

    -- Only lines that changed since they were last looked at can give a
    -- new tier-1 deduction; a placed cell dirties its row and column.
    local nl = #lines
    local dirty = {}
    for k = 1, nl do dirty[k] = true end
    local function markLine(L)
        for i = 1, n do
            local idx = L[i]
            if v[idx] ~= -1 and not seen[idx] then
                seen[idx] = true
                local r = (idx - 1 - (idx - 1) % n) / n + 1
                local c = (idx - 1) % n + 1
                dirty[2 * r - 1] = true
                dirty[2 * c] = true
            end
        end
    end
    for i = 1, n * n do if v[i] ~= -1 then seen[i] = true end end
    local t2 = 0
    while open > 0 do
        local progress = false
        local again = true
        while again do
            again = false
            for k = 1, nl do
                if dirty[k] then
                    dirty[k] = false
                    if tier1(lines[k]) then
                        progress, again = true, true
                        markLine(lines[k])
                    end
                end
            end
        end
        if open == 0 then break end
        if max_tier < 2 then break end
        local found = false
        for k = 1, nl do
            if tier2(lines[k]) then
                t2 = t2 + 1
                markLine(lines[k])
                found = true
                break   -- back to the easy rules after each hard step
            end
        end
        if not found then break end
    end
    return open == 0, t2, v
end
BinairoBoard._logicSolve = logicSolve

-- What each level asks for (1.5.0). Before, the levels differed only by
-- how many cells were shown, and digging only checked that the answer
-- stayed unique: some puzzles (12x12 Hard: 30%) could only be finished by
-- trial and error, and many Medium/Hard ones needed nothing beyond the
-- basic rules.
--   tier          the hardest reasoning the puzzle may need (see logicSolve)
--   min_given     never show fewer cells than this fraction of the grid
--   min_t2/max_t2 how many tier-2 steps the solution needs
-- Easy: basic rules only. Medium: a few whole-line steps. Hard: fewer
-- cells shown and more whole-line steps. Never trial and error.
local LEVELS = {
    easy   = function(n) return { tier = 1, min_given = 0.50, min_t2 = 0, max_t2 = 0 } end,
    medium = function(n) return { tier = 2, min_given = n <= 6 and 0.30 or 0.36,
                                  min_t2 = n >= 10 and 2 or 1, max_t2 = n } end,
    hard   = function(n) return { tier = 2, min_given = 0.20,
                                  min_t2 = n <= 6 and 2 or math.floor(n / 2), max_t2 = math.huge } end,
}
BinairoBoard.LEVELS = LEVELS
-- Candidates tried per puzzle, by size: small grids are cheap to dig but
-- miss the tier-2 window more often.
BinairoBoard.ATTEMPTS = { [6] = 24, [8] = 12, [10] = 6, [12] = 4 }

-- Digs one candidate puzzle from a full solution: cells are hidden in a
-- random order, each one only if the solver, limited to the level's tier,
-- still finishes the grid without it, and never below the level's floor of
-- shown cells. Returns the given mask, the number of givens and the
-- tier-2 step count of the result.
local function dig(solution, n, level, on_progress, base, span)
    local given = {}
    local grid = {}
    for r = 1, n do
        given[r], grid[r] = {}, {}
        for c = 1, n do given[r][c] = true; grid[r][c] = solution[r][c] end
    end
    local positions = {}
    for r = 1, n do
        for c = 1, n do positions[#positions + 1] = { r, c } end
    end
    shuffle(positions)
    local total = n * n
    local floor_given = math.ceil(total * level.min_given)
    local shown = total
    for i, pos in ipairs(positions) do
        if shown <= floor_given then break end
        if on_progress then on_progress(base + span * i / total) end
        local r, c = pos[1], pos[2]
        grid[r][c] = nil
        if logicSolve(grid, n, level.tier) then
            given[r][c] = false
            shown = shown - 1
        else
            grid[r][c] = solution[r][c]
        end
    end
    local _, t2 = logicSolve(grid, n, 2)
    return given, shown, t2
end

-- on_progress (optional) is called with a 0..1 fraction while digging.
function BinairoBoard:generate(n, difficulty, on_progress)
    self.n          = n or self.n
    self.difficulty = difficulty or self.difficulty
    self.solved     = false
    self.errors     = {}
    self.undo:clear()
    self.timer:reset()
    self.timer:start()
    n = self.n
    local level = (LEVELS[self.difficulty] or LEVELS.medium)(n)

    -- Up to ATTEMPTS candidates (fresh solution each time) until one needs
    -- a number of tier-2 steps in the level's range; otherwise the one
    -- closest to that range. Every candidate is solved by logicSolve
    -- without trial, so any of them is a valid, unique puzzle. Bounded by
    -- attempt counts only: same seed, same puzzle on every device.
    local attempts = BinairoBoard.ATTEMPTS[n] or 6
    local best, best_miss
    for attempt = 1, attempts do
        local grid
        repeat
            grid = {}
            for i = 1, n do grid[i] = {} end
        until self:_fillRows(grid)
        local given, _, t2 = dig(grid, n, level, on_progress,
            (attempt - 1) / attempts, 1 / attempts)
        local miss = 0
        if t2 < level.min_t2 then miss = level.min_t2 - t2
        elseif t2 > level.max_t2 then miss = t2 - level.max_t2 end
        if not best or miss < best_miss then
            best, best_miss = { solution = grid, given = given, t2 = t2, attempts = attempt }, miss
        end
        if miss == 0 then break end
    end

    self.solution = best.solution
    self.given = best.given
    -- How the kept puzzle graded (not saved; read by the specs).
    self.grade = { t2 = best.t2, attempt = best.attempts }
    self.cells = {}
    for r = 1, n do
        self.cells[r] = {}
        for c = 1, n do
            if self.given[r][c] then self.cells[r][c] = self.solution[r][c] end
        end
    end
    if on_progress then on_progress(1) end
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
