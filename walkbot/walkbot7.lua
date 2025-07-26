-- Version 7.0
local json_lib_file = "UlquiorraStore/Libraries/Json.lua"
local walkbot_record_file = "UlquiorraStore/Walkbot/WalkBotRoutes.txt" 
local function FileCreator()
    local exists_json_lib_file = false
    local exists_walkbot_record_file = false

    file.Enumerate(function(all_files)
        if all_files == json_lib_file then
            exists_json_lib_file = true
        end
        if all_files == walkbot_record_file then
            exists_walkbot_record_file = true
        end 
    end)

    if not exists_json_lib_file then
        local body = http.Get("https://raw.githubusercontent.com/blackscuro23b/aimware2025/refs/heads/main/Json.lua") 
        file.Write(json_lib_file, body) 
    end

    if not exists_walkbot_record_file then
        local body = http.Get("https://raw.githubusercontent.com/blackscuro23b/aimware2025/refs/heads/main/routes.txt")
        file.Write(walkbot_record_file, body or "{}")
    end
end
FileCreator()
RunScript(json_lib_file)


-- =================== LOGS FUNCTIONS =================== 

local logs = { info = {}, error = {} }
local LOG_DURATION = 1200
local frame = 0
local show_info = true
local show_error = true

function add_info_log(message)
    table.insert(logs.info, { message = message, frame = frame })
end

function add_error_log(message)
    table.insert(logs.error, { message = message, frame = frame })
end

-- =================== WALKBOT FUNCTIONS =================== 

local walk_data = {}
local play_index = 1
local is_playing = false
local is_recording = false
local walkbot_saved_names = ""

local function get_saved_walkbot_names()
    local contents = json.decode(file.Read(walkbot_record_file)) or {}
    local ordered_names = {}
    for route_name in pairs(contents) do
        table.insert(ordered_names, route_name)
    end
    table.sort(ordered_names)
    if #ordered_names == 0 then
        return { "-- No routes --" }
    end
    return ordered_names
end
walkbot_saved_names = get_saved_walkbot_names()

local function get_saved_walkbot_data(index)
    local contents = json.decode(file.Read(walkbot_record_file))
    local ordered_names = {}
    for route_name in pairs(contents) do
        table.insert(ordered_names, route_name)
    end
    table.sort(ordered_names)

    for i, route_name in ipairs(ordered_names) do
        if i - 1 == index then
            return contents[route_name] or {}
        end
    end
end

local function delete_route(route_name)
    local file_content = file.Read(walkbot_record_file)
    if not file_content then
        return
    end

    local contents = json.decode(file_content or "{}")
    if not contents then
        return
    end

    if contents[route_name] then
        contents[route_name] = nil
        local new_encoded = json.encode(contents)
        if new_encoded then
            file.Write(walkbot_record_file, new_encoded)
        end
    end
end

-- =================== FUNCTIONS =================== 

local primaryBuyCommands = {
    "",
    "buy ak47; buy m4a1; buy m4a1_silencer", 
    "buy awp",                                 
    "buy ssg08",                               
    "buy aug; buy sg556",                      
    "buy famas; buy galilar",                  
    "buy p90"                                 
}

local function is_in_map()
    local raw_name = engine.GetMapName()
    if not raw_name then return false, nil end
    local map_name = raw_name:match("maps/(.-)%.vpk") or raw_name
    if map_name ~= "" and map_name ~= "<empty>" then
        return true, map_name
    end
    return false, map_name
end

local function get_my_entity()
    local lp = entities.GetLocalPlayer()
    if lp and lp:IsAlive() then
        return lp
    end
    return nil
end

local function get_my_pos()
    local lp = entities.GetLocalPlayer()
    if not lp then return nil end
    return lp:GetAbsOrigin()
end

local function get_my_eye()
    local local_player = get_my_entity()
    if not local_player then
        return nil
    end

    local eye_offset = local_player:GetPropVector("m_vecViewOffset")
    local position = local_player:GetAbsOrigin()
    return position + eye_offset 
end

local function get_my_speed()
    local LocalPlayer = entities.GetLocalPlayer()
    if not LocalPlayer or not LocalPlayer:IsAlive() then
        return 0
    end

    local velocity = LocalPlayer:GetPropVector("m_vecVelocity")
    return velocity and velocity:Length2D() or 0
end

local function normalize_yaw(yaw)
    while yaw > 180 do yaw = yaw - 360 end
    while yaw < -180 do yaw = yaw + 360 end
    return yaw
end

local function normalize_pitch(pitch)
    if pitch > 89 then return 89 end
    if pitch < -89 then return -89 end
    return pitch
end

local function reverse_walk_data(data)
    local reversed = {}
    for i = #data, 1, -1 do
        table.insert(reversed, data[i])
    end
    return reversed
end

