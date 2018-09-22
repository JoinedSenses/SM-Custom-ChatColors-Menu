#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <regex>
#include <ccc>

enum {
	TAG,
	NAME,
	CHAT,
}

#define PLUGIN_NAME "Custom Chat Colors Menu"
#define PLUGIN_VERSION "2.6"
#define MAX_COLORS 255
#define ENABLEFLAG_TAG (1 << TAG)
#define ENABLEFLAG_NAME (1 << NAME)
#define ENABLEFLAG_CHAT (1 << CHAT)

Menu
	  MainMenu
	, TagMenu
	, NameMenu
	, ChatMenu;
ConVar
	  g_hCvarEnabled
	, g_hCvarHideTags;
Regex
	  g_hRegexHex;
Database
	  g_hSQL;
int
	  g_iColorCount
	, g_iCvarEnabled;
AdminFlag
	  g_iColorFlagList[MAX_COLORS][16];
bool
	  g_bCvarHideTags
	, g_bColorsLoaded[MAXPLAYERS+1]
	, g_bColorAdminFlags[MAX_COLORS]
	, g_bHideTag[MAXPLAYERS+1]
	, g_bAccessColor[MAXPLAYERS+1][3]
	, g_bAccessHideTags[MAXPLAYERS+1]
	, g_bLateLoad;
char
	  g_strAuth[MAXPLAYERS+1][32]
	, g_strColor[MAXPLAYERS+1][3][7]
	, g_strColorName[MAX_COLORS][255]
	, g_strColorHex[MAX_COLORS][255]
	, g_strColorFlags[MAX_COLORS][255]
	, g_strConfigFile[PLATFORM_MAX_PATH]
	, g_strSQLDriver[16];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLateLoad = late;
	return APLRes_Success;
}

// ====[PLUGIN]==============================================================

public Plugin myinfo = {
	name = PLUGIN_NAME,
	author = "ReFlexPoison, modified/fixed by JoinedSenses",
	description = "Change Custom Chat Colors settings through easy to access menus",
	version = PLUGIN_VERSION,
	url = "https://github.com/JoinedSenses"
}

// ====[EVENTS]==============================================================

public void OnPluginStart() {
	CreateConVar("sm_cccm_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY);

	g_hCvarEnabled = CreateConVar("sm_cccm_enabled", "7", "Enable Custom Chat Colors Menu (Add up the numbers to choose)\n0 = Disabled\n1 = Tag\n2 = Name\n4 = Chat", 0, true, 0.0, true, 7.0);
	g_iCvarEnabled = g_hCvarEnabled.IntValue;
	g_hCvarEnabled.AddChangeHook(OnConVarChange);

	g_hCvarHideTags = CreateConVar("sm_cccm_hidetags", "1", "Allow players to hide their chat tags\n0 = Disabled\n1 = Enabled", 0, true, 0.0, true, 1.0);
	g_bCvarHideTags = g_hCvarHideTags.BoolValue;
	g_hCvarHideTags.AddChangeHook(OnConVarChange);

	AutoExecConfig(true, "plugin.custom-chatcolors-menu");

	RegAdminCmd("sm_ccc", Command_Color, ADMFLAG_GENERIC, "Open Custom Chat Colors Menu");
	RegAdminCmd("sm_reload_cccm", Command_Reload, ADMFLAG_ROOT, "Reloads Custom Chat Colors Menu config");
	RegAdminCmd("sm_tagcolor", Command_TagColor, ADMFLAG_ROOT, "Change tag color to a specified hexadecimal value");
	RegAdminCmd("sm_namecolor", Command_NameColor, ADMFLAG_ROOT, "Change name color to a specified hexadecimal value");
	RegAdminCmd("sm_chatcolor", Command_ChatColor, ADMFLAG_ROOT, "Change chat color to a specified hexadecimal value");
	RegAdminCmd("sm_resettag", Command_ResetTagColor, ADMFLAG_GENERIC, "Reset tag color to default");
	RegAdminCmd("sm_resetname", Command_ResetNameColor, ADMFLAG_GENERIC, "Reset name color to default");
	RegAdminCmd("sm_resetchat", Command_ResetChatColor, ADMFLAG_GENERIC, "Reset chat color to default");

	LoadTranslations("core.phrases");
	LoadTranslations("common.phrases");

	g_hRegexHex = new Regex("([A-Fa-f0-9]{6})");

	BuildPath(Path_SM, g_strConfigFile, sizeof(g_strConfigFile), "configs/custom-chatcolors-menu.cfg");

	g_hSQL = null;
	if (SQL_CheckConfig("cccm")) {
		Database.Connect(SQLQuery_Connect, "cccm");
	}

	if (g_bLateLoad) {
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i)) {
				CheckSettings(i);
			}
		}
	}
}

