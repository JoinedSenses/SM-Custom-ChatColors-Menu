#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <regex>
#include <ccc>

#define PLUGIN_NAME "Custom Chat Colors Menu"
#define PLUGIN_VERSION "2.4"
#define MAX_COLORS 255
#define TAG 0
#define NAME 1
#define CHAT 2
#define ENABLEFLAG_TAG (1 << TAG)
#define ENABLEFLAG_NAME (1 << NAME)
#define ENABLEFLAG_CHAT (1 << CHAT)

ConVar g_hCvarEnabled, g_hCvarHideTags;
Handle g_hRegexHex, g_hSQL;
int g_iColorCount, g_iCvarEnabled;
AdminFlag g_iColorFlagList[MAX_COLORS][16];
bool g_bCvarHideTags, g_bColorsLoaded[MAXPLAYERS + 1], g_bColorAdminFlags[MAX_COLORS], g_bHideTag[MAXPLAYERS + 1], g_bAccessColor[MAXPLAYERS + 1][3], g_bAccessHideTags[MAXPLAYERS + 1];
char g_strAuth[MAXPLAYERS + 1][32], g_strColor[MAXPLAYERS + 1][3][7], g_strColorName[MAX_COLORS][255], g_strColorHex[MAX_COLORS][255];
char g_strColorFlags[MAX_COLORS][255], g_strConfigFile[PLATFORM_MAX_PATH], g_strSQLDriver[16];

