# zm_brain_drill
 Mindsaving, save the player's perks, weapons, and ammo. Includes a custom power-up to allow the use of mindsaving machines.
 
## How It Works

### Setting up the Brain Powerup

![Brain Powerup Drop in Celerium](https://github.com/EliotDucky/zm_brain_drill/blob/main/source_images/brain%20drop.jpg)

The brain drop enables the use of the brain drills to save the player's perks, points, weapons, and ammo. This is set by a simple boolean on the player. The boolean is initialised on each player when they connect to the game.
 
```c
//Call On: Player connected
function onPlayerConnect(){
	self.can_mindsave = false;
}
```

This callback is registered in the initialisation function of the script.

```
callback::on_connect(&onPlayerConnect);
```

The boolean is then set to `true` in the function to be called when a player picks up the brain drop.

```c
function grabDropBrain(player){
	player.can_mindsave = true;
	//set hintstrings for player based on who's stored there
	foreach(trig in level.brain_trigs){
		trig brainDrillHintEnable(player);
	}
}
```

The second half of this function tells each brain drill trigger to enable the Hintstring for that player only, to instruct only them to save themself. The `grabDropBrain(player)` function takes `player` as a parameter automatically when it is called from the powerup being picked up - the first parameter of any powerup's pickup function is the player.

This function is registered simply into the drop system by the following initialisation function.

```c
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
```

The first line registers the drop as `"brain"` and the grab/pick up function.

The second external call to `zm_powerups` sets the parameters for how the powerup should spawn into the level. The `add_zombie_powerup` function in this script takes the following parameters:

1. `powerup_name` - This must be the same name as the powerup was registered as on the line before to make the two correspond.
2. `model_name` - This is the name of the model as it appears in the Asset Property Editor (APE). This model should also be precached to allow it to load in efficiently as well as added to the zone file or zone package.

Script:
 ```c
 #precache("model", "p7_zm_der_zombie_brain"); //powerup model
 ```
Zone:
 ```c
 xmodel,p7_zm_der_zombie_brain
 ```
3. `hint` - this is not necessary to set for the purposes of this powerup as there is no hint displayed for it. Most other powerups have this set up as a specific localised string, i.e. `&"ZOMBIE_POWERUP_MAX_AMMO"`.
4. `func_should_drop_with_regular_powerups` - this is a function that returns a boolean whether to drop with regular powerups, meaning that if a powerup is about to be spawned, such as from a zombie being killed, should this drop be considered in the pool of possible drops that could be spawned.

Most powerups can be spawned from the start of the game, so simply reference `&zm_powerups::func_should_always_drop()`. However for this powerup, it drops after a specific round or if an event has occured.

```c
function shouldDropBrain(){
	b = level.train_hit || level.round_number >= BRAIN_DROP_ROUND;
	return b;
}
```

This event is `level.train_hit` which is specific to only one level I'm making, Celerium. Instead this should be changed to a generic name that can be set as `true` if the train is hit or any other override to make the drops spawn early. The `BRAIN_DROP_ROUND` is a constant which is replaced by macro upon linking the level. This is defined in the GSH file, replacing the capital text with `15` upon linking. This means that this GSH can be overriden per level depending on when it makes sense to enable the use of the brain drills.

```c
#define BRAIN_DROP_ROUND 				15
```
5. `only_affects_grabber` - does this drop only affect the grabber? Meaning, should the function registered against the powerup only be called on the player that picks up/grabs the powerup.
6. `any_team` - this is for multi-team setups, like Grief mode. This isn't applicable for our use.
7. `zombie_grabable` - can a zombie pick this drop up?

There are more paramters available but these are the minimum that need setting for this powerup to work the way intended.

The final external call of `brainDropInit()` is to set the powerup as player specific. This means that the fx surrounding the drop will be blue rather than green, which would mean it affects all players.

### Saving and Restoring

![Saving player data at brain drill](https://github.com/EliotDucky/zm_brain_drill/blob/main/source_images/saving.jpg)

The saving of the player's data is handles by the function `brainDrillSave(brain_drill, trig)`, where `brain_drill` is the `script_struct` of the specific brain drill the player is activating and `trig` is the trigger the player pressed activate on. The function is called on the player, such that the player becomes `self`.

Firstly, if the player is saved somewhere else, the property `self.brain_drill` will be defined, and as such the old clone model should be deleted to show that the player is no longer saved at the previous brain drill location. The the location needs to be replaced or defined for the first time as this brain drill.

```c
	if(isdefined(self.brain_drill)){
		//Hide old clone model
		self.brain_drill.clone Delete();
	}
	self.brain_drill = brain_drill;
```

The `grabDropBrain(player)` function set the variable `self.brain_drill` to true so now that the player is saving, it is set to false.

The player's data for weapons, perks, etc. are stored on a struct to keep simple properties under a tree-like structure.

```
	Saved info is a struct self.mindsaved
		.perks
		.weapon_info
			.weapon
			.clip_size
			.left_clip_size
			.stock_size
		.current_weapon
		.score
```

```c
	if(isdefined(self.perks_active)){
		self.mindsaved.perks = [];
		foreach(perk in self.perks_active){
			array::add(self.mindsaved.perks, perk, 0); //No dupes
		}
	}
```

The third parameter of `array::add` is set to false to indicate that no duplicates should be added to the array. We don't want to give the player two of the same perk back.

Although we get the list of the player's weapons, we also get the current weapon they're holding, such that once the player gets their weapons restored, they swap to the weapon that they were holding when they saved.

```c
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
```

There are some special weapons, such as flamethrowers or other charged weapons, that require some extra code to be added to support them as they do not use the standard ammo system. Most weapons are handled by this code block. If there is an alternate weapon in use - such as the AR mode of the SMG ripper (from COD: Ghosts & Infinite Warfare), a select fire, or a grenade launcher on a rifle - the code `continue`s for this case because its base will be handled and the alternate mode given with that base weapon. Therefore, there is no need to save it. The code also handles dual wield weapons, such as the Marshall 16 shotgun pistols, where the ammo in the left weapon is also saved.

To respawn the player, first they must be revived. The function `brainDrillRespawn()` takes no parameters because the brain drill the player is saved at, is stored on the player, who is `self` in this function.

```c
	self zm_laststand::auto_revive(self, true);
	self notify("stop_revive_trigger");
	if(isdefined(self.revivetrigger)){
		self.revivetrigger Delete();
		self.revivetrigger = undefined;
	}
```

`zm_laststand::auto_revive` instantly revives the player from laststand. This is called on the player and the first parameter is the same player, such that they *revive themself*. The second parameter is a boolean for whether the player's weapons shouldn't be given back and swapped to. `true` meaning "don't give back". `true` is used here because in earlier versions, the player would swap weapons about 5 seconds after being respawned because this script pre-empted this return by giving the weapons back faster. This also stops the returning of weapons that may have been intended to be returned by the laststand script after the player is revived. This is stopped because the player is to be given the weapons they had when they saved at the brain drill, not when they enterred laststand.

The revive trigger is stopped and deleted to stop it appearing permanently over the player for co-op players.

```c
	self EnableWeaponCycling();
	self EnableOffhandWeapons();
	self SetStance("stand");
```

The player is then respawned at the position and with the angles of the brain drill struct, placed in the floor. The clone model is also deleted to show that no player is saved at this location any more.

```c
	self SetOrigin(self.brain_drill.origin);
	self SetPlayerAngles(self.brain_drill.angles);
	//Delete clone model
	self.brain_drill.clone Delete();
```

To stop the player being considered for respawning if they die - especially in solo, where the game needs to decide whether to end if the player dies - the `brain_drill` property on the player is set to `undefined`.

Before returning anything, the player's current weapons are taken. These are weapons they may have if they are in last stand or have picked up after saving, such that they are solely returned to the state they were in at the point of saving.

```c
	current_wpns = self GetWeaponsList(true); //true - includes alt models
	foreach(wpn in current_wpns){
		self zm_weapons::weapon_take(wpn);
	}
```

The perks are returned to the player before giving weapons back. If the player had Mule Kick, which allows three weapons instead of the default two, the third weapon returned would cause the game to think that the player is cheating by having more weapons than allowed.

```c
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
```
 
## Licence:
 Not for use without permission. This work in progress is posted for reference only.
 
 

## To-do:

 - Stop the respawn on quick revive and only on death