public void OnConVarChange(ConVar convar, const char[] strOldValue, const char[] strNewValue) {
	if (convar == g_hCvarEnabled) {
		g_iCvarEnabled = g_hCvarEnabled.IntValue;
	}
	else if (convar == g_hCvarHideTags) {
		g_bCvarHideTags = g_hCvarHideTags.BoolValue;
	}
}

void SQL_LoadColors(int client) {
	if (!IsClientAuthorized(client)) {
		return;
	}

	if (g_hSQL != null) {
		char strAuth[32], strQuery[256];
		GetClientAuthId(client, AuthId_Steam2, strAuth, sizeof(strAuth));
		strcopy(g_strAuth[client], sizeof(g_strAuth[]), strAuth);
		Format(strQuery, sizeof(strQuery), "SELECT hidetag, tagcolor, namecolor, chatcolor FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		g_hSQL.Query(SQLQuery_LoadColors, strQuery, GetClientUserId(client), DBPrio_High);
	}
}

public void OnConfigsExecuted() {
	Config_Load();
}

public void OnClientConnected(int client) {
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

public void CCC_OnUserConfigLoaded(int client) {
	if (g_bColorsLoaded[client]) {
		return;
	}

	char strTag[7];
	IntToString(CCC_GetColor(client, CCC_TagColor), strTag, sizeof(strTag));
	if (IsValidHex(strTag)) {
		strcopy(g_strColor[client][TAG], sizeof(g_strColor[][]), strTag);
	}

	char strName[7];
	IntToString(CCC_GetColor(client, CCC_NameColor), strName, sizeof(strName));
	if (IsValidHex(strName)) {
		strcopy(g_strColor[client][NAME], sizeof(g_strColor[][]), strName);
	}

	char strChat[7];
	IntToString(CCC_GetColor(client, CCC_ChatColor), strChat, sizeof(strChat));
	if (IsValidHex(strChat)) {
		strcopy(g_strColor[client][CHAT], sizeof(g_strColor[][]), strChat);
	}
}

public void OnClientAuthorized(int client, const char[] strAuth) {
	strcopy(g_strAuth[client], sizeof(g_strAuth[]), strAuth);
}

public void OnRebuildAdminCache(AdminCachePart part) {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientConnected(i);
			OnClientPostAdminCheck(i);
		}
	}
}

public void OnClientPostAdminCheck(int client) {
	CheckSettings(client);
}

void CheckSettings(int client) {
	if (!CheckCommandAccess(client, "sm_ccc", ADMFLAG_GENERIC)) {
		return;
	}
	SQL_LoadColors(client);
	if (CheckCommandAccess(client, "sm_ccc_tag", ADMFLAG_GENERIC)) {
		g_bAccessColor[client][TAG] = true;
	}
	if (CheckCommandAccess(client, "sm_ccc_name", ADMFLAG_GENERIC)) {
		g_bAccessColor[client][NAME] = true;
	}
	if (CheckCommandAccess(client, "sm_ccc_chat", ADMFLAG_GENERIC)) {
		g_bAccessColor[client][CHAT] = true;
	}
	if (CheckCommandAccess(client, "sm_ccc_hidetags", ADMFLAG_GENERIC)) {
		g_bAccessHideTags[client] = true;
	}
}

