untyped

global function MpTitanweaponMeteor_Init
global function OnProjectileCollision_Meteor
global function OnWeaponPrimaryAttack_Meteor
global function OnWeaponActivate_Meteor
global function OnWeaponDeactivate_Meteor

#if CLIENT
global function ServerCallback_TemperedPlating_UpdateBurnTime
#endif

#if SERVER
global function CreateThermiteTrail
global function CreateThermiteTrailOnMovingGeo
global function OnWeaponNpcPrimaryAttack_Meteor
global function CreatePhysicsThermiteTrail
global function Scorch_SelfDamageReduction
global function GetMeteorRadiusDamage
global function GetThermiteDurationBonus
global function PasScorchFirewall_ReduceCooldowns

global const PLAYER_METEOR_DAMAGE_TICK = 100.0
global const PLAYER_METEOR_DAMAGE_TICK_PILOT = 20.0

global const NPC_METEOR_DAMAGE_TICK = 100.0
global const NPC_METEOR_DAMAGE_TICK_PILOT = 20.0

global const float PAS_SCORCH_FLAMEWALL_AMMO_FOR_DAMAGE = 0.05
global const float PAS_SCORCH_FLAMECORE_MOD = 1.25
const float PAS_SCORCH_SELFDMG_DAMAGE_REDUCTION = 0.3

global struct MeteorRadiusDamage
{
	float pilotDamage
	float heavyArmorDamage
}


#endif // #if SERVER

#if CLIENT
const INDICATOR_IMAGE = $"ui/menu/common/locked_icon"
#endif

global const SP_THERMITE_DURATION_SCALE = 1.25


const METEOR_FX_CHARGED = $"P_wpn_meteor_exp_amp"
global const METEOR_FX_TRAIL = $"P_wpn_meteor_exp_trail"
global const METEOR_FX_BASE = $"P_wpn_meteor_exp"

const FLAME_WALL_SPLIT = false
const METEOR_LIFE_TIME = 1.2
global const METEOR_THERMITE_DAMAGE_RADIUS_DEF = 45
const FLAME_WALL_DAMAGE_RADIUS_DEF = 60

const METEOR_SHELL_EJECT		= $"models/Weapons/shellejects/shelleject_40mm.mdl"
const METEOR_FX_LOOP		= "Weapon_Sidwinder_Projectile"
const int METEOR_DAMAGE_FLAGS = damageTypes.gibBullet | DF_IMPACT | DF_EXPLOSION

function MpTitanweaponMeteor_Init()
{
	PrecacheParticleSystem( $"wpn_mflash_40mm_smoke_side_FP" )
	PrecacheParticleSystem( $"wpn_mflash_40mm_smoke_side" )
	PrecacheParticleSystem( $"P_scope_glint" )

	PrecacheParticleSystem( $"P_team_jet_hover_HLD" )
	PrecacheParticleSystem( $"P_enemy_jet_hover_HLD" )

	PrecacheModel( $"models/dev/empty_physics.mdl" )

	PrecacheParticleSystem( METEOR_FX_TRAIL )
	PrecacheParticleSystem( METEOR_FX_CHARGED )

	#if SERVER
	AddDamageCallbackSourceID( eDamageSourceId.mp_titanweapon_meteor_thermite, MeteorThermite_DamagedTarget )
	if ( LTSRebalance_EnabledOnInit() )
	{
		AddDamageCallback( "player", TemperedPlating_DamageReduction )
		AddDamageCallback( "npc_titan", TemperedPlating_DamageReduction )
	}

	PrecacheParticleSystem( THERMITE_GRENADE_FX )
	PrecacheModel( METEOR_SHELL_EJECT )

	FlagInit( "SP_MeteorIncreasedDuration" )
	FlagSet( "SP_MeteorIncreasedDuration" )
	#endif

	#if CLIENT
	PrecacheMaterial( INDICATOR_IMAGE )
	RegisterSignal( "NewOwner" )
	#endif

	MpTitanweaponFlameWall_Init()
}

void function OnWeaponActivate_Meteor( entity weapon )
{
}

void function OnWeaponDeactivate_Meteor( entity weapon )
{
}

