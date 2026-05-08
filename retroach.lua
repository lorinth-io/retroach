addon.name      = 'retroach';
addon.author    = 'lorinth';
addon.version   = '1.0';
addon.desc      = 'Loads your achievement progress from retro achievements.';

require 'common';
local settings  = require('settings');
local http 		= require('socket.http');
local fonts 	= require('fonts');
local json 		= require('json');
local imgui 	= require('imgui');
local ffi 		= require('ffi');
local C         = ffi.C;
local d3d       = require('d3d8');
local d3d8dev   = d3d.get_device();

local gameSetIds = T{
	BaseGame = T{
		GameId = 28275,
		Icon = 'icons/basegame.png',
		Name = 'Final Fantasy XI',
		Texture = ''
	},
	HeroOfNations = T{
		GameId = 28303,
		SetId = 9299,
		Icon = 'icons/heroofnations.png',
		Name = 'Hero of Nations',
		Texture = ''
	},
	RiseOfTheZilart = T{
		GameId = 28317,
		Icon = 'icons/riseofthezilart.png',
		Name = 'Rise of the Zilart',
		Texture = ''
	},
	HardcoreHero = T{ 
		GameId = 28547,
		SetId = 9347,
		Icon = 'icons/hardcorehero.png',
		Name = 'Hardcore Hero',
		Texture = ''
	},
};

-- Default Settings
local default_settings = T{
    font = T{
        visible = true,
        font_family = 'Arial',
        font_height = 12,
        color = 0xFFFF0000,
        position_x = 1,
        position_y = 1,
    },
    retroach = T{
        name = '',
        apiKey = '',
    },
};

-- Variables
local retroach = T{
    font = nil,
    show = true,
    settings = settings.load(default_settings)
};

local gameOrder = T{
    'BaseGame',
    'HeroOfNations',
    'RiseOfTheZilart',
    'HardcoreHero',
};

local gameProgressData = {};
local selectedGameKey = nil;
local viewSplash = false;
local iconTextures = {};
local retroAchData = nil;
local viewAchievements = false;
local viewSetup = false;

local achievementSearch = achievementSearch or { '' };
local selectedAchievementIndex = selectedAchievementIndex or 1;
local hideUnlocked = hideUnlocked or { false };

-- Setup form buffers
local setupName = setupName or { '' };
local setupApiKey = setupApiKey or { '' };
local setupMessage = '';
local setupMessageColor = { 0.80, 0.80, 0.80, 1.00 };

--[[ 
* Updates the addon settings.
*
* @param {table} s - The new settings table to use for the addon settings. (Optional.)
--]]
local function update_settings(s)
    -- Update the settings table.
    if (s ~= nil) then
        retroach.settings = s;
    end

    -- Apply the font settings.
    if (retroach.font ~= nil) then
        retroach.font:apply(retroach.settings.font);
    end

    -- Save the current settings.
    settings.save();
end

function LoadTexture(textureName)
    local textures = T{};
    local fullPath = string.format('%s/%s', addon.path, textureName);

    local texture_ptr = ffi.new('IDirect3DTexture8*[1]');
    local res = C.D3DXCreateTextureFromFileA(d3d8dev, fullPath, texture_ptr);
    if (res ~= C.S_OK) then
        print(('Failed to load image texture: %08X (%s) path=%s'):format(res, d3d.get_error(res), fullPath));
        return nil;
    end

    textures.image = ffi.new('IDirect3DTexture8*', texture_ptr[0]);
    d3d.gc_safe_release(textures.image);

    return textures;
end

local function refresh_setup_buffers()
    setupName[1] = retroach.settings.retroach.name or '';
    setupApiKey[1] = retroach.settings.retroach.apiKey or '';
end

local function open_setup_window()
    refresh_setup_buffers();
    setupMessage = '';
    viewSetup = true;
end

local function save_setup()
    local name = setupName[1] or '';
    local apiKey = setupApiKey[1] or '';

    retroach.settings.retroach.name = name;
    retroach.settings.retroach.apiKey = apiKey;
    update_settings(retroach.settings);

    setupMessage = 'Settings saved.';
    setupMessageColor = { 0.45, 0.95, 0.50, 1.00 };
