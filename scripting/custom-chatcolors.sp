#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <scp>
#define PLUGIN_VERSION		"3.2.1"

public Plugin myinfo = {
	name        = "[Source 2013] Custom Chat Colors",
	author      = "Dr. McKay",
	description = "Processes chat and provides colors for Source 2013 games",
	version     = PLUGIN_VERSION,
	url         = "http://www.doctormckay.com"
};

GlobalForward
	  g_gfColorForward
	, g_gfNameForward
	, g_gfTagForward
	, g_gfApplicationForward
	, g_gfMessageForward
	, g_gfPreLoadedForward
	, g_gfLoadedForward
	, g_gfConfigReloadedForward;
KeyValues
	  g_kvConfigFile;
char
	  g_sTag[MAXPLAYERS+1][32]
	, g_sTagColor[MAXPLAYERS+1][12]
	, g_sUsernameColor[MAXPLAYERS+1][12]
	, g_sChatColor[MAXPLAYERS+1][12]
	, g_sDefaultTag[MAXPLAYERS+1][32]
	, g_sDefaultTagColor[MAXPLAYERS+1][12]
	, g_sDefaultUsernameColor[MAXPLAYERS+1][12]
	, g_sDefaultChatColor[MAXPLAYERS+1][12];

enum CCC_ColorType {
	CCC_TagColor,
	CCC_NameColor,
	CCC_ChatColor
};

#define COLOR_NONE -1
#define COLOR_GREEN -2
#define COLOR_OLIVE -3
#define COLOR_TEAM -4

#define UPDATE_FILE "chatcolors.txt"
#define CONVAR_PREFIX "custom_chat_colors"

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max){
	MarkNativeAsOptional("Updater_AddPlugin");
	CreateNative("CCC_GetColor", Native_GetColor);
	CreateNative("CCC_SetColor", Native_SetColor);
	CreateNative("CCC_GetTag", Native_GetTag);
	CreateNative("CCC_SetTag", Native_SetTag);
	CreateNative("CCC_ResetColor", Native_ResetColor);
	CreateNative("CCC_ResetTag", Native_ResetTag);

	RegPluginLibrary("ccc");

	return APLRes_Success;
}

public void OnPluginStart(){
	RegAdminCmd("sm_reloadccc", Command_ReloadConfig, ADMFLAG_CONFIG, "Reloads Custom Chat Colors config file");
	g_gfColorForward = new GlobalForward("CCC_OnChatColor", ET_Event, Param_Cell);
	g_gfNameForward = new GlobalForward("CCC_OnNameColor", ET_Event, Param_Cell);
	g_gfTagForward = new GlobalForward("CCC_OnTagApplied", ET_Event, Param_Cell);
	g_gfApplicationForward = new GlobalForward("CCC_OnColor", ET_Event, Param_Cell, Param_String, Param_Cell);
	g_gfMessageForward = new GlobalForward("CCC_OnChatMessage", ET_Ignore, Param_Cell, Param_String, Param_Cell);
	g_gfPreLoadedForward = new GlobalForward("CCC_OnUserConfigPreLoaded", ET_Event, Param_Cell);
	g_gfLoadedForward = new GlobalForward("CCC_OnUserConfigLoaded", ET_Ignore, Param_Cell);
	g_gfConfigReloadedForward = new GlobalForward("CCC_OnConfigReloaded", ET_Ignore);
	LoadConfig();
}

void LoadConfig(){
	if (g_kvConfigFile != null) {
		delete g_kvConfigFile;
	}
	g_kvConfigFile = new KeyValues("admin_colors");
	char path[64];
	BuildPath(Path_SM, path, sizeof(path), "configs/custom-chatcolors.cfg");
	if (!g_kvConfigFile.ImportFromFile(path)) {
		SetFailState("Config file missing");
	}
	for (int i = 1; i <= MaxClients; i++){
		if (!IsClientInGame(i) || IsFakeClient(i)) {
			continue;
		}
		ClearValues(i);
		OnClientPostAdminCheck(i);
	}
}