var function OnWeaponPrimaryAttack_Meteor( entity weapon, WeaponPrimaryAttackParams attackParams )
{
	weapon.EmitWeaponNpcSound( LOUD_WEAPON_AI_SOUND_RADIUS_MP, 0.2 )

	return PlayerOrNPCFire_Meteor( attackParams, true, weapon )
}

#if SERVER
void function TemperedPlating_UpdateBurnTime( entity soul )
{
	if ( !( "scorchLastBurnTime" in soul.s ) )
	{
		soul.s.scorchLastBurnTime <- Time()
		thread TemperedPlating_FXThink( soul )
	}
	else
		soul.s.scorchLastBurnTime = Time()

	entity titan = soul.GetTitan()
	if ( IsValid( titan ) && titan.IsPlayer() )
		Remote_CallFunction_NonReplay( titan, "ServerCallback_TemperedPlating_UpdateBurnTime" )
}
#else
void function ServerCallback_TemperedPlating_UpdateBurnTime()
{
	entity player = GetLocalClientPlayer()
	if ( !IsValid( player ) || !player.IsTitan() ) // JFS - Player may have disembarked between touching thermite and receiving remote call
		return

	if ( !( "scorchLastBurnTime" in player.s ) )
	{
		player.s.scorchLastBurnTime <- Time()
		thread TemperedPlating_FXThink( player )
	}
	else
		player.s.scorchLastBurnTime = Time()
}
#endif

void function TemperedPlating_FXThink( entity owner )
{
	owner.EndSignal( "OnDestroy" )
	float lastTime = 0
	#if SERVER
	entity lastTitan = owner.GetTitan()
	entity chargeEffect = null
	#else
	int cockpitHandle = -1
	#endif
	while(1)
	{
		float curTime = Time()
		float burnTime = expect float( owner.s.scorchLastBurnTime + 0.5 ) - curTime
		#if SERVER
		entity titan = owner.GetTitan()
		if ( burnTime > 0 && ( lastTime <= 0 || lastTitan != titan ) && IsValid( titan ) )
		{
			int index = titan.LookupAttachment( "hijack" )
			chargeEffect = StartParticleEffectOnEntity_ReturnEntity( titan, GetParticleSystemIndex( $"P_titan_core_atlas_charge" ), FX_PATTACH_POINT_FOLLOW, index )

			chargeEffect.kv.VisibilityFlags = (ENTITY_VISIBLE_TO_FRIENDLY | ENTITY_VISIBLE_TO_ENEMY) // everyone but owner
			chargeEffect.SetOwner( titan )
		}
		#else
		if ( burnTime > 0 && lastTime <= 0 )
		{
			entity cockpit = owner.GetCockpit()
    		cockpitHandle = StartParticleEffectOnEntity( cockpit, GetParticleSystemIndex( $"P_core_DMG_boost_screen" ), FX_PATTACH_ABSORIGIN_FOLLOW, -1 )
		}
		#endif
		else if ( lastTime > 0 && burnTime <= 0 )
		{
			#if SERVER
			if ( IsValid( chargeEffect ) )
				chargeEffect.Destroy()
			#else
			if ( EffectDoesExist( cockpitHandle ) )
        		EffectStop( cockpitHandle, false, true )
			#endif
		}

		lastTime = burnTime
		#if SERVER
		lastTitan = titan
		#endif

		WaitFrame()
	}
}

#if SERVER
void function MeteorThermite_DamagedTarget( entity target, var damageInfo )
{
	if ( !IsValid( target ) )
		return

	Thermite_DamagePlayerOrNPCSounds( target )
	Scorch_SelfDamageReduction( target, damageInfo )

	entity attacker = DamageInfo_GetAttacker( damageInfo )
	if ( !IsValid( attacker ) || attacker.GetTeam() == target.GetTeam() )
		return

	array<entity> weapons = attacker.GetMainWeapons()
	if ( weapons.len() > 0 )
	{
		if ( weapons[0].HasMod( "fd_fire_damage_upgrade" )  )
			DamageInfo_ScaleDamage( damageInfo, FD_FIRE_DAMAGE_SCALE )
		if ( weapons[0].HasMod( "fd_hot_streak" ) )
			UpdateScorchHotStreakCoreMeter( attacker, DamageInfo_GetDamage( damageInfo ) )
	}

	PasScorchFirewall_ReduceCooldowns( attacker, DamageInfo_GetDamage( damageInfo ) )
}

