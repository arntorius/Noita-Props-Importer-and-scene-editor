local gui = nil
local editor_ready = false
local props_menu_open = false
local editor_minimized = false
local props_page = 1
local props_per_page = 8
local props_library_mode = "custom"
local vanilla_loaded = false
local vanilla_folder_index = 1
local vanilla_folders = {"ALL"}
local selected_prop = 1
local selected_instance = 0
local status_text = "Ready"
local next_instance_uid = 1
local MOD_ID = "prop_placement_editor"
local MOD_ROOT = "mods/" .. MOD_ID
local GFX_DIR = MOD_ROOT .. "/files/gfx"
local GENERATED_DIR = MOD_ROOT .. "/files/generated"
local LAYOUT_PATH = MOD_ROOT .. "/layout.csv"

local function xml_escape(value)
    value = tostring(value or "")
    value = string.gsub(value, "&", "&amp;")
    value = string.gsub(value, '"', "&quot;")
    value = string.gsub(value, "<", "&lt;")
    value = string.gsub(value, ">", "&gt;")
    return value
end

local function sanitize_key(value)
    local key = string.lower(value or "prop")
    key = string.gsub(key, "[^%w]+", "_")
    key = string.gsub(key, "^_+", "")
    key = string.gsub(key, "_+$", "")
    if key == "" then key = "prop" end
    return key
end

local function read_png_size(filename)
    local file = io.open(GFX_DIR .. "/" .. filename, "rb")
    if file == nil then return nil,nil end
    local header = file:read(24)
    file:close()
    if header == nil or #header < 24 then return nil,nil end
    if string.sub(header,2,4) ~= "PNG" or string.sub(header,13,16) ~= "IHDR" then return nil,nil end
    local function u32be(index)
        local a,b,c,d = string.byte(header,index,index+3)
        if a == nil or b == nil or c == nil or d == nil then return nil end
        return a*16777216 + b*65536 + c*256 + d
    end
    return u32be(17),u32be(21)
end

local function ensure_generated_dir()
    local path = "mods\\" .. MOD_ID .. "\\files\\generated"
    pcall(os.execute, 'cmd /c if not exist "' .. path .. '" mkdir "' .. path .. '" >nul 2>nul')
end

local function list_gfx_pngs()
    local result = {}
    local command = 'cmd /c dir /b /a-d "mods\\' .. MOD_ID .. '\\files\\gfx\\*.png" 2>nul'
    local ok,pipe = pcall(io.popen,command)
    if ok and pipe ~= nil then
        for filename in pipe:lines() do
            if string.match(string.lower(filename),"%.png$") then table.insert(result,filename) end
        end
        pipe:close()
    end
    if #result == 0 then
        ensure_generated_dir()
        local scan_path = GENERATED_DIR .. "/gfx_scan.txt"
        local scan_win = "mods\\" .. MOD_ID .. "\\files\\generated\\gfx_scan.txt"
        pcall(os.execute, 'cmd /c dir /b /a-d "mods\\' .. MOD_ID .. '\\files\\gfx\\*.png" > "' .. scan_win .. '" 2>nul')
        local file = io.open(scan_path,"r")
        if file ~= nil then
            for filename in file:lines() do
                if string.match(string.lower(filename),"%.png$") then table.insert(result,filename) end
            end
            file:close()
            os.remove(scan_path)
        end
    end
    table.sort(result,function(a,b) return string.lower(a) < string.lower(b) end)
    return result
end

local function write_generated_file(filename,content)
    ensure_generated_dir()
    local file = io.open(GENERATED_DIR .. "/" .. filename,"w")
    if file == nil then return false end
    file:write(content)
    file:close()
    return true
end

local props = {}

local claimed_gfx = {}

local used_keys = {}
local instances = {}

local function rebuild_used_keys()
    used_keys = {}
    for _,prop in ipairs(props) do used_keys[prop.key] = true end
end

rebuild_used_keys()

local function unique_key(label)
    local base = "auto_" .. sanitize_key(label)
    local key = base
    local index = 2
    while used_keys[key] do
        key = base .. "_" .. tostring(index)
        index = index + 1
    end
    used_keys[key] = true
    return key
end

local function clean_label(filename)
    local label = string.gsub(filename,"%.png$","")
    label = string.gsub(label,"%s*%(%d+%)$","")
    return label
end

local function parse_sheet_filename(filename)
    local stem = string.gsub(filename,"%.png$","")
    local label,fw,fh,count,wait = string.match(stem,"^(.-)__sheet_(%d+)x(%d+)_(%d+)_([%d%.]+)$")
    if label ~= nil then return label,tonumber(fw),tonumber(fh),tonumber(count),tonumber(wait) end
    label,fw,fh,count = string.match(stem,"^(.-)__sheet_(%d+)x(%d+)_(%d+)$")
    if label ~= nil then return label,tonumber(fw),tonumber(fh),tonumber(count),0.10 end
    label,fw,fh,wait = string.match(stem,"^(.-)__sheet_(%d+)x(%d+)_([%d%.]+)$")
    if label ~= nil then return label,tonumber(fw),tonumber(fh),nil,tonumber(wait) end
    label,fw,fh = string.match(stem,"^(.-)__sheet_(%d+)x(%d+)$")
    if label ~= nil then return label,tonumber(fw),tonumber(fh),nil,0.10 end
    label,fw,fh,count,wait = string.match(stem,"^(.-)_sheet_(%d+)x(%d+)_(%d+)_([%d%.]+)$")
    if label ~= nil then return label,tonumber(fw),tonumber(fh),tonumber(count),tonumber(wait) end
    label,fw,fh,count = string.match(stem,"^(.-)_sheet_(%d+)x(%d+)_(%d+)$")
    if label ~= nil then return label,tonumber(fw),tonumber(fh),tonumber(count),0.10 end
    label,fw,fh = string.match(stem,"^(.-)_sheet_(%d+)x(%d+)$")
    if label ~= nil then return label,tonumber(fw),tonumber(fh),nil,0.10 end
    return nil,nil,nil,nil,nil