end

local function has_credentials()
    local apiKey = retroach.settings
        and retroach.settings.retroach
        and retroach.settings.retroach.apiKey
        or '';

    local name = retroach.settings
        and retroach.settings.retroach
        and retroach.settings.retroach.name
        or '';

    return name ~= '' and apiKey ~= '';
end

local function get_progress_values(data)
    local awarded = 0;
    local total = 0;
    local percent = 0.0;

    if (data ~= nil) then
        awarded = data.NumAwardedToUser or 0;
        total = data.NumAchievements or 0;

        if (total > 0) then
            percent = awarded / total;
        end
    end

    return awarded, total, percent;
end

local function select_game(gameKey)
    local game = gameSetIds[gameKey];
    if (game == nil) then
        return;
    end

    retroAchData = gameProgressData[gameKey];
    selectedGameKey = gameKey;
    viewAchievements = (retroAchData ~= nil);
end

local function get_game_info(gameId, updateSelectedView)
    local apiKey = retroach and retroach.settings and retroach.settings.retroach and retroach.settings.retroach.apiKey;
    local name   = retroach and retroach.settings and retroach.settings.retroach and retroach.settings.retroach.name;

    if (apiKey == nil or apiKey == '' or name == nil or name == '') then
        setupMessage = 'Missing RetroAchievements name or API key. Use /retroach setup.';
        setupMessageColor = { 0.95, 0.45, 0.45, 1.00 };
        viewSetup = true;
        return nil, 0, nil, 'Missing credentials';
    end

    assert(gameId, 'gameId is nil');

    local request_url = 'https://retroachievements.org/API/API_GetGameInfoAndUserProgress.php?a=1';
    request_url = request_url .. '&y=' .. tostring(apiKey);
    request_url = request_url .. '&u=' .. tostring(name);
    request_url = request_url .. '&g=' .. tostring(gameId);

    local body, code, headers, status = http.request(request_url);

    if (body ~= nil and code == 200) then
        local decoded = json.decode(body);

        if (updateSelectedView == true) then
            retroAchData = decoded;
            viewAchievements = true;
            setupMessage = '';
        end

        return decoded, code, headers, status;
    end

    setupMessage = 'Failed to load achievement data. HTTP code: ' .. tostring(code);
    setupMessageColor = { 0.95, 0.45, 0.45, 1.00 };
    return nil, code, headers, status;
end

local function load_all_game_progress(force)
	if force or next(gameProgressData) == nil then
		gameProgressData = {};
		retroAchData = nil;
		viewAchievements = false;
		viewSplash = false;
		selectedGameKey = nil;

		for i = 1, #gameOrder do
			local gameKey = gameOrder[i];
			local game = gameSetIds[gameKey];

			if (game ~= nil and game.GameId ~= nil) then
				local decoded = get_game_info(game.GameId, false);
				gameProgressData[gameKey] = decoded;
			end
		end
	end

    viewSplash = true;
    setupMessage = '';
end

--[[ 
* Registers a callback for the settings to monitor for character switches.
--]]
settings.register('settings', 'settings_update', update_settings);

--[[ 
* event: load
* desc : Event called when the addon is being loaded.
--]]
ashita.events.register('load', 'load_cb', function ()
    retroach.font = fonts.new(retroach.settings.font);
    refresh_setup_buffers();
	
    for _, record in pairs(gameSetIds) do
        record.Texture = nil;

        if (record.Icon ~= nil and record.Icon ~= '') then
            local texture = LoadTexture(record.Icon);
            if (texture ~= nil and texture.image ~= nil) then
                record.Texture = texture;
            end
        end
    end
end);

--[[ 
* event: unload
* desc : Event called when the addon is being unloaded.
--]]
ashita.events.register('unload', 'unload_cb', function ()
    if (retroach.font ~= nil) then
        retroach.font:destroy();
        retroach.font = nil;
    end

    settings.save();
end);

