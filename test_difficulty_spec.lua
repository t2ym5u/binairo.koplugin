-- Difficulty guarantees for Binairo (see docs/dev/TESTING.md, "Difficulty
-- specs"). Levels are graded by the board's human-style solver
-- (Board._logicSolve): tier 1 = basic rules, tier 2 = whole-line
-- reasoning, never trial. Easy: tier 1 only; Medium/Hard: a window of
-- tier-2 steps, fewer givens as the level goes up.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("Binairo difficulty", function()
    local Board

    setup(function()
        Board = require("board")
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

        it("the level table is ordered: tier, givens floor, tier-2 window", function()
            for _, n in ipairs(SIZES) do
                local e, m, h = Board.LEVELS.easy(n), Board.LEVELS.medium(n), Board.LEVELS.hard(n)
                assert.are.equal(1, e.tier)
                assert.are.equal(0, e.max_t2)
                assert.is_true(m.tier == 2 and h.tier == 2)
                assert.is_true(e.min_given > m.min_given and m.min_given > h.min_given)
                assert.is_true(e.min_t2 < m.min_t2 and m.min_t2 <= h.min_t2)
            end
        end)

        -- Generation is bounded by attempt and node counts, never by time:
        -- with a clock that jumps 1000 s at every read, a seed still gives
        -- the same puzzle.
        it("generation never reads the clock", function()
            local oc, ot = os.clock, os.time
            for _, n in ipairs({ 6, 8 }) do
                for _, d in ipairs(LEVELS) do
                    math.randomseed(55 + n); local a = Board:new(); a:generate(n, d)
                    local t = 0
                    os.clock = function() t = t + 1000; return t end
                    os.time = function(x) if x then return ot(x) end; t = t + 1000; return t end
                    local ok, b = pcall(function()
                        math.randomseed(55 + n); local b = Board:new(); b:generate(n, d)
                        return b
                    end)
                    os.clock, os.time = oc, ot
                    assert.is_true(ok, tostring(b))
                    assert.are.same(a.solution, b.solution)
                    assert.are.same(a.given, b.given)
                end
            end
            local src = assert(io.open(DIR .. "board.lua")):read("*a")
            assert.is_nil(src:find("os%.clock"))
            assert.is_nil(src:find("os%.time"))
        end)
    end)
end)