// ====[ PLUGIN ]==============================================================
public Plugin myinfo = {
	name = PLUGIN_NAME,
	author = "ReFlexPoison, modified/fixed by JoinedSenses",
	description = "Change Custom Chat Colors settings through easy to access menus",
	version = PLUGIN_VERSION,
	url = "http://www.sourcemod.net"
}
// ====[ EVENTS ]==============================================================
public void OnPluginStart(){
	CreateConVar("sm_cccm_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY);

	g_hCvarEnabled = CreateConVar("sm_cccm_enabled", "7", "Enable Custom Chat Colors Menu (Add up the numbers to choose)\n0 = Disabled\n1 = Tag\n2 = Name\n4 = Chat", 0, true, 0.0, true, 7.0);
	g_iCvarEnabled = g_hCvarEnabled.IntValue;
	HookConVarChange(g_hCvarEnabled, OnConVarChange);

	g_hCvarHideTags = CreateConVar("sm_cccm_hidetags", "1", "Allow players to hide their chat tags\n0 = Disabled\n1 = Enabled", 0, true, 0.0, true, 1.0);
	g_bCvarHideTags = GetConVarBool(g_hCvarHideTags);
	HookConVarChange(g_hCvarHideTags, OnConVarChange);

	AutoExecConfig(true, "plugin.custom-chatcolors-menu");

	RegAdminCmd("sm_ccc", Command_Color, ADMFLAG_GENERIC, "Open Custom Chat Colors Menu");
	RegAdminCmd("sm_reload_cccm", Command_Reload, ADMFLAG_ROOT, "Reloads Custom Chat Colors Menu config");
	RegAdminCmd("sm_tagcolor", Command_TagColor, ADMFLAG_ROOT, "Change tag color to a specified hexadecimal value");
	RegAdminCmd("sm_resettag", Command_ResetTagColor, ADMFLAG_GENERIC, "Reset tag color to default");
	RegAdminCmd("sm_namecolor", Command_NameColor, ADMFLAG_ROOT, "Change name color to a specified hexadecimal value");
	RegAdminCmd("sm_resetname", Command_ResetNameColor, ADMFLAG_GENERIC, "Reset name color to default");
	RegAdminCmd("sm_chatcolor", Command_ChatColor, ADMFLAG_ROOT, "Change chat color to a specified hexadecimal value");
	RegAdminCmd("sm_resetchat", Command_ResetChatColor, ADMFLAG_GENERIC, "Reset chat color to default");

	LoadTranslations("core.phrases");
	LoadTranslations("common.phrases");
	LoadTranslations("custom-chatcolors-menu.phrases");

	g_hRegexHex = CompileRegex("([A-Fa-f0-9]{6})");

	BuildPath(Path_SM, g_strConfigFile, sizeof(g_strConfigFile), "configs/custom-chatcolors-menu.cfg");

	g_hSQL = INVALID_HANDLE;
	if (SQL_CheckConfig("cccm"))
		SQL_TConnect(SQLQuery_Connect, "cccm");
}

public void OnConVarChange(ConVar convar, const char[] strOldValue, const char[] strNewValue){
	if (convar == g_hCvarEnabled)
		g_iCvarEnabled = g_hCvarEnabled.IntValue;
	else if (convar == g_hCvarHideTags)
		g_bCvarHideTags = g_hCvarHideTags.BoolValue;
}

public void SQL_LoadColors(int client){
	if (!IsClientAuthorized(client))
		return;

	if (g_hSQL != INVALID_HANDLE){
		char strAuth[32], strQuery[256];
		GetClientAuthId(client, AuthId_Steam2, strAuth, sizeof(strAuth));
		strcopy(g_strAuth[client], sizeof(g_strAuth[]), strAuth);
		Format(strQuery, sizeof(strQuery), "SELECT hidetag, tagcolor, namecolor, chatcolor FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		SQL_TQuery(g_hSQL, SQLQuery_LoadColors, strQuery, GetClientUserId(client), DBPrio_High);
	}
}

public void OnConfigsExecuted(){
	Config_Load();
}

public void OnClientConnected(int client){
	g_bColorsLoaded[client] = false;
	g_bHideTag[client] = false;
	g_bAccessColor[client][TAG] = false;
	g_bAccessColor[client][NAME] = false;
	g_bAccessColor[client][CHAT] = false;
	g_bAccessHideTags[client] = false;
	strcopy(g_strAuth[client], sizeof(g_strAuth[]), "");
	strcopy(g_strColor[client][TAG], sizeof(g_strColor[][]), "");
	strcopy(g_strColor[client][NAME], sizeof(g_strColor[][]), "");
	strcopy(g_strColor[client][CHAT], sizeof(g_strColor[][]), "");
}

public void CCC_OnUserConfigLoaded(int client){
	if (g_bColorsLoaded[client])
		return;

	char strTag[7], strName[7], strChat[7];
	IntToString(CCC_GetColor(client, CCC_TagColor), strTag, sizeof(strTag));
	if (IsValidHex(strTag))
		strcopy(g_strColor[client][TAG], sizeof(g_strColor[][]), strTag);

	IntToString(CCC_GetColor(client, CCC_NameColor), strName, sizeof(strName));
	if (IsValidHex(strName))
		strcopy(g_strColor[client][NAME], sizeof(g_strColor[][]), strName);

	IntToString(CCC_GetColor(client, CCC_ChatColor), strChat, sizeof(strChat));
	if (IsValidHex(strChat))
		strcopy(g_strColor[client][CHAT], sizeof(g_strColor[][]), strChat);
}

public void OnClientAuthorized(int client, const char[] strAuth){
	strcopy(g_strAuth[client], sizeof(g_strAuth[]), strAuth);
}

public void OnRebuildAdminCache(AdminCachePart part){
	for (int i = 1; i <= MaxClients; i++) if (IsClientInGame(i)){
		OnClientConnected(i);
		OnClientPostAdminCheck(i);
	}
}

public void OnClientPostAdminCheck(int client){
	SQL_LoadColors(client);
	if (CheckCommandAccess(client, "sm_ccc_tag", ADMFLAG_GENERIC))
		g_bAccessColor[client][TAG] = true;
	if (CheckCommandAccess(client, "sm_ccc_name", ADMFLAG_GENERIC))
		g_bAccessColor[client][NAME] = true;
	if (CheckCommandAccess(client, "sm_ccc_chat", ADMFLAG_GENERIC))
		g_bAccessColor[client][CHAT] = true;
	if (CheckCommandAccess(client, "sm_ccc_hidetags", ADMFLAG_GENERIC))
		g_bAccessHideTags[client] = true;
}

public Action CCC_OnColor(int client, const char[] strMessage, CCC_ColorType type){
	if (type == CCC_TagColor){
		if (!(g_iCvarEnabled & ENABLEFLAG_TAG))
			return Plugin_Handled;

		if (g_bHideTag[client])
			return Plugin_Handled;
	}

	if (type == CCC_NameColor){
		if (!(g_iCvarEnabled & ENABLEFLAG_NAME))
			return Plugin_Handled;

		if (!IsValidHex(g_strColor[client][NAME]))
			return Plugin_Handled;
	}

	if (type == CCC_ChatColor){
		if (!(g_iCvarEnabled & ENABLEFLAG_CHAT))
			return Plugin_Handled;

		if (!IsValidHex(g_strColor[client][CHAT]))
			return Plugin_Handled;
	}

	return Plugin_Continue;
}
// ====[ COMMANDS ]============================================================
public Action Command_Color(int client, int args){
	if (!IsValidClient(client))
		return Plugin_Continue;

	Menu_Settings(client);
	return Plugin_Handled;
}

public Action Command_Reload(int client, int args){
	Config_Load();
	ReplyToCommand(client, "[SM] Configuration file %s reloaded.", g_strConfigFile);
	return Plugin_Handled;
}

public Action Command_TagColor(int client, int args){
	if (!IsValidClient(client))
		return Plugin_Continue;

	if (args != 1){
		ReplyToCommand(client, "[SM] Usage: sm_tagcolor <hex>");
		return Plugin_Handled;
	}

	char strArg[32];
	GetCmdArgString(strArg, sizeof(strArg));
	ReplaceString(strArg, sizeof(strArg), "#", "", false);

	if (!IsValidHex(strArg)){
		ReplyToCommand(client, "[SM] Usage: sm_tagcolor <hex>");
		return Plugin_Handled;
	}

	PrintToChat(client, "\x01[SM] %T \x07%s#%s\x01", "TagSet", client, strArg, strArg);
	strcopy(g_strColor[client][TAG], sizeof(g_strColor[][]), strArg);
	CCC_SetColor(client, CCC_TagColor, StringToInt(strArg, 16), false);

	if (g_hSQL != INVALID_HANDLE && IsClientAuthorized(client)){
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "SELECT tagcolor FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		SQL_TQuery(g_hSQL, SQLQuery_TagColor, strQuery, GetClientUserId(client), DBPrio_High);
	}

	return Plugin_Handled;
}

public Action Command_ResetTagColor(int client, int args){
	if (!IsValidClient(client))
		return Plugin_Continue;

	PrintToChat(client, "[SM] %T", "TagReset", client);
	strcopy(g_strColor[client][TAG], sizeof(g_strColor[][]), "");
	CCC_ResetColor(client, CCC_TagColor);


	if (g_hSQL != INVALID_HANDLE && IsClientAuthorized(client)){
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "SELECT tagcolor FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		SQL_TQuery(g_hSQL, SQLQuery_TagColor, strQuery, GetClientUserId(client), DBPrio_High);
	}

	return Plugin_Handled;
}

public Action Command_NameColor(int client, int args){
	if (!IsValidClient(client))
		return Plugin_Continue;

	if (args != 1){
		ReplyToCommand(client, "[SM] Usage: sm_namecolor <hex>");
		return Plugin_Handled;
	}

	char strArg[32];
	GetCmdArgString(strArg, sizeof(strArg));
	ReplaceString(strArg, sizeof(strArg), "#", "", false);

	if (!IsValidHex(strArg)){
		ReplyToCommand(client, "[SM] Usage: sm_namecolor <hex>");
		return Plugin_Handled;
	}

	PrintToChat(client, "\x01[SM] %T \x07%s#%s\x01", "NameSet", client, strArg, strArg);
	strcopy(g_strColor[client][NAME], sizeof(g_strColor[][]), strArg);
	CCC_SetColor(client, CCC_NameColor, StringToInt(strArg, 16), false);

	if (g_hSQL != INVALID_HANDLE && IsClientAuthorized(client)){
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "SELECT namecolor FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		SQL_TQuery(g_hSQL, SQLQuery_NameColor, strQuery, GetClientUserId(client), DBPrio_High);
	}

	return Plugin_Handled;
}

public Action Command_ResetNameColor(int client, int args){
	if (!IsValidClient(client))
		return Plugin_Continue;

	PrintToChat(client, "[SM] %T", "NameReset", client);
	strcopy(g_strColor[client][NAME], sizeof(g_strColor[][]), "");
	CCC_ResetColor(client, CCC_NameColor);

	if (g_hSQL != INVALID_HANDLE && IsClientAuthorized(client)){
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "SELECT namecolor FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		SQL_TQuery(g_hSQL, SQLQuery_NameColor, strQuery, GetClientUserId(client), DBPrio_High);
	}

	return Plugin_Handled;
}

public Action Command_ChatColor(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Continue;

	if (args != 1){
		ReplyToCommand(client, "[SM] Usage: sm_chatcolor <hex>");
		return Plugin_Handled;
	}

	char strArg[32];
	GetCmdArgString(strArg, sizeof(strArg));
	ReplaceString(strArg, sizeof(strArg), "#", "", false);

	if (!IsValidHex(strArg)){
		ReplyToCommand(client, "[SM] Usage: sm_chatcolor <hex>");
		return Plugin_Handled;
	}

	PrintToChat(client, "\x01[SM] %T \x07%s#%s\x01", "ChatSet", client, strArg, strArg);
	strcopy(g_strColor[client][TAG], sizeof(g_strColor[][]), strArg);
	CCC_SetColor(client, CCC_TagColor, StringToInt(strArg, 16), false);

	if (g_hSQL != INVALID_HANDLE && IsClientAuthorized(client)){
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "SELECT chatcolor FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		SQL_TQuery(g_hSQL, SQLQuery_TagColor, strQuery, GetClientUserId(client), DBPrio_High);
	}

	return Plugin_Handled;
}

public Action Command_ResetChatColor(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Continue;

	PrintToChat(client, "[SM] %T", "ChatReset", client);
	strcopy(g_strColor[client][CHAT], sizeof(g_strColor[][]), "");
	CCC_ResetColor(client, CCC_ChatColor);

	if (g_hSQL != INVALID_HANDLE && IsClientAuthorized(client)){
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "SELECT chatcolor FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		SQL_TQuery(g_hSQL, SQLQuery_ChatColor, strQuery, GetClientUserId(client), DBPrio_High);
	}

	return Plugin_Handled;
}
// ====[ MENUS ]===============================================================
public void Menu_Settings(int client)
{
	if (IsVoteInProgress())
		return;

	Menu menu = CreateMenu(MenuHandler_Settings);
	SetMenuTitle(menu, "%T:", "Title", client);

	char strBuffer[32];
	if (g_bCvarHideTags){
		
		if (!g_bHideTag[client]){
			Format(strBuffer, sizeof(strBuffer), "%T", "HideTag", client);
			AddMenuItem(menu, "HideTag", strBuffer);
		}
		else {
			Format(strBuffer, sizeof(strBuffer), "%T", "ShowTag", client);
			AddMenuItem(menu, "HideTag", strBuffer);
		}
	}
	Format(strBuffer, sizeof(strBuffer), "%T", "ChangeTag", client);
	if (g_iCvarEnabled & ENABLEFLAG_TAG && g_bAccessColor[client][TAG])
		AddMenuItem(menu, "Tag", strBuffer);

	Format(strBuffer, sizeof(strBuffer), "%T", "ChangeName", client);
	if (g_iCvarEnabled & ENABLEFLAG_NAME && g_bAccessColor[client][NAME])
		AddMenuItem(menu, "Name", strBuffer);

	Format(strBuffer, sizeof(strBuffer), "%T", "ChangeChat", client);
	if (g_iCvarEnabled & ENABLEFLAG_CHAT && g_bAccessColor[client][CHAT])
		AddMenuItem(menu, "Chat", strBuffer);

	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandler_Settings(Menu menu, MenuAction action, int param1, int param2){
	if (action == MenuAction_End){
		CloseHandle(menu);
		return;
	}

	if (action == MenuAction_Select){
		char strBuffer[32];
		GetMenuItem(menu, param2, strBuffer, sizeof(strBuffer));
		if (StrEqual(strBuffer, "HideTag")){
			if (g_bHideTag[param1]){
				g_bHideTag[param1] = false;
				PrintToChat(param1, "[SM] %T", "TagEnabled", param1);
				Menu_Settings(param1);
			}
			else {
				g_bHideTag[param1] = true;
				PrintToChat(param1, "[SM] %T", "TagDisabled", param1);
				Menu_Settings(param1);
			}

			if (g_hSQL != INVALID_HANDLE && IsClientAuthorized(param1)){
				char strQuery[256];
				Format(strQuery, sizeof(strQuery), "SELECT hidetag FROM cccm_users WHERE auth = '%s'", g_strAuth[param1]);
				SQL_TQuery(g_hSQL, SQLQuery_HideTag, strQuery, GetClientUserId(param1), DBPrio_High);
			}
		}
		if (StrEqual(strBuffer, "Tag"))
			Menu_TagColor(param1);
		else if (StrEqual(strBuffer, "Name"))
			Menu_NameColor(param1);
		else if (StrEqual(strBuffer, "Chat"))
			Menu_ChatColor(param1);
	}
}

public void Menu_TagColor(int client){
	if (IsVoteInProgress())
		return;

	Menu menu = CreateMenu(MenuHandler_TagColor);
	SetMenuTitle(menu, "%T:", "TagColor", client);
	SetMenuExitBackButton(menu, true);

	char strBuffer[32], strColorIndex[4];
	Format(strBuffer, sizeof(strBuffer), "%T", "Reset", client);
	AddMenuItem(menu, "Reset", strBuffer);

	for (int i = 0; i < g_iColorCount; i++){
		if (!g_bColorAdminFlags[i] || (g_bColorAdminFlags[i] && HasAdminFlag(client, g_iColorFlagList[i]))){
			IntToString(i, strColorIndex, sizeof(strColorIndex));
			AddMenuItem(menu, strColorIndex, g_strColorName[i]);
		}
	}

	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandler_TagColor(Menu menu, MenuAction action, int param1, int param2){
	if (action == MenuAction_End)
		return;

	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack){
		Menu_Settings(param1);
		return;
	}

	if (action == MenuAction_Select){
		char strBuffer[32];
		GetMenuItem(menu, param2, strBuffer, sizeof(strBuffer));

		if (StrEqual(strBuffer, "Reset")){
			PrintToChat(param1, "[SM] %T", "TagReset", param1);
			strcopy(g_strColor[param1][TAG], sizeof(g_strColor[][]), "");
			CCC_ResetColor(param1, CCC_TagColor);

			char strTag[7];
			IntToString(CCC_GetColor(param1, CCC_TagColor), strTag, sizeof(strTag));
			strcopy(g_strColor[param1][TAG], sizeof(g_strColor[][]), strTag);
		}
		else {
			int iColorIndex = StringToInt(strBuffer);
			PrintToChat(param1, "\x01[SM] %T \x07%s%s\x01", "TagSet", param1, g_strColorHex[iColorIndex], g_strColorName[iColorIndex]);
			strcopy(g_strColor[param1][TAG], sizeof(g_strColor[][]), g_strColorHex[iColorIndex]);
			CCC_SetColor(param1, CCC_TagColor, StringToInt(g_strColorHex[iColorIndex], 16), false);
		}

		if (g_hSQL != INVALID_HANDLE && IsClientAuthorized(param1)){
			char strQuery[256];
			Format(strQuery, sizeof(strQuery), "SELECT tagcolor FROM cccm_users WHERE auth = '%s'", g_strAuth[param1]);
			SQL_TQuery(g_hSQL, SQLQuery_TagColor, strQuery, GetClientUserId(param1), DBPrio_High);
		}

		DisplayMenuAtItem(menu, param1, GetMenuSelectionPosition(), MENU_TIME_FOREVER);
	}
}

public void Menu_NameColor(int client){
	if (IsVoteInProgress())
		return;

	Menu menu = CreateMenu(MenuHandler_NameColor);
	SetMenuTitle(menu, "%T:", "NameColor", client);
	SetMenuExitBackButton(menu, true);

	char strBuffer[32], strColorIndex[4];
	Format(strBuffer, sizeof(strBuffer), "%T", "Reset", client);
	AddMenuItem(menu, "Reset", strBuffer);

	for (int i = 0; i < g_iColorCount; i++){
		if (!g_bColorAdminFlags[i] || (g_bColorAdminFlags[i] && HasAdminFlag(client, g_iColorFlagList[i]))){
			IntToString(i, strColorIndex, sizeof(strColorIndex));
			AddMenuItem(menu, strColorIndex, g_strColorName[i]);
		}
	}

	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandler_NameColor(Menu menu, MenuAction action, int param1, int param2){
	if (action == MenuAction_End)
		return;

	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack){
		Menu_Settings(param1);
		return;
	}

	if (action == MenuAction_Select){
		char strBuffer[32];
		GetMenuItem(menu, param2, strBuffer, sizeof(strBuffer));

		if (StrEqual(strBuffer, "Reset")){
			PrintToChat(param1, "[SM] %T", "NameReset", param1);
			strcopy(g_strColor[param1][NAME], sizeof(g_strColor[][]), "");
			CCC_ResetColor(param1, CCC_NameColor);
		}
		else {
			int iColorIndex = StringToInt(strBuffer);
			PrintToChat(param1, "\x01[SM] %T \x07%s%s\x01", "NameSet", param1, g_strColorHex[iColorIndex], g_strColorName[iColorIndex]);
			strcopy(g_strColor[param1][NAME], sizeof(g_strColor[][]), g_strColorHex[iColorIndex]);
			CCC_SetColor(param1, CCC_NameColor, StringToInt(g_strColorHex[iColorIndex], 16), false);
		}

		if (g_hSQL != INVALID_HANDLE && IsClientAuthorized(param1)){
			char strQuery[256];
			Format(strQuery, sizeof(strQuery), "SELECT namecolor FROM cccm_users WHERE auth = '%s'", g_strAuth[param1]);
			SQL_TQuery(g_hSQL, SQLQuery_NameColor, strQuery, GetClientUserId(param1), DBPrio_High);
		}

		DisplayMenuAtItem(menu, param1, GetMenuSelectionPosition(), MENU_TIME_FOREVER);
	}
}

public void Menu_ChatColor(int client){
	if (IsVoteInProgress())
		return;

	Menu menu = CreateMenu(MenuHandler_ChatColor);
	SetMenuTitle(menu, "%T:", "ChatColor", client);
	SetMenuExitBackButton(menu, true);

	char strBuffer[32], strColorIndex[4];
	Format(strBuffer, sizeof(strBuffer), "%T", "Reset", client);
	AddMenuItem(menu, "Reset", strBuffer);

	for (int i = 0; i < g_iColorCount; i++){
		if (!g_bColorAdminFlags[i] || (g_bColorAdminFlags[i] && HasAdminFlag(client, g_iColorFlagList[i]))){
			IntToString(i, strColorIndex, sizeof(strColorIndex));
			AddMenuItem(menu, strColorIndex, g_strColorName[i]);
		}
	}

	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandler_ChatColor(Menu menu, MenuAction action, int param1, int param2){
	if (action == MenuAction_End)
		return;

	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack){
		Menu_Settings(param1);
		return;
	}

	if (action == MenuAction_Select){
		char strBuffer[32];
		GetMenuItem(menu, param2, strBuffer, sizeof(strBuffer));

		if (StrEqual(strBuffer, "Reset")){
			PrintToChat(param1, "[SM] %T", "ChatReset", param1);
			strcopy(g_strColor[param1][CHAT], sizeof(g_strColor[][]), "");
			CCC_ResetColor(param1, CCC_ChatColor);
		}
		else {
			int iColorIndex = StringToInt(strBuffer);
			PrintToChat(param1, "\x01[SM] %T \x07%s%s\x01", "ChatSet", param1, g_strColorHex[iColorIndex], g_strColorName[iColorIndex]);
			strcopy(g_strColor[param1][CHAT], sizeof(g_strColor[][]), g_strColorHex[iColorIndex]);
			CCC_SetColor(param1, CCC_ChatColor, StringToInt(g_strColorHex[iColorIndex], 16), false);
		}

		if (g_hSQL != INVALID_HANDLE && IsClientAuthorized(param1)){
			char strQuery[256];
			Format(strQuery, sizeof(strQuery), "SELECT chatcolor FROM cccm_users WHERE auth = '%s'", g_strAuth[param1]);
			SQL_TQuery(g_hSQL, SQLQuery_ChatColor, strQuery, GetClientUserId(param1), DBPrio_High);
		}

		DisplayMenuAtItem(menu, param1, GetMenuSelectionPosition(), MENU_TIME_FOREVER);
	}
}
// ====[ CONFIGURATION ]=======================================================
public void Config_Load(){
	if (!FileExists(g_strConfigFile)){
		SetFailState("Configuration file %s not found!", g_strConfigFile);
		return;
	}

	KeyValues keyvalues = CreateKeyValues("CCC Menu Colors");
	if (!FileToKeyValues(keyvalues, g_strConfigFile)){
		SetFailState("Improper structure for configuration file %s!", g_strConfigFile);
		return;
	}

	if (!KvGotoFirstSubKey(keyvalues)){
		SetFailState("Can't find configuration file %s!", g_strConfigFile);
		return;
	}

	for (int i = 0; i < MAX_COLORS; i++){
		strcopy(g_strColorName[i], sizeof(g_strColorName[]), "");
		strcopy(g_strColorHex[i], sizeof(g_strColorHex[]), "");
		strcopy(g_strColorFlags[i], sizeof(g_strColorFlags[]), "");
		g_bColorAdminFlags[i] = false;
		for (int i2 = 0; i2 < 16; i2++)
			g_iColorFlagList[i][i2] = view_as<AdminFlag>(-1);
	}

	g_iColorCount = 0;
	do {
		KvGetString(keyvalues, "name", g_strColorName[g_iColorCount], sizeof(g_strColorName[]));
		KvGetString(keyvalues, "hex",	g_strColorHex[g_iColorCount], sizeof(g_strColorHex[]));
		ReplaceString(g_strColorHex[g_iColorCount], sizeof(g_strColorHex[]), "#", "", false);
		KvGetString(keyvalues, "flags", g_strColorFlags[g_iColorCount], sizeof(g_strColorFlags[]));

		if (!IsValidHex(g_strColorHex[g_iColorCount])){
			LogError("Invalid hexadecimal value for color %s.", g_strColorName[g_iColorCount]);
			strcopy(g_strColorName[g_iColorCount], sizeof(g_strColorName[]), "");
			strcopy(g_strColorHex[g_iColorCount], sizeof(g_strColorHex[]), "");
			strcopy(g_strColorFlags[g_iColorCount], sizeof(g_strColorFlags[]), "");
		}

		if (!StrEqual(g_strColorFlags[g_iColorCount], "")){
			g_bColorAdminFlags[g_iColorCount] = true;
			FlagBitsToArray(ReadFlagString(g_strColorFlags[g_iColorCount]), g_iColorFlagList[g_iColorCount], sizeof(g_iColorFlagList[]));
		}
		g_iColorCount++;
	}
	while (KvGotoNextKey(keyvalues));
	CloseHandle(keyvalues);

	LogMessage("Loaded %i colors from configuration file %s.", g_iColorCount, g_strConfigFile);
}
// ====[ SQL QUERIES ]=========================================================
public void SQLQuery_Connect(Handle owner, Handle hndl, const char[] strError, any data){
	if (hndl == INVALID_HANDLE)
		return;

	g_hSQL = hndl;
	SQL_GetDriverIdent(owner, g_strSQLDriver, sizeof(g_strSQLDriver));

	if (StrEqual(g_strSQLDriver, "mysql", false)){
		LogMessage("MySQL server configured. Variable saving enabled.");
		SQL_TQuery(g_hSQL, SQLQuery_Update, "CREATE TABLE IF NOT EXISTS cccm_users (id INT(64) NOT NULL AUTO_INCREMENT, auth varchar(32) UNIQUE, hidetag varchar(1), tagcolor varchar(7), namecolor varchar(7), chatcolor varchar(7), PRIMARY KEY (id))", _, DBPrio_High);
	}
	else if (StrEqual(g_strSQLDriver, "sqlite", false)){
		LogMessage("SQlite server configured. Variable saving enabled.");
		SQL_TQuery(g_hSQL, SQLQuery_Update, "CREATE TABLE IF NOT EXISTS cccm_users (id INTERGER PRIMARY KEY, auth varchar(32) UNIQUE, hidetag varchar(1), tagcolor varchar(7), namecolor varchar(7), chatcolor varchar(7))", _, DBPrio_High);
	}
	else {
		LogMessage("Saved variable server not configured. Variable saving disabled.");
		return;
	}

	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			SQL_LoadColors(i);
}

public void SQLQuery_LoadColors(Handle owner, Handle hndl, const char[] strError, any data){
	int client = GetClientOfUserId(data);
	if (!IsValidClient(client))
		return;

	if (owner == INVALID_HANDLE || hndl == INVALID_HANDLE){
		LogError("SQL Error: %s", strError);
		return;
	}

	if (SQL_FetchRow(hndl) && SQL_GetRowCount(hndl) != 0){
		g_bHideTag[client] = view_as<bool>(SQL_FetchInt(hndl, 0));

		char strTag[7], strName[7], strChat[7];
		SQL_FetchString(hndl, 1, strTag, sizeof(strTag));
		if (IsValidHex(strTag)){
			strcopy(g_strColor[client][TAG], sizeof(g_strColor[][]), strTag);
			CCC_SetColor(client, CCC_TagColor, StringToInt(g_strColor[client][TAG], 16), false);
		}
		else if (StrEqual(strTag, "-1"))
			strcopy(g_strColor[client][TAG], sizeof(g_strColor[][]), "-1");

		SQL_FetchString(hndl, 2, strName, sizeof(strName));
		if (IsValidHex(strName)){
			strcopy(g_strColor[client][NAME], sizeof(g_strColor[][]), strName);
			CCC_SetColor(client, CCC_NameColor, StringToInt(g_strColor[client][NAME], 16), false);
		}

		SQL_FetchString(hndl, 3, strChat, sizeof(strChat));
		if (IsValidHex(strChat)){
			strcopy(g_strColor[client][CHAT], sizeof(g_strColor[][]), strChat);
			CCC_SetColor(client, CCC_ChatColor, StringToInt(g_strColor[client][CHAT], 16), false);
		}

		g_bColorsLoaded[client] = true;
	}
}

public void SQLQuery_HideTag(Handle owner, Handle hndl, const char[] strError, any data){
	int client = GetClientOfUserId(data);
	if (!IsValidClient(client))
		return;

	if (owner == INVALID_HANDLE || hndl == INVALID_HANDLE){
		LogError("SQL Error: %s", strError);
		return;
	}

	if (SQL_GetRowCount(hndl) == 0){
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "INSERT INTO cccm_users (hidetag, auth) VALUES (%i, '%s')", g_bHideTag[client], g_strAuth[client]);
		SQL_TQuery(g_hSQL, SQLQuery_Update, strQuery, _, DBPrio_High);
	}
	else {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "UPDATE cccm_users SET hidetag = '%i' WHERE auth = '%s'", g_bHideTag[client], g_strAuth[client]);
		SQL_TQuery(g_hSQL, SQLQuery_Update, strQuery, _, DBPrio_Normal);
	}
}

public void SQLQuery_TagColor(Handle owner, Handle hndl, const char[] strError, any data){
	int client = GetClientOfUserId(data);
	if (!IsValidClient(client))
		return;

	if (owner == INVALID_HANDLE || hndl == INVALID_HANDLE){
		LogError("SQL Error: %s", strError);
		return;
	}

	if (SQL_GetRowCount(hndl) == 0){
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "INSERT INTO cccm_users (tagcolor, auth) VALUES ('%s', '%s')", g_strColor[client][TAG], g_strAuth[client]);
		SQL_TQuery(g_hSQL, SQLQuery_Update, strQuery, _, DBPrio_High);
	}
	else {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "UPDATE cccm_users SET tagcolor = '%s' WHERE auth = '%s'", g_strColor[client][TAG], g_strAuth[client]);
		SQL_TQuery(g_hSQL, SQLQuery_Update, strQuery, _, DBPrio_Normal);
	}
}

