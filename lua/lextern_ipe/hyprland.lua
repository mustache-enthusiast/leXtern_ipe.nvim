--- Hyprland integration: launch Ipe as a floating, centered window of a
--- fixed size.
---
--- Hyprland is configured in Lua since 0.55 and exposes
--- `hyprctl eval <code>` to run Lua inside the compositor, so instead of
--- the legacy `hyprctl dispatch exec "[float;size W H;center] cmd"`
--- string syntax we evaluate the same call a hyprland.lua would make.
--- (On 0.56 `hyprctl dispatch X` is already only shorthand for
--- `hl.dispatch(X)` -- the old string form is a Lua syntax error, not
--- merely deprecated.)
---
---   hl.exec_cmd(cmd: string, rules?: table<string, string|number|boolean>)
---
--- Signature and value types are from Hyprland's own type stub,
--- /usr/share/hypr/stubs/hl.meta.lua. Rule effects are flat values, as
--- in the shipped example config (float = true, move = "20 monitor_h-120"),
--- so the size is the string "W H". Verified against Hyprland 0.56.2:
--- the window comes up floating, 800x900, centered.
---
--- If a future Hyprland changes the API, this file is the only place to
--- update; user configs just set `floating = true`.
local M = {}

--- Whether we're running under Hyprland with hyprctl available
function M.is_available()
  return vim.env.HYPRLAND_INSTANCE_SIGNATURE ~= nil and vim.fn.executable("hyprctl") == 1
end

--- Serialize a flat rules table as a Lua table literal, keys sorted
--- for a stable result
local function lua_table(rules)
  local keys = vim.tbl_keys(rules)
  table.sort(keys)
  local parts = {}
  for _, key in ipairs(keys) do
    local value = rules[key]
    local literal
    if type(value) == "string" then
      literal = string.format("%q", value)
    elseif type(value) == "number" or type(value) == "boolean" then
      literal = tostring(value)
    else
      error("lextern_ipe.hyprland: unsupported rule value for " .. key .. ": " .. type(value))
    end
    table.insert(parts, string.format("[%q] = %s", key, literal))
  end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

--- The rule effects for a floating window of `size` = { width, height }
function M.float_rules(size)
  return { float = true, size = string.format("%d %d", size[1], size[2]), center = true }
end

--- Shell-quote one argument, leaving plain words (ipe, /usr/bin/ipe,
--- --flag) bare for readability
local function shell_arg(arg)
  if arg:match("^[%w%._/%-]+$") then
    return arg
  end
  return vim.fn.shellescape(arg)
end

--- Build the Lua snippet Hyprland evaluates to spawn `argv` with
--- `rules`. hl.exec_cmd runs its command through a shell, so each
--- argument is shell-quoted first; the resulting command line is then
--- embedded as a Lua string literal via %q.
function M.exec_snippet(argv, rules)
  local cmd = table.concat(vim.tbl_map(shell_arg, argv), " ")
  return string.format("hl.exec_cmd(%s, %s)", string.format("%q", cmd), lua_table(rules))
end

--- Launch `argv` floating at `size` = { width, height }, centered.
--- Asynchronous; calls on_error(message) on the main loop if hyprctl
--- refused (non-zero exit, or anything but "ok" on stdout), in which
--- case nothing was spawned and the caller can fall back.
function M.launch(argv, size, on_error)
  local code = M.exec_snippet(argv, M.float_rules(size))
  vim.system({ "hyprctl", "eval", code }, { text = true }, function(result)
    local out = vim.trim((result.stdout or "") .. (result.stderr or ""))
    if result.code ~= 0 or out ~= "ok" then
      vim.schedule(function()
        on_error(string.format("hyprctl eval exited %d: %s", result.code, out ~= "" and out or "(no output)"))
      end)
    end
  end)
end

return M
