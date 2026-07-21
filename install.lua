-- install.lua — Bootstrap installer do EPC (El Pkg Congroo)
-- Uso: wget run https://raw.githubusercontent.com/SeveningCC/epc/refs/heads/main/install.lua [tag]

local OWNER        = "SeveningCC"
local REPO         = "epc"
local REGISTRY     = "/.local/epc/packages"
local INSTALL_PATH = "/pkgs"

local tag = ({ ... })[1] or "main"

if not http then
  printError("HTTP nao esta habilitado. Habilite nas configuracoes do CC:Tweaked.")
  return
end

local function ref(t)
  return t == "main" and "refs/heads/main" or "refs/tags/" .. t
end

local function http_get(url)
  local res = http.get(url)
  if not res then error("Falha ao baixar: " .. url) end
  local body = res.readAll()
  res.close()
  return body
end

local base_url = ("https://raw.githubusercontent.com/%s/%s/%s"):format(OWNER, REPO, ref(tag))

print("Instalando EPC (El Pkg Congroo) [" .. tag .. "]...")
print("")

local pkg_data = textutils.unserializeJSON(http_get(base_url .. "/package.json"))
if not pkg_data then error("Falha ao parsear package.json") end

local dest = INSTALL_PATH .. "/epc.lua"
fs.makeDir(INSTALL_PATH)
local current_path = shell.path()
local already_in_path = false
for segment in current_path:gmatch("[^:]+") do
  if segment == INSTALL_PATH then already_in_path = true ; break end
end
if not already_in_path then
  local new_path = current_path .. ":" .. INSTALL_PATH
  shell.setPath(new_path)
  settings.set("shell.path", new_path)
  settings.save()
  print("  + " .. INSTALL_PATH .. " adicionado ao Path")
end
local f = fs.open(dest, "w")
if not f then error("Falha ao escrever: " .. dest) end
f.write(http_get(base_url .. "/epc.lua"))
f.close()
print("  + " .. dest)

-- Registra o epc como pacote para que 'epc update' funcione
fs.makeDir(fs.getDir(REGISTRY))
local packages = {}
if fs.exists(REGISTRY) then
  local rf = fs.open(REGISTRY, "r")
  if rf then packages = textutils.unserialize(rf.readAll()) or {} ; rf.close() end
end
packages[OWNER .. "/" .. REPO] = {
  owner        = OWNER,
  repo         = REPO,
  tag          = tag,
  name         = pkg_data.name,
  version      = pkg_data.version,
  description  = pkg_data.description or "",
  files        = { dest },
  dependencies = pkg_data.dependencies or {},
}
local wf = fs.open(REGISTRY, "w")
if not wf then error("Falha ao salvar registry") end
wf.write(textutils.serialize(packages))
wf.close()

print("")
print(("EPC v%s instalado com sucesso!"):format(pkg_data.version))
print("")
print("Uso: epc install <owner/repo>")
print("     epc update SeveningCC/epc")