public void SQLQuery_NameColor(Handle owner, Handle hndl, const char[] strError, any data){
	int client = GetClientOfUserId(data);
	if (!IsValidClient(client))
		return;

	if (owner == INVALID_HANDLE || hndl == INVALID_HANDLE){
		LogError("SQL Error: %s", strError);
		return;
	}

	if (SQL_GetRowCount(hndl) == 0){
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "INSERT INTO cccm_users (namecolor, auth) VALUES ('%s', '%s')", g_strColor[client][NAME], g_strAuth[client]);
		SQL_TQuery(g_hSQL, SQLQuery_Update, strQuery, _, DBPrio_High);
	}
	else {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "UPDATE cccm_users SET namecolor = '%s' WHERE auth = '%s'", g_strColor[client][NAME], g_strAuth[client]);
		SQL_TQuery(g_hSQL, SQLQuery_Update, strQuery, _, DBPrio_Normal);
	}
}

public void SQLQuery_ChatColor(Handle owner, Handle hndl, const char[] strError, any data){
	int client = GetClientOfUserId(data);
	if (!IsValidClient(client))
		return;

	if (owner == INVALID_HANDLE || hndl == INVALID_HANDLE){
		LogError("SQL Error: %s", strError);
		return;
	}

	if (SQL_GetRowCount(hndl) == 0){
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "INSERT INTO cccm_users (chatcolor, auth) VALUES ('%s', '%s')", g_strColor[client][CHAT], g_strAuth[client]);
		SQL_TQuery(g_hSQL, SQLQuery_Update, strQuery, _, DBPrio_High);
	}
	else {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "UPDATE cccm_users SET chatcolor = '%s' WHERE auth = '%s'", g_strColor[client][CHAT], g_strAuth[client]);
		SQL_TQuery(g_hSQL, SQLQuery_Update, strQuery, _, DBPrio_Normal);
	}
}

public void SQLQuery_Update(Handle owner, Handle hndl, const char[] strError, any data){
	if (hndl == INVALID_HANDLE)
		LogError("SQL Error: %s", strError);
}
// ====[ STOCKS ]==============================================================
stock bool IsValidClient(int client){
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
		return false;
	return true;
}

stock bool IsValidHex(const char[] hex){
	if (strlen(hex) == 6 && MatchRegex(g_hRegexHex, hex))
		return true;
	return false;
}

stock bool HasAdminFlag(int client, const AdminFlag flaglist[16]){
	int flags = GetUserFlagBits(client);
	if (flags & ADMFLAG_ROOT)
		return true;

	for (int i = 0; i < sizeof(flaglist); i++)
		if (flags & FlagToBit(flaglist[i]))
			return true;
	return false;
}