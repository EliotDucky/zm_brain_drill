#using scripts\shared\system_shared;

#using scripts\zm\_zm_powerups;

#insert scripts\zm\zm_brain_drill\zm_brain_drill.gsh;

#namespace zm_brain_drill;

function autoexec __init__system(){
	system::register("zm_brain_drill", &__init__, undefined, undefined);
}

function __init__(){
	zm_powerups::include_zombie_powerup("brain");
	zm_powerups::add_zombie_powerup("brain");
}