public Action CCC_OnColor(int client, const char[] strMessage, CCC_ColorType type) {
	if (type == CCC_TagColor && (!(g_iCvarEnabled & ENABLEFLAG_TAG) || g_bHideTag[client])) {
		return Plugin_Handled;
	}

	if (type == CCC_NameColor && (!(g_iCvarEnabled & ENABLEFLAG_NAME) || !IsValidHex(g_strColor[client][NAME]))) {
		return Plugin_Handled;
	}

	if (type == CCC_ChatColor && (!(g_iCvarEnabled & ENABLEFLAG_CHAT) || !IsValidHex(g_strColor[client][CHAT]))) {
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

// ====[COMMANDS]============================================================

public Action Command_Color(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Continue;
	}

	DisplayColorMenu(MainMenu, client);
	return Plugin_Handled;
}

public Action Command_Reload(int client, int args) {
	Config_Load();
	ReplyToCommand(client, "\x01[\x03CCC\x01] Configuration file %s reloaded.", g_strConfigFile);
	return Plugin_Handled;
}

public Action Command_TagColor(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Continue;
	}

	if (args != 1) {
		ReplyToCommand(client, "\x01[\x03CCC\x01] Usage: sm_tagcolor <hex>");
		return Plugin_Handled;
	}

	char strArg[32];
	GetCmdArgString(strArg, sizeof(strArg));
	ReplaceString(strArg, sizeof(strArg), "#", "", false);

	if (!IsValidHex(strArg)) {
		ReplyToCommand(client, "\x01[\x03CCC\x01] Usage: sm_tagcolor <hex>");
		return Plugin_Handled;
	}

	PrintToChat(client, "\x01[\x03CCC\x01] Tag color set to: \x07%s#%s\x01", strArg, strArg);
	strcopy(g_strColor[client][TAG], sizeof(g_strColor[][]), strArg);
	CCC_SetColor(client, CCC_TagColor, StringToInt(strArg, 16), false);

	if (g_hSQL != null && IsClientAuthorized(client)) {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "SELECT tagcolor FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		g_hSQL.Query(SQLQuery_TagColor, strQuery, GetClientUserId(client), DBPrio_High);
	}

	return Plugin_Handled;
}

public Action Command_ResetTagColor(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Continue;
	}

	PrintToChat(client, "\x01[\x03CCC\x01] Tag color \x03reset");
	strcopy(g_strColor[client][TAG], sizeof(g_strColor[][]), "");
	CCC_ResetColor(client, CCC_TagColor);


	if (g_hSQL != null && IsClientAuthorized(client)) {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "SELECT tagcolor FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		g_hSQL.Query(SQLQuery_TagColor, strQuery, GetClientUserId(client), DBPrio_High);
	}

	return Plugin_Handled;
}

public Action Command_NameColor(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Continue;
	}

	if (args != 1) {
		ReplyToCommand(client, "\x01[\x03CCC\x01] Usage: sm_namecolor <hex>");
		return Plugin_Handled;
	}

	char strArg[32];
	GetCmdArgString(strArg, sizeof(strArg));
	ReplaceString(strArg, sizeof(strArg), "#", "", false);

	if (!IsValidHex(strArg)) {
		ReplyToCommand(client, "\x01[\x03CCC\x01] Usage: sm_namecolor <hex>");
		return Plugin_Handled;
	}

	PrintToChat(client, "\x01[\x03CCC\x01] Name color set to: \x07%s#%s\x01", strArg, strArg);
	strcopy(g_strColor[client][NAME], sizeof(g_strColor[][]), strArg);
	CCC_SetColor(client, CCC_NameColor, StringToInt(strArg, 16), false);

	if (g_hSQL != null && IsClientAuthorized(client)) {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "SELECT namecolor FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		g_hSQL.Query(SQLQuery_NameColor, strQuery, GetClientUserId(client), DBPrio_High);
	}

	return Plugin_Handled;
}

public Action Command_ResetNameColor(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Continue;
	}

	PrintToChat(client, "\x01[\x03CCC\x01] Name color \x03reset");
	strcopy(g_strColor[client][NAME], sizeof(g_strColor[][]), "");
	CCC_ResetColor(client, CCC_NameColor);

	if (g_hSQL != null && IsClientAuthorized(client)) {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "SELECT namecolor FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		g_hSQL.Query(SQLQuery_NameColor, strQuery, GetClientUserId(client), DBPrio_High);
	}

	return Plugin_Handled;
}

public Action Command_ChatColor(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Continue;
	}

	if (args != 1) {
		ReplyToCommand(client, "\x01[\x03CCC\x01] Usage: sm_chatcolor <hex>");
		return Plugin_Handled;
	}

	char strArg[32];
	GetCmdArgString(strArg, sizeof(strArg));
	ReplaceString(strArg, sizeof(strArg), "#", "", false);

	if (!IsValidHex(strArg)) {
		ReplyToCommand(client, "\x01[\x03CCC\x01] Usage: sm_chatcolor <hex>");
		return Plugin_Handled;
	}

	PrintToChat(client, "\x01[\x03CCC\x01] Chat color set to: \x07%s#%s\x01", strArg, strArg);
	strcopy(g_strColor[client][TAG], sizeof(g_strColor[][]), strArg);
	CCC_SetColor(client, CCC_TagColor, StringToInt(strArg, 16), false);

	if (g_hSQL != null && IsClientAuthorized(client)) {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "SELECT chatcolor FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		g_hSQL.Query(SQLQuery_TagColor, strQuery, GetClientUserId(client), DBPrio_High);
	}

	return Plugin_Handled;
}

