#using scripts\codescripts\struct;

#using scripts\shared\array_shared;
#using scripts\shared\callbacks_shared;
#using scripts\shared\system_shared;
#using scripts\shared\util_shared;

#using scripts\zm\_zm_laststand;
#using scripts\zm\_zm_perks;
#using scripts\zm\_zm_weapons;

#precache("hintstring", "Press ^3[{+activate}]^7 to ^5Mindsave^7");
#precache("model", "c_t6_default_character_fb");

#namespace zm_brain_drill;

function autoexec __init__(){
	system::register("zm_brain_drill", &brainDrillInit, undefined, undefined);
}

/*
Brain Drill setup:
	trigger_use
	targetname: "brain_drill_trig"
	target: "brain_drill_respawn"

	THIS IS THE brain_drill to parse into brainDrillSave
	struct
	targetname: "brain_drill_respawn"
	target: "brain_drill_clone"

	THIS IS WHERE TO SHOW THE MODEL IN THE MACHINE
	struct
	targetname: "brain_drill_clone"

*/

function brainDrillInit()
{
	
	//level.func_brain_drill_respawn = &brainDrillRespawn;
	level.check_end_solo_game_override = &checkPlayerBrainDrill;
	level.var_50d5cc84 = 0;
	
	//GET ENT OF BRAIN DRILLS and thread on waitfors
	callback::on_player_killed(&checkPlayerBrainDrill);
	//level.callbackPlayerKilled = &checkPlayerBrainDrill;

	//GLOBAL LOGIC DOESN'T WORK, DELETE AND UNCOMMENT IN ZM_PATCH
	//level.brain_drill_callback = &checkPlayerBrainDrill;

	brain_trigs = GetEntArray("brain_drill_trig", "targetname");
	array::thread_all(brain_trigs, &brainDrillWaitFor);

	level thread demo();
}

//FOR TESTING ONLY
//THREAD
function demo(){
	demo_trig = GetEnt("brain_demo", "targetname");
	while(true){
		demo_trig waittill("trigger", p);
		p brainDrillRespawn();
	}
	
}

//Call On: brain drill trigger
//THREAD
function brainDrillWaitFor(){
	self UseTriggerRequireLookAt();
	self SetCursorHint("HINT_NOICON");
	self SetHintString("Press ^3[{+activate}]^7 to ^5Mindsave^7");

	brain_drill = struct::get(self.target, "targetname");

	for(;;){
		self waittill("trigger", player);
		IPrintLnBold("mindsaved");
		player thread brainDrillSave(brain_drill);
	}
}

/*
	Player has attribute player.brain_drill which is the ent/struct of the saved brain drill
	Saved info is a struct self.mindsaved
		.perks
		.weapon_info
			.weapon
			.clip_size
			.left_clip_size
			.stock_size
		.current_weapon
		.score
*/

/*
//Call On: Player  - callback::on_player_killed
function deathCallback(){
	self endon("disconnect");
	IPrintLnBold("dead");
	if(self checkPlayerBrainDrill()){
		IPrintLnBold("go");
		self thread brainDrillRespawn();
	}
}
*/

//Call On: Player to mindsave
function brainDrillSave(brain_drill){
	self endon("disconnect");
	if(isdefined(self.brain_drill)){
		//Hide old clone model
		self.brain_drill.clone Delete();
	}
	self.brain_drill = brain_drill;

	//Show new clone model
	self.brain_drill.clone = brain_drill brainDrillSpawnClone();

	//Save info
	self.mindsaved = SpawnStruct();

	//Active perks
	if(isdefined(self.perks_active)){
		self.mindsaved.perks = [];
		foreach(perk in self.perks_active){
			array::add(self.mindsaved.perks, perk, 0); //No dupes
			IPrintLnBold(perk);
		}
	}
	wait(0.05);
	//NO GUMS
	self.mindsaved.current_weapon = self GetCurrentWeapon();
	player_weapons = self GetWeaponsList();
	self.mindsaved.weapon_info = [];
	foreach(weapon in player_weapons){
		IPrintLnBold(weapon.displayname);
		//Handle Alt Weapons
		base_of_alt = zm_weapons::get_nonalternate_weapon(weapon);
		if(base_of_alt != weapon){
			//Don't need to save the alt weapon when we save the base weapon
			continue;
		}
		//DO SPECIAL CASES FOR SPECIAL WEAPONS IF NEEDED
		
		//Save weapon info
		info = SpawnStruct();
		info.weapon = weapon;
		info.clip_size = self GetWeaponAmmoClip(weapon);
		info.left_clip_size = 0;
		if(weapon.dualWieldWeapon != level.weaponNone){
			info.left_clip_size = self GetWeaponAmmoClip(weapon.dualWieldWeapon);
		}
		info.stock_size = self GetWeaponAmmoStock(weapon);

		array::add(self.mindsaved.weapon_info, info);

	}

	self.mindsaved.score = self.score;
	IPrintLnBold(self.score);

}

//Call On: Player to respawn
function brainDrillRespawn(){
	self endon("disconnect");
	//SAY QUOTE
	self notify("stop_revive_trigger");
	wait(0.05);

	self zm_laststand::auto_revive(self);

	self SetOrigin(self.brain_drill.origin);
	self SetPlayerAngles(self.brain_drill.angles);
	//Delete clone model
	self.brain_drill.clone Delete();

	self.brain_drill = undefined; //The player no longer has a brain drill

	//Give Saved Perks
	if(isdefined(self.mindsaved.perks)){
		foreach(perk in self.mindsaved.perks){
			self zm_perks::give_perk(perk);
		}
	}

	//Take current weapons
	current_wpns = self GetWeaponsList(true); //true - includes alt models
	foreach(wpn in current_wpns){
		//NO HERO WPN
		self zm_weapons::weapon_take(wpn);
	}

	//Give saved weapons
	foreach(wpn_info in self.mindsaved.weapon_info){
		//NO SHIELD
		given_weapon = self zm_weapons::weapon_give(wpn_info.weapon);
		self SetWeaponAmmoClip(given_weapon, wpn_info.clip_size);

		//Check if dual wield
		dual_wield_wpn = given_weapon.dualWieldWeapon;
		if(level.weaponNone != dual_wield_wpn && isdefined(wpn_info.left_clip_size)){
			self SetWeaponAmmoClip(dual_wield_wpn, wpn_info.left_clip_size);
		}
		//IF FLAMETHROWER WILL NEED TO SET FUEL

		self SetWeaponAmmoStock(given_weapon, wpn_info.stock_size);
		//AAT NOT SUPPORTED ATM

	}

	self SwitchToWeapon(self.mindsaved.current_weapon);

	//Points
	self.score = self.mindsaved.score;
	self.pers["score"] = self.score;

	//GOBBLEGUM NOT SUPPORTED ATM
	//BUCKET STUFF NOT NEEDED

}

//Call On: Player
function checkPlayerBrainDrill(){
	saved = false;
	if(isdefined(self.brain_drill)){
		self thread brainDrillRespawn();
		saved = true;
	}
	return saved;
}

//Call On: Brain Drill respawn point
function brainDrillSpawnClone(){
	clone_struct = struct::get(self.target, "targetname");
	clone = util::spawn_model("c_t6_default_character_fb", clone_struct.origin, clone_struct.angles);
	return clone;
}