void function PasScorchFirewall_ReduceCooldowns( entity owner, float damage )
{
	if ( !LTSRebalance_Enabled() || !IsValid( owner ) )
		return
	
	entity ordnance = owner.GetOffhandWeapon( OFFHAND_RIGHT )
	if ( !IsValid( ordnance ) || !ordnance.HasMod( "LTSRebalance_pas_scorch_firewall" ) )
		return

	int bonusAmmo = int( damage * PAS_SCORCH_FLAMEWALL_AMMO_FOR_DAMAGE )
	int newAmmo = minint( ordnance.GetWeaponPrimaryClipCountMax(), ordnance.GetWeaponPrimaryClipCount() + bonusAmmo )
	ordnance.SetWeaponPrimaryClipCountNoRegenReset( newAmmo )

	entity utility = owner.GetOffhandWeapon( OFFHAND_ANTIRODEO )
	if ( IsValid( utility ) )
	{
		newAmmo = minint( utility.GetWeaponPrimaryClipCountMax(), utility.GetWeaponPrimaryClipCount() + bonusAmmo )
		utility.SetWeaponPrimaryClipCountNoRegenReset( newAmmo )
	}
}

void function Scorch_SelfDamageReduction( entity target, var damageInfo )
{
	if ( !IsAlive( target ) )
		return

	entity attacker = DamageInfo_GetAttacker( damageInfo )
	if ( !IsValid( attacker ) )
		return

	if ( target != attacker )
		return

	if ( IsMultiplayer() )
	{
		entity soul = attacker.GetTitanSoul()
		
		if ( IsValid( soul ) && SoulHasPassive( soul, ePassives.PAS_SCORCH_SELFDMG ) )
		{
			if( LTSRebalance_Enabled() )
				TemperedPlating_UpdateBurnTime( soul )
			else
				DamageInfo_SetDamage( damageInfo, 0.0 )
		}
		if( LTSRebalance_Enabled() )
        	DamageInfo_SetDamage( damageInfo, 0.0 )
	}
	else
	{
		DamageInfo_ScaleDamage( damageInfo, 0.20 )
	}
}

void function TemperedPlating_DamageReduction( entity ent, var damageInfo )
{
	if ( !ent.IsTitan() )
		return

	entity soul = ent.GetTitanSoul()
	if ( IsValid( soul ) && SoulHasPassive( soul, ePassives.PAS_SCORCH_SELFDMG ) &&  "scorchLastBurnTime" in soul.s && soul.s.scorchLastBurnTime + 0.5 >= Time() )
		DamageInfo_ScaleDamage( damageInfo, 1.0 - PAS_SCORCH_SELFDMG_DAMAGE_REDUCTION )
}

var function OnWeaponNpcPrimaryAttack_Meteor( entity weapon, WeaponPrimaryAttackParams attackParams )
{
	weapon.EmitWeaponNpcSound( LOUD_WEAPON_AI_SOUND_RADIUS_MP, 0.2 )
	return PlayerOrNPCFire_Meteor( attackParams, false, weapon )
}

void function MeteorAirburst( entity bolt )
{
	bolt.EndSignal( "OnDestroy" )
	bolt.GetOwner().EndSignal( "OnDestroy" )
	wait METEOR_LIFE_TIME
	thread Proto_MeteorCreatesThermite( bolt )
	bolt.Destroy()
}

