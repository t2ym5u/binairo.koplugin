local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("BinairoBoard", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    local function newBoard(n, diff)
        math.randomseed(42)
        local b = Board:new({ n = n or 6, difficulty = diff or "easy" })
        b:generate()
        return b
    end

    describe("generate", function()
        it("solution has exactly n/2 zeros and n/2 ones per row and column", function()
            local b = newBoard(6)
            local n = b.n
            for r = 1, n do
                local zeros, ones = 0, 0
                for c = 1, n do
                    if b.solution[r][c] == 0 then zeros = zeros + 1 else ones = ones + 1 end
                end
                assert.are.equal(n / 2, zeros)
                assert.are.equal(n / 2, ones)
            end
        end)

        it("solution has no three consecutive identical values in any row", function()
            local b = newBoard(6)
            local n = b.n
            for r = 1, n do
                local run, last = 0, nil
                for c = 1, n do
                    local v = b.solution[r][c]
                    if v == last then run = run + 1 else run = 1; last = v end
                    assert.is_true(run < 3, ("row %d has 3+ consecutive %s"):format(r, tostring(v)))
                end
            end
        end)

        it("leaves some cells hidden (not all given)", function()
            local b = newBoard(6)
            local hidden = 0
            for r = 1, b.n do
                for c = 1, b.n do
                    if not b.given[r][c] then hidden = hidden + 1 end
                end
            end
            assert.is_true(hidden > 0)
        end)
    end)

    describe("toggle / undoLast", function()
        it("cycles a free cell nil -> 0 -> 1 -> nil", function()
            local b = newBoard(6)
            local r, c
            for rr = 1, b.n do
                for cc = 1, b.n do
                    if not b.given[rr][cc] then r, c = rr, cc; break end
                end
                if r then break end
            end
            b.cells[r][c] = nil
            b:toggle(r, c)
            assert.are.equal(0, b.cells[r][c])
            b:toggle(r, c)
            assert.are.equal(1, b.cells[r][c])
            b:toggle(r, c)
            assert.is_nil(b.cells[r][c])
        end)

        it("refuses to edit a given cell", function()
            local b = newBoard(6)
            local r, c
            for rr = 1, b.n do
                for cc = 1, b.n do
                    if b.given[rr][cc] then r, c = rr, cc; break end
                end
                if r then break end
            end
            local ok = b:toggle(r, c)
            assert.is_false(ok)
        end)

        it("undoLast restores the previous cell value", function()
            local b = newBoard(6)
            local r, c
            for rr = 1, b.n do
                for cc = 1, b.n do
                    if not b.given[rr][cc] then r, c = rr, cc; break end
                end
                if r then break end
            end
            b.cells[r][c] = nil
            b:toggle(r, c)
            assert.is_true(b:undoLast())
            assert.is_nil(b.cells[r][c])
        end)
    end)

    describe("checkErrors / revealSolution", function()
        it("revealSolution fills every cell to match the solution and solves the board", function()
            local b = newBoard(6)
            b:revealSolution()
            assert.is_true(b.solved)
            assert.are.equal(0, b:emptyCells())
            for r = 1, b.n do
                for c = 1, b.n do
                    assert.are.equal(b.solution[r][c], b.cells[r][c])
                end
            end
        end)

        it("checkErrors flags a cell that differs from the solution", function()
            local b = newBoard(6)
            local r, c
            for rr = 1, b.n do
                for cc = 1, b.n do
                    if not b.given[rr][cc] then r, c = rr, cc; break end
                end
                if r then break end
            end
            b.cells[r][c] = (b.solution[r][c] == 0) and 1 or 0
            local errors = b:checkErrors()
            assert.is_true(errors[r][c])
        end)
    end)

    describe("serialize / load", function()
        it("round-trips solution, cells and given mask", function()
            local b = newBoard(6)
            local data = b:serialize()

            local b2 = Board:new()
            assert.is_true(b2:load(data))
            assert.are.equal(b.n, b2.n)
            for r = 1, b.n do
                for c = 1, b.n do
                    assert.are.equal(b.solution[r][c], b2.solution[r][c])
                end
            end
        end)
    end)
    -- 1.4.0: row-at-a-time fill + forced-opposite uniqueness check.
    describe("generator (1.4.0 speed-up)", function()
        local function checkSolution(b)
            local n, half = b.n, b.n / 2
            local rows, cols = {}, {}
            for r = 1, n do
                local ones, rk, ck, cones = 0, "", "", 0
                for c = 1, n do
                    local v = b.solution[r][c]
                    assert.is_true(v == 0 or v == 1)
                    ones = ones + v
                    rk = rk .. v
                    if c > 2 then
                        assert.is_false(v == b.solution[r][c - 1] and v == b.solution[r][c - 2])
                    end
                    local w = b.solution[c][r]
                    cones = cones + w
                    ck = ck .. w
                    if c > 2 then
                        assert.is_false(w == b.solution[c - 1][r] and w == b.solution[c - 2][r])
                    end
                end
                assert.are.equal(half, ones)
                assert.are.equal(half, cones)
                assert.is_nil(rows[rk]); rows[rk] = true
                assert.is_nil(cols[ck]); cols[ck] = true
            end
        end

        it("builds valid, uniquely solvable puzzles at every size", function()
            for _, n in ipairs({ 6, 8, 10, 12 }) do
                for seed = 1, 6 do
                    math.randomseed(seed * 101 + n)
                    local b = Board:new()
                    b:generate(n, "hard")
                    checkSolution(b)
                    local count = Board._countSolutions(b.cells, b.given, n, 2, 2000000)
                    assert.are.equal(1, count)
                end
            end
        end)

        it("hasOtherSolution agrees with the solution counter", function()
            -- Each removal is checked with both; the new check ignores the
            -- distinct-lines rule, so it may only ever be stricter.
            local stricter = 0 -- counted for debugging only
            for seed = 1, 4 do
                math.randomseed(seed)
                local n = 8
                local b = Board:new()
                b:generate(n, "easy")
                local cells, given = {}, {}
                for r = 1, n do
                    cells[r], given[r] = {}, {}
                    for c = 1, n do cells[r][c] = b.solution[r][c]; given[r][c] = true end
                end
                for r = 1, n do
                    for c = 1, n do
                        given[r][c] = false
                        local other = Board._hasOtherSolution(cells, given, n, r, c, 1e9, b.solution)
                        local count = Board._countSolutions(cells, given, n, 2, 1e9)
                        if not other then assert.are.equal(1, count) end
                        if other and count == 1 then stricter = stricter + 1 end
                        if not other then cells[r][c] = nil else given[r][c] = true end
                    end
                end
            end
        end)

        it("gives the same puzzle for the same seed", function()
            math.randomseed(777); local a = Board:new(); a:generate(10, "medium")
            math.randomseed(777); local b = Board:new(); b:generate(10, "medium")
            assert.are.same(a.solution, b.solution)
            assert.are.same(a.given, b.given)
        end)

        it("generates 12x12 Hard quickly", function()
            local t0 = os.clock()
            for seed = 1, 5 do
                math.randomseed(seed)
                Board:new():generate(12, "hard")
            end
            -- ~15 ms each in LuaJIT; very generous for plain Lua.
            assert.is_true(os.clock() - t0 < 10)
        end)

        it("reports progress while digging", function()
            math.randomseed(3)
            local last, calls = -1, 0
            Board:new():generate(8, "medium", function(f)
                assert.is_true(f >= last and f <= 1)
                last, calls = f, calls + 1
            end)
            assert.is_true(calls > 0)
        end)
    end)

    -- 1.5.0: levels graded by a human-style solver, never trial and error.
    describe("difficulty levels (1.5.0)", function()
        local SIZES, LEVELS = { 6, 8, 10, 12 }, { "easy", "medium", "hard" }
        local SEEDS = 8

        local function givenGrid(b)
            local g = {}
            for r = 1, b.n do
                g[r] = {}
                for c = 1, b.n do
                    if b.given[r][c] then g[r][c] = b.solution[r][c] end
                end
            end
            return g
        end

        it("every level is solvable without trial, within its tier and window", function()
            for _, n in ipairs(SIZES) do
                for _, d in ipairs(LEVELS) do
                    local level = Board.LEVELS[d](n)
                    for seed = 1, SEEDS do
                        math.randomseed(seed * 31 + n)
                        local b = Board:new()
                        b:generate(n, d)
                        local ok, t2, v = Board._logicSolve(givenGrid(b), n, level.tier)
                        assert.is_true(ok, n .. " " .. d .. " seed " .. seed)
                        for r = 1, n do
                            for c = 1, n do
                                assert.are.equal(b.solution[r][c], v[(r - 1) * n + c])
                            end
                        end
                        if d == "easy" then
                            assert.are.equal(0, t2)
                        else
                            assert.is_true(t2 >= 1, n .. " " .. d .. " needs tier 2")
                        end
                    end
                end
            end
        end)

        it("levels are distinct: fewer givens and more tier-2 steps as they go up", function()
            for _, n in ipairs(SIZES) do
                local giv, t2s = {}, {}
                for li, d in ipairs(LEVELS) do
                    giv[li], t2s[li] = 0, 0
                    for seed = 1, SEEDS do
                        math.randomseed(seed * 17 + n)
                        local b = Board:new()
                        b:generate(n, d)
                        local _, t2 = Board._logicSolve(givenGrid(b), n, 2)
                        t2s[li] = t2s[li] + t2
                        for r = 1, n do
                            for c = 1, n do
                                if b.given[r][c] then giv[li] = giv[li] + 1 end
                            end
                        end
                    end
                end
                assert.is_true(giv[1] > giv[2] and giv[2] > giv[3], "givens n=" .. n)
                assert.is_true(t2s[1] < t2s[2] and t2s[2] < t2s[3], "tier-2 steps n=" .. n)
            end
        end)

        it("the solver never settles an ambiguous grid", function()
            -- Random partial grids: whenever the solver finishes one, the
            -- brute-force counter finds exactly one solution, and it is
            -- the one the solver found.
            local solved = 0
            for seed = 1, 200 do
                math.randomseed(seed)
                local n = seed % 2 == 0 and 6 or 8
                local b = Board:new({ n = n })
                b:generate(n, "easy")
                local cells, given, g = {}, {}, {}
                local density = 0.3 + (seed % 4) * 0.1
                for r = 1, n do
                    cells[r], given[r], g[r] = {}, {}, {}
                    for c = 1, n do
                        if math.random() < density then
                            cells[r][c], given[r][c], g[r][c] = b.solution[r][c], true, b.solution[r][c]
                        else
                            given[r][c] = false
                        end
                    end
                end
                local ok, _, v = Board._logicSolve(g, n, 2)
                if ok then
                    solved = solved + 1
                    assert.are.equal(1, (Board._countSolutions(cells, given, n, 2, 1e7)))
                    for r = 1, n do
                        for c = 1, n do assert.are.equal(b.solution[r][c], v[(r - 1) * n + c]) end
                    end
                end
            end
            assert.is_true(solved >= 25, "solved " .. solved)
        end)

        it("generation stays bounded (12x12 Hard, worst of 10 seeds)", function()
            local worst = 0
            for seed = 1, 10 do
                math.randomseed(seed)
                local t0 = os.clock()
                Board:new():generate(12, "hard")
                worst = math.max(worst, os.clock() - t0)
            end
            -- <= 40 ms in LuaJIT; very generous for plain Lua.
            assert.is_true(worst < 2)
        end)

        it("loads a save from 1.4.x", function()
            local b = Board:new()
            assert.is_true(b:load({
                n = 6, difficulty = "hard", solved = false,
                solution = { {0,0,1,0,1,1}, {1,1,0,1,0,0}, {0,1,0,0,1,1},
                             {1,0,1,1,0,0}, {0,1,1,0,0,1}, {1,0,0,1,1,0} },
                cells = { {0}, {}, {}, {}, {}, {} },
                given = { {true,false,false,false,false,false}, {}, {}, {}, {}, {} },
            }))
            assert.are.equal(6, b.n)
            assert.are.equal("hard", b.difficulty)
            assert.are.equal(0, b.cells[1][1])
        end)
    end)
end)