local function auto_duck_hole(cmd, my_pos, my_speed)
    if my_speed > 10 then return end

    local viewAngles = engine.GetViewAngles()
    viewAngles.x = 0
    local forward = viewAngles:Forward()

    local base = my_pos + Vector3(0, 0, 55)
    local head = base + Vector3(0, 0, 20)

    local stomach_end = base + forward * 30
    local head_end = head + forward * 30

    local stomach_trace = engine.TraceLine(base, stomach_end, MASK_SOLID)
    local head_trace = engine.TraceLine(head, head_end, MASK_SOLID)

    local duck_in_gap = head_trace.fraction < 1.0 and stomach_trace.fraction == 1.0

    if duck_in_gap then
        cmd:SetButtons(bit.bor(cmd:GetButtons(), 4))
    end
end

local function attack_dynamicprop(cmd, my_eye, my_speed)
    if my_speed > 10 then return end
    local view_angles = engine.GetViewAngles()
    local forward = view_angles:Forward()
    local target_pos = my_eye + forward * 60
    local trace = engine.TraceLine(my_eye, target_pos, 0x1)
    local hit_ent = trace.entity
    if hit_ent then
        local class = hit_ent:GetClass()
        if class == "C_DynamicProp" then
            cmd:SetButtons(bit.bor(cmd:GetButtons(), 1))
        end
    end
end

local function open_door(cmd, my_eye, my_speed)
    if my_speed > 10 then return end
    local view_angles = engine.GetViewAngles()
    local forward = view_angles:Forward()
    local target_pos = my_eye + forward * 60
    local trace = engine.TraceLine(my_eye, target_pos, MASK_SOLID)
    local hit_ent = trace.entity
    if hit_ent then
        local class = hit_ent:GetClass()
        if class == "C_PropDoorRotating" then
            cmd:SetButtons(bit.bor(cmd:GetButtons(), 32))
        end
    end
end

local function move_to_pos(cmd, my_pos, my_speed, speed, pos_target)
    local origin = entities.GetLocalPlayer():GetAbsOrigin()
    local move_dir = pos_target - origin
    move_dir.z = 0

    local yaw_diff = normalize_yaw(move_dir:Angles().y - engine.GetViewAngles().y)
    if math.abs(yaw_diff) < 9 then yaw_diff = 0 end

    yaw_diff = math.rad(yaw_diff)

    if my_speed > speed then return end
    cmd:SetForwardMove(math.cos(yaw_diff) * speed)
    cmd:SetSideMove(math.sin(yaw_diff) * speed)
end

