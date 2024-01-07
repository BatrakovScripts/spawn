#pragma semicolon 1
#include <sourcemod>
#include <sdktools>

#pragma tabsize 0

#define PLUGIN_VERSION "1.9.3"

static PlayerDeath[MAXPLAYERS];

public Plugin:myinfo =
{
	name = "L4D SM Respawn",
	author = "AtomicStryker & Ivailosp",
	description = "Let's you respawn Players by console",
	version = PLUGIN_VERSION,
	url = "http://forums.alliedmods.net/showthread.php?t=96249"
}

static Float:g_pos[3];
static Handle:hRoundRespawn = INVALID_HANDLE;
static Handle:hBecomeGhost = INVALID_HANDLE;
static Handle:hState_Transition = INVALID_HANDLE;
static Handle:hGameConf = INVALID_HANDLE;

public OnPluginStart()
{
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("player_disconnect", OnPlayerDisconnect, EventHookMode_Pre);
	HookEvent("player_spawn", OnPlayerSpawn);
	
	decl String:game_name[24];
	GetGameFolderName(game_name, sizeof(game_name));
	if (!StrEqual(game_name, "left4dead2", false) && !StrEqual(game_name, "left4dead", false))
	{
		SetFailState("Plugin supports Left 4 Dead and L4D2 only.");
	}

	LoadTranslations("common.phrases");
	hGameConf = LoadGameConfigFile("l4drespawn");
	
	CreateConVar("respawn_version", PLUGIN_VERSION, "L4D SM Respawn Version", FCVAR_NOTIFY|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_DONTRECORD);
	//RegAdminCmd("sm_spawn", Command_Respawn, ADMFLAG_BAN, "sm_spawn");
	RegConsoleCmd("sm_spawn", Command_Respawn);

	if (hGameConf != INVALID_HANDLE)
	{
		StartPrepSDKCall(SDKCall_Player);
		PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "RoundRespawn");
		hRoundRespawn = EndPrepSDKCall();
		if (hRoundRespawn == INVALID_HANDLE) SetFailState("L4D_SM_Respawn: RoundRespawn Signature broken");
		
		StartPrepSDKCall(SDKCall_Player);
		PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "BecomeGhost");
		PrepSDKCall_AddParameter(SDKType_PlainOldData , SDKPass_Plain);
		hBecomeGhost = EndPrepSDKCall();
		if (hBecomeGhost == INVALID_HANDLE && StrEqual(game_name, "left4dead2", false))
			LogError("L4D_SM_Respawn: BecomeGhost Signature broken");

		StartPrepSDKCall(SDKCall_Player);
		PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "State_Transition");
		PrepSDKCall_AddParameter(SDKType_PlainOldData , SDKPass_Plain);
		hState_Transition = EndPrepSDKCall();
		if (hState_Transition == INVALID_HANDLE && StrEqual(game_name, "left4dead2", false))
			LogError("L4D_SM_Respawn: State_Transition Signature broken");
	}
	else
	{
		SetFailState("could not find gamedata file at addons/sourcemod/gamedata/l4drespawn.txt , you FAILED AT INSTALLING");
	}
}

public OnClientPostAdminCheck(client)
{
	if (client > 0 && !IsFakeClient(client)) 
	{
		if(IsPlayerAlive(client) == true)
		{
			PrintToChat(client, "\x04Ваш персонаж мертв, чтобы начать играть пропишите !spawn");
			PlayerDeath[client] = 1;
		}
		if(IsPlayerAlive(client) == false)
		{
			PrintToChat(client, "\x04Добро пожаловать на сервер \x05Battle Born.");
		}
	}
}
public OnPlayerSpawn(Handle:hEvent, const String:sEventName[], bool:bDontBroadcast) 
{ 
	new client  = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	PlayerDeath[client] = 0;
}
public Action:OnPlayerDisconnect(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
	PlayerDeath[client] = 0;
}
public Action:OnPlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(client != 0 && IsClientInGame(client) && GetClientTeam(client) == 2 && !IsFakeClient(client))
	{
		PrintToChat(client, "\x04Что-бы продолжить игру, пропишите !spawn");
		PlayerDeath[client] = 1;
	}
}
public Action:Command_Respawn(client, args)
{
	if(PlayerDeath[client] == 0) { PrintToChat(client, "\x04Невозможно себя заспавнить, вы не мертвы!"); return Plugin_Handled;}
	if(PlayerDeath[client] == 1) { RespawnPlayer(client, client); PlayerDeath[client] = 0;}
	return Plugin_Handled;
}

static RespawnPlayer(client, player_id)
{
	switch(GetClientTeam(player_id))
	{
		case 2:
		{
			new bool:canTeleport = SetTeleportEndPoint(client);
		
			SDKCall(hRoundRespawn, player_id);
			
			new flags = GetCommandFlags("give");
			SetCommandFlags("give", flags & ~FCVAR_CHEAT);
			FakeClientCommand(client, "give autoshotgun");
			FakeClientCommand(client, "give pistol");
			FakeClientCommand(client, "give pipe_bomb");
			SetCommandFlags ("give", 0);
			
			if(canTeleport)
			{
				PerformTeleport(client,player_id,g_pos);
			}
		}
		
		case 3:
		{
			decl String:game_name[24];
			GetGameFolderName(game_name, sizeof(game_name));
			if (StrEqual(game_name, "left4dead", false)) return;
		
			SDKCall(hState_Transition, player_id, 8);
			SDKCall(hBecomeGhost, player_id, 1);
			SDKCall(hState_Transition, player_id, 6);
			SDKCall(hBecomeGhost, player_id, 1);
		}
	}
}

public bool:TraceEntityFilterPlayer(entity, contentsMask)
{
	return entity > MaxClients || !entity;
} 

static bool:SetTeleportEndPoint(client)
{
	decl Float:vAngles[3], Float:vOrigin[3];
	
	GetClientEyePosition(client,vOrigin);
	GetClientEyeAngles(client, vAngles);
	
	//get endpoint for teleport
	new Handle:trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceEntityFilterPlayer);
	
	if(TR_DidHit(trace))
	{
		decl Float:vBuffer[3], Float:vStart[3];

		TR_GetEndPosition(vStart, trace);
		GetVectorDistance(vOrigin, vStart, false);
		new Float:Distance = -35.0;
		GetAngleVectors(vAngles, vBuffer, NULL_VECTOR, NULL_VECTOR);
		g_pos[0] = vStart[0] + (vBuffer[0]*Distance);
		g_pos[1] = vStart[1] + (vBuffer[1]*Distance);
		g_pos[2] = vStart[2] + (vBuffer[2]*Distance);
	}
	else
	{
		CloseHandle(trace);
		return false;
	}
	CloseHandle(trace);
	return true;
}

PerformTeleport(client, target, Float:pos[3])
{
	pos[2]+=40.0;
	TeleportEntity(target, pos, NULL_VECTOR, NULL_VECTOR);
	
	LogAction(client,target, "\"%L\" teleported \"%L\" after respawning him" , client, target);
}