local base64 = require("cc.base64")

-- ─── Settings ─────────────────────────────────────────────────────────────────

local INSTALL_PATH  = settings.get("epc.install_path", "/pkgs")
local REGISTRY_PATH = "/.local/epc/packages"

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function tag_to_ref(tag)
  return tag == "main" and "refs/heads/main" or "refs/tags/" .. tag
end

local function dest_path(base, rel)
  if base == "/" then return "/" .. rel end
  return base .. "/" .. rel
end

local function write_file(dest, content)
  fs.makeDir(fs.getDir(dest))
  local f = fs.open(dest, "w")
  if not f then error(("Falha ao abrir arquivo para escrita: %s"):format(dest)) end
  f.write(content)
  f.close()
end

-- ─── Registry ─────────────────────────────────────────────────────────────────

local registry = { _packages = {} }

function registry:load()
  if not fs.exists(REGISTRY_PATH) then return end
  local f = fs.open(REGISTRY_PATH, "r")
  if not f then return end
  local data = textutils.unserialize(f.readAll())
  f.close()
  if data then self._packages = data end
end

function registry:save()
  fs.makeDir(fs.getDir(REGISTRY_PATH))
  local f = fs.open(REGISTRY_PATH, "w")
  if not f then error("Falha ao salvar registry em: " .. REGISTRY_PATH) end
  f.write(textutils.serialize(self._packages))
  f.close()
end

function registry:add(pkg, installed_files)
  self._packages[pkg.owner .. "/" .. pkg.repo] = {
    owner        = pkg.owner,
    repo         = pkg.repo,
    tag          = pkg.tag,
    name         = pkg.name,
    version      = pkg.version,
    description  = pkg.description,
    files        = installed_files,
    dependencies = pkg.dependencies,
    install_path = pkg.install_path,
  }
  self:save()
end

function registry:remove(owner, repo)
  self._packages[owner .. "/" .. repo] = nil
  self:save()
end

function registry:get(owner, repo)
  return self._packages[owner .. "/" .. repo]
end

function registry:list()
  return self._packages
end

-- ─── Package ──────────────────────────────────────────────────────────────────

local Package = {}
Package.__index = Package