public Action Command_ResetChatColor(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Continue;
	}

	PrintToChat(client, "\x01[\x03CCC\x01] Chat color \x03reset", "ChatReset");
	strcopy(g_strColor[client][CHAT], sizeof(g_strColor[][]), "");
	CCC_ResetColor(client, CCC_ChatColor);

	if (g_hSQL != null && IsClientAuthorized(client)) {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "SELECT chatcolor FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		g_hSQL.Query(SQLQuery_ChatColor, strQuery, GetClientUserId(client), DBPrio_High);
	}

	return Plugin_Handled;
}

// ====[MENUS]===============================================================

// ------------------------------- Build Menu
void BuildMainMenu() {
	MainMenu = new Menu(MenuHandler_Settings, MENU_ACTIONS_DEFAULT|MenuAction_DrawItem|MenuAction_DisplayItem);
	MainMenu.SetTitle("Custom Chat Colors");

	if (g_bCvarHideTags) {
		MainMenu.AddItem("HideTag", "Hide Tag");
	}
	MainMenu.AddItem("Tag", "Change Tag Color");
	MainMenu.AddItem("Name", "Change Name Color");
	MainMenu.AddItem("Chat", "Change Chat Color");
}

void BuildTagMenu() {
	TagMenu = new Menu(MenuHandler_TagColor, MENU_ACTIONS_DEFAULT|MenuAction_DrawItem);
	TagMenu.SetTitle("Tag Color");
	TagMenu.ExitBackButton = true;

	TagMenu.AddItem("Reset", "Reset");

	char strColorIndex[4];
	for (int i = 0; i < g_iColorCount; i++) {
		IntToString(i, strColorIndex, sizeof(strColorIndex));
		TagMenu.AddItem(strColorIndex, g_strColorName[i]);
	}
}

void BuildNameMenu() {
	NameMenu = new Menu(MenuHandler_NameColor, MENU_ACTIONS_DEFAULT|MenuAction_DrawItem);
	NameMenu.SetTitle("Name Color");
	NameMenu.ExitBackButton = true;

	NameMenu.AddItem("Reset", "Reset");

	char strColorIndex[4];
	for (int i = 0; i < g_iColorCount; i++) {
		IntToString(i, strColorIndex, sizeof(strColorIndex));
		NameMenu.AddItem(strColorIndex, g_strColorName[i]);
	}
}

void BuildChatMenu() {
	ChatMenu = new Menu(MenuHandler_ChatColor, MENU_ACTIONS_DEFAULT|MenuAction_DrawItem);
	ChatMenu.SetTitle("Chat Color");
	ChatMenu.ExitBackButton = true;

	ChatMenu.AddItem("Reset", "Reset");

	char strColorIndex[4];
	for (int i = 0; i < g_iColorCount; i++) {
		IntToString(i, strColorIndex, sizeof(strColorIndex));
		ChatMenu.AddItem(strColorIndex, g_strColorName[i]);
	}
}

// ------------------------------- Display Menu

void DisplayColorMenu(Menu menu, int client) {
	if (IsVoteInProgress()) {
		ReplyToCommand(client, "\x01[\x03CCC\x01] Vote In Progress.");
		return;
	}
	menu.Display(client, MENU_TIME_FOREVER);
}

// ------------------------------- Menu Handlers