public Action Command_ReloadConfig(int client, int args){
	LoadConfig();
	LogAction(client, -1, "Reloaded Custom Chat Colors config file");
	ReplyToCommand(client, "[CCC] Reloaded config file.");
	Call_StartForward(g_gfConfigReloadedForward);
	Call_Finish();
	return Plugin_Handled;
}

void ClearValues(int client){
	Format(g_sTag[client], sizeof(g_sTag[]), "");
	Format(g_sTagColor[client], sizeof(g_sTagColor[]), "");
	Format(g_sUsernameColor[client], sizeof(g_sUsernameColor[]), "");
	Format(g_sChatColor[client], sizeof(g_sChatColor[]), "");

	Format(g_sDefaultTag[client], sizeof(g_sDefaultTag[]), "");
	Format(g_sDefaultTagColor[client], sizeof(g_sDefaultTagColor[]), "");
	Format(g_sDefaultUsernameColor[client], sizeof(g_sDefaultUsernameColor[]), "");
	Format(g_sDefaultChatColor[client], sizeof(g_sDefaultChatColor[]), "");
}

public void OnClientConnected(int client){
	ClearValues(client);
}

public void OnClientDisconnect(int client){
	// On connect and on disconnect, just to be safe
	ClearValues(client);
}

public void OnClientPostAdminCheck(int client){
	if (!ConfigForward(client)) {
		// Another plugin wants to block this
		return;
	}
	// check the Steam ID first
	char auth[32];
	GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));
	g_kvConfigFile.Rewind();
	if (!g_kvConfigFile.JumpToKey(auth)){
		g_kvConfigFile.Rewind();
		g_kvConfigFile.GotoFirstSubKey();

		AdminId admin = GetUserAdmin(client);
		AdminFlag flag;
		char configFlag[2];
		char section[32];
		bool found = false;

		do {
			g_kvConfigFile.GetSectionName(section, sizeof(section));
			g_kvConfigFile.GetString("flag", configFlag, sizeof(configFlag));
			if (strlen(configFlag) > 1) {
				LogError("Multiple flags given in section \"%s\", which is not allowed. Using first character.", section);
			}
			if (strlen(configFlag) == 0 && StrContains(section, "STEAM_", false) == -1 && StrContains(section, "[U:1:", false) == -1){
				found = true;
				break;
			}
			if (!FindFlagByChar(configFlag[0], flag)){
				if (strlen(configFlag) > 0) {
					LogError("Invalid flag given for section \"%s\", skipping", section);
				}
				continue;
			}
			if (admin.HasFlag(flag)){
				found = true;
				break;
			}
		}
		while (g_kvConfigFile.GotoNextKey());
		if (!found) {
			return;
		}
	}
	char clientTagColor[12];
	char clientNameColor[12];
	char clientChatColor[12];

	g_kvConfigFile.GetString("tag", g_sTag[client], sizeof(g_sTag[]));
	g_kvConfigFile.GetString("tagcolor", clientTagColor, sizeof(clientTagColor));
	g_kvConfigFile.GetString("namecolor", clientNameColor, sizeof(clientNameColor));
	g_kvConfigFile.GetString("textcolor", clientChatColor, sizeof(clientChatColor));

	ReplaceString(clientTagColor, sizeof(clientTagColor), "#", "");
	ReplaceString(clientNameColor, sizeof(clientNameColor), "#", "");
	ReplaceString(clientChatColor, sizeof(clientChatColor), "#", "");

	int tagLen = strlen(clientTagColor);
	int nameLen = strlen(clientNameColor);
	int chatLen = strlen(clientChatColor);

	if (tagLen == 6 || tagLen == 8 || StrEqual(clientTagColor, "T", false) || StrEqual(clientTagColor, "G", false) || StrEqual(clientTagColor, "O", false)) {
		strcopy(g_sTagColor[client], sizeof(g_sTagColor[]), clientTagColor);
	}
	if (nameLen == 6 || nameLen == 8 || StrEqual(clientNameColor, "G", false) || StrEqual(clientNameColor, "O", false)) {
		strcopy(g_sUsernameColor[client], sizeof(g_sUsernameColor[]), clientNameColor);
	}
	if (chatLen == 6 || chatLen == 8 || StrEqual(clientChatColor, "T", false) || StrEqual(clientChatColor, "G", false) || StrEqual(clientChatColor, "O", false)) {
		strcopy(g_sChatColor[client], sizeof(g_sChatColor[]), clientChatColor);
	}

	strcopy(g_sDefaultTag[client], sizeof(g_sDefaultTag[]), g_sTag[client]);
	strcopy(g_sDefaultTagColor[client], sizeof(g_sDefaultTagColor[]), g_sTagColor[client]);
	strcopy(g_sDefaultUsernameColor[client], sizeof(g_sDefaultUsernameColor[]), g_sUsernameColor[client]);
	strcopy(g_sDefaultChatColor[client], sizeof(g_sDefaultChatColor[]), g_sChatColor[client]);

	Call_StartForward(g_gfLoadedForward);
	Call_PushCell(client);
	Call_Finish();
}