end

local function has_sheet_hint(filename)
    local lower = string.lower(filename)
    return string.find(lower,"sheet",1,true) ~= nil or string.find(lower,"spritesheet",1,true) ~= nil or string.find(lower,"anim",1,true) ~= nil
end

local function infer_strip_sheet(filename)
    local width,height = read_png_size(filename)
    if width == nil or height == nil then return nil,nil end
    local best_w,best_h,best_score = nil,nil,nil
    if width > height then
        for count=2,32 do
            if width % count == 0 then
                local fw = width / count
                local aspect = fw / height
                if fw >= 8 and aspect >= 0.45 and aspect <= 2.20 then
                    local score = math.abs(math.log(aspect / 0.80)) + count * 0.015
                    if best_score == nil or score < best_score then
                        best_w,best_h,best_score = fw,height,score
                    end
                end
            end
        end
    elseif height > width then
        for count=2,32 do
            if height % count == 0 then
                local fh = height / count
                local aspect = width / fh
                if fh >= 8 and aspect >= 0.45 and aspect <= 2.20 then
                    local score = math.abs(math.log(aspect / 0.80)) + count * 0.015
                    if best_score == nil or score < best_score then
                        best_w,best_h,best_score = width,fh,score
                    end
                end
            end
        end
    end
    return best_w,best_h
end

local function animation_family(filename)
    local stem = string.lower(string.gsub(filename,"%.png$",""))
    stem = string.gsub(stem,"%s*%(%d+%)$","")
    local tokens = {}
    for token in string.gmatch(stem,"[%w]+") do
        table.insert(tokens,token)
        if #tokens >= 2 then break end
    end
    if #tokens == 0 then return stem end
    return table.concat(tokens,"_")
end

local function infer_from_known_sizes(filename,known_sizes,require_family)
    local width,height = read_png_size(filename)
    if width == nil or height == nil then return nil,nil end
    local family = animation_family(filename)
    local found_w,found_h,found_count = nil,nil,nil
    for _,size in ipairs(known_sizes) do
        local fw,fh = size[1],size[2]
        local family_ok = not require_family or size.family == family
        if family_ok and fw > 0 and fh > 0 and width % fw == 0 and height % fh == 0 then
            local count = (width/fw) * (height/fh)
            if count >= 2 and (found_count == nil or count > found_count) then
                found_w,found_h,found_count = fw,fh,count
            end
        end
    end
    return found_w,found_h
end


local function powershell_quote(value)
    return string.gsub(tostring(value or ""), "'", "''")
end

local function detect_visible_frame_count(filename,frame_w,frame_h,max_frames)
    if frame_w == nil or frame_h == nil or max_frames == nil or max_frames < 1 then return nil end
    local image_path = "mods\\" .. MOD_ID .. "\\files\\gfx\\" .. filename
    local ps_path = powershell_quote(image_path)
    local script =
        "$ErrorActionPreference='Stop';" ..
        "Add-Type -AssemblyName System.Drawing;" ..
        "$b=[System.Drawing.Bitmap]::FromFile('" .. ps_path .. "');" ..
        "$fw=" .. tostring(math.floor(frame_w)) .. ";$fh=" .. tostring(math.floor(frame_h)) .. ";" ..
        "$cols=[int]($b.Width/$fw);$max=" .. tostring(math.floor(max_frames)) .. ";$last=0;" ..
        "for($i=$max-1;$i-ge 0 -and $last-eq 0;$i--){" ..
        "$ox=($i%$cols)*$fw;$oy=[math]::Floor($i/$cols)*$fh;$visible=$false;" ..
        "for($yy=0;$yy-lt $fh -and -not $visible;$yy++){for($xx=0;$xx-lt $fw;$xx++){if($b.GetPixel($ox+$xx,$oy+$yy).A -gt 0){$visible=$true;break}}}" ..
        "if($visible){$last=$i+1}};" ..
        "$b.Dispose();Write-Output $last"
    local command = 'powershell -NoProfile -ExecutionPolicy Bypass -Command "' .. string.gsub(script,'"','\\"') .. '" 2>nul'
    local ok,pipe = pcall(io.popen,command)
    if not ok or pipe == nil then return nil end
    local line = pipe:read("*l")
    pipe:close()
    local count = tonumber(line or "")
    if count ~= nil and count >= 1 and count <= max_frames then return math.floor(count) end
    return nil
end

local function add_auto_static(filename)
    local label = clean_label(filename)
    local width,height = read_png_size(filename)
    if width == nil or height == nil then return false end
    local key = unique_key(label)
    local entity_filename = key .. ".xml"
    local xml =
        '<Entity name="prop_editor_' .. xml_escape(key) .. '">\n' ..
        '    <SpriteComponent image_file="' .. xml_escape(GFX_DIR .. "/" .. filename) .. '" offset_x="' .. tostring(math.floor(width/2+0.5)) .. '" offset_y="' .. tostring(height) .. '" z_index="0.5" update_transform="1" />\n' ..
        '</Entity>\n'
    if not write_generated_file(entity_filename,xml) then return false end
    table.insert(props,{key=key,label=label,entity=GENERATED_DIR .. "/" .. entity_filename,auto_generated=true,source=filename,sheet=false,library="custom"})
    return true