int MenuHandler_Settings(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char strBuffer[32];
			menu.GetItem(param2, strBuffer, sizeof(strBuffer));
			if (StrEqual(strBuffer, "HideTag")) {
				g_bHideTag[param1] = !g_bHideTag[param1];
				PrintToChat(param1, "\x01[\x03CCC\x01] Chat tag \x03%s", g_bHideTag[param1] ? "disabled" : "enabled");

				if (g_hSQL != null && IsClientAuthorized(param1)) {
					char strQuery[256];
					Format(strQuery, sizeof(strQuery), "SELECT hidetag FROM cccm_users WHERE auth = '%s'", g_strAuth[param1]);
					g_hSQL.Query(SQLQuery_HideTag, strQuery, GetClientUserId(param1), DBPrio_High);
				}
				menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);
			}
			if (StrEqual(strBuffer, "Tag")) {
				DisplayColorMenu(TagMenu, param1);
			}
			else if (StrEqual(strBuffer, "Name")) {
				DisplayColorMenu(NameMenu, param1);
			}
			else if (StrEqual(strBuffer, "Chat")) {
				DisplayColorMenu(ChatMenu, param1);
			}			
		}
		case MenuAction_DrawItem: {
			char item[32];
			menu.GetItem(param2, item, sizeof(item));
			if (StrEqual(item, "Tag")) {
				if (!((g_iCvarEnabled & ENABLEFLAG_TAG) && g_bAccessColor[param1][TAG])) {
					return ITEMDRAW_DISABLED;
				}				
			}
			if (StrEqual(item, "Name")) {
				if (!((g_iCvarEnabled & ENABLEFLAG_NAME) && g_bAccessColor[param1][NAME])) {
					return ITEMDRAW_DISABLED;
				}
			}
			if (StrEqual(item, "Chat")) {
				if (!((g_iCvarEnabled & ENABLEFLAG_CHAT) && g_bAccessColor[param1][CHAT])) {
					return ITEMDRAW_DISABLED;
				}
			}
			return ITEMDRAW_DEFAULT;
		} 
		case MenuAction_DisplayItem: {
			char item[32];
			menu.GetItem(param2, item, sizeof(item));
			if (StrEqual(item, "HideTag")) {
				if (g_bHideTag[param1]) {
					return RedrawMenuItem("Show Tag");
				}
			}

		}
	}
	return 0;
}

int MenuHandler_TagColor(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				DisplayColorMenu(MainMenu, param1);
			}
		}
		case MenuAction_Select: {
			char strBuffer[32];
			menu.GetItem(param2, strBuffer, sizeof(strBuffer));

			if (StrEqual(strBuffer, "Reset")) {
				PrintToChat(param1, "\x01[\x03CCC\x01] Tag color \x03reset");
				strcopy(g_strColor[param1][TAG], sizeof(g_strColor[][]), "");
				CCC_ResetColor(param1, CCC_TagColor);

				char strTag[7];
				IntToString(CCC_GetColor(param1, CCC_TagColor), strTag, sizeof(strTag));
				strcopy(g_strColor[param1][TAG], sizeof(g_strColor[][]), strTag);
			}
			else {
				int iColorIndex = StringToInt(strBuffer);
				PrintToChat(param1, "\x01[\x03CCC\x01] Tag color set to: \x07%s%s\x01", g_strColorHex[iColorIndex], g_strColorName[iColorIndex]);
				strcopy(g_strColor[param1][TAG], sizeof(g_strColor[][]), g_strColorHex[iColorIndex]);
				CCC_SetColor(param1, CCC_TagColor, StringToInt(g_strColorHex[iColorIndex], 16), false);
			}

			if (g_hSQL != null && IsClientAuthorized(param1)) {
				char strQuery[256];
				Format(strQuery, sizeof(strQuery), "SELECT tagcolor FROM cccm_users WHERE auth = '%s'", g_strAuth[param1]);
				g_hSQL.Query(SQLQuery_TagColor, strQuery, GetClientUserId(param1), DBPrio_High);
			}

			menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);			
		}
		case MenuAction_DrawItem: {
			char colorIndex[8];
			menu.GetItem(param2, colorIndex, sizeof(colorIndex));
			int i = StringToInt(colorIndex);
			if (!g_bColorAdminFlags[i] || (g_bColorAdminFlags[i] && HasAdminFlag(param1, g_iColorFlagList[i]))) {
				return ITEMDRAW_DEFAULT;
			}
			return ITEMDRAW_DISABLED;
		}
	}
	return 0;
}