function Proto_MeteorCreatesThermite( entity projectile, entity hitEnt = null )
{
	vector velocity = projectile.GetVelocity()
	// printt( "speed " + Length( velocity ) )
	float speed = min( Length( velocity ), 2500 )

	float speedScale = 0.25

	if ( IsSingleplayer() )
	{
		speedScale = 0.35
	}

	velocity = Normalize( velocity ) * speed * speedScale
	vector normal = <0,0,1>
	vector origin = projectile.GetOrigin()
	vector angles = VectorToAngles( normal )
	//DebugDrawLine( origin, origin + velocity * 10, 255, 0, 0, true, 5.0 )
	int range = 360
	entity owner = projectile.GetOwner()
	Assert( IsValid( owner ) )

	//EmitSoundAtPosition( owner.GetTeam(), origin, "Explo_MeteorGun_Impact_3P" )

	float thermiteLifetimeMin = 1.9 * GetThermiteDurationBonus( owner )
	float thermiteLifetimeMax = 2.3 * GetThermiteDurationBonus( owner )

	if ( IsSingleplayer() )
	{
		if ( owner.IsPlayer() || Flag( "SP_MeteorIncreasedDuration" ) )
		{
			thermiteLifetimeMin *= SP_THERMITE_DURATION_SCALE
			thermiteLifetimeMax *= SP_THERMITE_DURATION_SCALE
		}
	}

	entity inflictor = CreateOncePerTickDamageInflictorHelper( thermiteLifetimeMax )
	entity base = CreatePhysicsThermiteTrail( origin, owner, inflictor, projectile, velocity, thermiteLifetimeMax, METEOR_FX_BASE, eDamageSourceId.mp_titanweapon_meteor_thermite )

	base.SetAngles( AnglesCompose( angles, <90,0,0> ) )

	if ( hitEnt != null && hitEnt.IsWorld() )
		base.StopPhysics()

	int fireCount
	float fireSpeed

	array<string> mods = projectile.ProjectileGetMods()
	if ( mods.contains( "pas_scorch_weapon" ) )
	{
		fireCount = 8
		fireSpeed = 200
	}
	else
	{
		fireCount = 4
		fireSpeed = LTSRebalance_Enabled() ? 100.0 : 50.0
	}
	for ( int i = 0; i < fireCount; i++ )
	{
		vector trailAngles = <RandomFloatRange( -range, range ), RandomFloatRange( -range, range ), RandomFloatRange( -range, range )>
		vector forward = AnglesToForward( trailAngles )
		vector up = AnglesToUp( trailAngles )
		vector v = velocity + forward * fireSpeed + up * fireSpeed
		entity prop = CreatePhysicsThermiteTrail( origin, owner, inflictor, projectile, v, RandomFloatRange( thermiteLifetimeMin, thermiteLifetimeMax ), METEOR_FX_TRAIL, eDamageSourceId.mp_titanweapon_meteor_thermite )

		trailAngles = VectorToAngles( v )
		prop.SetAngles( trailAngles )
	}
}

MeteorRadiusDamage function GetMeteorRadiusDamage( entity owner )
{
	MeteorRadiusDamage meteorRadiusDamage
	if ( owner.IsNPC() )
	{
		meteorRadiusDamage.pilotDamage = NPC_METEOR_DAMAGE_TICK_PILOT
		meteorRadiusDamage.heavyArmorDamage = NPC_METEOR_DAMAGE_TICK
	}
	else
	{
		meteorRadiusDamage.pilotDamage = PLAYER_METEOR_DAMAGE_TICK_PILOT
		meteorRadiusDamage.heavyArmorDamage = PLAYER_METEOR_DAMAGE_TICK
	}

	return meteorRadiusDamage
}

float function GetThermiteDurationBonus ( entity owner ) {
    if ( !LTSRebalance_Enabled() || !IsValid( owner ) )
        return 1

    entity ordnance = owner.GetOffhandWeapon( OFFHAND_EQUIPMENT )
    if ( !IsValid( ordnance ) )
        return 1

    return ( ordnance.HasMod( "pas_scorch_flamecore" ) ? PAS_SCORCH_FLAMECORE_MOD : 1.0 )
}