end

local function add_auto_sheet(filename,label,frame_w,frame_h,frame_count,frame_wait)
    local width,height = read_png_size(filename)
    if width == nil or height == nil then return false end
    if frame_w == nil or frame_h == nil or frame_w <= 0 or frame_h <= 0 then return false end
    local columns = math.floor(width/frame_w)
    local rows = math.floor(height/frame_h)
    if columns < 1 or rows < 1 or columns*frame_w ~= width or rows*frame_h ~= height then return false end
    local max_frames = columns*rows
    if frame_count == nil then
        local detected_count = detect_visible_frame_count(filename,frame_w,frame_h,max_frames)
        frame_count = detected_count or max_frames
    else
        frame_count = math.max(1,math.min(frame_count,max_frames))
    end
    if frame_wait == nil or frame_wait <= 0 then frame_wait = 0.10 end
    local key = unique_key(label)
    local sprite_filename = key .. "_sprite.xml"
    local entity_filename = key .. ".xml"
    local sprite_xml =
        '<Sprite filename="' .. xml_escape(GFX_DIR .. "/" .. filename) .. '" offset_x="0" offset_y="0" default_animation="auto">\n' ..
        '    <RectAnimation name="auto" pos_x="0" pos_y="0" frame_count="' .. tostring(frame_count) .. '" frame_width="' .. tostring(frame_w) .. '" frame_height="' .. tostring(frame_h) .. '" frame_wait="' .. tostring(frame_wait) .. '" frames_per_row="' .. tostring(columns) .. '" loop="1" />\n' ..
        '</Sprite>\n'
    local entity_xml =
        '<Entity name="prop_editor_' .. xml_escape(key) .. '">\n' ..
        '    <SpriteComponent image_file="' .. xml_escape(GENERATED_DIR .. "/" .. sprite_filename) .. '" rect_animation="auto" offset_x="' .. tostring(math.floor(frame_w/2+0.5)) .. '" offset_y="' .. tostring(frame_h) .. '" z_index="0.5" update_transform="1" />\n' ..
        '</Entity>\n'
    if not write_generated_file(sprite_filename,sprite_xml) then return false end
    if not write_generated_file(entity_filename,entity_xml) then return false end
    table.insert(props,{key=key,label=label,entity=GENERATED_DIR .. "/" .. entity_filename,auto_generated=true,source=filename,sheet=true,frame_w=frame_w,frame_h=frame_h,frame_count=frame_count,frame_wait=frame_wait,library="custom"})
    return true
end

local function remove_auto_prop_definitions()
    for i=#props,1,-1 do
        if props[i].auto_generated then table.remove(props,i) end
    end
    rebuild_used_keys()
    if selected_prop > #props then selected_prop = math.max(1,#props) end
end

local function discover_auto_props()
    local files = list_gfx_pngs()
    local added = 0
    local sheets = 0
    local auto_sheets = 0
    local failed = 0
    local known_sizes = {}
    local pending_hinted = {}
    local pending_plain = {}

    local function remember_size(fw,fh,filename)
        if fw == nil or fh == nil then return end
        local family = animation_family(filename or "")
        for _,size in ipairs(known_sizes) do
            if size[1] == fw and size[2] == fh and size.family == family then return end
        end
        table.insert(known_sizes,{fw,fh,family=family})
    end

    for _,filename in ipairs(files) do
        if not claimed_gfx[string.lower(filename)] then
            local label,fw,fh,count,wait = parse_sheet_filename(filename)
            if label ~= nil then
                local ok = add_auto_sheet(filename,label,fw,fh,count,wait)
                if ok then
                    added = added + 1
                    sheets = sheets + 1
                    remember_size(fw,fh,filename)
                else
                    failed = failed + 1
                end
            elseif has_sheet_hint(filename) then
                table.insert(pending_hinted,filename)
            else
                table.insert(pending_plain,filename)
            end
        end
    end

    for _,filename in ipairs(pending_hinted) do
        local auto_fw,auto_fh = infer_strip_sheet(filename)
        if auto_fw == nil then
            auto_fw,auto_fh = infer_from_known_sizes(filename,known_sizes,false)
        end
        if auto_fw ~= nil then
            local ok = add_auto_sheet(filename,clean_label(filename),auto_fw,auto_fh,nil,0.10)
            if ok then
                added = added + 1
                sheets = sheets + 1
                auto_sheets = auto_sheets + 1
                remember_size(auto_fw,auto_fh,filename)
            else
                failed = failed + 1
            end
        else
            failed = failed + 1
        end
    end

    for _,filename in ipairs(pending_plain) do
        local fw,fh = infer_from_known_sizes(filename,known_sizes,true)
        if fw ~= nil then
            local ok = add_auto_sheet(filename,clean_label(filename),fw,fh,nil,0.10)
            if ok then
                added = added + 1
                sheets = sheets + 1
                auto_sheets = auto_sheets + 1
            else
                failed = failed + 1
            end
        else
            local ok = add_auto_static(filename)
            if ok then added = added + 1 else failed = failed + 1 end
        end
    end

    return #files,added,sheets,auto_sheets,failed
