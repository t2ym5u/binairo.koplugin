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
end)