function loadSplash() 
	if (not has_credentials()) then
		open_setup_window();
		setupMessage = 'Please enter your RetroAchievements name and API key first.';
		setupMessageColor = { 1.00, 0.82, 0.25, 1.00 };
		return;
	end

	load_all_game_progress();
end

--[[ 
* event: command
* desc : Event called when the addon is processing a command.
--]]
ashita.events.register('command', 'command_cb', function (e)
    local args = e.command:args();
    if (#args == 0 or args[1] ~= '/retroach') then
        return;
    end

    e.blocked = true;

    if (#args == 1) then
        loadSplash();
        return;
    end

    local sub = args[2]:lower();

    if (sub == 'setup') then
        open_setup_window();
        return;
    end

    if (sub == 'load') then
        loadSplash();
        return;
    end
end);

local function push_retro_style()
    -- Colors
    imgui.PushStyleColor(ImGuiCol_WindowBg,      { 0.10, 0.11, 0.13, 0.96 });
    imgui.PushStyleColor(ImGuiCol_ChildBg,       { 0.14, 0.15, 0.18, 0.92 });
    imgui.PushStyleColor(ImGuiCol_Border,        { 0.24, 0.27, 0.32, 1.00 });
    imgui.PushStyleColor(ImGuiCol_TitleBg,       { 0.12, 0.13, 0.16, 1.00 });
    imgui.PushStyleColor(ImGuiCol_TitleBgActive, { 0.16, 0.17, 0.21, 1.00 });
    imgui.PushStyleColor(ImGuiCol_FrameBg,       { 0.18, 0.19, 0.23, 1.00 });
    imgui.PushStyleColor(ImGuiCol_FrameBgHovered,{ 0.24, 0.27, 0.34, 1.00 });
    imgui.PushStyleColor(ImGuiCol_FrameBgActive, { 0.28, 0.31, 0.38, 1.00 });
    imgui.PushStyleColor(ImGuiCol_Button,        { 0.22, 0.25, 0.31, 1.00 });
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.30, 0.36, 0.46, 1.00 });
    imgui.PushStyleColor(ImGuiCol_ButtonActive,  { 0.36, 0.42, 0.52, 1.00 });
    imgui.PushStyleColor(ImGuiCol_Header,        { 0.22, 0.25, 0.31, 1.00 });
    imgui.PushStyleColor(ImGuiCol_HeaderHovered, { 0.30, 0.36, 0.46, 1.00 });
    imgui.PushStyleColor(ImGuiCol_HeaderActive,  { 0.36, 0.42, 0.52, 1.00 });
    imgui.PushStyleColor(ImGuiCol_Separator,     { 0.24, 0.27, 0.32, 1.00 });
    imgui.PushStyleColor(ImGuiCol_CheckMark,     { 0.95, 0.82, 0.30, 1.00 });
    imgui.PushStyleColor(ImGuiCol_SliderGrab,    { 0.95, 0.82, 0.30, 1.00 });
    imgui.PushStyleColor(ImGuiCol_SliderGrabActive, { 1.00, 0.88, 0.40, 1.00 });
	imgui.PushStyleColor(ImGuiCol_TextSelectedBg, { 0.30, 0.36, 0.46, 0.55 });
	imgui.PushStyleColor(ImGuiCol_PlotHistogram,        { 0.95, 0.82, 0.30, 1.00 });
	imgui.PushStyleColor(ImGuiCol_PlotHistogramHovered, { 1.00, 0.88, 0.40, 1.00 });
	imgui.PushStyleColor(ImGuiCol_ScrollbarBg,       { 0.12, 0.13, 0.16, 0.90 });
	imgui.PushStyleColor(ImGuiCol_ScrollbarGrab,     { 0.35, 0.60, 0.95, 1.00 });
	imgui.PushStyleColor(ImGuiCol_ScrollbarGrabHovered, { 0.45, 0.72, 1.00, 1.00 });
	imgui.PushStyleColor(ImGuiCol_ScrollbarGrabActive,  { 0.55, 0.82, 1.00, 1.00 });
	imgui.PushStyleColor(ImGuiCol_ResizeGrip,        { 0.35, 0.60, 0.95, 0.40 });
	imgui.PushStyleColor(ImGuiCol_ResizeGripHovered, { 0.45, 0.72, 1.00, 0.75 });
	imgui.PushStyleColor(ImGuiCol_ResizeGripActive,  { 0.55, 0.82, 1.00, 1.00 });
	
	-- Rounding
	imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 8.0);
	imgui.PushStyleVar(ImGuiStyleVar_ChildRounding, 8.0);
	imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 6.0);

    -- Layout / sizing
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 14, 14 });
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding,  { 10, 6 });
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing,   { 10, 8 });
    imgui.PushStyleVar(ImGuiStyleVar_ItemInnerSpacing, { 8, 6 });
    imgui.PushStyleVar(ImGuiStyleVar_ChildBorderSize, 1.0);
    imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 1.0);
