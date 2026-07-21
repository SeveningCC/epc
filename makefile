ROOT := ~/.local/share/PrismLauncher/instances/Primos\ CCC\ v1.3.0/minecraft/saves/Laboratorio/computercraft/computer/3

dev:
	cp epc.lua $(ROOT)/pkgs/
	cp 09-epc.lua $(ROOT)/startup/
	cp epc-autocomplete.lua $(ROOT)/sys/autocomplete/
