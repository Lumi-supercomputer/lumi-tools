#! /usr/bin/env lua

local debug = false

local lfs = require('lfs')

-- -----------------------------------------------------------------------------
--
-- Include code to decode a JSON file
--
-- -----------------------------------------------------------------------------

function json_decode( str )

    local parse

    local function create_set(...)
        local res = {}
        for i = 1, select("#", ...) do
            res[ select(i, ...) ] = true
        end
        return res
    end

    local space_chars   = create_set(" ", "\t", "\r", "\n")
    local delim_chars   = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
    local escape_chars  = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
    local literals      = create_set("true", "false", "null")

    local literal_map = {
    [ "true"  ] = true,
    [ "false" ] = false,
    [ "null"  ] = nil,
    }


    local function next_char(str, idx, set, negate)
        for i = idx, #str do
            if set[str:sub(i, i)] ~= negate then
            return i
            end
        end
        return #str + 1
    end


    local function decode_error(str, idx, msg)
        local line_count = 1
        local col_count = 1
        for i = 1, idx - 1 do
            col_count = col_count + 1
            if str:sub(i, i) == "\n" then
            line_count = line_count + 1
            col_count = 1
            end
        end
        error( string.format("%s at line %d col %d", msg, line_count, col_count) )
    end


    local function codepoint_to_utf8(n)
    -- http://scripts.sil.org/cms/scripts/page.php?site_id=nrsi&id=iws-appendixa
        local f = math.floor
        if n <= 0x7f then
            return string.char(n)
        elseif n <= 0x7ff then
            return string.char(f(n / 64) + 192, n % 64 + 128)
        elseif n <= 0xffff then
            return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128, n % 64 + 128)
        elseif n <= 0x10ffff then
            return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128,
                            f(n % 4096 / 64) + 128, n % 64 + 128)
        end -- if
        error( string.format("invalid unicode codepoint '%x'", n) )
    end


    local function parse_unicode_escape(s)
        local n1 = tonumber( s:sub(1, 4),  16 )
        local n2 = tonumber( s:sub(7, 10), 16 )
        -- Surrogate pair?
        if n2 then
            return codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
        else
            return codepoint_to_utf8(n1)
        end
    end


    local function parse_string(str, i)
        local res = ""
        local j = i + 1
        local k = j

        while j <= #str do
            local x = str:byte(j)

            if x < 32 then
                decode_error(str, j, "control character in string")

            elseif x == 92 then -- `\`: Escape
                res = res .. str:sub(k, j - 1)
                j = j + 1
                local c = str:sub(j, j)
                if c == "u" then
                    local hex = str:match("^[dD][89aAbB]%x%x\\u%x%x%x%x", j + 1)
                            or str:match("^%x%x%x%x", j + 1)
                            or decode_error(str, j - 1, "invalid unicode escape in string")
                    res = res .. parse_unicode_escape(hex)
                    j = j + #hex
                else
                    if not escape_chars[c] then
                    decode_error(str, j - 1, "invalid escape char '" .. c .. "' in string")
                    end
                    res = res .. escape_char_map_inv[c]
                end
                k = j + 1

            elseif x == 34 then -- `"`: End of string
                res = res .. str:sub(k, j - 1)
                return res, j + 1
            end -- if x < 32 ... elsif ... elsif

            j = j + 1
        end

        decode_error(str, i, "expected closing quote for string")
    end -- function parse_string


    local function parse_number(str, i)
        local x = next_char(str, i, delim_chars)
        local s = str:sub(i, x - 1)
        local n = tonumber(s)
        if not n then
            decode_error(str, i, "invalid number '" .. s .. "'")
        end
        return n, x
    end


    local function parse_literal(str, i)
        local x = next_char(str, i, delim_chars)
        local word = str:sub(i, x - 1)
        if not literals[word] then
            decode_error(str, i, "invalid literal '" .. word .. "'")
        end
        return literal_map[word], x
    end


    local function parse_array(str, i)
        local res = {}
        local n = 1
        i = i + 1
        while 1 do
            local x
            i = next_char(str, i, space_chars, true)
            -- Empty / end of array?
            if str:sub(i, i) == "]" then
            i = i + 1
            break
            end
            -- Read token
            x, i = parse(str, i)
            res[n] = x
            n = n + 1
            -- Next token
            i = next_char(str, i, space_chars, true)
            local chr = str:sub(i, i)
            i = i + 1
            if chr == "]" then break end
            if chr ~= "," then decode_error(str, i, "expected ']' or ','") end
        end
        return res, i
    end


    local function parse_object(str, i)
        local res = {}
        i = i + 1
        while 1 do
            local key, val
            i = next_char(str, i, space_chars, true)
            -- Empty / end of object?
            if str:sub(i, i) == "}" then
                i = i + 1
                break
            end
            -- Read key
            if str:sub(i, i) ~= '"' then
                decode_error(str, i, "expected string for key")
            end
            key, i = parse(str, i)
            -- Read ':' delimiter
            i = next_char(str, i, space_chars, true)
            if str:sub(i, i) ~= ":" then
                decode_error(str, i, "expected ':' after key")
            end
            i = next_char(str, i + 1, space_chars, true)
            -- Read value
            val, i = parse(str, i)
            -- Set
            res[key] = val
            -- Next token
            i = next_char(str, i, space_chars, true)
            local chr = str:sub(i, i)
            i = i + 1
            if chr == "}" then break end
            if chr ~= "," then decode_error(str, i, "expected '}' or ','") end
        end
        return res, i
    end


    local char_func_map = {
    [ '"' ] = parse_string,
    [ "0" ] = parse_number,
    [ "1" ] = parse_number,
    [ "2" ] = parse_number,
    [ "3" ] = parse_number,
    [ "4" ] = parse_number,
    [ "5" ] = parse_number,
    [ "6" ] = parse_number,
    [ "7" ] = parse_number,
    [ "8" ] = parse_number,
    [ "9" ] = parse_number,
    [ "-" ] = parse_number,
    [ "t" ] = parse_literal,
    [ "f" ] = parse_literal,
    [ "n" ] = parse_literal,
    [ "[" ] = parse_array,
    [ "{" ] = parse_object,
    }


    parse = function(str, idx)
        local chr = str:sub(idx, idx)
        local f = char_func_map[chr]
        if f then
            return f(str, idx)
        end
        decode_error(str, idx, "unexpected character '" .. chr .. "'")
    end

  --
  -- Actual json_decode code
  --

    if type(str) ~= "string" then
        error("expected argument of type string, got " .. type(str))
    end
    local res, idx = parse(str, next_char(str, 1, space_chars, true))
    idx = next_char(str, idx, space_chars, true)
    if idx <= #str then
        decode_error(str, idx, "trailing garbage")
    end
    return res