end

local VANILLA_PROP_FALLBACK = {
    "data/entities/props/altar_torch.xml",
    "data/entities/props/altar_torch_old.xml",
    "data/entities/props/banner.xml",
    "data/entities/props/boss_arena_statue_1.xml",
    "data/entities/props/boss_arena_statue_2.xml",
    "data/entities/props/boss_arena_statue_3.xml",
    "data/entities/props/boss_arena_statue_4.xml",
    "data/entities/props/candle_1.xml",
    "data/entities/props/candle_2.xml",
    "data/entities/props/candle_3.xml",
    "data/entities/props/coalmine_i_structure_01.xml",
    "data/entities/props/coalmine_i_structure_02.xml",
    "data/entities/props/coalmine_large_structure_01.xml",
    "data/entities/props/coalmine_large_structure_02.xml",
    "data/entities/props/coalmine_structure_01.xml",
    "data/entities/props/coalmine_structure_02.xml",
    "data/entities/props/crystal_green.xml",
    "data/entities/props/crystal_pink.xml",
    "data/entities/props/crystal_red.xml",
    "data/entities/props/dripping_acid_gas.xml",
    "data/entities/props/dripping_oil.xml",
    "data/entities/props/dripping_radioactive.xml",
    "data/entities/props/dripping_water.xml",
    "data/entities/props/dripping_water_heavy.xml",
    "data/entities/props/dummy_target.xml",
    "data/entities/props/excavationsite_machine_3b.xml",
    "data/entities/props/excavationsite_machine_3c.xml",
    "data/entities/props/forcefield_generator.xml",
    "data/entities/props/furniture_bed.xml",
    "data/entities/props/furniture_bunk.xml",
    "data/entities/props/furniture_castle_chair.xml",
    "data/entities/props/furniture_castle_divan.xml",
    "data/entities/props/furniture_castle_statue.xml",
    "data/entities/props/furniture_castle_table.xml",
    "data/entities/props/furniture_castle_wardrobe.xml",
    "data/entities/props/furniture_cryopod.xml",
    "data/entities/props/furniture_dresser.xml",
    "data/entities/props/furniture_footlocker.xml",
    "data/entities/props/furniture_locker.xml",
    "data/entities/props/furniture_rocking_chair.xml",
    "data/entities/props/furniture_stool.xml",
    "data/entities/props/furniture_table.xml",
    "data/entities/props/furniture_tombstone_01.xml",
    "data/entities/props/furniture_tombstone_02.xml",
    "data/entities/props/furniture_tombstone_03.xml",
    "data/entities/props/furniture_wardrobe.xml",
    "data/entities/props/furniture_wood_chair.xml",
    "data/entities/props/furniture_wood_table.xml",
    "data/entities/props/ladder_long.xml",
    "data/entities/props/mountain_left_entrance_grass.xml",
    "data/entities/props/physics_barrel_burning.xml",
    "data/entities/props/physics_barrel_oil.xml",
    "data/entities/props/physics_barrel_radioactive.xml",
    "data/entities/props/physics_barrel_water.xml",
    "data/entities/props/physics_bed.xml",
    "data/entities/props/physics_bone_01.xml",
    "data/entities/props/physics_bone_02.xml",
    "data/entities/props/physics_bone_03.xml",
    "data/entities/props/physics_bone_04.xml",
    "data/entities/props/physics_bone_05.xml",
    "data/entities/props/physics_bone_06.xml",
    "data/entities/props/physics_bottle_blue.xml",
    "data/entities/props/physics_bottle_green.xml",
    "data/entities/props/physics_bottle_red.xml",
    "data/entities/props/physics_bottle_yellow.xml",
    "data/entities/props/physics_box_explosive.xml",
    "data/entities/props/physics_box_harmless.xml",
    "data/entities/props/physics_box_harmless_small.xml",
    "data/entities/props/physics_brewing_stand.xml",
    "data/entities/props/physics_bucket.xml",
    "data/entities/props/physics_campfire.xml",
    "data/entities/props/physics_candle_1.xml",
    "data/entities/props/physics_candle_2.xml",
    "data/entities/props/physics_candle_3.xml",
    "data/entities/props/physics_cart.xml",
    "data/entities/props/physics_chain_torch.xml",
    "data/entities/props/physics_chain_torch_blue.xml",
    "data/entities/props/physics_chain_torch_ghostly.xml",
    "data/entities/props/physics_chair_1.xml",
    "data/entities/props/physics_chair_2.xml",
    "data/entities/props/physics_chandelier.xml",
    "data/entities/props/physics_crate.xml",
    "data/entities/props/physics_darksun_rock.xml",
    "data/entities/props/physics_electricity_source.xml",
    "data/entities/props/physics_fungus.xml",
    "data/entities/props/physics_fungus_acid.xml",
    "data/entities/props/physics_fungus_acid_big.xml",
    "data/entities/props/physics_fungus_acid_huge.xml",
    "data/entities/props/physics_fungus_acid_hugeish.xml",
    "data/entities/props/physics_fungus_acid_small.xml",
    "data/entities/props/physics_lantern_small.xml",
    "data/entities/props/physics_minecart.xml",
    "data/entities/props/physics_propane_tank.xml",
    "data/entities/props/physics_seamine.xml",
    "data/entities/props/physics_skull_01.xml",
    "data/entities/props/physics_skull_02.xml",
    "data/entities/props/physics_skull_03.xml",
    "data/entities/props/physics_stone_01.xml",
    "data/entities/props/physics_stone_02.xml",
    "data/entities/props/physics_stone_03.xml",
    "data/entities/props/physics_stone_04.xml",
    "data/entities/props/physics_sun_rock.xml",
    "data/entities/props/physics_torch_stand.xml",
    "data/entities/props/physics_trap_circle_acid.xml",
    "data/entities/props/physics_trap_electricity.xml",
    "data/entities/props/physics_trap_electricity_enabled.xml",
    "data/entities/props/physics_trap_ignite.xml",
    "data/entities/props/pumpkin_01.xml",
    "data/entities/props/pumpkin_02.xml",
    "data/entities/props/pumpkin_03.xml",
    "data/entities/props/pumpkin_04.xml",
    "data/entities/props/pumpkin_05.xml",
    "data/entities/props/stonepile.xml"
}