int MenuHandler_NameColor(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				DisplayColorMenu(MainMenu, param1);
			}
		}
		case MenuAction_Select: {
			char strBuffer[32];
			menu.GetItem(param2, strBuffer, sizeof(strBuffer));

			if (StrEqual(strBuffer, "Reset")) {
				PrintToChat(param1, "\x01[\x03CCC\x01] Name color \x03reset");
				strcopy(g_strColor[param1][NAME], sizeof(g_strColor[][]), "");
				CCC_ResetColor(param1, CCC_NameColor);
			}
			else {
				int iColorIndex = StringToInt(strBuffer);
				PrintToChat(param1, "\x01[\x03CCC\x01] Name color set to: \x07%s%s\x01", g_strColorHex[iColorIndex], g_strColorName[iColorIndex]);
				strcopy(g_strColor[param1][NAME], sizeof(g_strColor[][]), g_strColorHex[iColorIndex]);
				CCC_SetColor(param1, CCC_NameColor, StringToInt(g_strColorHex[iColorIndex], 16), false);
			}

			if (g_hSQL != null && IsClientAuthorized(param1)) {
				char strQuery[256];
				Format(strQuery, sizeof(strQuery), "SELECT namecolor FROM cccm_users WHERE auth = '%s'", g_strAuth[param1]);
				g_hSQL.Query(SQLQuery_NameColor, strQuery, GetClientUserId(param1), DBPrio_High);
			}

			menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);			
		}
		case MenuAction_DrawItem: {
			char colorIndex[8];
			menu.GetItem(param2, colorIndex, sizeof(colorIndex));
			int i = StringToInt(colorIndex);
			if (!g_bColorAdminFlags[i] || (g_bColorAdminFlags[i] && HasAdminFlag(param1, g_iColorFlagList[i]))) {
				return ITEMDRAW_DEFAULT;
			}
			return ITEMDRAW_DISABLED;
		}
	}
	return 0;
}

int MenuHandler_ChatColor(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				DisplayColorMenu(MainMenu, param1);
			}
		}
		case MenuAction_Select: {
			char strBuffer[32];
			menu.GetItem(param2, strBuffer, sizeof(strBuffer));

			if (StrEqual(strBuffer, "Reset")) {
				PrintToChat(param1, "\x01[\x03CCC\x01] Chat color \x03reset");
				strcopy(g_strColor[param1][CHAT], sizeof(g_strColor[][]), "");
				CCC_ResetColor(param1, CCC_ChatColor);
			}
			else {
				int iColorIndex = StringToInt(strBuffer);
				PrintToChat(param1, "\x01[\x03CCC\x01] Chat color set to: \x07%s%s\x01", g_strColorHex[iColorIndex], g_strColorName[iColorIndex]);
				strcopy(g_strColor[param1][CHAT], sizeof(g_strColor[][]), g_strColorHex[iColorIndex]);
				CCC_SetColor(param1, CCC_ChatColor, StringToInt(g_strColorHex[iColorIndex], 16), false);
			}

			if (g_hSQL != null && IsClientAuthorized(param1)) {
				char strQuery[256];
				Format(strQuery, sizeof(strQuery), "SELECT chatcolor FROM cccm_users WHERE auth = '%s'", g_strAuth[param1]);
				g_hSQL.Query(SQLQuery_ChatColor, strQuery, GetClientUserId(param1), DBPrio_High);
			}

			menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);			
		}
		case MenuAction_DrawItem: {
			char colorIndex[8];
			menu.GetItem(param2, colorIndex, sizeof(colorIndex));
			int i = StringToInt(colorIndex);
			if (!g_bColorAdminFlags[i] || (g_bColorAdminFlags[i] && HasAdminFlag(param1, g_iColorFlagList[i]))) {
				return ITEMDRAW_DEFAULT;
			}
			return ITEMDRAW_DISABLED;
		}
	}
	return 0;
}

// ====[CONFIGURATION]=======================================================

void Config_Load() {
	if (!FileExists(g_strConfigFile)) {
		SetFailState("Configuration file %s not found!", g_strConfigFile);
		return;
	}

	KeyValues keyvalues = new KeyValues("CCC Menu Colors");
	if (!keyvalues.ImportFromFile(g_strConfigFile)) {
		SetFailState("Improper structure for configuration file %s!", g_strConfigFile);
		return;
	}

	if (!keyvalues.GotoFirstSubKey()) {
		SetFailState("Can't find configuration file %s!", g_strConfigFile);
		return;
	}

	for (int i = 0; i < MAX_COLORS; i++) {
		strcopy(g_strColorName[i], sizeof(g_strColorName[]), "");
		strcopy(g_strColorHex[i], sizeof(g_strColorHex[]), "");
		strcopy(g_strColorFlags[i], sizeof(g_strColorFlags[]), "");
		g_bColorAdminFlags[i] = false;
		for (int i2 = 0; i2 < 16; i2++) {
			g_iColorFlagList[i][i2] = view_as<AdminFlag>(-1);
		}
	}

	g_iColorCount = 0;
	do {
		keyvalues.GetString("name", g_strColorName[g_iColorCount], sizeof(g_strColorName[]));
		keyvalues.GetString("hex",	g_strColorHex[g_iColorCount], sizeof(g_strColorHex[]));
		ReplaceString(g_strColorHex[g_iColorCount], sizeof(g_strColorHex[]), "#", "", false);
		keyvalues.GetString("flags", g_strColorFlags[g_iColorCount], sizeof(g_strColorFlags[]));

		if (!IsValidHex(g_strColorHex[g_iColorCount])) {
			LogError("Invalid hexadecimal value for color %s.", g_strColorName[g_iColorCount]);
			strcopy(g_strColorName[g_iColorCount], sizeof(g_strColorName[]), "");
			strcopy(g_strColorHex[g_iColorCount], sizeof(g_strColorHex[]), "");
			strcopy(g_strColorFlags[g_iColorCount], sizeof(g_strColorFlags[]), "");
		}

		if (!StrEqual(g_strColorFlags[g_iColorCount], "")) {
			g_bColorAdminFlags[g_iColorCount] = true;
			FlagBitsToArray(ReadFlagString(g_strColorFlags[g_iColorCount]), g_iColorFlagList[g_iColorCount], sizeof(g_iColorFlagList[]));
		}
		g_iColorCount++;
	} while (keyvalues.GotoNextKey());
	delete keyvalues;

	BuildMainMenu();
	BuildTagMenu();
	BuildNameMenu();
	BuildChatMenu();

	LogMessage("Loaded %i colors from configuration file %s.", g_iColorCount, g_strConfigFile);
}

