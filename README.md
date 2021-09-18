# zm_brain_drill
 Mindsaving, save the player's perks, weapons, and ammo. Includes a custom power-up to allow the use of mindsaving machines.
 
## How It Works

### Setting up the Brain Powerup

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
 
## Licence:
 Not for use without permission. This work in progress is posted for reference only.

## To-do:

 - Stop the respawn on quick revive and only on death