end

local function pop_retro_style()
    imgui.PopStyleVar(9);
    imgui.PopStyleColor(28);
end

local function render_highest_award_progressbar(percent, size, highestAwardKind)
	if type(highestAwardKind) == 'string' and highestAwardKind == 'mastered' then
		imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 0.95, 0.82, 0.30, 1.00 });
		imgui.PushStyleColor(ImGuiCol_PlotHistogramHovered, { 1.00, 0.88, 0.40, 1.00 });
		imgui.PushStyleColor(ImGuiCol_FrameBg, { 0.24, 0.21, 0.12, 1.00 });
		imgui.PushStyleColor(ImGuiCol_Text, { 0.08, 0.10, 0.14, 1.00 });
	elseif type(highestAwardKind) == 'string' and string.match(highestAwardKind, 'beaten') then
		imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 0.75, 0.78, 0.84, 1.00 });
		imgui.PushStyleColor(ImGuiCol_PlotHistogramHovered, { 0.86, 0.89, 0.94, 1.00 });
		imgui.PushStyleColor(ImGuiCol_FrameBg, { 0.20, 0.22, 0.26, 1.00 });
		imgui.PushStyleColor(ImGuiCol_Text, { 0.08, 0.10, 0.14, 1.00 });
	else
		imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 0.35, 0.60, 0.95, 1.00 });
		imgui.PushStyleColor(ImGuiCol_PlotHistogramHovered, { 0.45, 0.72, 1.00, 1.00 });
		imgui.PushStyleColor(ImGuiCol_FrameBg, { 0.14, 0.18, 0.26, 1.00 });
		imgui.PushStyleColor(ImGuiCol_Text, { 0.96, 0.97, 1.00, 1.00 });
	end
	imgui.ProgressBar(percent, size, '');
	imgui.PopStyleColor(4);
end

local setupWindowOpen = T{};
local function render_setup_window()
    if (not viewSetup) then
        return;
    end
	
    push_retro_style();

    imgui.SetNextWindowBgAlpha(0.96);
    imgui.SetNextWindowSize({ 480, 270 });

    setupWindowOpen[1] = viewSetup;
    imgui.Begin('Retro Achievements Setup', setupWindowOpen);

    if (not setupWindowOpen[1]) then
        viewSetup = false;
    end

    imgui.TextColored({ 1.00, 0.84, 0.25, 1.00 }, 'RetroAchievements Setup');
    imgui.Spacing();
    imgui.TextWrapped('Enter your RetroAchievements username and Web API key. These values will be saved to your addon settings.');

    imgui.Spacing();
    imgui.InputText('Name', setupName, 128);
    imgui.InputText('API Key', setupApiKey, 256);

    imgui.Spacing();

    if (imgui.Button('Save')) then
        save_setup();
    end

    imgui.SameLine();

    if (imgui.Button('Save && Load')) then
        save_setup();
        load_all_game_progress();
    end

    imgui.SameLine();

    if (imgui.Button('Close')) then
        viewSetup = false;
        setupMessage = '';
    end

    if (setupMessage ~= '') then
        imgui.Spacing();
        imgui.TextColored(setupMessageColor, setupMessage);
    end

    imgui.Spacing();
    imgui.Separator();
    imgui.TextColored({ 0.70, 0.70, 0.75, 1.00 }, 'Command: /retroach setup');

    imgui.End();
    pop_retro_style();