// ====[SQL QUERIES]=========================================================

void SQLQuery_Connect(Database db, const char[] error, any data) {
	if (db == null) {
		return;
	}

	g_hSQL = db;

	DBDriver driverType = g_hSQL.Driver; 
	driverType.GetProduct(g_strSQLDriver, sizeof(g_strSQLDriver));

	if (StrEqual(g_strSQLDriver, "mysql", false)) {
		LogMessage("MySQL server configured. Variable saving enabled.");
		g_hSQL.Query(
			SQLQuery_Update
			, "CREATE TABLE IF NOT EXISTS cccm_users"
			... "("
			... "id INT(64) NOT NULL AUTO_INCREMENT, "
			... "auth VARCHAR(32) UNIQUE, "
			... "hidetag VARCHAR(1), "
			... "tagcolor VARCHAR(7), "
			... "namecolor VARCHAR(7), "
			... "chatcolor VARCHAR(7), "
			... "PRIMARY KEY (id)"
			... ")"
			, _
			, DBPrio_High
		);
	}
	else if (StrEqual(g_strSQLDriver, "sqlite", false)) {
		LogMessage("SQlite server configured. Variable saving enabled.");
		g_hSQL.Query(
			SQLQuery_Update
			, "CREATE TABLE IF NOT EXISTS cccm_users "
			... "("
			... "id INTERGER PRIMARY KEY, "
			... "auth varchar(32) UNIQUE, "
			... "hidetag varchar(1), "
			... "tagcolor varchar(7), "
			... "namecolor varchar(7), "
			... "chatcolor varchar(7)"
			... ")"
			, _
			, DBPrio_High
		);
	}
	else {
		LogMessage("Saved variable server not configured. Variable saving disabled.");
		return;
	}

	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			SQL_LoadColors(i);
		}
	}
}

void SQLQuery_LoadColors(Database db, DBResultSet results, const char[] error, any data) {
	int client = GetClientOfUserId(data);
	if (!IsValidClient(client)) {
		return;
	}

	if (db == null || results == null) {
		LogError("SQL Error: %s", error);
		return;
	}

	if (results.FetchRow() && results.RowCount != 0) {
		g_bHideTag[client] = view_as<bool>(results.FetchInt(0));

		char strTag[7], strName[7], strChat[7];
		results.FetchString(1, strTag, sizeof(strTag));
		if (IsValidHex(strTag)) {
			strcopy(g_strColor[client][TAG], sizeof(g_strColor[][]), strTag);
			CCC_SetColor(client, CCC_TagColor, StringToInt(g_strColor[client][TAG], 16), false);
		}
		else if (StrEqual(strTag, "-1")) {
			strcopy(g_strColor[client][TAG], sizeof(g_strColor[][]), "-1");
		}

		results.FetchString(2, strName, sizeof(strName));
		if (IsValidHex(strName)) {
			strcopy(g_strColor[client][NAME], sizeof(g_strColor[][]), strName);
			CCC_SetColor(client, CCC_NameColor, StringToInt(g_strColor[client][NAME], 16), false);
		}

		results.FetchString(3, strChat, sizeof(strChat));
		if (IsValidHex(strChat)) {
			strcopy(g_strColor[client][CHAT], sizeof(g_strColor[][]), strChat);
			CCC_SetColor(client, CCC_ChatColor, StringToInt(g_strColor[client][CHAT], 16), false);
		}

		g_bColorsLoaded[client] = true;
	}
}