local function normalize_vanilla_path(path)
    path = string.gsub(path or "","\\","/")
    local lower = string.lower(path)
    local marker = "data/entities/props/"
    local pos = string.find(lower,marker,1,true)
    if pos == nil then return nil end
    return string.sub(path,pos)
end

local function list_vanilla_prop_xmls()
    local result = {}
    local seen = {}
    local command = 'cmd /c dir /b /s /a-d "data\\entities\\props\\*.xml" 2>nul'
    local ok,pipe = pcall(io.popen,command)
    if ok and pipe ~= nil then
        for line in pipe:lines() do
            local path = normalize_vanilla_path(line)
            if path ~= nil and not seen[string.lower(path)] then
                seen[string.lower(path)] = true
                table.insert(result,path)
            end
        end
        pipe:close()
    end
    if #result == 0 then
        ensure_generated_dir()
        local scan_path = GENERATED_DIR .. "/vanilla_scan.txt"
        local scan_win = "mods\\" .. MOD_ID .. "\\files\\generated\\vanilla_scan.txt"
        pcall(os.execute, 'cmd /c dir /b /s /a-d "data\\entities\\props\\*.xml" > "' .. scan_win .. '" 2>nul')
        local file = io.open(scan_path,"r")
        if file ~= nil then
            for line in file:lines() do
                local path = normalize_vanilla_path(line)
                if path ~= nil and not seen[string.lower(path)] then
                    seen[string.lower(path)] = true
                    table.insert(result,path)
                end
            end
            file:close()
            os.remove(scan_path)
        end
    end
    for _,path in ipairs(VANILLA_PROP_FALLBACK) do
        local lower = string.lower(path)
        local exists = true
        if ModDoesFileExist ~= nil then
            local ok,value = pcall(ModDoesFileExist,path)
            exists = ok and value
        end
        if exists and not seen[lower] then
            seen[lower] = true
            table.insert(result,path)
        end
    end
    table.sort(result,function(a,b) return string.lower(a) < string.lower(b) end)
    return result
end

local function vanilla_info(path)
    local rel = string.gsub(path,"^data/entities/props/","")
    local folder = string.match(rel,"^(.*)/[^/]+$") or "ROOT"
    local name = string.match(rel,"([^/]+)%.xml$") or rel
    local label = string.gsub(name,"_"," ")
    return rel,folder,label
end

local function rebuild_vanilla_folders()
    local folders = {"ALL"}
    local seen = {ALL=true}
    for _,prop in ipairs(props) do
        if prop.library == "vanilla" then
            local folder = prop.folder or "ROOT"
            if not seen[folder] then
                seen[folder] = true
                table.insert(folders,folder)
            end
        end
    end
    table.sort(folders,function(a,b)
        if a == "ALL" then return true end
        if b == "ALL" then return false end
        return string.lower(a) < string.lower(b)
    end)
    vanilla_folders = folders
    if vanilla_folder_index > #vanilla_folders then vanilla_folder_index = 1 end
end