end  -- function json_decode

-- -----------------------------------------------------------------------------
--
-- End of: Include code to decode a JSON file
--
-- -----------------------------------------------------------------------------


-- -----------------------------------------------------------------------------
--
-- Helper function: Split a string
--
-- -----------------------------------------------------------------------------

function string:split(sep)
    local sep, fields = sep or ":", {}
    local pattern = string.format("([^%s]+)", sep)
    self:gsub(pattern, function(c) fields[#fields+1] = c end)
    return fields
 end


-- -----------------------------------------------------------------------------
--
-- Function to print help information.
--
-- -----------------------------------------------------------------------------

function print_help()

    print( 
        '\nlumi-ldap-userinfo: Print information about current quota and allocations\n\n' ..
        'Arguments:\n' ..
        '  -h/--help:              Show this help and quit\n' ..
        '  -u/--user <userid> :    Show information for the given user or users\n' ..
        '                          (comma-separated list)\n' ..
        'Users can also be specified without using -u.\n' ..
        'Without any arguments the information of the current user will be printed.'
    )

end


-- -----------------------------------------------------------------------------
--
-- Function to get the list of projects of a userid.
--
-- -----------------------------------------------------------------------------

function get_projects_from_user( userid )

    local cmd = "/usr/bin/getent group | /usr/bin/grep project_ | " ..
                "/usr/bin/sed -e 's/,/|/g' -e 's/:/|/g' -e 's/\\(.*\\)/\\1|/' | " ..
                "/usr/bin/grep '|" .. userid .. "|' | " ..
                "/usr/bin/cut -d'|' -f1"

    local project_list = {}
    
    fh = io.popen( cmd, 'r')
    for line in fh:lines() do table.insert( project_list, line ) end
    fh:close()
    table.sort( project_list )
    
    return project_list


end  -- function get_projects_from_user


-- -----------------------------------------------------------------------------
--
-- Function to get the title of a project.
--
-- -----------------------------------------------------------------------------

function get_project_title( project )

    local project_path = '/var/lib/project_info'
    local project_postfix = project .. '/' .. project .. '.json'

    -- First try to open the lust version as that one contains more data.
    local project_file = project_path .. '/lust/' .. project_postfix
    -- print( 'Attempting to read information from ' ..project_file )
    local fh = io.open( project_file, 'r' )
    if fh == nil then
        project_file = project_path .. '/users/' .. project_postfix
        -- print( 'Now attempting to read information from ' project_file )
        fh = io.open( project_file, 'r' )
    end
    if fh == nil then 
        return 'TITLE UNKNOWN'
    end
    local project_info_str = fh:read( '*all' )
    fh:close()
    
    local project_timestamp = lfs.attributes( project_file, 'modification' )

    local project_info = json_decode( project_info_str )
    
    return project_info['title'] or 'TITLE UNKNOWN'
   
end  -- function get_project_title


-- -----------------------------------------------------------------------------
--
-- Function to generate the escape codes for printing values that are compared
-- to thresholds. Two values are returned: The escape codes to turn the colour
-- on and off.
--
-- -----------------------------------------------------------------------------

function colour_thresholds( value )

    local threshold_red =    100.0
    local threshold_orange = 90.0
    
    if value >= threshold_red then 
        return string.char(27) .. '[31m', string.char(27) .. '[0m'
    elseif value >= threshold_orange then 
        return string.char(27) .. '[33m', string.char(27) .. '[0m'
    else
        return '', ''
    end

end


-- -----------------------------------------------------------------------------
--
-- Function to format numbers in a field of given width
--
-- -----------------------------------------------------------------------------

function format_value( value, width )

    if value == math.ceil( value ) then
        local format_string = '%' .. width .. 'd'
        value_str = string.format( format_string, value )
    elseif value < 10 then
        local field_post = width - 2
        local field_pre = 1
        local format_string = '%' .. field_pre .. '.' .. field_post .. 'f'
        value_str = string.format( format_string, value )
    elseif value < 100 then
        local field_post = width - 3
        local field_pre = 2
        local format_string = '%' .. field_pre .. '.' .. field_post .. 'f'
        value_str = string.format( format_string, value )
    elseif value < 1000 then
        local field_post = width - 4
        local field_pre = 3
        local format_string = '%' .. field_pre .. '.' .. field_post .. 'f'
        value_str = string.format( format_string, value )
    else
        local field_post = width - 5
        local field_pre
        if width == 5 then field_pre = width else field_pre = 4 end
        local format_string = '%' .. field_pre .. '.' .. field_post .. 'f'
        value_str = string.format( format_string, value )
    end    
    
    return value_str

end


-- -----------------------------------------------------------------------------
--
-- Function to convert to KiB/MiB/GiB/TiB/PiB.
--
-- Pretty dirty code at the moment that could be made a lot shorter with
-- a loop and constant array, and the second part could be moved to a separate
-- function also as it is repeaded elsewhere.
--
-- -----------------------------------------------------------------------------

function convert_to_iec( value, width )

    -- Note we currently assue width >= 5.
    -- The width parameter also does not include the width for the units.

    local value_str
    local unit_str

    if value < 1024 then  
        unit_str = 'B  '
    else
        value = value / 1024
        if value < 1024 then
            unit_str = 'KiB'
        else
            value = value / 1024
            if value < 1024 then
                unit_str = 'MiB'
            else
                value = value / 1024
                if value < 1024 then
                    unit_str = 'GiB'
                else
                    value = value / 1024
                    if value < 1024 then
                        unit_str = 'TiB'
                    else
                        value = value / 1024
                        unit_str = 'PiB'
                    end
                end
            end
        end    
    end


    return format_value( value, width ) .. unit_str

end


-- -----------------------------------------------------------------------------
--
-- Function to convert to SI: K, M, G, T, P
--
-- Pretty dirty code at the moment that could be made a lot shorter with
-- a loop and constant array, and the second part could be moved to a separate
-- function also as it is repeaded elsewhere.
--
-- -----------------------------------------------------------------------------

function convert_to_si( value, width )

    -- Note we currently assue width >= 5.
    -- The width parameter also does not include the width for the units.

    local value_str
    local unit_str

    if value < 1000 then  
        unit_str = ' '
    else
        value = value / 1000
        if value < 1000 then
            unit_str = 'K'
        else
            value = value / 1000
            if value < 1000 then
                unit_str = 'M'
            else
                value = value / 1000
                if value < 1000 then
                    unit_str = 'G'
                else
                    value = value / 1000
                    if value < 1000 then
                        unit_str = 'T'
                    else
                        value = value / 1000
                        unit_str = 'P'
                    end
                end
            end
        end    
    end

    return format_value( value, width ) .. unit_str

end


-- -----------------------------------------------------------------------------
--
-- Process the command line arguments
--

local argctr = 1
local user_list = {}

while ( argctr <= #arg )
do
    if ( arg[argctr] == '-h' or arg[argctr] == '--help' ) then
        print_help()
        os.exit( 0 )
    elseif ( arg[argctr] == '-u' or arg[argctr] == '--user' ) then
        argctr = argctr + 1
        for _, user in ipairs( arg[argctr]:split( ',' ) ) do
            table.insert( user_list, user )
        end
    elseif arg[argctr]:sub(1, 1)  ~=  '-' then
        -- An argument that does not start with a dash: treat as a user list
        for _, user in ipairs( arg[argctr]:split( ',' ) ) do
            table.insert( user_list, user )
        end
        if debug then io.stderr:write( 'DEBUG: Found project argument with value ' .. arg[argctr] .. '\n' ) end        
    else
        io.stderr:write( 'Error: ' .. arg[argctr]  .. ' is an unrecognised argument.\n' )
        os.exit( 1 )
    end
    argctr = argctr + 1
end

if #arg == 0 then

    -- No arguments so we use the projects of the current user.
    
    local user_executing = os.getenv( 'USER' )
    table.insert( user_list, user_executing )

end

local user_path = '/var/lib/user_info'
local first = true

for _,user in ipairs( user_list )
do

    -- print( 'Gathering information for user ' .. user )
    
    local user_postfix = user .. '/' .. user .. '.json'

    -- First try to open the lust version as that one contains more data.
    local user_file = user_path .. '/lust/' .. user_postfix
    -- print( 'Attempting to read information from ' .. user_file )
    local fh = io.open( user_file, 'r' )
    if fh == nil then
        user_file = user_path .. '/users/' .. user_postfix
        -- print( 'Now attempting to read information from ' user_file )
        fh = io.open( user_file, 'r' )
    end
    if fh == nil then 
        io.stderr:write( 'ERROR: You may not have sufficient rights to get information from user ' .. user .. 
                         ' or the user name is invalid.\n\n' )
        os.exit( 1 )
    end
    local user_info_str = fh:read( '*all' )
    fh:close()
    
    local user_timestamp = lfs.attributes( user_file, 'modification' )

    local user_info = json_decode( user_info_str )
    -- for key,value in pairs( user_info ) do print( 'Key: ' .. key ) end

    --
    -- Print the header
    --

    if first then
        print()
        first = false
    else
        print( '--------------------------------------------------------------------------------\n' )
    end
    print( 'Information for ' .. user .. ':\n' )
    print( '- Data was last refreshed at ' .. os.date( '%c', user_timestamp ) )
        
    --
    -- Get some general information
    --
    print( '- General information:' )
    print( '  - GECOS: ' .. (user_info['gecos'] or 'UNKNOWN') )
    
    if user_info['is_active']  ~=  nil then
	    if user_info['is_active'] then
	        print( '  - User is an active user (field is_active true)' )
	    else
	        print( '  - User is not an active user (field is_active false)' )
	    end
    end
    
    if user_info['valid_compute_user']  ~=  nil then
	    if user_info['valid_compute_user'] then
	        print( '  - User is a valid compute user (field valid_compute_user true)' )
	    else
	        print( '  - User is a valid compute user (field valid_compute_user false)' )
	    end
    end
    
    if user_info['is_banned']  ~=  nil then
	    if user_info['is_banned'] then
	        print( '  - User is banned (field is_banned true)' )
	    else
	        print( '  - User is not banned (field is_banned false)' )
	    end
    end
    
    --
    -- Storage information
    --
    
    if user_info['home_fs'] == nil or user_info['home_quota'] == nil then
        print( '- User is no longer hosted on lumi.' )
    else
        --
	    -- Determine the location of the project in the file system
	    --
        _, _, user_fs = string.find( user_info['home_fs'], '/pfs/(lustrep%d)/users' )
	    print( '- Storage information:' )
	    print( '  - User hosted on ' .. ( user_fs or 'UNKNOWN' ) )
 
        --
        -- Check disk quotas
        --

	    local use_cached = true
	    local quota = {}
	    
	    -- Project directory
	    quota = {}
        quota['block_used'] = user_info['home_quota']['block_quota_used']
	    quota['block_soft'] = user_info['home_quota']['block_quota_soft']
	    quota['block_hard'] = user_info['home_quota']['block_quota_hard']
	    quota['inode_used'] = user_info['home_quota']['inode_quota_used']
	    quota['inode_soft'] = user_info['home_quota']['inode_quota_soft']
	    quota['inode_hard'] = user_info['home_quota']['inode_quota_hard']
    
	    print( '  - Disk quota (cached info):' )
	    
        block_perc_used = 100 * quota['block_used'] / quota['block_soft']
	    inode_perc_used = 100 * quota['inode_used'] / quota['inode_soft']
	    local block_colour_on, block_colour_off = colour_thresholds( block_perc_used )
	    local inode_colour_on, inode_colour_off = colour_thresholds( inode_perc_used )
	    
	    print( '    - block quota: '  .. block_colour_on .. string.format( '%5.1f', block_perc_used ) .. 
	           '% used (' .. convert_to_iec( quota['block_used'] * 1024, 5 ) .. ' of ' .. convert_to_iec( quota['block_soft'] * 1024, 5 ) .. 
	           '/' .. convert_to_iec( quota['block_hard'] * 1024, 7 ) .. ' soft/hard)' .. block_colour_off ..
	           ',\n' ..  
	           '    - file quota:  ' .. inode_colour_on .. string.format( '%5.1f', inode_perc_used ) .. 
	           '% used (' .. convert_to_si( quota['inode_used'], 5 ) .. '   of ' .. convert_to_si( quota['inode_soft'], 5 ) .. 
	           '  /' .. convert_to_si( quota['inode_hard'], 7 ) .. '   soft/hard)' .. inode_colour_off )
	        
    end
    
    --
    -- Print key information (if sufficient privileges)
    --
    
    local fh = io.open( '/project/project_462000008/ldaplog/sshkey_fingerprints.txt', 'r' )
    
    if fh ~= nil then
    
        -- Read the file at once (though I don't knw if this is more efficient than
        -- using lines() to process line by line)
    	local key_info_str = fh:read( '*all' )
        fh:close()
        
        local keys = {}
        local key
        
        for line in key_info_str:gmatch("([^\n]*)\n?") do
        
            local pos, key
            pos, _, key = string.find( line, '^' .. user .. '%.pub: (.*)' )
            
            if pos == 1 then table.insert( keys, key ) end
                  
        end
        
        local keys_timestamp = lfs.attributes( '/project/project_462000008/ldaplog/sshkey_fingerprints.txt', 'modification' )
        
        if #keys == 0 then
        
            print( '- No keys found for this account (key data from ' .. os.date( '%c', keys_timestamp ) .. ')' )
            
        else   
            
            print( '- Keys found on the system for this account (key data from ' .. os.date( '%c', keys_timestamp ) .. '):' )
            for _, key in ipairs( keys ) do
                print( '  - ' .. key )
            end
            
        end
    
    end -- if fh = nil, processing key data.

    
    --
    -- List the projects
    --
    
    local project_list = get_projects_from_user( user )
    
    if project_list ~=  nil and #project_list > 0 then
    
        print( '- Projects on the system the user is a member of:' )
        
        for _,project in ipairs( project_list ) do
        
            print( '  - ' .. project .. ' - ' .. get_project_title( project ) )
            
        end
        
    else
    
        print( '- No projects of the user found on the system' )
    
    end -- if project_list ~=  nil and #project_list > 0

    print( )

end
