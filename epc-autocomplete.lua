---@diagnostic disable: undefined-global
local REGISTRY_PATH = "/.local/epc/packages"

local registry = { _packages = {} }

function registry:load()
  if not fs.exists(REGISTRY_PATH) then return end
  local f = fs.open(REGISTRY_PATH, "r")
  if not f then return end
  local data = textutils.unserialize(f.readAll())
  f.close()
  if data then self._packages = data end
end

function registry:list()
  return self._packages
end

local completion = require("cc.completion")
local COMMANDS = { "install", "uninstall", "update", "list" }

shell.setCompletionFunction(shell.resolveProgram("epc") or "epc.lua",
  function(_, index, text, previous)
    if index == 1 then return completion.choice(text, COMMANDS, true) end
    local cmd = previous[#previous]
    if (cmd == "uninstall" or cmd == "update") and index == 2 then
      registry:load()
      local ids = {}
      for id in pairs(registry:list()) do ids[#ids + 1] = id end
      table.sort(ids)
      return completion.choice(text, ids, true)
    end
  end)