local function record()
    local lp = entities.GetLocalPlayer()
    if not is_recording or not lp then return end
    local pos = lp:GetAbsOrigin()
    local last = walk_data[#walk_data]
    if not last or (pos - Vector3(last.x, last.y, last.z)):Length() > 25 then
        table.insert(walk_data, { x = pos.x, y = pos.y, z = pos.z })
    end
end

local function update_play_index(cmd, my_pos, my_speed, play_index)

    local current_point = walk_data[play_index]
    local dist_to_current = vector.Distance({current_point.x, current_point.y, current_point.z},{my_pos.x, my_pos.y, my_pos.z})

    if dist_to_current >= 60 then
        local best_index, best_dist = nil, math.huge
        local px, py, pz = my_pos.x, my_pos.y, my_pos.z

        for i = 1, #walk_data do
            local point = walk_data[i]
            local dx = point.x - px
            local dy = point.y - py
            local dz = point.z - pz
            local dist = dx * dx + dy * dy + dz * dz

            if math.abs(dz) <= 60 and dist < best_dist then
                best_dist = dist
                best_index = i
            end
        end

        if best_index then
            play_index = best_index
        end
    else

        local dx = math.abs(current_point.x - my_pos.x)
        local dy = math.abs(current_point.y - my_pos.y)
        local dz = current_point.z - my_pos.z

        if dx <= 15 and dy <= 15 and dz >= 5 and dz <= 50 then
            cmd:SetButtons(bit.bor(cmd:GetButtons(), 4))
            cmd:SetButtons(bit.bor(cmd:GetButtons(), 2))
        end

        if dist_to_current <= 25 then
            if play_index < #walk_data then
                play_index = play_index + 1
            else
                walk_data = reverse_walk_data(walk_data)
                play_index = 1
            end
        end
    end

    return play_index
end


local ui_buttons_text = {}
-- =================== WALKBOT SUBTAB REFERENCE ===================
local wb_tab = gui.Tab(gui.Reference("Settings"), "simpleswalkbot.tab", "Ulquiorra.Store - Walkbot")

-- =================== AIMBOT ===================
local gb_aimbot = gui.Groupbox(wb_tab, "Aimbot", 15, 15, 296, 0)
local aimbot_enable = gui.Checkbox(gb_aimbot, "aimbot.enable", "Auto Shot Target", true)
local aimbot_aimlock = gui.Checkbox(gb_aimbot, "aimbot.aimlock", "Auto Aim Target", true)

--======================= AIMBOT SETTINGS =======================--
local aimbot_settings_window = gui.Window("aimbot.settings", "Aimbot Settings", 200, 250, 300, 280)
aimbot_settings_window:SetPosX(0)
aimbot_settings_window:SetPosY(0)
aimbot_settings_window:SetActive(false)

local aimbot_settings_button = gui.Button(gb_aimbot, "⚙", function() 
    aimbot_settings_window:SetActive(not aimbot_settings_window:IsActive()) 
end)
aimbot_settings_button:SetWidth(10)
aimbot_settings_button:SetHeight(10)
aimbot_settings_button:SetPosX(250)
aimbot_settings_button:SetPosY(-40)

local backward_smooth_checkbox = gui.Checkbox(aimbot_settings_window, "aimbot.smooth_backward", "Backward Smoothing", true)
backward_smooth_checkbox:SetDescription("adds automatic smoothing when the target is out of view")

local aimbot_smooth_slider = gui.Slider(aimbot_settings_window, "aimbot.smooth", "Aimbot Smooth", 15, 1, 100)
aimbot_smooth_slider:SetWidth(150)
aimbot_smooth_slider:SetDescription("Controls how smooth the aimbot movement is")

local aimbot_shotfov_slider = gui.Slider(aimbot_settings_window, "aimbot.shotfov", "Aimbot Shot FOV", 5, 1, 100)
aimbot_shotfov_slider:SetWidth(150)
aimbot_shotfov_slider:SetDescription("Minimum distance from target for auto shot")

local aimbot_shotspeed_slider = gui.Slider(aimbot_settings_window, "aimbot.shotspeed", "Aimbot Shot Speed", 5, 1, 50)
aimbot_shotspeed_slider:SetWidth(150)
aimbot_shotspeed_slider:SetDescription("Tick interval between auto-shots")



-- =================== TARGET ===================
local gb_eye = gui.Groupbox(wb_tab, "Aimbot/Target", 15, 145, 296, 0)
local scan_enemy = gui.Checkbox(gb_eye, "target.scan_enemy", "Scan Enemy Target", true)
local scan_ally = gui.Checkbox(gb_eye, "target.scan_ally", "Scan Ally Target", false)


-- =================== Visuals ===================
local wb_visuals_gb = gui.Groupbox(wb_tab, "Visuals", 15, 275, 296, 0)
local show_lines = gui.Checkbox(wb_visuals_gb, "visuals.lines", "Show Route", false)
local show_target= gui.Checkbox(wb_visuals_gb, "visuals.target", "Show Target", true)
local show_mousepushforce = gui.Checkbox(wb_visuals_gb, "visuals.mousepushforce", "Show Mouse Push Force", false)


-- =================== RIGHT SIDE ===================

-- =================== WALKBOT ===================
local gb_walkbot = gui.Groupbox(wb_tab, "Walkbot/Start/Stop", 330, 15, 296, 0)

local wb_route_selector = gui.Combobox(gb_walkbot, "simpleswalkbot.walk.routes", "Routes", unpack(walkbot_saved_names))
wb_route_selector:SetWidth(120)

local function toggle_start_route()
    is_playing = not is_playing
    ui_buttons_text.wb_play_text:SetText(is_playing and "Stop Route" or "Start Route")

    local status = is_playing and "Started Route" or "Stopped Route"
    add_info_log("[Ulquiorra.Store] Walkbot ✅ " .. status)
end
local wb_play_btn = gui.Button(gb_walkbot, "", toggle_start_route)
wb_play_btn:SetWidth(120)
wb_play_btn:SetPosX(140)
wb_play_btn:SetPosY(10)
ui_buttons_text.wb_play_text = gui.Text(gb_walkbot, "Start Route")
ui_buttons_text.wb_play_text:SetPosX(175)
ui_buttons_text.wb_play_text:SetPosY(22)



-- =================== Walkbot Settings ===================
local walkbot_settings_window = gui.Window("walkbot.settings", "Walkbot Settings", 200, 200, 300, 200)
walkbot_settings_window:SetPosX(0)
walkbot_settings_window:SetPosY(0)
walkbot_settings_window:SetActive(false)
local settings_button = gui.Button(gb_walkbot, "⚙", function() walkbot_settings_window:SetActive(not walkbot_settings_window:IsActive()) end)
settings_button:SetWidth(10)
settings_button:SetHeight(10)
settings_button:SetPosX(250)
settings_button:SetPosY(-40)


local walkbot_walk_speed = gui.Slider(walkbot_settings_window, "walkbot.walk_speed", "Walk Speed", 450, 0, 450)
walkbot_walk_speed:SetWidth(150)

local walkbot_walkshot_speed = gui.Slider(walkbot_settings_window, "walkbot.walk_shot_speed", "Walk Shot Speed", 0, 0, 450)
walkbot_walkshot_speed:SetWidth(150)





-- =================== RECORDER ===================
local gb_walkbot_recorder = gui.Groupbox(wb_tab, "Walkbot/RecordRoute", 330, 130, 296, 0)

-- =================== Input Route Name ===================
local wb_route_name_entry = gui.Editbox(gb_walkbot_recorder, "simpleswalkbot.routename", "Route name")
wb_route_name_entry:SetWidth(120)
wb_route_name_entry:SetPosX(0)

-- =================== Save Route ===================

local function save_route()
    if not walk_data or #walk_data < 2 then
        add_error_log("[Ulquiorra.Store] Walkbot ❌ Route too short to save (need at least 2 points).")
        return
    end

    local route_name_raw = wb_route_name_entry:GetValue()
    local route_name = route_name_raw and route_name_raw:gsub("^%s*(.-)%s*$", "%1") or ""

    if route_name == "" then
        add_error_log("[Ulquiorra.Store] Walkbot ❌ Please enter a valid route name.")
        return
    end

    local file_content = file.Read(walkbot_record_file)
    local contents = json.decode(file_content or "{}")
    if not contents then
        add_error_log("[Ulquiorra.Store] Walkbot ❌ Failed to load walkbot record file.")
        return
    end

    if contents[route_name] then
        add_error_log("[Ulquiorra.Store] Walkbot ❌ Route name already exists: " .. route_name)
        return
    end

    for saved_route_name, saved_route_data in pairs(contents) do
        if #walk_data == #saved_route_data then
            local is_same_route = true
            for i = 1, #walk_data do
                local a, b = walk_data[i], saved_route_data[i]
                if a.x ~= b.x or a.y ~= b.y or a.z ~= b.z then
                    is_same_route = false
                    break
                end
            end
            if is_same_route then
                add_error_log("[Ulquiorra.Store] Walkbot ❌ Identical route already saved as: " .. saved_route_name)
                return
            end
        end
    end

    contents[route_name] = walk_data
    local encoded = json.encode(contents)

    if not encoded then
        add_error_log("[Ulquiorra.Store] Walkbot ❌ Failed to encode walkbot data.")
        return
    end

    file.Write(walkbot_record_file, encoded)
    local saved_walkbot_names = get_saved_walkbot_names()
    wb_route_selector:SetOptions(unpack(saved_walkbot_names))       
    wb_route_selector:SetValue(#saved_walkbot_names - 1)
    wb_route_name_entry:SetValue("")

    add_info_log("[Ulquiorra.Store] Walkbot ✅ Saved route " .. route_name)
end



local wb_save_btn = gui.Button(gb_walkbot_recorder, "Save Route", save_route)
wb_save_btn:SetWidth(120)
wb_save_btn:SetPosX(140)
wb_save_btn:SetPosY(13)


-- =================== Delete Route ===================
local function delete_selected_route()
    local selected_index = wb_route_selector:GetValue()
    walkbot_saved_names = get_saved_walkbot_names()
    local selected_route = walkbot_saved_names[selected_index + 1]
    if selected_route and selected_route ~= "" then
        delete_route(selected_route)
        walkbot_saved_names = get_saved_walkbot_names()
        wb_route_selector:SetOptions(unpack(walkbot_saved_names))       
        wb_route_selector:SetValue(#walkbot_saved_names - 1)
        add_info_log("[Ulquiorra.Store] Walkbot ✅ Deleted route: " .. selected_route)
    end

    if walk_data and #walk_data >= 1 then
        play_index = 1
        walk_data = get_saved_walkbot_data(wb_route_selector:GetValue())
    else
        walk_data = {}
        play_index = 1
    end
end
local wb_delete_btn = gui.Button(gb_walkbot_recorder, "Delete Route", delete_selected_route)
wb_delete_btn:SetWidth(120)
wb_delete_btn:SetPosX(0)
wb_delete_btn:SetPosY(65)



-- =================== Record Button ===================
local function auto_set_route_name_from_map()
    local in_map, map_name = is_in_map()
    if in_map and map_name and map_name ~= "" and map_name ~= "<empty>" then
        wb_route_name_entry:SetValue(map_name)
    end
end

local function toggle_start_record()
    is_recording = not is_recording
    if is_recording then
        walk_data = {}
        auto_set_route_name_from_map()
    end
    ui_buttons_text.wb_record_text:SetText(is_recording and "Stop Record" or "Start Record")
    local status = is_recording and "Start Record" or "Stop Record"
    add_info_log("[Ulquiorra.Store] Walkbot ✅ " .. status)
end

local wb_record_btn = gui.Button(gb_walkbot_recorder, "", toggle_start_record)
wb_record_btn:SetWidth(120)
wb_record_btn:SetPosX(140)
wb_record_btn:SetPosY(65)
ui_buttons_text.wb_record_text = gui.Text(gb_walkbot_recorder, "Start Record")
ui_buttons_text.wb_record_text:SetPosX(170)
ui_buttons_text.wb_record_text:SetPosY(76)




-- -- =================== EYE ===================
local gb_eye = gui.Groupbox(wb_tab, "Walkbot/Angles", 330, 301, 296, 0)
local yaw_at_route = gui.Checkbox(gb_eye, "angles.yaw_at_route", "Yaw At Route", true)

--======================= ANGLES SETTINGS =======================--
local angles_settings_window = gui.Window("walkbot.settings", "Angles Settings", 200, 250, 300, 250)
angles_settings_window:SetPosX(0)
angles_settings_window:SetPosY(0)
angles_settings_window:SetActive(false)

local settings_button = gui.Button(gb_eye, "⚙", function() 
    angles_settings_window:SetActive(not angles_settings_window:IsActive()) 
end)
settings_button:SetWidth(10)
settings_button:SetHeight(10)
settings_button:SetPosX(250)
settings_button:SetPosY(-40)

local smooth_range_slider = gui.Slider(angles_settings_window, "walkbot.smoothrange", "Smooth Range", 10000, 1, 10000)
smooth_range_slider:SetWidth(150)
smooth_range_slider:SetDescription("Distance where the min and max smooth are divided")

local smooth_min_slider = gui.Slider(angles_settings_window, "walkbot.smoothmin", "Min Smooth", 1, 1, 100)
smooth_min_slider:SetWidth(150)
smooth_min_slider:SetDescription("Used when the angles target is far away.")

local smooth_max_slider = gui.Slider(angles_settings_window, "walkbot.smoothmax", "Max Smooth", 30, 1, 100)
smooth_max_slider:SetWidth(150)
smooth_max_slider:SetDescription("Used when the angles target is very close")


-- =================== Auto Buy ===================
local wa_autobuy_bg = gui.Groupbox(wb_tab, "Misc/AutoBuy", 330, 396, 296, 0)
local primaryWeapons = gui.Combobox(wa_autobuy_bg, "autobuy.primary", "Auto Buy Primary Weapon", "None", "AK/M4", "AWP", "Scout", "AUG/SG", "FAMAS/Galil", "P90")
primaryWeapons:SetValue(1)









local AW_MENU = gui.Reference("MENU")
local Owb_route_selector = -1
function ui_update()
    if AW_MENU:IsActive() then 
        local new_value = wb_route_selector:GetValue()
        if Owb_route_selector ~= new_value then
            play_index = 1
            walk_data = get_saved_walkbot_data(new_value) or {} 
            Owb_route_selector = new_value
        end

        if is_playing or is_recording then
            wb_route_selector:SetDisabled(true)
            wb_route_name_entry:SetDisabled(true)
            if is_playing then
                wb_delete_btn:SetDisabled(true)
                wb_save_btn:SetDisabled(true)
                wb_record_btn:SetDisabled(true)
                ui_buttons_text.wb_record_text:SetDisabled(true)
            elseif is_recording then
                wb_delete_btn:SetDisabled(true)
                wb_play_btn:SetDisabled(true)
                wb_save_btn:SetDisabled(true)         
                ui_buttons_text.wb_play_text:SetDisabled(true)
            end 
        else
            wb_route_selector:SetDisabled(false)
            wb_route_name_entry:SetDisabled(false)
            wb_record_btn:SetDisabled(false)
            wb_delete_btn:SetDisabled(false)
            wb_play_btn:SetDisabled(false)
            wb_save_btn:SetDisabled(false)
            ui_buttons_text.wb_play_text:SetDisabled(false)
            ui_buttons_text.wb_record_text:SetDisabled(false)
        end
    end
end



local last_logged_tick = -500
local function is_visible(targetPos)
    local my_eye_position = get_my_eye()
    if not my_eye_position or not targetPos then
        return false
    end

    local traceResult = engine.TraceLine(my_eye_position, targetPos, MASK_SHOT)
    if traceResult.entity then
        local ent = traceResult.entity
        local entityClass = ent:GetClass()
        if traceResult.dispFlags == 268435460 and entityClass == "CHostageRescueZone" then
            if vector.Distance({my_eye_position.x, my_eye_position.y, my_eye_position.z}, {targetPos.x, targetPos.y, targetPos.z}) > 400 then
                return false
            end

            local steps = 2
            local stepSize = (targetPos - my_eye_position) / steps
            for i = 1, steps do
                local checkPos = my_eye_position + (stepSize * i)
                local stepTrace = engine.TraceLine(my_eye_position, checkPos, MASK_SHOT)
                if stepTrace.entity and stepTrace.entity:GetClass() ~= "CHostageRescueZone" then
                    return false
                end
            end

            local current_tick = globals.TickCount()
            local tick_window = math.floor(current_tick / 500)
            local last_tick_window = math.floor(last_logged_tick / 500)

            if tick_window ~= last_tick_window then
                add_error_log("[Ulquiorra.Store] Walkbot ❌ Target is inside a CHostageRescueZone visibility check may behave unexpectedly")
                last_logged_tick = current_tick
            end
            return true
        end
    end

    return traceResult.fraction == 1.0
end



local scanned_target = nil
local walkbot_speed = 0

local function normalize_vector(vec)
    local length = math.sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z)
    if length == 0 then
        return Vector3(0, 0, 0)
    end
    return Vector3(vec.x / length, vec.y / length, vec.z / length)
end

local function AngleToForward(angles)
    local pitch = math.rad(angles.pitch)
    local yaw = math.rad(angles.yaw)

    local cos_pitch = math.cos(pitch)
    local sin_pitch = math.sin(pitch)
    local cos_yaw = math.cos(yaw)
    local sin_yaw = math.sin(yaw)

    return Vector3(cos_pitch * cos_yaw, cos_pitch * sin_yaw, -sin_pitch)
end

local function get_targets()
    local my_entity = get_my_entity()
    local my_position = get_my_pos()
    local my_eye = get_my_eye()
    if not my_entity or not my_position or not my_eye then return nil end

    local view_angles = engine.GetViewAngles()
    local forward = AngleToForward(view_angles)

    local best_target = nil
    local best_fov = math.huge

    for i = 1, globals.MaxClients() do
        local pEntity = entities.GetByIndex(i)
        if not pEntity then goto continue end

        local m_hPawn = pEntity:GetPropEntity("m_hPawn")
        if not m_hPawn or not m_hPawn:IsAlive() or m_hPawn:GetIndex() == my_entity:GetIndex() then goto continue end

        if m_hPawn:GetPropBool("m_bGunGameImmunity") then goto continue end

        local isEnemy = m_hPawn:GetTeamNumber() ~= my_entity:GetTeamNumber()
        local valid = (scan_enemy:GetValue() and isEnemy) or (scan_ally:GetValue() and not isEnemy)
        if not valid then goto continue end

        local target_origin = m_hPawn:GetAbsOrigin()
        local view_offset = m_hPawn:GetPropVector("m_vecViewOffset")
        local target_eye = target_origin + view_offset

        if is_visible(target_eye) then
            local direction = normalize_vector(target_eye - my_eye)
            local fov = math.acos(direction:Dot(forward)) * (180 / math.pi)

            if fov < best_fov then
                best_fov = fov
                best_target = m_hPawn
            end
        end

        ::continue::
    end

    return best_target
end

local mouse_force_history = {}
local max_history_length = 200
local jitter_history = {val=0, target=0, timer=0}

local font = draw.CreateFont and draw.CreateFont("Tahoma", 16, 800)
function walkbot_draw()
    frame = frame + 1

    if draw.SetFont and font then
        draw.SetFont(font)
    end

    local my_entity = get_my_entity()
    if not my_entity or not my_entity:IsAlive() then return end 

    local x, y = 10, 10
    local spacing = 20
    local line = 0

    local function draw_log_group(group, color)
        for i = #group, 1, -1 do
            local log = group[i]
            if frame - log.frame > LOG_DURATION then
                table.remove(group, i)
            else
                draw.Color(color[1], color[2], color[3], 255)
                draw.Text(x, y + line * spacing, log.message)
                line = line + 1
            end
        end
    end

    if show_info then draw_log_group(logs.info, {0, 255, 0}) end
    if show_error then draw_log_group(logs.error, {255, 0, 0}) end

    if show_lines:GetValue() then
        local function draw_line_path(data, r, g, b, a)
            for i = 1, #data - 1 do
                local a_pos = data[i]
                local b_pos = data[i + 1]
    
                local ax, ay = client.WorldToScreen(Vector3(a_pos.x, a_pos.y, a_pos.z + 5))
                local bx, by = client.WorldToScreen(Vector3(b_pos.x, b_pos.y, b_pos.z + 5))
    
                if ax and ay and bx and by then
                    draw.Color(r, g, b, a or 255)
                    draw.Line(ax, ay, bx, by)
                end
            end
        end
    
        if walk_data and #walk_data > 1 then
            draw_line_path(walk_data, 255, 255, 255)
        end
    end

    if scanned_target and scanned_target:IsPlayer() and scanned_target:IsAlive() and show_target:GetValue() then
        local origin = scanned_target:GetAbsOrigin()
        local view_offset = scanned_target:GetPropVector("m_vecViewOffset")
        
        local head_pos = origin + view_offset
        local feet_pos = origin

        local top_x, top_y = client.WorldToScreen(head_pos)
        local bot_x, bot_y = client.WorldToScreen(feet_pos)

        if top_x and bot_x then
            local height = bot_y - top_y
            local width = height / 2  

            draw.Color(255, 0, 0, 40)                        
            draw.FilledRect(top_x - width / 2, top_y, top_x + width / 2, bot_y)

            draw.Color(255, 0, 0, 200)
            draw.Text(top_x - 50, top_y - 15, "Scanned Target")
        end
    end

    if show_mousepushforce:GetValue() then
        local fov = last_fov or 0
        local strength = math.min(fov / 20, 1)
        local screen_x, screen_y = draw.GetScreenSize()

        local y_offset = 100 + 50 
        local x_offset = -10   

        local bar_height = 150
        local bar_width = 10
        local filled_height = bar_height * strength

        local bar_x = 50 + x_offset
        local bar_y = screen_y / 2 - bar_height / 2 + y_offset

        local wave_width = 300
        local padding = 10
        local background_x1 = bar_x - padding
        local background_y1 = bar_y - padding
        local background_x2 = bar_x + bar_width + wave_width + padding
        local background_y2 = bar_y + bar_height + padding

        local r = 255
        local g = math.floor(180 * (1 - strength)) 
        local b = math.floor(180 * (1 - strength))
        local a = 255

        local title = "Mouse Push Force"
        draw.Color(r, g, b, a)
        local text_width, text_height = draw.GetTextSize(title)
        local title_x = background_x1 + ((background_x2 - background_x1) - text_width) / 2
        local title_y = background_y1 - text_height - 4
        draw.Text(title_x, title_y, title)

        draw.Color(0, 0, 0, 50)
        draw.FilledRect(background_x1, background_y1, background_x2, background_y2)

        draw.Color(0, 0, 0, 150)
        draw.FilledRect(bar_x, bar_y, bar_x + bar_width, bar_y + bar_height)

        draw.Color(255, 0, 0, 255)
        draw.FilledRect(bar_x, bar_y + bar_height - filled_height, bar_x + bar_width, bar_y + bar_height)

        local wave_x = bar_x + 40
        local wave_y = bar_y + bar_height
        local scale = bar_height / 1.5

        draw.Color(0, 200, 255, 255)
        for i = 1, #mouse_force_history - 1 do
            local x1 = wave_x + i
            local y1 = wave_y - (mouse_force_history[i] or 0) * scale
            local x2 = wave_x + i + 1
            local y2 = wave_y - (mouse_force_history[i + 1] or 0) * scale
            draw.Line(x1, y1, x2, y2)
        end
    end
end

local function aimbot(cmd, my_speed, target)
    if not target or not target:IsPlayer() or not target:IsAlive() then return end

    local me = entities.GetLocalPlayer()
    if not me or not me:IsAlive() then return end

    local origin = target:GetAbsOrigin()
    local view_offset = target:GetPropVector("m_vecViewOffset") or Vector3(0, 0, 64)
    local aim_pos = Vector3(origin.x, origin.y, origin.z + (view_offset.z * 0.60))

    local eye_pos = me:GetAbsOrigin() + Vector3(0, 0, 64)
    local delta = aim_pos - eye_pos

    local yaw = math.deg(math.atan2(delta.y, delta.x))
    local hyp = math.sqrt(delta.x^2 + delta.y^2)
    local pitch = -math.deg(math.atan2(delta.z, hyp))

    local current = engine.GetViewAngles()
    local dy = normalize_yaw(yaw - current.y)
    local dp = normalize_pitch(pitch - current.x)

    local fov = math.sqrt(dp^2 + dy^2)
    last_fov = fov

    local base_smooth = math.max(aimbot_smooth_slider:GetValue(), 1)
    local smooth = base_smooth

    if fov > 60 and backward_smooth_checkbox:GetValue() then
        local extra_smooth = ((fov - 60) / 10) * 5
        smooth = base_smooth + extra_smooth
    end

    local new_pitch = current.x + (dp / smooth)
    local new_yaw = current.y + (dy / smooth)

    engine.SetViewAngles(EulerAngles(new_pitch, new_yaw, 0))

    local force = math.min(fov / 20, 1.5)
    table.insert(mouse_force_history, 1, force)
    if #mouse_force_history > max_history_length then
        table.remove(mouse_force_history)
    end


    local current_tick = globals.TickCount()
    local tick_toggle = current_tick % aimbot_shotspeed_slider:GetValue() == 0
    local buttons = cmd:GetButtons()
    if fov < aimbot_shotfov_slider:GetValue() and aimbot_enable:GetValue() then
        walkbot_speed = walkbot_walkshot_speed:GetValue()
        if tick_toggle then
            buttons = bit.bor(buttons, 1)
        else
            buttons = bit.band(buttons, bit.bnot(1))
        end
        cmd:SetButtons(buttons)
    end
end

local function aim_to_pos(target)
    local me = entities.GetLocalPlayer()
    if not me or not me:IsAlive() or not target then return end
    local eye = me:GetAbsOrigin() + Vector3(0, 0, 64)
    local delta = target - eye

    local desired_yaw = math.deg(math.atan2(delta.y, delta.x))
    local view = engine.GetViewAngles()
    local dy = normalize_yaw(desired_yaw - view.y)

    local dist = math.sqrt(delta.x^2 + delta.y^2)
    local t = math.min(dist / smooth_range_slider:GetValue(), 1)

    local smooth = smooth_max_slider:GetValue() * (1 - t) + smooth_min_slider:GetValue() * t

    local new_yaw = view.y + dy / smooth

    local dp = normalize_pitch(0 - view.x)
    local new_pitch = view.x + dp / smooth

    engine.SetViewAngles(EulerAngles(new_pitch, new_yaw, 0))

    local fov = math.sqrt(dp^2 + dy^2)
    last_fov = fov

    local force = math.min(fov / 20, 1.5)
    table.insert(mouse_force_history, 1, force)
    if #mouse_force_history > max_history_length then
        table.remove(mouse_force_history)
    end
end

local function is_shooting(cmd)
    if not cmd then return false end
    local ok, buttons = pcall(function() return cmd:GetButtons() end)
    if not ok or not buttons then return false end
    return bit.band(buttons, 1) ~= 0
end

local function play(cmd)

    if not is_playing then return end
    if not walk_data or #walk_data <= 1 then return end
    if is_shooting(cmd) and not aimbot_enable:GetValue() then return end

    local my_entity = get_my_entity()
    local my_pos = get_my_pos()
    local my_eye = get_my_eye()
    local my_speed = get_my_speed()

    if not my_speed or not my_entity or not my_eye or not my_pos then return end

    play_index = update_play_index(cmd, my_pos, my_speed, play_index)
    local pos_target = Vector3(walk_data[play_index].x, walk_data[play_index].y, walk_data[play_index].z)

    if scan_enemy:GetValue() or scan_ally:GetValue() then
        scanned_target = get_targets()
    end

    walkbot_speed = walkbot_walk_speed:GetValue()
    if yaw_at_route:GetValue() and (not scanned_target or not aimbot_aimlock:GetValue()) then
        aim_to_pos(pos_target)
    elseif scanned_target and aimbot_aimlock:GetValue() then
        aimbot(cmd, my_speed, scanned_target)
    end 

    auto_duck_hole(cmd, my_pos, my_speed)
    open_door(cmd, my_eye, my_speed)   
    attack_dynamicprop(cmd, my_eye, my_speed)
    move_to_pos(cmd, my_pos, my_speed, walkbot_speed, pos_target)
end

local loaded_map_check = false
loaded_map_check = true
local function auto_load_route_by_map()
    if not loaded_map_check then 
        return 
    end
    loaded_map_check = false

    local in_map, map_name = is_in_map()
    if not in_map then return end

    local selected_route = walkbot_saved_names[wb_route_selector:GetValue() + 1]
    if selected_route == map_name then
        return 
    end

    for i, name in ipairs(walkbot_saved_names) do
        if name == map_name then
            local index = i - 1
            wb_route_selector:SetValue(index)
            play_index = 1
            walk_data = get_saved_walkbot_data(index) or {}
            add_info_log("[Ulquiorra.Store] Walkbot ✅ Loaded route for map: " .. map_name)
            break
        end
    end 
end

local function on_connect_full(e)
    if not e or type(e.GetName) ~= "function" or e:GetName() ~= "game_newmap" then return end
    loaded_map_check = true
end

local function is_local_spawn(userid)
    local playercontroller = entities.GetByIndex(userid + 1)
    if not playercontroller then return false end
    local playerpawn = playercontroller:GetPropEntity("m_hPlayerPawn")
    if not playerpawn then return false end
    return playerpawn:GetIndex() == client.GetLocalPlayerIndex()
end

local function spawn_player(e)
    if not e or e:GetName() ~= "player_spawn" then return end
    if is_local_spawn(e:GetInt("userid")) then
        local primaryIndex = primaryWeapons:GetValue() + 1
        local primaryCommand = primaryBuyCommands[primaryIndex] or ""

        if primaryCommand ~= "" then
            client.Command(primaryCommand, true)
        end
    end
end

client.AllowListener("player_spawn")
callbacks.Register("FireGameEvent", spawn_player)

client.AllowListener("game_newmap")
callbacks.Register("FireGameEvent", on_connect_full)

callbacks.Register("Draw", function()
    auto_load_route_by_map()
    record()
    walkbot_draw()
    ui_update()
end)

callbacks.Register("CreateMove", function(cmd)
    if not cmd or type(cmd.SetForwardMove) ~= "function" or type(cmd.SetSideMove) ~= "function" then return end
    play(cmd)
end)
