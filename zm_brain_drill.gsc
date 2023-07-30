#using scripts\codescripts\struct;

#using scripts\shared\array_shared;
#using scripts\shared\callbacks_shared;
#using scripts\shared\flag_shared;
#using scripts\shared\laststand_shared;
#using scripts\shared\system_shared;
#using scripts\shared\util_shared;

#insert scripts\shared\shared.gsh;

#using scripts\zm\_zm;
#using scripts\zm\_zm_laststand;
#using scripts\zm\_zm_perks;
#using scripts\zm\_zm_stats;
#using scripts\zm\_zm_weapons;
#using scripts\zm\_zm_powerups;

#insert scripts\zm\zm_brain_drill\zm_brain_drill.gsh;
#insert scripts\zm\_zm_perks.gsh;


#precache("triggerstring", "Press ^3[{+activate}]^7 to ^5Mindsave^7");
#precache("triggerstring", "SOMEONE ELSE IS SAVED HERE");
#precache("triggerstring", "YOU ARE MINDSAVED HERE");
#precache("model", "c_t6_default_character_fb");
#precache("model", "p7_zm_der_zombie_brain"); //powerup model

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

Scripting Use:

brain_drill trig:
	.stored_player = the player stored there

player:
	.brain_drill → brain_drill struct
	.can_mindsave, bool for whether this player can save themselves to machine

level:
	.train_hit, true if player has shot train to spawn a brain drop

*/

function brainDrillInit()
{
	level.check_end_solo_game_override = &checkPlayerBrainDrill;
	
	callback::on_player_killed(&brainDrillDeath);
	callback::on_joined_spectate(&brainDrillDeath);
	callback::on_laststand(&brainDrillLastStand);
	callback::on_connect(&onPlayerConnect);

	level.brain_trigs = GetEntArray("brain_drill_trig", "targetname");
	array::thread_all(level.brain_trigs, &brainDrillWaitFor);

	//powerup
	brainDropInit();
}

//Call On: Player connected
function onPlayerConnect(){
	self.can_mindsave = false;
}

function brainDropInit(){
	zm_powerups::register_powerup( "brain", &grabDropBrain );
	zm_powerups::add_zombie_powerup( "brain",
									"p7_zm_der_zombie_brain",
								 	"BRAIN DROP",
								 	&shouldDropBrain,
								 	true,
								 	false,
								 	false);
	zm_powerups::powerup_set_player_specific("brain", true);
}

function grabDropBrain(player){
	player.can_mindsave = true;
	//set hintstrings for player based on who's stored there
	foreach(trig in level.brain_trigs){
		trig brainDrillHintEnable(player);
	}
}

function shouldDropBrain(){
	b = false;
	if(isdefined(level.brain_drill_override)){
		b = [[level.brain_drill_override]]();
	}else{
		b = level.round_number >= BRAIN_DROP_ROUND;
	}
	
	//FOLLOWING IS FOR TESTING ONLY:
	b = true; //DELETE FOR RELEASE
	return b;
}

//Call On: brain drill trig
//enable to turn on ones to be used
//enable = false to turn off all for player
	//(other than the one that they are saved at)
function brainDrillHintEnable(player, enable = true){
	if(enable){
		//if this trigger already storing another player
		if(isdefined(self.stored_player) && self.stored_player != player){
			//"someone else is saved here"
			self SetHintStringForPlayer(player, "SOMEONE ELSE IS SAVED HERE");
		}else{
			//(this includes if this player is stored here - they replace themself)
			self SetHintStringForPlayer(player, "Press ^3[{+activate}]^7 to ^5Mindsave^7");
		}
	}else{
		if(!(isdefined(self.stored_player) && self.stored_player == player)){
			self SetHintStringForPlayer(player, "");
		}
	}
	
}



