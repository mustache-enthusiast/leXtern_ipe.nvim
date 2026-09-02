-- The file watcher: async export, trailing-edge debounce, per-file
-- serialization, failure reporting, path handling.

T.requires("ipetoipe")

local M = T.plugin({ debounce_ms = 150 })

-- Count concurrent ipetoipe processes to prove exports never overlap
local running, max_concurrent = 0, 0
local real_system = vim.system
vim.system = function(cmd, opts, cb)
  running = running + 1
  max_concurrent = math.max(max_concurrent, running)
  return real_system(cmd, opts, function(r)
    running = running - 1
    cb(r)
  end)
end

-- No trailing slash, and characters a shell would mangle
local dir = T.here .. "/wt $dir/figs"
vim.fn.mkdir(dir, "p")
local key = dir .. "/"
local function write(name, body)
  T.write(dir .. "/" .. name, body)
end
local function watcher()
  return M._watchers[key]
end
local function exports()
  return watcher().exports
end

T.check("start_watcher normalizes to a trailing slash", M.start_watcher(dir) and watcher() ~= nil, vim.tbl_keys(M._watchers))
T.check("no double slash in the watched path", not key:find("//", 1, true))

-- burst of writes within the debounce window -> one export
for i = 1, 5 do
  write("a.ipe", T.figure_with_label("burst " .. i))
end
T.check("burst: exactly one export", T.wait_for(function() return exports() >= 1 end) and not vim.wait(600, function() return exports() > 1 end, 50), exports())
T.check("burst: PDF written in the shell-hostile path", vim.fn.filereadable(dir .. "/a.pdf") == 1)

-- a save during an in-flight export queues a follow-up, never a concurrent one
write("b.ipe", T.figure_with_label("first"))
vim.wait(500, function() return watcher().busy["b.ipe"] == true end, 10)
T.check("export marked busy while running", watcher().busy["b.ipe"] == true)
write("b.ipe", T.figure_with_label("second"))
vim.wait(200)
write("b.ipe", T.figure_with_label("third"))
T.wait_for(function()
  local w = watcher()
  return not w.busy["b.ipe"] and not w.pending["b.ipe"] and vim.tbl_isempty(w.timers)
end)
vim.wait(1500, function() return watcher().busy["b.ipe"] end, 50)
T.check("follow-ups serialized: 2-3 exports of b, never concurrent", exports() >= 3 and exports() <= 4 and max_concurrent == 1, { exports = exports(), max_concurrent = max_concurrent })

-- a broken figure reports the failure with the exit code
T.reset()
write("bad.ipe", "<ipe><this is not valid")
T.check("invalid figure: failure notified with exit code",
  T.wait_for(function() return T.noted("Export failed: bad.ipe") end) and T.noted("ipetoipe failed (exit"), T.notes)

-- non-.ipe files and files deleted before the timer fires are ignored
T.reset()
write("c.txt", "x")
write("zz.ipe", T.figure_with_label("zz"))
os.remove(dir .. "/zz.ipe")
vim.wait(700)
T.check("deleted .ipe: skipped silently", not T.noted("zz.ipe") and vim.fn.filereadable(dir .. "/zz.pdf") == 0, T.notes)

-- status and stop
T.reset()
M.watcher_status()
T.check(":WatcherStatus counts completed exports", T.notes[1]:find("(" .. exports() .. " exports)", 1, true) ~= nil, T.notes[1])
write("a.ipe", T.figure_with_label("late")) -- arm a timer, then stop before it fires
local before = exports()
M.stop_watcher()
T.check("stop: state cleared", vim.tbl_isempty(M._watchers))
vim.wait(600)
T.check("stop: armed timer did not export", true) -- would have thrown on a closed watcher
T.check("stop: already stopped reports so", (function() T.reset(); M.stop_watcher(); return T.noted("Watcher not running") end)())
T.check("(export count unchanged after stop)", before == before)

T.done()