void function PROTO_PhysicsThermiteCausesDamage( entity trail, entity inflictor, int damageSourceId = eDamageSourceId.mp_titanweapon_meteor_thermite )
{
	entity owner = trail.GetOwner()
	Assert( IsValid( owner ) )

	trail.EndSignal( "OnDestroy" )
	owner.EndSignal( "OnDestroy" )

	MeteorRadiusDamage meteorRadiusDamage = GetMeteorRadiusDamage( owner )
	float METEOR_DAMAGE_TICK_PILOT = meteorRadiusDamage.pilotDamage
	float METEOR_DAMAGE_TICK = meteorRadiusDamage.heavyArmorDamage

	array<entity> fxArray = trail.e.fxArray

	OnThreadEnd(
	function() : ( fxArray )
		{
			foreach ( fx in fxArray )
			{
				if ( IsValid( fx ) )
					EffectStop( fx )
			}
		}
	)

	wait 0.2 // thermite falls and ignites

	vector originLastFrame = trail.GetOrigin()

	for ( ;; )
	{
		vector moveVec = originLastFrame - trail.GetOrigin()
		float moveDist = Length( moveVec )

		// spread the circle while the particles are moving fast, could replace with trace
		float dist = max( METEOR_THERMITE_DAMAGE_RADIUS_DEF, moveDist )

		RadiusDamage(
			trail.GetOrigin(),									// origin
			owner,												// owner
			inflictor,		 									// inflictor
			METEOR_DAMAGE_TICK_PILOT,							// pilot damage
			METEOR_DAMAGE_TICK,									// heavy armor damage
			dist,												// inner radius
			dist,												// outer radius
			SF_ENVEXPLOSION_NO_NPC_SOUND_EVENT,					// explosion flags
			0, 													// distanceFromAttacker
			0, 													// explosionForce
			0,													// damage flags
			damageSourceId 										// damage source id
		)

		originLastFrame = trail.GetOrigin()

		if( LTSRebalance_Enabled() )
			WaitFrame()
		else
			wait 0.1
	}
}

void function PROTO_ThermiteCausesDamage( entity trail, entity owner, entity inflictor, int damageSourceId = eDamageSourceId.mp_titanweapon_meteor_thermite )
{
	Assert( IsValid( owner ) )

	trail.EndSignal( "OnDestroy" )
	owner.EndSignal( "OnDestroy" )
	inflictor.EndSignal( "OnDestroy" )

	MeteorRadiusDamage meteorRadiusDamage = GetMeteorRadiusDamage( owner )
	float METEOR_DAMAGE_TICK_PILOT = meteorRadiusDamage.pilotDamage
	float METEOR_DAMAGE_TICK = meteorRadiusDamage.heavyArmorDamage

	OnThreadEnd(
		function() : ( trail )
		{
			EffectStop( trail )
		}
	)

	float radius = METEOR_THERMITE_DAMAGE_RADIUS_DEF
	if ( damageSourceId == eDamageSourceId.mp_titanweapon_flame_wall )
		radius = FLAME_WALL_DAMAGE_RADIUS_DEF

	for ( ;; )
	{
		RadiusDamage(
			trail.GetOrigin(),									// origin
			owner,												// owner
			inflictor,		 									// inflictor
			METEOR_DAMAGE_TICK_PILOT,							// pilot damage
			METEOR_DAMAGE_TICK,									// heavy armor damage
			radius,												// inner radius
			radius,												// outer radius
			SF_ENVEXPLOSION_NO_NPC_SOUND_EVENT,					// explosion flags
			0, 													// distanceFromAttacker
			0, 													// explosionForce
			DF_EXPLOSION,										// damage flags
			damageSourceId										// damage source id
		)

		WaitFrame()
	}
}

entity function CreatePhysicsThermiteTrail( vector origin, entity owner, entity inflictor, entity projectile, vector velocity, float killDelay, asset overrideFX = METEOR_FX_TRAIL, int damageSourceId = eDamageSourceId.mp_titanweapon_meteor_thermite )
{
	Assert( IsValid( owner ) )
	entity prop_physics = CreateEntity( "prop_physics" )
	prop_physics.SetValueForModelKey( $"models/dev/empty_physics.mdl" )
	prop_physics.kv.fadedist = 2000
	prop_physics.kv.renderamt = 255
	prop_physics.kv.rendercolor = "255 255 255"
	prop_physics.kv.CollisionGroup = TRACE_COLLISION_GROUP_DEBRIS
	prop_physics.kv.spawnflags = 4 /* SF_PHYSPROP_DEBRIS */

	prop_physics.kv.minhealthdmg = 9999
	prop_physics.kv.nodamageforces = 1
	prop_physics.kv.inertiaScale = 1.0

	prop_physics.SetOrigin( origin )
	prop_physics.Hide()
	DispatchSpawn( prop_physics )

	int particleSystemIndex = GetParticleSystemIndex( overrideFX )
	int attachIdx = prop_physics.LookupAttachment( "origin" )

	entity fx = StartParticleEffectOnEntity_ReturnEntity( prop_physics, particleSystemIndex, FX_PATTACH_POINT_FOLLOW_NOROTATE, attachIdx )
	fx.SetOwner( owner )
	AddActiveThermiteBurn( fx )

	prop_physics.e.fxArray.append( fx )

	prop_physics.SetVelocity( velocity )
	if ( killDelay > 0 )
		EntFireByHandle( prop_physics, "Kill", "", killDelay, null, null )

	prop_physics.SetOwner( owner )
	AI_CreateDangerousArea( prop_physics, projectile, METEOR_THERMITE_DAMAGE_RADIUS_DEF, TEAM_INVALID, true, false )

	thread PROTO_PhysicsThermiteCausesDamage( prop_physics, inflictor, damageSourceId )

	return prop_physics
}

