-- :checkhealth lextern_ipe: config validation, unknown option names,
-- stylesheet and IPESTYLES checks.

local starter = T.root .. "/templates/preamble.isy"
T.write(T.here .. "/not-a-sheet.isy", "nope")

local function health(setup_opts, env)
  local M = require("lextern_ipe")
  -- start from pristine defaults each time
  M.config = vim.deepcopy(M.defaults)
  M.setup(setup_opts)
  local saved = {}
  for k, v in pairs(env or {}) do
    saved[k] = vim.env[k]
    vim.env[k] = v
  end
  local out = T.checkhealth()
  for k in pairs(env or {}) do
    vim.env[k] = saved[k]
  end
  return out
end

-- a config with several problems
local out = health({
  floating_typo = true, -- unknown
  float_width = 900, -- an option from an old version
  stylesheets = { "~/nope.isy", starter, T.here .. "/not-a-sheet.isy" },
  float_size = { 800 },
  library_dir = T.here .. "/my lib",
}, { IPESTYLES = "/tmp:/some/file.isy:_" })

T.check("unknown options warned, sorted", out:find("unrecognized config option(s), ignored: float_width, floating_typo", 1, true) ~= nil, out)
T.check("missing stylesheet: error with ~ expanded", out:find("stylesheet not readable: " .. vim.env.HOME .. "/nope.isy", 1, true) ~= nil)
T.check("valid stylesheet: ok", out:find("stylesheet found: " .. starter, 1, true) ~= nil)
T.check("non-stylesheet: error", out:find("not an Ipe stylesheet (no <ipestyle> element): " .. T.here .. "/not-a-sheet.isy", 1, true) ~= nil)
T.check("IPESTYLES: file entry warned, dirs and _ accepted", out:find("IPESTYLES entry is not a directory: /some/file.isy", 1, true) ~= nil and out:find("not a directory: /tmp", 1, true) == nil and out:find("not a directory: _", 1, true) == nil)
T.check("float_size: bad shape is an error", out:find("float_size should be { width, height }", 1, true) ~= nil)
T.check("library_dir: space is an error", out:find("library_dir contains", 1, true) ~= nil and out:find("LaTeX can't use", 1, true) ~= nil, out)

-- a clean config
out = health({ library_dir = T.here .. "/lib", stylesheets = { starter } })
T.check("clean: all option names recognized", out:find("all config option names recognized", 1, true) ~= nil)
T.check("clean: launch mode reported", out:find("plain detached job", 1, true) ~= nil)
T.check("clean: TEXINPUTS ok against the isolated package dir", out:find("TEXINPUTS is set up correctly", 1, true) ~= nil, out)
T.check("clean: no errors", out:find("ERROR", 1, true) == nil, out:match("[^\n]*ERROR[^\n]*"))

-- floating + launch_cmd precedence, and floating without Hyprland
out = health({ floating = true, launch_cmd = function() end })
T.check("floating + launch_cmd: precedence warned", out:find("launch_cmd takes precedence", 1, true) ~= nil)
out = health({ floating = true }, { HYPRLAND_INSTANCE_SIGNATURE = "" })
-- vim.env["X"] = "" sets it to empty rather than unsetting, so also cover the unset case directly
vim.env.HYPRLAND_INSTANCE_SIGNATURE = nil
out = health({ floating = true })
T.check("floating without Hyprland: warned", out:find("Hyprland isn't detected", 1, true) ~= nil, out)

T.done()