local function ensure_vanilla_props_loaded()
    if vanilla_loaded then return true end
    local files = list_vanilla_prop_xmls()
    if #files == 0 then
        status_text = "Vanilla props scan failed"
        return false
    end
    for _,path in ipairs(files) do
        local rel,folder,label = vanilla_info(path)
        table.insert(props,{
            key="vanilla:" .. rel,
            label=label,
            entity=path,
            library="vanilla",
            folder=folder,
            vanilla=true
        })
    end
    vanilla_loaded = true
    rebuild_vanilla_folders()
    status_text = "Vanilla props: " .. tostring(#files)
    return true
end

local function library_indices()
    local result = {}
    local folder = vanilla_folders[vanilla_folder_index] or "ALL"
    for i,prop in ipairs(props) do
        if props_library_mode == "custom" then
            if prop.library ~= "vanilla" then table.insert(result,i) end
        elseif prop.library == "vanilla" and (folder == "ALL" or prop.folder == folder) then
            table.insert(result,i)
        end
    end
    return result
end

local function find_prop(key)
    for i,prop in ipairs(props) do
        if prop.key == key then return prop,i end
    end
    return nil,nil
end

local function get_sprite(entity)
    if entity == nil or entity == 0 then return nil end
    return EntityGetFirstComponentIncludingDisabled(entity,"SpriteComponent")
end

local function get_z(entity)
    local sprite = get_sprite(entity)
    if sprite == nil then return 0.5 end
    return ComponentGetValue2(sprite,"z_index")
end

local function set_z(entity,z)
    local sprite = get_sprite(entity)
    if sprite == nil then return end
    local image_file = ComponentGetValue2(sprite,"image_file")
    local offset_x = ComponentGetValue2(sprite,"offset_x")
    local offset_y = ComponentGetValue2(sprite,"offset_y")
    local alpha = ComponentGetValue2(sprite,"alpha")
    local visible = ComponentGetValue2(sprite,"visible")
    local emissive = ComponentGetValue2(sprite,"emissive")
    local additive = ComponentGetValue2(sprite,"additive")
    local smooth_filtering = ComponentGetValue2(sprite,"smooth_filtering")
    local rect_animation = ComponentGetValue2(sprite,"rect_animation")
    EntityRemoveComponent(entity,sprite)
    local new_sprite = EntityAddComponent2(entity,"SpriteComponent",{
        image_file=image_file,offset_x=offset_x,offset_y=offset_y,alpha=alpha,visible=visible,
        emissive=emissive,additive=additive,smooth_filtering=smooth_filtering,
        rect_animation=rect_animation,z_index=z,update_transform=true
    })
    EntityRefreshSprite(entity,new_sprite)
end

local function compact_instances()
    for i=#instances,1,-1 do
        local instance = instances[i]
        if instance.entity == nil or instance.entity == 0 or not EntityGetIsAlive(instance.entity) then
            table.remove(instances,i)
            if selected_instance > i then selected_instance = selected_instance - 1 end
        end
    end
    if #instances == 0 then selected_instance = 0
    elseif selected_instance < 1 then selected_instance = 1
    elseif selected_instance > #instances then selected_instance = #instances end
end

local function get_selected_instance()
    compact_instances()
    if selected_instance < 1 or selected_instance > #instances then return nil end
    return instances[selected_instance]
end

local function spawn_instance(prop,x,y,z)
    if prop == nil then return nil end
    local entity = EntityLoad(prop.entity,x,y)
    if entity == nil or entity == 0 then return nil end
    EntityAddTag(entity,"prop_editor_instance")
    if z ~= nil then set_z(entity,z) end
    local instance = {uid=next_instance_uid,prop_key=prop.key,entity=entity}
    next_instance_uid = next_instance_uid + 1
    table.insert(instances,instance)
    selected_instance = #instances
    return instance
end

local function spawn_selected_at_player()
    local prop = props[selected_prop]
    if prop == nil then return end
    local players = EntityGetWithTag("player_unit") or {}
    if #players == 0 then status_text = "Player not found" return end
    local x,y = EntityGetTransform(players[1])
    local instance = spawn_instance(prop,x,y,0.5)
    if instance ~= nil then status_text = "Spawned " .. prop.label else status_text = "Spawn failed" end
end

local function delete_selected_instance()
    local instance = get_selected_instance()
    if instance == nil then status_text = "No instance selected" return end
    local deleted_label = instance.prop_key
    if instance.entity ~= nil and EntityGetIsAlive(instance.entity) then EntityKill(instance.entity) end
    table.remove(instances,selected_instance)
    if selected_instance > #instances then selected_instance = #instances end
    status_text = "Deleted " .. deleted_label
end

local function clear_scene(silent)
    for _,instance in ipairs(instances) do
        if instance.entity ~= nil and EntityGetIsAlive(instance.entity) then EntityKill(instance.entity) end
    end
    instances = {}
    selected_instance = 0
    if not silent then status_text = "Scene cleared" end
end

local function move_selected(dx,dy)
    local instance = get_selected_instance()
    if instance == nil then return end
    local x,y = EntityGetTransform(instance.entity)
    EntitySetTransform(instance.entity,x+dx,y+dy)
end

local function change_selected_z(delta)
    local instance = get_selected_instance()
    if instance == nil then return end
    local z = get_z(instance.entity)
    z = math.floor((z+delta)*1000+0.5)/1000
    set_z(instance.entity,z)
end

local function cycle_instance(delta)
    compact_instances()
    if #instances == 0 then return end
    selected_instance = selected_instance + delta
    if selected_instance < 1 then selected_instance = #instances end
    if selected_instance > #instances then selected_instance = 1 end
end

local function save_scene()
    local file = io.open(LAYOUT_PATH,"w")
    if file == nil then
        status_text = "Save failed - Unsafe mods?"
        GamePrintImportant("Prop Editor","Could not write layout.csv. Enable Unsafe mods.")
        return
    end
    file:write("prop,x,y,z\n")
    compact_instances()
    for _,instance in ipairs(instances) do
        local prop = find_prop(instance.prop_key)
        if prop ~= nil and EntityGetIsAlive(instance.entity) then
            local x,y = EntityGetTransform(instance.entity)
            local z = get_z(instance.entity)
            file:write(prop.key .. "," .. tostring(math.floor(x+0.5)) .. "," .. tostring(math.floor(y+0.5)) .. "," .. string.format("%.3f",z) .. "\n")
        end
    end
    file:close()
    status_text = "Scene saved: " .. tostring(#instances) .. " props"
    GamePrintImportant("Prop Editor",status_text)
end

local function load_scene()
    ensure_vanilla_props_loaded()
    local file = io.open(LAYOUT_PATH,"r")
    if file == nil then status_text = "layout.csv not found" return end
    local rows = {}
    for line in file:lines() do
        local key,x,y,z = string.match(line,"^([^,]+),([^,]+),([^,]+),([^,]+)$")
        if key ~= nil and key ~= "prop" then
            table.insert(rows,{key=key,x=tonumber(x),y=tonumber(y),z=tonumber(z)})
        end
    end
    file:close()
    clear_scene(true)
    local loaded = 0
    local missing = 0
    for _,row in ipairs(rows) do
        local prop = find_prop(row.key)
        if prop ~= nil and row.x ~= nil and row.y ~= nil then
            if spawn_instance(prop,row.x,row.y,row.z or 0.5) ~= nil then loaded = loaded + 1 end
        else
            missing = missing + 1
        end
    end
    status_text = "Loaded " .. tostring(loaded)
    if missing > 0 then status_text = status_text .. " | missing " .. tostring(missing) end
    GamePrintImportant("Prop Editor",status_text)
end

local function refresh_gfx_props()
    ensure_generated_dir()
    remove_auto_prop_definitions()
    local scanned,added,sheets,auto_sheets,failed = discover_auto_props()
    props_page = 1
    status_text = "PNG " .. tostring(scanned) .. " | imported " .. tostring(added) .. " | anim " .. tostring(sheets)
    if auto_sheets > 0 then status_text = status_text .. " (auto " .. tostring(auto_sheets) .. ")" end
    if failed > 0 then status_text = status_text .. " | unresolved " .. tostring(failed) end
    GamePrintImportant("Prop Editor",status_text)
end

ensure_generated_dir()
discover_auto_props()

local function draw_panel(gui,id,x,y,w,h,alpha)
    GuiZSetForNextWidget(gui,100)
    GuiImage(gui,id,x,y,MOD_ROOT .. "/files/ui/panel.png",alpha or 0.80,w,h,0)
end

local function draw_prop_library(gui,id_base,panel_x,panel_y)
    if not props_menu_open then return end
    local w = 174
    local x = math.max(5,panel_x-w-8)
    local y = panel_y
    local indices = library_indices()
    local total_pages = math.max(1,math.ceil(#indices/props_per_page))
    if props_page > total_pages then props_page = total_pages end
    local first = (props_page-1)*props_per_page+1
    local last = math.min(#indices,first+props_per_page-1)
    local rows = math.max(0,last-first+1)
    local extra = props_library_mode == "vanilla" and 24 or 12
    local h = 38 + extra + rows*11 + (total_pages > 1 and 15 or 0)
    draw_panel(gui,id_base,x-5,y-5,w+10,h+10,0.84)
    local id = id_base + 1
    GuiText(gui,x,y,"PROP LIBRARY")
    y = y + 12
    if GuiButton(gui,id,x,y,props_library_mode == "custom" and "> CUSTOM" or "CUSTOM") then
        props_library_mode = "custom"
        props_page = 1
    end
    id = id + 1
    if GuiButton(gui,id,x+82,y,props_library_mode == "vanilla" and "> VANILLA" or "VANILLA") then
        if ensure_vanilla_props_loaded() then
            props_library_mode = "vanilla"
            props_page = 1
        end
    end
    id = id + 1
    y = y + 13

    if props_library_mode == "vanilla" then
        local folder = vanilla_folders[vanilla_folder_index] or "ALL"
        if GuiButton(gui,id,x,y,"<") then
            vanilla_folder_index = vanilla_folder_index - 1
            if vanilla_folder_index < 1 then vanilla_folder_index = #vanilla_folders end
            props_page = 1
        end
        id = id + 1
        local folder_text = folder
        if #folder_text > 18 then folder_text = string.sub(folder_text,1,18) .. ".." end
        GuiText(gui,x+18,y+1,folder_text)
        if GuiButton(gui,id,x+151,y,">") then
            vanilla_folder_index = vanilla_folder_index + 1
            if vanilla_folder_index > #vanilla_folders then vanilla_folder_index = 1 end
            props_page = 1
        end
        id = id + 1
        y = y + 12
        indices = library_indices()
        total_pages = math.max(1,math.ceil(#indices/props_per_page))
        if props_page > total_pages then props_page = total_pages end
        first = (props_page-1)*props_per_page+1
        last = math.min(#indices,first+props_per_page-1)
    end

    for pos=first,last do
        local i = indices[pos]
        local prop = props[i]
        if prop ~= nil then
            local prefix = i == selected_prop and "> " or "  "
            local suffix = prop.sheet and " [ANIM]" or ""
            local label = prop.label
            local max_label = 23 - #suffix
            if #label > max_label then
                label = string.sub(label,1,math.max(1,max_label-2)) .. ".."
            end
            local text = label .. suffix
            if GuiButton(gui,id,x,y,prefix .. text) then
                selected_prop = i
                status_text = "Type: " .. prop.label
            end
            id = id + 1
            y = y + 11
        end
    end
    if #indices == 0 then
        GuiText(gui,x,y,"No props in this group")
        y = y + 11
    end
    if total_pages > 1 then
        if GuiButton(gui,id,x,y,"< PREV") then props_page = math.max(1,props_page-1) end
        id = id + 1
        GuiText(gui,x+66,y+1,tostring(props_page) .. "/" .. tostring(total_pages))
        if GuiButton(gui,id,x+112,y,"NEXT >") then props_page = math.min(total_pages,props_page+1) end
    end
end

local function draw_editor()
    if not editor_ready then return end
    if gui == nil then gui = GuiCreate() end
    GuiStartFrame(gui)
    compact_instances()
    local sw,sh = GuiGetScreenDimensions(gui)
    if editor_minimized then
        local mini_w = 94
        local mini_h = 18
        local mini_x = math.max(6,sw-mini_w-7)
        local mini_y = math.max(6,sh-mini_h-7)
        local mini_id = 51900
        draw_panel(gui,mini_id,mini_x,mini_y,mini_w,mini_h,0.82)
        if GuiButton(gui,mini_id+1,mini_x+6,mini_y+5,"PROP EDITOR +") then
            editor_minimized = false
        end
        return
    end
    local panel_w = 184
    local panel_h = 214
    local panel_x = math.max(6,sw-panel_w-7)
    local panel_y = math.min(math.max(62,math.floor(sh*0.13)),math.max(6,sh-panel_h-6))
    local x = panel_x + 7
    local y = panel_y + 6
    local id = 52000
    draw_panel(gui,id,panel_x,panel_y,panel_w,panel_h,0.82)
    id = id + 1

    GuiText(gui,x,y,"PROP EDITOR")
    if GuiButton(gui,id,x+151,y,"-") then
        editor_minimized = true
        props_menu_open = false
        return
    end
    id = id + 1
    y = y + 13
    if GuiButton(gui,id,x,y,props_menu_open and "PROPS -" or "PROPS +") then props_menu_open = not props_menu_open end
    id = id + 1
    if GuiButton(gui,id,x+72,y,"REFRESH GFX") then refresh_gfx_props() end
    id = id + 1
    y = y + 14

    local prop = props[selected_prop]
    GuiText(gui,x,y,"TYPE: " .. (prop and prop.label or "none"))
    y = y + 11

    local instance = get_selected_instance()
    if instance ~= nil then
        local instance_prop = find_prop(instance.prop_key)
        GuiText(gui,x,y,"INSTANCE " .. tostring(selected_instance) .. "/" .. tostring(#instances) .. ": " .. (instance_prop and instance_prop.label or instance.prop_key))
    else
        GuiText(gui,x,y,"INSTANCE: none")
    end
    y = y + 11
    if GuiButton(gui,id,x,y,"<") then cycle_instance(-1) end; id=id+1
    if GuiButton(gui,id,x+18,y,">") then cycle_instance(1) end; id=id+1
    if GuiButton(gui,id,x+43,y,"SPAWN") then spawn_selected_at_player() end; id=id+1
    if GuiButton(gui,id,x+95,y,"DELETE") then delete_selected_instance() end; id=id+1
    y = y + 14

    GuiText(gui,x,y,"POSITION")
    y = y + 10
    instance = get_selected_instance()
    if instance ~= nil then
        local px,py = EntityGetTransform(instance.entity)
        GuiText(gui,x,y,"X " .. tostring(math.floor(px+0.5)) .. "  Y " .. tostring(math.floor(py+0.5)) .. "  Z " .. string.format("%.2f",get_z(instance.entity)))
    else
        GuiText(gui,x,y,"No placed prop selected")
    end
    y = y + 13

    GuiText(gui,x,y,"MOVE 1")
    y = y + 10
    if GuiButton(gui,id,x,y,"LEFT") then move_selected(-1,0) end; id=id+1
    if GuiButton(gui,id,x+42,y,"UP") then move_selected(0,-1) end; id=id+1
    if GuiButton(gui,id,x+73,y,"DOWN") then move_selected(0,1) end; id=id+1
    if GuiButton(gui,id,x+119,y,"RIGHT") then move_selected(1,0) end; id=id+1
    y = y + 13

    GuiText(gui,x,y,"MOVE 10")
    y = y + 10
    if GuiButton(gui,id,x,y,"LEFT") then move_selected(-10,0) end; id=id+1
    if GuiButton(gui,id,x+42,y,"UP") then move_selected(0,-10) end; id=id+1
    if GuiButton(gui,id,x+73,y,"DOWN") then move_selected(0,10) end; id=id+1
    if GuiButton(gui,id,x+119,y,"RIGHT") then move_selected(10,0) end; id=id+1
    y = y + 14

    GuiText(gui,x,y,"LAYER  lower Z = front")
    y = y + 10
    if GuiButton(gui,id,x,y,"FRONT 1") then change_selected_z(-1.0) end; id=id+1
    if GuiButton(gui,id,x+57,y,"FRONT .1") then change_selected_z(-0.1) end; id=id+1
    if GuiButton(gui,id,x+119,y,"BACK .1") then change_selected_z(0.1) end; id=id+1
    y = y + 11
    if GuiButton(gui,id,x,y,"BACK 1") then change_selected_z(1.0) end; id=id+1
    y = y + 14

    GuiText(gui,x,y,"SCENE  " .. tostring(#instances) .. " placed")
    y = y + 10
    if GuiButton(gui,id,x,y,"SAVE") then save_scene() end; id=id+1
    if GuiButton(gui,id,x+46,y,"LOAD") then load_scene() end; id=id+1
    if GuiButton(gui,id,x+93,y,"CLEAR") then clear_scene(false) end; id=id+1
    y = y + 13

    GuiText(gui,x,y,status_text)
    draw_prop_library(gui,53000,panel_x,panel_y)
end

function OnWorldPostUpdate()
    if editor_ready then return end
    if GameGetFrameNum()%15 ~= 0 then return end
    local players = EntityGetWithTag("player_unit") or {}
    if #players == 0 then return end
    editor_ready = true
    status_text = "Choose prop, then SPAWN"
end

function OnWorldPreUpdate()
    draw_editor()
end