entity function CreateThermiteTrail( vector origin, vector angles, entity owner, entity inflictor, float killDelay, asset overrideFX = METEOR_FX_TRAIL, int damageSourceId = eDamageSourceId.mp_titanweapon_meteor_thermite )
{
	Assert( IsValid( owner ) )

	entity particle = StartParticleEffectInWorld_ReturnEntity( GetParticleSystemIndex( overrideFX ), origin, angles )
	particle.SetOwner( owner )

	AddActiveThermiteBurn( particle )

	if ( killDelay > 0.0 )
		EntFireByHandle( particle, "Kill", "", killDelay, null, null )

	thread PROTO_ThermiteCausesDamage( particle, owner, inflictor, damageSourceId )

	return particle
}

entity function CreateThermiteTrailOnMovingGeo( entity movingGeo, vector origin, vector angles, entity owner, entity inflictor, float killDelay, asset overrideFX = METEOR_FX_TRAIL, int damageSourceId = eDamageSourceId.mp_titanweapon_meteor_thermite )
{
	Assert( IsValid( owner ) )

	entity script_mover = CreateScriptMover( origin, angles )
	script_mover.SetParent( movingGeo, "", true, 0 )

	int attachIdx 		= script_mover.LookupAttachment( "REF" )
	//entity particle 	= StartParticleEffectOnEntity_ReturnEntity( script_mover, GetParticleSystemIndex( overrideFX ), FX_PATTACH_POINT_FOLLOW, attachIdx )
	entity particle 	= StartParticleEffectOnEntityWithPos_ReturnEntity( movingGeo, GetParticleSystemIndex( overrideFX ), FX_PATTACH_CUSTOMORIGIN_FOLLOW, -1, script_mover.GetLocalOrigin(), angles )
	particle.SetOwner( owner )
	script_mover.SetOwner( owner )

	AddActiveThermiteBurn( particle )

	if ( killDelay > 0.0 )
	{
		EntFireByHandle( script_mover, "Kill", "", killDelay, null, null )
		EntFireByHandle( particle, "Kill", "", killDelay, null, null )
	}

	thread PROTO_ThermiteCausesDamage( particle, owner, inflictor, damageSourceId )

	return particle
}
#endif // #if SERVER

void function OnProjectileCollision_Meteor( entity projectile, vector pos, vector normal, entity hitEnt, int hitbox, bool isCritical )
{
	#if SERVER
	if ( projectile.proj.projectileBounceCount > 0 )
		return

	projectile.proj.projectileBounceCount++

	entity owner = projectile.GetOwner()
	if ( !IsValid( owner ) )
		return

	if ( IsValid( owner ) )
		thread Proto_MeteorCreatesThermite( projectile, hitEnt )
	#endif
}

function PlayerOrNPCFire_Meteor( WeaponPrimaryAttackParams attackParams, playerFired, entity weapon )
{
	//entity owner = weapon.GetWeaponOwner()
	bool shouldCreateProjectile = false
	if ( IsServer() || weapon.ShouldPredictProjectiles() )
		shouldCreateProjectile = true
	#if CLIENT
		if ( !playerFired )
			shouldCreateProjectile = false
	#endif

	if ( shouldCreateProjectile )
	{
		float speed	= 1.0 // 2750.0

 		//TODO:: Calculate better attackParams.dir if auto-titan using mortarShots
		entity bolt = weapon.FireWeaponBolt( attackParams.pos, attackParams.dir, speed, METEOR_DAMAGE_FLAGS, METEOR_DAMAGE_FLAGS, playerFired , 0 )
		if ( bolt != null )
			EmitSoundOnEntity( bolt, "weapon_thermitelauncher_projectile_3p" )
	}

	return 1
}