//Call On: brain drill trigger
//THREAD
function brainDrillWaitFor(){
	self UseTriggerRequireLookAt();
	self SetCursorHint("HINT_NOICON");
	self SetHintString("");

	brain_drill = struct::get(self.target, "targetname");

	for(;;){
		self waittill("trigger", player);
		can_save_here = isdefined(player.can_mindsave) && player.can_mindsave;
		can_save_here &= !(isdefined(self.stored_player) && self.stored_player != player);
		if(can_save_here){
			player thread brainDrillSave(brain_drill, self);
			wait(0.05);
			foreach(trig in level.brain_trigs){
				trig brainDrillHintEnable(player, false);
			}
		}
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

//Call On: Player to mindsave
function brainDrillSave(brain_drill, trig){
	self endon("disconnect");
	if(isdefined(self.brain_drill)){
		//Hide old clone model
		self.brain_drill.clone Delete();
	}
	self.brain_drill = brain_drill;

	//player has saved so no longer allow them to save again
	self.can_mindsave = false;

	//Show new clone model
	self.brain_drill.clone = brain_drill brainDrillSpawnClone(self);

	//Save info
	self.mindsaved = SpawnStruct();

	//tell this trig that it belongs to this player
	trig.stored_player = self;

	//trig Hintstring turn off
	plrs = GetPlayers();
	ArrayRemoveValue(plrs, self);
	foreach(plr in plrs){
		str = "";
		if(isdefined(plr.can_mindsave) && plr.can_mindsave){
			str = "SOMEONE ELSE IS SAVED HERE";
		}
		trig SetHintStringForPlayer(plr, str);
	}
	trig SetHintStringForPlayer(self, "YOU ARE MINDSAVED HERE");

	//Active perks
	if(isdefined(self.perks_active)){
		self.mindsaved.perks = [];
		foreach(perk in self.perks_active){
			array::add(self.mindsaved.perks, perk, 0); //No dupes
		}
	}
	wait(0.05);
	//NO GUMS
	self.mindsaved.current_weapon = self GetCurrentWeapon();
	player_weapons = self GetWeaponsList();
	self.mindsaved.weapon_info = [];
	foreach(weapon in player_weapons){
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
}

//Call On: Player to respawn
function brainDrillRespawn(){
	self endon("disconnect");
	//SAY QUOTE
	self notify("stop_revive_trigger");

	IPrintLnBold("brain drill respawn");

	wait(0.05);

	self zm_laststand::auto_revive(self, true);
	wait(0.05);
	wait(0.05);
	self notify("revive_done");
	if(isdefined(self.revivetrigger)){
		self.revivetrigger Delete();
		self.revivetrigger = undefined;
	}
	self EnableWeaponCycling();
	self EnableOffhandWeapons();
	self AllowJump(true); 
	self AllowCrouch(true); 
	self AllowStand(true); 
	self AllowSprint(true); 
	self SetStance("stand");
	if(isdefined(self.revivetrigger)){ 
		self.revivetrigger Delete(); 
		self.revivetrigger = undefined; 
	} 
	self notify("stop_revive_trigger");
	self UndoLastStand();

	self SetOrigin(self.brain_drill.origin);
	self SetPlayerAngles(self.brain_drill.angles);
	//Delete clone model
	self.brain_drill.clone Delete();

	self.brain_drill = undefined; //The player no longer has a brain drill

	//Take current weapons
	current_wpns = self GetWeaponsList(true); //true - includes alt models
	foreach(wpn in current_wpns){
		//NO HERO WPN
		self zm_weapons::weapon_take(wpn);
	}

	//Give Saved Perks
	if(isdefined(self.mindsaved.perks)){
		foreach(perk in self.mindsaved.perks){
			self zm_perks::give_perk(perk);
		}
	}

	//Give saved weapons
	foreach(wpn_info in self.mindsaved.weapon_info){
		//NO SHIELD SUPPORT
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

	//turn hinstring off and no longer store this player on the trig
	foreach(trg in level.brain_trigs){
		if(isdefined(trg.stored_player) && trg.stored_player == self){
			trg.stored_player = undefined;
			trg SetHintStringForPlayer(self, "");
		}
	}
}

//Call On: Player in laststand
function brainDrillLastStand(){
	if(self checkPlayerBrainDrill()){
		if(level flag::get("solo_game")){
			if(self HasPerk(PERK_QUICK_REVIVE)){
				//self thread zm_laststand::suicide_trigger_spawn();
				self brainDrillSuicidePrompt();
			}else{
				self brainDrillRespawn();
			}
		}else{
			if(self zm::getAllOtherPlayers().size == 0){
				self brainDrillRespawn();
			}else{
				//self thread zm_laststand::suicide_trigger_spawn();
				self brainDrillSuicidePrompt();
			}
		}
	}
}

function brainDrillSuicidePrompt(){
	//copied from zm_laststand
	radius = GetDvarint( "revive_trigger_radius" );

	self.suicidePrompt = newclientHudElem( self );
	
	self.suicidePrompt.alignX = "center";
	self.suicidePrompt.alignY = "middle";
	self.suicidePrompt.horzAlign = "center";
	self.suicidePrompt.vertAlign = "bottom";
	self.suicidePrompt.y = -170;
	if ( self IsSplitScreen() )
	{
		self.suicidePrompt.y = -132;
	}
	self.suicidePrompt.foreground = true;
	self.suicidePrompt.font = "default";
	self.suicidePrompt.fontScale = 1.5;
	self.suicidePrompt.alpha = 1;
	self.suicidePrompt.color = ( 1.0, 1.0, 1.0 );
	self.suicidePrompt.hidewheninmenu = true;

	self thread suicidePromptThink();
}

function suicidePromptThink(){
	self endon ( "disconnect" );
	self endon ( "zombified" );
	self endon ( "stop_revive_trigger" );
	self endon ( "player_revived");
	self endon ( "bled_out");
	self endon ("fake_death");
	level endon("end_game");
	level endon("stop_suicide_trigger");
	
	//in case the game ends while this is running
	self thread laststand::clean_up_suicide_hud_on_end_game();
	
	//in case user is holding UseButton while this is running
	self thread laststand::clean_up_suicide_hud_on_bled_out();
	
	// If player was holding use while going into last stand, wait for them to release it
	while ( self UseButtonPressed() )
	{
		wait ( 1 );
	}
	
	if(!isdefined(self.suicidePrompt))
	{
		return;
	}
	
	while( true )
	{
		wait ( 0.1 );
		
		if(!isdefined(self.suicidePrompt))
		{
			continue;
		}
					
		self.suicidePrompt setText( &"ZOMBIE_BUTTON_TO_SUICIDE" );
		
		if ( !self zm_laststand::is_suiciding() )
		{
			continue;
		}



		self.pre_suicide_weapon = self GetCurrentWeapon();
		self GiveWeapon( level.weaponSuicide );
		self SwitchToWeapon( level.weaponSuicide );
		duration = 4.0;

		suicide_success = zm_laststand::suicide_do_suicide( duration );
		self.laststand = undefined;
		self TakeWeapon( level.weaponSuicide );

		if ( suicide_success )
		{
			IPrintLnBold("suicide succeeded");

			util::wait_network_frame(); //to guarantee the notify gets sent and processed before the rest of this script continues to turn the guy into a spectator
			
			self thread brainDrillRespawn();

			return;
		}

		IPrintLnBold("suicide failed");

		self SwitchToWeapon( self.pre_suicide_weapon );
		self.pre_suicide_weapon = undefined;
	}
}

//Call On: Dead Player
function brainDrillDeath(){
	//testing
	if(self.sessionstate == "spectator"){
		IPrintLnBold("player is a spectator");
	}
	IPrintLnBold("called on dead player");
	if(self checkPlayerBrainDrill()){
		brainDrillRespawn();
	}
}

//Call On: Player in laststand
function checkPlayerBrainDrill(){
	saved = false;
	if(isdefined(self.brain_drill)){
		saved = true;
	}
	return saved;
}

//Call On: Brain Drill respawn point
function brainDrillSpawnClone(player){
	clone_struct = struct::get(self.target, "targetname");
	clone = util::spawn_model(player getPlayerCloneModel(), clone_struct.origin, clone_struct.angles);
	return clone;
}

//Call On: Player
//Returns string of player's model
function getPlayerCloneModel(){
	str = "c_t6_default_character_fb";
	if(isdefined(level.braindrill_c_models) && isdefined(self) && isdefined(self.characterIndex) && isdefined(level.braindrill_c_models[self.characterIndex])){
		str = level.braindrill_c_models[self.characterIndex];
		IPrintLnBold("Index: " + self.characterIndex);
		if(!isdefined(self.characterIndex)){
			IPrintLnBold("Not Defined");
		}
		wait(0.5);
	}
	IPrintLnBold(str);
	return str;
}

//Call On: Player
//Register at start of game
function registerBraindrillCharacterModel(str_model_name){
	DEFAULT(level.braindrill_c_models, array("", "", "", "", "", "", "", ""));
	if(isdefined(self) && isdefined(self.characterIndex)){
		level.braindrill_c_models[self.characterIndex] = str_model_name;
	}
}

function disableBrainDrills(){
	foreach(player in GetPlayers()){
		//delete clone
		if(isdefined(player.brain_drill)){
			player.brain_drill.clone Delete();
		}
		//undefine the player's saved braindrill
		player.brain_drill = undefined;
		//stop players from mindsaving
		player.can_mindsave = false;
		//turn off all triggers
		foreach(trig in level.brain_trigs){
			trig brainDrillHintEnable(player, false);
		}
	}
	//stop the brain from spawning
	zm_powerups::powerup_remove_from_regular_drops("brain");
	wait(0.05);
	foreach(trig in level.brain_trigs){
		trig Delete();
	}
}

//removes currently saved players at arr_locs or all locations if arr_locs is undefined
//arr_locs is an array of integers that correspond to the script_int of that braindrill
function resetBrainDrill(arr_locs){
	foreach(player in GetPlayers()){
		delete = false;
		//delete clone
		if(isdefined(player.brain_drill)){
			if(isdefined(arr_locs)){
				if(!IsArray(arr_locs)){
					if(IS_EQUAL(arr_locs, player.brain_drill.script_int)){
						delete = true;
					}
				}else{
					foreach(num in arr_locs){
						if(IS_EQUAL(num, player.brain_drill.script_int)){
							delete = true;
						}
					}
				}
			}else{
				delete = true;
			}
			if(delete){
				player.brain_drill.clone Delete();
				//undefine the player's saved braindrill
				player.brain_drill = undefined;
			}
		}
	}
}
