-- The Hyprland floating launch: the Lua snippet we hand to
-- `hyprctl eval`, and (opt-in, LEXTERN_TEST_LIVE=1) a real launch.

local H = require("lextern_ipe.hyprland")

local rules = H.float_rules({ 800, 900 })
T.check("float_rules: float/size/center", rules.float == true and rules.size == "800 900" and rules.center == true, rules)

local snippet = H.exec_snippet({ "ipe", "/tmp/a b/$x.ipe" }, rules)
T.check("snippet calls hl.exec_cmd", snippet:find("^hl%.exec_cmd%(") ~= nil, snippet)
T.check("snippet shell-escapes the path", snippet:find("'/tmp/a b/$x.ipe'", 1, true) ~= nil, snippet)

-- It must be valid Lua that passes the escaped command and the rules
-- through unchanged: evaluate it against a stub `hl`.
local captured
local chunk = assert((loadstring or load)("return " .. snippet))
setfenv(chunk, { hl = { exec_cmd = function(cmd, r) captured = { cmd = cmd, rules = r } end } })
chunk()
T.check("snippet evaluates: command line", captured and captured.cmd == "ipe '/tmp/a b/$x.ipe'", captured)
T.check("snippet evaluates: rules", captured and vim.deep_equal(captured.rules, rules), captured)

-- Odd characters survive the %q round trip
local weird = H.exec_snippet({ "ipe", 'q"uote\\back\nnl.ipe' }, rules)
chunk = assert((loadstring or load)("return " .. weird))
setfenv(chunk, { hl = { exec_cmd = function(cmd) captured = cmd end } })
chunk()
T.check("snippet survives quotes, backslashes, newlines", captured == "ipe " .. vim.fn.shellescape('q"uote\\back\nnl.ipe'), captured)

local sig = vim.env.HYPRLAND_INSTANCE_SIGNATURE
vim.env.HYPRLAND_INSTANCE_SIGNATURE = nil
T.check("is_available: false without HYPRLAND_INSTANCE_SIGNATURE", H.is_available() == false)
vim.env.HYPRLAND_INSTANCE_SIGNATURE = sig

-- Live launch (opens and closes a real Ipe window)
if vim.env.LEXTERN_TEST_LIVE ~= "1" then
  print("SKIP (partial): live launch needs LEXTERN_TEST_LIVE=1 under Hyprland")
elseif not H.is_available() or vim.fn.executable("ipe") == 0 then
  print("SKIP (partial): live launch needs a Hyprland session and ipe")
else
  local probe = T.here .. "/probe.ipe"
  T.write(probe, T.template())
  local function ipe_windows()
    local ok, clients = pcall(vim.json.decode, vim.fn.system({ "hyprctl", "clients", "-j" }))
    if not ok then
      return {}
    end
    return vim.tbl_filter(function(c)
      return c.class == "ipe" and (c.title or ""):find(probe, 1, true) ~= nil
    end, clients)
  end
  local launch_err
  H.launch({ "ipe", probe }, { 800, 900 }, function(err) launch_err = err end)
  local appeared = T.wait_for(function() return #ipe_windows() == 1 end, 10000)
  local win = ipe_windows()[1]
  T.check("live: window appeared", appeared and launch_err == nil, launch_err)
  T.check("live: floating", win and win.floating == true, win)
  T.check("live: 800x900", win and vim.deep_equal(win.size, { 800, 900 }), win and win.size)
  if win then
    -- cleanup: terminate the Ipe process Hyprland reported for the window
    vim.uv.kill(win.pid, "sigterm")
    local gone = T.wait_for(function() return #ipe_windows() == 0 end, 5000)
    T.check("live: window closed again", gone)
  end

  -- A refused eval reports an error instead of silently doing nothing
  local refused
  vim.system = (function(real)
    return function(cmd, opts, cb)
      if cmd[1] == "hyprctl" and cmd[2] == "eval" then
        cmd = { "hyprctl", "eval", "nosuchfunction()" }
      end
      return real(cmd, opts, cb)
    end
  end)(vim.system)
  H.launch({ "ipe", probe }, { 800, 900 }, function(err) refused = err end)
  T.check("live: hyprctl error surfaces to on_error", T.wait_for(function() return refused ~= nil end, 5000) and refused:find("exited", 1, true) ~= nil, refused)
end

T.done()
