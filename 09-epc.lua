local packages_dir = "/pkgs"

-- Cria o diretório de pacotes se não existir
if not fs.isDir(packages_dir) then
    fs.makeDir(packages_dir)
end

-- Define o diretório de pacotes como parte do PATH do shell
shell.setPath(shell.path() .. ":" .. packages_dir)