void SQLQuery_HideTag(Database db, DBResultSet results, const char[] error, any data) {
	int client = GetClientOfUserId(data);
	if (!IsValidClient(client)) {
		return;
	}

	if (db == null || results == null) {
		LogError("SQL Error: %s", error);
		return;
	}

	if (results.RowCount == 0) {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "INSERT INTO cccm_users (hidetag, auth) VALUES (%i, '%s')", g_bHideTag[client], g_strAuth[client]);
		g_hSQL.Query(SQLQuery_Update, strQuery, _, DBPrio_High);
	}
	else {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "UPDATE cccm_users SET hidetag = '%i' WHERE auth = '%s'", g_bHideTag[client], g_strAuth[client]);
		g_hSQL.Query(SQLQuery_Update, strQuery, _, DBPrio_Normal);
	}
}

void SQLQuery_TagColor(Database db, DBResultSet results, const char[] error, any data) {
	int client = GetClientOfUserId(data);
	if (!IsValidClient(client)) {
		return;
	}

	if (db == null || results == null) {
		LogError("SQL Error: %s", error);
		return;
	}

	if (results.RowCount == 0) {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "INSERT INTO cccm_users (tagcolor, auth) VALUES ('%s', '%s')", g_strColor[client][TAG], g_strAuth[client]);
		g_hSQL.Query(SQLQuery_Update, strQuery, _, DBPrio_High);
	}
	else {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "UPDATE cccm_users SET tagcolor = '%s' WHERE auth = '%s'", g_strColor[client][TAG], g_strAuth[client]);
		g_hSQL.Query(SQLQuery_Update, strQuery, _, DBPrio_Normal);
	}
}

void SQLQuery_NameColor(Database db, DBResultSet results, const char[] error, any data) {
	int client = GetClientOfUserId(data);
	if (!IsValidClient(client)) {
		return;
	}

	if (db == null || results == null) {
		LogError("SQL Error: %s", error);
		return;
	}

	if (results.RowCount == 0) {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "INSERT INTO cccm_users (namecolor, auth) VALUES ('%s', '%s')", g_strColor[client][NAME], g_strAuth[client]);
		g_hSQL.Query(SQLQuery_Update, strQuery, _, DBPrio_High);
	}
	else {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "UPDATE cccm_users SET namecolor = '%s' WHERE auth = '%s'", g_strColor[client][NAME], g_strAuth[client]);
		g_hSQL.Query(SQLQuery_Update, strQuery, _, DBPrio_Normal);
	}
}

void SQLQuery_ChatColor(Database db, DBResultSet results, const char[] error, any data) {
	int client = GetClientOfUserId(data);
	if (!IsValidClient(client)) {
		return;
	}

	if (db == null || results == null) {
		LogError("SQL Error: %s", error);
		return;
	}

	if (results.RowCount == 0) {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "INSERT INTO cccm_users (chatcolor, auth) VALUES ('%s', '%s')", g_strColor[client][CHAT], g_strAuth[client]);
		g_hSQL.Query(SQLQuery_Update, strQuery, _, DBPrio_High);
	}
	else {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "UPDATE cccm_users SET chatcolor = '%s' WHERE auth = '%s'", g_strColor[client][CHAT], g_strAuth[client]);
		g_hSQL.Query(SQLQuery_Update, strQuery, _, DBPrio_Normal);
	}
}

void SQLQuery_Update(Handle owner, Handle hndl, const char[] strError, any data) {
	if (hndl == null) {
		LogError("SQL Error: %s", strError);
	}
}
// ====[STOCKS]==============================================================
bool IsValidClient(int client) {
	return (client > 0 || client <= MaxClients || IsClientInGame(client));
}

bool IsValidHex(const char[] hex) {
	return (strlen(hex) == 6 && g_hRegexHex.Match(hex));
}

bool HasAdminFlag(int client, const AdminFlag flaglist[16]) {
	int flags = GetUserFlagBits(client);
	if (flags & ADMFLAG_ROOT) {
		return true;
	}

	for (int i = 0; i < sizeof(flaglist); i++) {
		if (flags & FlagToBit(flaglist[i])) {
			return true;
		}
	}
	return false;
}