local function copy_array(arr)
  local t = {}
  if arr then for _, v in ipairs(arr) do t[#t + 1] = v end end
  return t
end

function Package:new(owner, repo, tag, data)
  return setmetatable({
    owner        = owner,
    repo         = repo,
    tag          = tag,
    name         = data.name,
    version      = data.version,
    description  = data.description or "",
    files        = copy_array(data.files),
    dependencies = copy_array(data.dependencies),
    install_path = data.install_path,
  }, self)
end

function Package:instantiate_from_data(data)
  return Package:new(data.owner, data.repo, data.tag, data)
end

function Package.fetch(id)
  local owner, repo, tag = string.match(id, "([^/]+)/([^@]+)@?(.*)")
  if not tag or tag == "" or tag == "latest" then tag = "main" end

  local url = ("https://raw.githubusercontent.com/%s/%s/%s/package.json")
    :format(owner, repo, tag_to_ref(tag))
  local res = http.get(url)
  if not res then error("Falha ao buscar package.json de: " .. url) end
  local raw = res.readAll()
  res.close()

  local data, err = textutils.unserializeJSON(raw)
  if not data then error("Falha ao parsear package.json: " .. (err or "erro desconhecido")) end

  return Package:new(owner, repo, tag, data)
end

local function download_tree(owner, repo, tag, path, installed, install_path)
  local url = ("https://api.github.com/repos/%s/%s/contents/%s?ref=%s")
    :format(owner, repo, path, tag_to_ref(tag))
  local res = http.get(url, { ["User-Agent"] = "epc" })
  if not res then error(("Falha ao acessar API do GitHub para: %s"):format(path)) end
  local data = textutils.unserializeJSON(res.readAll())
  res.close()
  if not data then error(("Falha ao parsear resposta da API para: %s"):format(path)) end

  if data[1] ~= nil then
    for _, entry in ipairs(data) do
      if entry.type == "file" or entry.type == "dir" then
        download_tree(owner, repo, tag, entry.path, installed, install_path)
      end
    end
  elseif data.type == "file" then
    if data.encoding ~= "base64" then
      error(("Encoding desconhecido '%s' para: %s"):format(data.encoding, data.path))
    end
    local dest = dest_path(install_path, data.path)
    write_file(dest, base64.decode((data.content:gsub("\n", ""))))
    installed[#installed + 1] = dest
  else
    error(("Tipo inesperado da API para: %s"):format(path))
  end
end

function Package:install()
  local installed = {}
  local effective_path = self.install_path or INSTALL_PATH
  for _, path in ipairs(self.files) do
    download_tree(self.owner, self.repo, self.tag, path, installed, effective_path)
  end
  registry:load()
  registry:add(self, installed)
  for _, dep_id in ipairs(self.dependencies) do
    local owner, repo = string.match(dep_id, "([^/]+)/([^@]+)")
    if registry:get(owner, repo) then
      print("  Dependencia ja instalada: " .. dep_id)
    else
      print("  Instalando dependencia: " .. dep_id)
      Package.fetch(dep_id):install()
    end
  end
end

function Package:uninstall()
  for _, dest in ipairs(self.files) do
    if fs.exists(dest) then fs.delete(dest) end
  end
  registry:load()
  registry:remove(self.owner, self.repo)
end

-- ─── Commands ─────────────────────────────────────────────────────────────────

local function cmd_install(id)
  local owner, repo = string.match(id, "([^/]+)/([^@]+)")
  if not owner or not repo then error("Id invalido: use o formato owner/repo[@tag]") end
  registry:load()
  if registry:get(owner, repo) then
    print(("Pacote '%s' ja esta instalado."):format(id))
    return
  end
  print("Buscando " .. id .. "...")
  local pkg = Package.fetch(id)
  print(("Instalando %s v%s..."):format(pkg.name, pkg.version))
  pkg:install()
  print("Instalado com sucesso.")
end

local function cmd_uninstall(id)
  local owner, repo = string.match(id, "([^/]+)/([^@]+)")
  if not owner or not repo then error("Id invalido: use o formato owner/repo") end
  registry:load()
  local entry = registry:get(owner, repo)
  if not entry then error(("Pacote '%s' nao esta instalado"):format(id)) end
  print(("Desinstalando %s..."):format(id))
  Package:instantiate_from_data(entry):uninstall()
  print("Desinstalado com sucesso.")
end

local function cmd_update(id)
  local owner, repo = string.match(id, "([^/]+)/([^@]+)")
  if not owner or not repo then error("Id invalido: use o formato owner/repo[@tag]") end
  registry:load()
  local entry = registry:get(owner, repo)
  if not entry then error(("Pacote '%s' nao esta instalado"):format(id)) end
  print(("Atualizando %s..."):format(id))
  Package:instantiate_from_data(entry):uninstall()
  print("Buscando " .. id .. "...")
  local pkg = Package.fetch(id)
  print(("Instalando %s v%s..."):format(pkg.name, pkg.version))
  pkg:install()
  print("Atualizado com sucesso.")
end

local function cmd_list()
  registry:load()
  local packages = registry:list()
  local count = 0
  for id, pkg in pairs(packages) do
    print(("%-30s v%s"):format(id, pkg.version))
    count = count + 1
  end
  if count == 0 then print("Nenhum pacote instalado.") end
end

-- ─── Autocomplete ─────────────────────────────────────────────────────────────

if shell then
  local completion       = require("cc.completion")
  local shell_completion = require("cc.shell.completion")

  shell.setCompletionFunction(shell.getRunningProgram(), shell_completion.build(
    { shell_completion.choice, { "install", "uninstall", "update", "list" }, true },
    function(_, text, previous)
      local cmd = previous[#previous]
      if cmd == "uninstall" or cmd == "update" then
        registry:load()
        local ids = {}
        for id in pairs(registry:list()) do ids[#ids + 1] = id end
        table.sort(ids)
        return completion.choice(text, ids, true)
      end
    end
  ))
end

-- ─── CLI ──────────────────────────────────────────────────────────────────────

local commands = {
  install   = function(args) cmd_install(args[1]) end,
  uninstall = function(args) cmd_uninstall(args[1]) end,
  update    = function(args) cmd_update(args[1]) end,
  list      = function(_)    cmd_list() end,
}

local args = { ... }
local cmd  = args[1]

if not cmd then
  print("Uso: epc <comando> [args]")
  print("  install <owner/repo[@tag]>")
  print("  uninstall <owner/repo>")
  print("  update <owner/repo[@tag]>")
  print("  list")
  return
end

local handler = commands[cmd]
if not handler then
  print("Comando desconhecido: " .. cmd)
  return
end

local cmd_args = {}
for i = 2, #args do cmd_args[i - 1] = args[i] end
handler(cmd_args)