public Action OnChatMessage(int &author, ArrayList recipients, char[] name, char[] message) {
	if (CheckForward(author, message, CCC_NameColor)){
		if (StrEqual(g_sUsernameColor[author], "G", false)) {
			Format(name, MAXLENGTH_NAME, "\x04%s", name);
		}
		else if (StrEqual(g_sUsernameColor[author], "O", false)) {
			Format(name, MAXLENGTH_NAME, "\x05%s", name);
		}
		else if (strlen(g_sUsernameColor[author]) == 6) {
			Format(name, MAXLENGTH_NAME, "\x07%s%s", g_sUsernameColor[author], name);
		}
		else if (strlen(g_sUsernameColor[author]) == 8) {
			Format(name, MAXLENGTH_NAME, "\x08%s%s", g_sUsernameColor[author], name);
		}
		else {
			Format(name, MAXLENGTH_NAME, "\x03%s", name);
		} // team color by default!
	}
	else {
		Format(name, MAXLENGTH_NAME, "\x03%s", name);
	} // team color by default!
	if (CheckForward(author, message, CCC_TagColor)){
		if (strlen(g_sTag[author]) > 0){
			if (StrEqual(g_sTagColor[author], "T", false)) {
				Format(name, MAXLENGTH_NAME, "\x03%s%s", g_sTag[author], name);
			}
			else if (StrEqual(g_sTagColor[author], "G", false)) {
				Format(name, MAXLENGTH_NAME, "\x04%s%s", g_sTag[author], name);
			}
			else if (StrEqual(g_sTagColor[author], "O", false)) {
				Format(name, MAXLENGTH_NAME, "\x05%s%s", g_sTag[author], name);
			}
			else if (strlen(g_sTagColor[author]) == 6) {
				Format(name, MAXLENGTH_NAME, "\x07%s%s%s", g_sTagColor[author], g_sTag[author], name);
			}
			else if (strlen(g_sTagColor[author]) == 8) {
				Format(name, MAXLENGTH_NAME, "\x08%s%s%s", g_sTagColor[author], g_sTag[author], name);
			}
			else {
				Format(name, MAXLENGTH_NAME, "\x01%s%s", g_sTag[author], name);
			}
		}
	}

	// MAXLENGTH_MESSAGE = maximum characters in a chat message, including name. Subtract the characters in the name, and 5 to account for the colon, spaces, and null terminator
	int MaxMessageLength = MAXLENGTH_MESSAGE - strlen(name) - 5;

	if (strlen(g_sChatColor[author]) > 0 && CheckForward(author, message, CCC_ChatColor)){
		if (StrEqual(g_sChatColor[author], "T", false)) {
			Format(message, MaxMessageLength, "\x03%s", message);
		}
		else if (StrEqual(g_sChatColor[author], "G", false)) {
			Format(message, MaxMessageLength, "\x04%s", message);
		}
		else if (StrEqual(g_sChatColor[author], "O", false)) {
			Format(message, MaxMessageLength, "\x05%s", message);
		}
		else if (strlen(g_sChatColor[author]) == 6) {
			Format(message, MaxMessageLength, "\x07%s%s", g_sChatColor[author], message);
		}
		else if (strlen(g_sChatColor[author]) == 8) {
			Format(message, MaxMessageLength, "\x08%s%s", g_sChatColor[author], message);
		}
	}
	char game[64];
	GetGameFolderName(game, sizeof(game));
	if (StrEqual(game, "csgo")) {
		Format(name, MAXLENGTH_NAME, "\x01\x0B%s", name);
	}

	Call_StartForward(g_gfMessageForward);
	Call_PushCell(author);
	Call_PushStringEx(message, MaxMessageLength, SM_PARAM_STRING_UTF8|SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(MaxMessageLength);
	Call_Finish();

	return Plugin_Changed;
}

bool CheckForward(int author, const char[] message, CCC_ColorType type){
	Action result = Plugin_Continue;
	Call_StartForward(g_gfApplicationForward);
	Call_PushCell(author);
	Call_PushString(message);
	Call_PushCell(type);
	Call_Finish(result);
	if (result >= Plugin_Handled) {
		return false;
	}

	// Compatibility
	switch(type) {
		case CCC_TagColor: {
			return TagForward(author);
		}
		case CCC_NameColor: {
			return NameForward(author);
		}
		case CCC_ChatColor: {
			return ColorForward(author);
		}
	}

	return true;
}

bool ColorForward(int author){
	Action result = Plugin_Continue;
	Call_StartForward(g_gfColorForward);
	Call_PushCell(author);
	Call_Finish(result);
	if (result >= Plugin_Handled) {
		return false;
	}

	return true;
}

bool NameForward(int author){
	Action result = Plugin_Continue;
	Call_StartForward(g_gfNameForward);
	Call_PushCell(author);
	Call_Finish(result);
	if (result >= Plugin_Handled) {
		return false;
	}

	return true;
}

bool TagForward(int author){
	Action result = Plugin_Continue;
	Call_StartForward(g_gfTagForward);
	Call_PushCell(author);
	Call_Finish(result);
	if (result >= Plugin_Handled) {
		return false;
	}

	return true;
}

bool ConfigForward(int client){
	Action result = Plugin_Continue;
	Call_StartForward(g_gfPreLoadedForward);
	Call_PushCell(client);
	Call_Finish(result);
	if (result >= Plugin_Handled) {
		return false;
	}

	return true;
}

public int Native_GetColor(Handle plugin, int numParams){
	int client = GetNativeCell(1);
	if (client < 1 || client > MaxClients || !IsClientInGame(client)){
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client or client is not in game");
		return COLOR_NONE;
	}
	switch(GetNativeCell(2)){
		case CCC_TagColor: {
			if (StrEqual(g_sTagColor[client], "T", false)){
				SetNativeCellRef(3, false);
				return COLOR_TEAM;
			}
			else if (StrEqual(g_sTagColor[client], "G", false)){
				SetNativeCellRef(3, false);
				return COLOR_GREEN;
			}
			else if (StrEqual(g_sTagColor[client], "O", false)){
				SetNativeCellRef(3, false);
				return COLOR_OLIVE;
			}
			else if (strlen(g_sTagColor[client]) == 6 || strlen(g_sTagColor[client]) == 8){
				SetNativeCellRef(3, strlen(g_sTagColor[client]) == 8);
				return StringToInt(g_sTagColor[client], 16);
			}
			else {
				SetNativeCellRef(3, false);
				return COLOR_NONE;
			}
		}
		case CCC_NameColor: {
			if (StrEqual(g_sUsernameColor[client], "G", false)){
				SetNativeCellRef(3, false);
				return COLOR_GREEN;
			}
			else if (StrEqual(g_sUsernameColor[client], "O", false)){
				SetNativeCellRef(3, false);
				return COLOR_OLIVE;
			}
			else if (strlen(g_sUsernameColor[client]) == 6 || strlen(g_sUsernameColor[client]) == 8){
				SetNativeCellRef(3, strlen(g_sUsernameColor[client]) == 8);
				return StringToInt(g_sUsernameColor[client], 16);
			}
			else {
				SetNativeCellRef(3, false);
				return COLOR_TEAM;
			}
		}
		case CCC_ChatColor: {
			if (StrEqual(g_sChatColor[client], "T", false)){
				SetNativeCellRef(3, false);
				return COLOR_TEAM;
			}
			else if (StrEqual(g_sChatColor[client], "G", false)){
				SetNativeCellRef(3, false);
				return COLOR_GREEN;
			}
			else if (StrEqual(g_sChatColor[client], "O", false)){
				SetNativeCellRef(3, false);
				return COLOR_OLIVE;
			}
			else if (strlen(g_sChatColor[client]) == 6 || strlen(g_sChatColor[client]) == 8){
				SetNativeCellRef(3, strlen(g_sChatColor[client]) == 8);
				return StringToInt(g_sChatColor[client], 16);
			}
			else {
				SetNativeCellRef(3, false);
				return COLOR_NONE;
			}
		}
	}
	return COLOR_NONE;
}

public int Native_SetColor(Handle plugin, int numParams){
	int client = GetNativeCell(1);
	if (client < 1 || client > MaxClients || !IsClientInGame(client)){
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client or client is not in game");
		return false;
	}
	char color[32];
	if (GetNativeCell(3) < 0){
		switch(GetNativeCell(3)){
			case COLOR_GREEN: {
				Format(color, sizeof(color), "G");
			}
			case COLOR_OLIVE: {
				Format(color, sizeof(color), "O");
			}
			case COLOR_TEAM: {
				Format(color, sizeof(color), "T");
			}
			case COLOR_NONE: {
				Format(color, sizeof(color), "");
			}
		}
	}
	else {
		if (!GetNativeCell(4)) {
			Format(color, sizeof(color), "%06X", GetNativeCell(3));
		} // No alpha
		else {
			Format(color, sizeof(color), "%08X", GetNativeCell(3));
		} // Alpha specified
	}
	if (strlen(color) != 6 && strlen(color) != 8 && !StrEqual(color, "G", false) && !StrEqual(color, "O", false) && !StrEqual(color, "T", false)) {
		return false;
	}
	switch(GetNativeCell(2)){
		case CCC_TagColor: {
			strcopy(g_sTagColor[client], sizeof(g_sTagColor[]), color);
		}
		case CCC_NameColor: {
			strcopy(g_sUsernameColor[client], sizeof(g_sUsernameColor[]), color);
		}
		case CCC_ChatColor: {
			strcopy(g_sChatColor[client], sizeof(g_sChatColor[]), color);
		}
	}
	return true;
}

public int Native_GetTag(Handle plugin, int numParams){
	int client = GetNativeCell(1);
	if (client < 1 || client > MaxClients || !IsClientInGame(client)){
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client or client is not in game");
		return;
	}
	SetNativeString(2, g_sTag[client], GetNativeCell(3));
}

public int Native_SetTag(Handle plugin, int numParams){
	int client = GetNativeCell(1);
	if (client < 1 || client > MaxClients || !IsClientInGame(client)){
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client or client is not in game");
		return;
	}
	GetNativeString(2, g_sTag[client], sizeof(g_sTag[]));
}

public int Native_ResetColor(Handle plugin, int numParams){
	int client = GetNativeCell(1);
	if (client < 1 || client > MaxClients || !IsClientInGame(client)){
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client or client is not in game");
		return;
	}
	switch(GetNativeCell(2)){
		case CCC_TagColor: {
			strcopy(g_sTagColor[client], sizeof(g_sTagColor[]), g_sDefaultTagColor[client]);
		}
		case CCC_NameColor: {
			strcopy(g_sUsernameColor[client], sizeof(g_sUsernameColor[]), g_sDefaultUsernameColor[client]);
		}
		case CCC_ChatColor: {
			strcopy(g_sChatColor[client], sizeof(g_sChatColor[]), g_sDefaultChatColor[client]);
		}
	}
}

public int Native_ResetTag(Handle plugin, int numParams){
	int client = GetNativeCell(1);
	if (client < 1 || client > MaxClients || !IsClientInGame(client)){
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client or client is not in game");
		return;
	}
	strcopy(g_sTag[client], sizeof(g_sTag[]), g_sDefaultTag[client]);
}