end

local splashWindowOpen = T{};
local function render_splash_window()
    if (not viewSplash) then
        return;
    end
	
    push_retro_style();

    imgui.SetNextWindowBgAlpha(0.96);
    imgui.SetNextWindowSize({ 980, 420 }, ImGuiCond_FirstUseEver);

    splashWindowOpen[1] = viewSplash;
    imgui.Begin('Retro Achievements Games', splashWindowOpen);

    if (not splashWindowOpen[1]) then
        viewSplash = false;
    end

    imgui.PushStyleColor(ImGuiCol_Text, { 1.00, 0.84, 0.25, 1.00 });
    imgui.Text('RetroAchievements Game Hub');
    imgui.PopStyleColor();
	
    local totalAwardedAll = 0;
    local totalAchievementsAll = 0;

    for i = 1, #gameOrder do
        local gameKey = gameOrder[i];
        local data = gameProgressData[gameKey];
        local awarded, total = get_progress_values(data);

        totalAwardedAll = totalAwardedAll + awarded;
        totalAchievementsAll = totalAchievementsAll + total;
    end

    local totalPercentAll = 0.0;
    if (totalAchievementsAll > 0) then
        totalPercentAll = totalAwardedAll / totalAchievementsAll;
    end

    imgui.Spacing();
	imgui.TextColored({ 0.95, 0.90, 0.55, 1.00 }, 'Overall Progress');
	imgui.SameLine();
	imgui.TextColored({ 0.55, 0.85, 1.00, 1.00 }, string.format('%d / %d', totalAwardedAll, totalAchievementsAll));
	imgui.SameLine();
	imgui.TextColored({ 0.95, 0.90, 0.55, 1.00 }, string.format('(%s', string.format('%.1f%%', totalPercentAll * 100.0)) .. '%)');

	imgui.PushStyleColor(ImGuiCol_FrameBg, { 0.24, 0.21, 0.12, 1.00 });
	imgui.PushStyleColor(ImGuiCol_PlotHistogram, { 0.95, 0.82, 0.30, 1.00 });
	imgui.ProgressBar(totalPercentAll, { -1, 22 }, '');
	imgui.PopStyleColor(2);

	imgui.TextColored({ 0.60, 0.62, 0.68, 1.00 }, 'Achievements unlocked across all sets');

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    local availableWidth = imgui.GetContentRegionAvail();
    local spacing = 12;
    local cardWidth = math.floor((availableWidth - spacing) / 2);
    local cardHeight = 160;
    local iconSize = 96;

	for i = 1, #gameOrder do
		local gameKey = gameOrder[i];
		local game = gameSetIds[gameKey];
		local data = gameProgressData[gameKey];

		local awarded, total, percent = get_progress_values(data);
		local highestAwardKind = data.HighestAwardKind or '';

		imgui.BeginChild('game_card_' .. tostring(gameKey), { cardWidth, cardHeight }, true);

		local cardHovered = imgui.IsWindowHovered();

		if (cardHovered) then
			imgui.PushStyleColor(ImGuiCol_Text, { 1.00, 0.95, 0.70, 1.00 });
		else
			imgui.PushStyleColor(ImGuiCol_Text, { 0.95, 0.90, 0.55, 1.00 });
		end
		imgui.Text(game.Name or gameKey);
		imgui.PopStyleColor();

		imgui.Spacing();

		if (game.Texture ~= nil) then
			imgui.Image(tonumber(ffi.cast('uint32_t', game.Texture.image)), { iconSize, iconSize });
		else
			imgui.BeginChild('missing_icon_' .. tostring(gameKey), { iconSize, iconSize }, true);
			imgui.TextColored({ 0.55, 0.75, 1.00, 1.00 }, 'No Icon');
			imgui.EndChild();
		end

		imgui.SameLine();

		local startX, startY = imgui.GetCursorPos();

		imgui.SetCursorPos({ startX, startY + 4 });
		imgui.TextColored({ 0.70, 0.70, 0.75, 1.00 }, string.format('%d of %d unlocked (%s', awarded, total, string.format('%.1f%%', percent * 100.0)) .. '%)');

		imgui.SetCursorPos({ startX, startY + 28 });
		
		render_highest_award_progressbar(percent, { -1, 16 }, highestAwardKind);

		imgui.SetCursorPos({ startX, startY + 54 });
		if (cardHovered) then
			imgui.TextColored({ 0.55, 0.85, 1.00, 1.00 }, 'Open achievements');
		else
			imgui.TextColored({ 0.45, 0.45, 0.50, 1.00 }, 'Open achievements');
		end

		imgui.EndChild();

		if (imgui.IsItemHovered() and imgui.IsMouseClicked(0)) then
			select_game(gameKey);
			viewSplash = false;
			return;
		end

		if ((i % 2) == 1 and i < #gameOrder) then
			imgui.SameLine();
		end
	end

    imgui.End();
    pop_retro_style();
end

local achievementWindowOpen = T{};
local function render_achievement_window()
    if (retroAchData == nil or not viewAchievements) then
        return;
    end
	
    push_retro_style();

    local awarded = retroAchData.NumAwardedToUser or 0;
    local total = retroAchData.NumAchievements or 0;
	local highestAwardKind = retroAchData.HighestAwardKind or '';
    local percent = 0.0;

    if (total > 0) then
        percent = awarded / total;
    end

    imgui.SetNextWindowBgAlpha(0.96);
    imgui.SetNextWindowSize({ 980, 620 });

	achievementWindowOpen[1] = viewAchievements;
	imgui.Begin('Retro Achievements', achievementWindowOpen);

	if (not achievementWindowOpen[1]) then
		viewAchievements = false;
	end

    imgui.PushStyleColor(ImGuiCol_Text, { 1.00, 0.84, 0.25, 1.00 });
    local selectedName = 'Retro Achievements';
	if (selectedGameKey ~= nil and gameSetIds[selectedGameKey] ~= nil) then
		selectedName = 'Retro Achievements - ' .. tostring(gameSetIds[selectedGameKey].Name or selectedGameKey);
	end

	imgui.Text(selectedName);
	if (imgui.Button('Back to Games')) then
		viewSplash = true;
		viewAchievements = false;
		retroAchData = nil;
		selectedGameKey = nil;
		return;
	end

	imgui.SameLine();
    imgui.PopStyleColor();

    imgui.Spacing();
    imgui.Text(string.format('%d of %d unlocked', awarded, total));
    imgui.SameLine();
    imgui.TextColored({ 0.55, 0.85, 1.00, 1.00 }, string.format('(%.1f%%)', percent * 100.0));
	
	render_highest_award_progressbar(percent, { -1, 18 }, highestAwardKind);

    imgui.Spacing();

    local changed = imgui.InputText('Search', achievementSearch, 256);
    if (changed) then
        selectedAchievementIndex = 1;
    end

	imgui.SameLine();
	local hideChanged = imgui.Checkbox('Hide Unlocked', hideUnlocked);
	if (hideChanged) then
		selectedAchievementIndex = 1;
	end

    local searchText = achievementSearch[1] or '';
    local searchLower = string.lower(searchText);

    local filtered = { };

    for k, v in pairs(retroAchData.Achievements or { }) do
        local title = v.Title or 'Unknown Achievement';
        local description = v.Description or '';
        local points = v.Points or 0;
        local unlocked = (v.Unlocked == true) or (v.DateEarned ~= nil) or (v.HardcoreDateEarned ~= nil);

        local matchesSearch = true;
        if (searchLower ~= '') then
            local titleLower = string.lower(title);
            local descLower = string.lower(description);

            matchesSearch =
                (string.find(titleLower, searchLower, 1, true) ~= nil) or
                (string.find(descLower, searchLower, 1, true) ~= nil);
        end

        local passesUnlockedFilter = true;
        if (hideUnlocked[1] and unlocked) then
            passesUnlockedFilter = false;
        end

        if (matchesSearch and passesUnlockedFilter) then
            table.insert(filtered, {
                Title = title,
                Description = description,
                Points = points,
                Unlocked = unlocked,
                Raw = v
            });
        end
    end

    table.sort(filtered, function(a, b)
        if (a.Unlocked ~= b.Unlocked) then
            return a.Unlocked and not b.Unlocked;
        end
        if (a.Points ~= b.Points) then
            return a.Points > b.Points;
        end
        return a.Title < b.Title;
    end);

    if (#filtered == 0) then
        selectedAchievementIndex = 1;
    elseif (selectedAchievementIndex > #filtered) then
        selectedAchievementIndex = #filtered;
    elseif (selectedAchievementIndex < 1) then
        selectedAchievementIndex = 1;
    end

    imgui.SameLine();
    imgui.TextColored({ 0.70, 0.70, 0.75, 1.00 }, string.format('%d shown', #filtered));

    imgui.Spacing();
    imgui.Separator();
    imgui.Spacing();

    imgui.BeginChild('achievement_list_pane', { 420, 0 }, true);

    for i = 1, #filtered do
        local a = filtered[i];
        local metaColor = a.Unlocked and { 0.95, 0.84, 0.30, 1.00 } or { 0.65, 0.65, 0.70, 1.00 };

        if (imgui.Selectable(a.Title .. '##achievement_' .. tostring(i), selectedAchievementIndex == i)) then
            selectedAchievementIndex = i;
        end

        imgui.Indent(12);
        imgui.PushStyleColor(ImGuiCol_Text, metaColor);
        imgui.Text((a.Unlocked and 'Unlocked' or 'Locked') .. ' | ' .. tostring(a.Points) .. ' pts');
        imgui.PopStyleColor();
        imgui.Unindent(12);

        if (i < #filtered) then
            imgui.Separator();
        end
    end

    imgui.EndChild();

    imgui.SameLine();

    imgui.BeginChild('achievement_detail_pane', { 0, 0 }, true);

    if (#filtered > 0) then
        local current = filtered[selectedAchievementIndex];
        local raw = current.Raw;

        imgui.PushStyleColor(ImGuiCol_Text, current.Unlocked and { 0.45, 0.95, 0.50, 1.00 } or { 1.00, 0.88, 0.35, 1.00 });
        imgui.Text(current.Title);
        imgui.PopStyleColor();

        imgui.Spacing();
        imgui.Text('Points: ' .. tostring(current.Points));
        imgui.TextColored(
            current.Unlocked and { 0.45, 0.95, 0.50, 1.00 } or { 0.85, 0.40, 0.40, 1.00 },
            'Status: ' .. (current.Unlocked and 'Unlocked' or 'Locked')
        );

        if (raw.DateEarned ~= nil) then
            imgui.TextColored({ 0.70, 0.80, 1.00, 1.00 }, 'Earned: ' .. tostring(raw.DateEarned));
        end

        if (raw.HardcoreDateEarned ~= nil) then
            imgui.TextColored({ 1.00, 0.65, 0.35, 1.00 }, 'Hardcore Earned: ' .. tostring(raw.HardcoreDateEarned));
        end

        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();

        imgui.PushTextWrapPos();
        imgui.TextColored({ 0.82, 0.84, 0.90, 1.00 }, current.Description ~= '' and current.Description or 'No description.');
        imgui.PopTextWrapPos();

        imgui.Spacing();
        imgui.Separator();
        imgui.Spacing();
    else
        imgui.TextColored({ 0.85, 0.45, 0.45, 1.00 }, 'No achievements match your search.');
    end

    imgui.EndChild();
    imgui.End();
    pop_retro_style();
end

--[[ 
* event: d3d_present
* desc : Event called when the Direct3D device is presenting a scene.
--]]
ashita.events.register('d3d_present', 'present_cb', function ()
    render_setup_window();
    render_splash_window();
    render_achievement_window();
end);