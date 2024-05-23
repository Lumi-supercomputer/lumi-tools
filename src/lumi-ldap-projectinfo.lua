#! /usr/bin/env lua

local debug = false

local lfs = require('lfs')

-- -----------------------------------------------------------------------------
--
-- Include code to decode a JSON file
--
-- -----------------------------------------------------------------------------

function json_decode( str )

	local escape_char_map = {
	    [ "\\" ] = "\\",
	    [ "\"" ] = "\"",
	    [ "\b" ] = "b",
	    [ "\f" ] = "f",
	    [ "\n" ] = "n",
	    [ "\r" ] = "r",
	    [ "\t" ] = "t",
	}
	
	local escape_char_map_inv = { [ "/" ] = "/" }
	for k, v in pairs(escape_char_map) do
	    escape_char_map_inv[v] = k
	end

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
-- Helper function: Check if a node has the proper data
--
-- -----------------------------------------------------------------------------

function check_ldap_info()

    require( 'lfs' )
    
    return ( lfs.attributes( '/var/lib/project_info', 'mode' ) == 'directory' ) and
           ( lfs.attributes( '/var/lib/user_info', 'mode' )    == 'directory' )

 end


-- -----------------------------------------------------------------------------
--
-- Function to print help information.
--
-- -----------------------------------------------------------------------------

function print_help()

    print( 
        '\nlumi-ldap-projectinfo: Print information about current quota and allocations\n\n' ..
        'Arguments:\n' ..
        '  -h/--help:              Show this help and quit\n' ..
        '  -p/--project <project>: Show information for the given project or given list of projects\n' ..
        '                          (comma-separated and without spaces)\n' ..
        '  -u/--user <userid> :    Add all projects of user <userid> to the list\n' ..
        'Projects can also be specified without using -p.\n' ..
        'Without any arguments the information of the projects of the current user will be printed.'
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
-- Function to create a table with names for each userid
--
-- -----------------------------------------------------------------------------

function get_user_table()

	cmd = '/usr/bin/getent passwd'
	
	local user_table = {}
	
	fh = io.popen( cmd, 'r' )
	for line in fh:lines() do
	    local userid, name
	    _, _, userid, name = line:find( '([^:]*):[^:]*:[^*]*:[^:]*:([^:]*):[^:]*:[^:]*' )
	    user_table[userid] = name
	end
	fh:close()

    
    return user_table


end  -- function get_user_table


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
-- Main code
--

if not check_ldap_info() then

    io.stderr:write( 'Error: This node does not provide the LDAP information needed.\n\n' )
    os.exit( 1 )

end

-- -----------------------------------------------------------------------------
--
-- Process the command line arguments
--

local argctr = 1
local project_list = {}

while ( argctr <= #arg )
do
    if ( arg[argctr] == '-h' or arg[argctr] == '--help' ) then
        print_help()
        os.exit( 0 )
    elseif ( arg[argctr] == '-p' or arg[argctr] == '--project' ) then
        argctr = argctr + 1
        for _, project in ipairs( arg[argctr]:split( ',' ) ) do
            if string.match( project, '^46%d%d%d%d%d%d%d$' ) then
                table.insert( project_list, 'project_' .. project )
            else
                table.insert( project_list, project )
            end
        end
        if debug then io.stderr:write( 'DEBUG: Found -p/--project argument with value ' .. arg[argctr] .. '\n' ) end
    elseif ( arg[argctr] == '-u' or arg[argctr] == '--user' ) then
        argctr = argctr + 1
        local user_projects = get_projects_from_user( arg[argctr] )
        for _, project in ipairs( user_projects ) do
            table.insert( project_list, project )
        end
    elseif arg[argctr]:sub(1, 1)  ~=  '-' then
        -- An argument that does not start with a dash: treat as a project list
        for _, project in ipairs( arg[argctr]:split( ',' ) ) do
             if string.match( project, '^46%d%d%d%d%d%d%d$' ) then
                table.insert( project_list, 'project_' .. project )
            else
                table.insert( project_list, project )
            end
        end
        if debug then io.stderr:write( 'DEBUG: Found project argument with value ' .. arg[argctr] .. '\n' ) end        
    else
        io.stderr:write( 'Error: ' .. arg[argctr]  .. ' is an unrecognised argument.\n' )
        os.exit( 1 )
    end
    argctr = argctr + 1
end

if #arg == 0 then

    -- No arguments so we use the projects of the current user.without
    
    local user_executing = os.getenv( 'USER' )
    
    user_projects = get_projects_from_user( user_executing )
    for _, project in ipairs( user_projects ) do
        table.insert( project_list, project )
    end

end

local project_path = '/var/lib/project_info'
local first = true

for _,project in ipairs( project_list )
do

    -- print( 'Gathering information for project ' .. project )
    
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
        io.stderr:write( 'ERROR: You may not have sufficient rights to get information from project ' .. project .. 
                         ' or the project name is invalid.\n\n' )
        os.exit( 1 )
    end
    local project_info_str = fh:read( '*all' )
    fh:close()
    
    local project_timestamp = lfs.attributes( project_file, 'modification' )

    local project_info = json_decode( project_info_str )
    -- for key,value in pairs( project_info ) do print( 'Key: ' .. key ) end

    --
    -- Print the header
    --

    if first then
        print()
        first = false
    else
        print( '--------------------------------------------------------------------------------\n' )
    end
    print( 'Information for ' .. project .. ':\n' )
    print( '- Data was last refreshed at ' .. os.date( '%c', project_timestamp ) )
        
    --
    -- Get some general information
    --
    print( '- General information:' )
    print( '  - Title: ' .. (project_info['title'] or 'UNKNOWN') )
    
    if project_info['valid_compute_project']  ~=  nil then
	    if project_info['valid_compute_project'] then
	        print( '  - Project is valid for compute' )
	    else
	        print( '  - Project is not valid for compute' )
	    end
    end
    
    
    if project_info['is_open']  ~=  nil then
	    if project_info['is_open'] then
	        print( '  - Project is open (field is_open true)' )
	    else
	        print( '  - Project is closed (field is_open false)' )
	    end
    end

    --
    -- Storage information
    --
    
    if project_info['storage_quotas']['directories'] == nil or project_info['storage_quotas']['directories']['projappl'] == nil then
        print( '- Project is no longer hosted on lumi.' )
    else
	    local project_scratch_dir = lfs.symlinkattributes( '/scratch/' .. project, 'target' )
	    local project_fs
	    if project_scratch_dir == nil then
	        project_fs = UNKNOWN
	    else
		    --
		    -- Determine the location of the project in the file system
		    --
	        _, _, project_fs = string.find( project_scratch_dir, '/pfs/(lustrep%d)/.*' )
	    end
	    print( '- Storage information:' )
	    print( '  - Project hosted on ' .. ( project_fs or 'UNKNOWN' ) )
 
        --
        -- Check disk quotas
        --

	    local use_cached = true
	    local quota = {}
	    
	    local quota_cached = project_info['storage_quotas']['directories']
	    
	    -- Project directory
	    quota['project'] = {}
	    quota['project']['has_dir'] = quota_cached ~= nil and quota_cached ['projappl'] ~=  nil
	    if quota['project']['has_dir'] then
		    quota['project']['block_used'] = quota_cached['projappl']['block_quota_used']
		    quota['project']['block_soft'] = quota_cached['projappl']['block_quota_soft']
		    quota['project']['block_hard'] = quota_cached['projappl']['block_quota_hard']
		    quota['project']['inode_used'] = quota_cached['projappl']['inode_quota_used']
		    quota['project']['inode_soft'] = quota_cached['projappl']['inode_quota_soft']
		    quota['project']['inode_hard'] = quota_cached['projappl']['inode_quota_hard']
	    end
	    
	    -- Scratch directory
	    quota['scratch'] = {}
	    quota['scratch']['has_dir'] = quota_cached ~= nil and quota_cached ['scratch'] ~=  nil
	    if quota['scratch']['has_dir'] then
		    quota['scratch']['block_used'] = quota_cached['scratch']['block_quota_used']
		    quota['scratch']['block_soft'] = quota_cached['scratch']['block_quota_soft']
		    quota['scratch']['block_hard'] = quota_cached['scratch']['block_quota_hard']
		    quota['scratch']['inode_used'] = quota_cached['scratch']['inode_quota_used']
		    quota['scratch']['inode_soft'] = quota_cached['scratch']['inode_quota_soft']
		    quota['scratch']['inode_hard'] = quota_cached['scratch']['inode_quota_hard']
		end
	    
	    -- Flash directory
	    quota['flash'] = {}
	    quota['flash']['has_dir'] = true
	    quota['flash']['has_dir'] = quota_cached ~= nil and quota_cached ['flash'] ~=  nil
	    if quota['flash']['has_dir'] then
		    quota['flash']['block_used'] = quota_cached['flash']['block_quota_used']
		    quota['flash']['block_soft'] = quota_cached['flash']['block_quota_soft']
		    quota['flash']['block_hard'] = quota_cached['flash']['block_quota_hard']
		    quota['flash']['inode_used'] = quota_cached['flash']['inode_quota_used']
		    quota['flash']['inode_soft'] = quota_cached['flash']['inode_quota_soft']
		    quota['flash']['inode_hard'] = quota_cached['flash']['inode_quota_hard']
	    end
	    
	
	    print( '  - Disk quota (cached info):' )
	    
	    local spacer = string.gsub( project, '.', ' ' )
	
	    if quota['project']['has_dir'] then
		    block_perc_used = 100 * quota['project']['block_used'] / quota['project']['block_soft']
		    inode_perc_used = 100 * quota['project']['inode_used'] / quota['project']['inode_soft']
		    local block_colour_on, block_colour_off = colour_thresholds( block_perc_used )
		    local inode_colour_on, inode_colour_off = colour_thresholds( inode_perc_used )
		    
		    print( '    - /project/' .. project .. ': ' ..
		           'block quota: '  .. block_colour_on .. string.format( '%5.1f', block_perc_used ) .. 
		           '% used (' .. convert_to_iec( quota['project']['block_used'] * 1024, 5 ) .. ' of ' .. convert_to_iec( quota['project']['block_soft'] * 1024, 5 ) .. 
		           '/' .. convert_to_iec( quota['project']['block_hard'] * 1024, 7 ) .. ' soft/hard)' .. block_colour_off ..
		           ',\n                 ' .. spacer ..  
		           'file quota:  ' .. inode_colour_on .. string.format( '%5.1f', inode_perc_used ) .. 
		           '% used (' .. convert_to_si( quota['project']['inode_used'], 5 ) .. '   of ' .. convert_to_si( quota['project']['inode_soft'], 5 ) .. 
		           '  /' .. convert_to_si( quota['project']['inode_hard'], 7 ) .. '   soft/hard)' .. inode_colour_off )
	    end
	
	    if quota['scratch']['has_dir'] then
		    block_perc_used = 100 * quota['scratch']['block_used'] / quota['scratch']['block_soft']
		    inode_perc_used = 100 * quota['scratch']['inode_used'] / quota['scratch']['inode_soft']
		    local block_colour_on, block_colour_off = colour_thresholds( block_perc_used )
		    local inode_colour_on, inode_colour_off = colour_thresholds( inode_perc_used )
		    
		    print( '    - /scratch/' .. project .. ': ' ..
		           'block quota: '  .. block_colour_on .. string.format( '%5.1f', block_perc_used ) .. 
		           '% used (' .. convert_to_iec( quota['scratch']['block_used'] * 1024, 5 ) .. ' of ' .. convert_to_iec( quota['scratch']['block_soft'] * 1024, 5 ) .. 
		           '/' .. convert_to_iec( quota['scratch']['block_hard'] * 1024, 7 ) .. ' soft/hard)' .. block_colour_off ..
		           ',\n                 ' .. spacer ..  
		           'file quota:  ' .. inode_colour_on .. string.format( '%5.1f', inode_perc_used ) .. 
		           '% used (' .. convert_to_si( quota['scratch']['inode_used'], 5 ) .. '   of ' .. convert_to_si( quota['scratch']['inode_soft'], 5 ) .. 
		           '  /' .. convert_to_si( quota['scratch']['inode_hard'], 7 ) .. '   soft/hard)' .. inode_colour_off )
	    end
	
	    if quota['flash']['has_dir'] then
		    block_perc_used = 100 * quota['flash']['block_used'] / quota['flash']['block_soft']
		    inode_perc_used = 100 * quota['flash']['inode_used'] / quota['flash']['inode_soft']
		    local block_colour_on, block_colour_off = colour_thresholds( block_perc_used )
		    local inode_colour_on, inode_colour_off = colour_thresholds( inode_perc_used )
		    
		    print( '    - /flash/' .. project .. ':   ' ..
		           'block quota: '  .. block_colour_on .. string.format( '%5.1f', block_perc_used ) .. 
		           '% used (' .. convert_to_iec( quota['flash']['block_used'] * 1024, 5 ) .. ' of ' .. convert_to_iec( quota['flash']['block_soft'] * 1024, 5 ) .. 
		           '/' .. convert_to_iec( quota['flash']['block_hard'] * 1024, 7 ) .. ' soft/hard)' .. block_colour_off ..
		           ',\n                 ' .. spacer ..  
		           'file quota:  ' .. inode_colour_on .. string.format( '%5.1f', inode_perc_used ) .. 
		           '% used (' .. convert_to_si( quota['flash']['inode_used'], 5 ) .. '   of ' .. convert_to_si( quota['flash']['inode_soft'], 5 ) .. 
		           '  /' .. convert_to_si( quota['flash']['inode_hard'], 7 ) .. '   soft/hard)' .. inode_colour_off )
	    end
    
    end

    --
    -- Check the allocation
    --
    
    if project_info['billing']['cpu_hours']['alloc'] == 0 and
       project_info['billing']['gpu_hours']['alloc'] == 0 and
       project_info['billing']['storage_hours']['alloc'] == 0 and
       project_info['billing']['qpu_secs']['alloc'] == 0 then

        print( '- The project has no allocation' )
       
       
    else
        
        print( '- State of the allocation (cached info):' )

	    if project_info['billing']['cpu_hours']['alloc'] > 0 then
	        local alloc = project_info['billing']['cpu_hours']['alloc']
	        local used = project_info['billing']['cpu_hours']['used']
	        local perc_used = 100 * used / alloc
            local k_alloc = alloc / 1000
            local alloc_format
            if ( k_alloc == math.floor( k_alloc ) ) then alloc_format='%.0f' else alloc_format='%.3f' end
	        local colour_on, colour_off = colour_thresholds( perc_used )
	        print( '  - CPU Khours:      ' .. colour_on .. string.format( '%5.1f', perc_used ) .. '% used (' .. string.format( '%.3f', used / 1000 ) .. ' of ' .. string.format( alloc_format, k_alloc ) .. ')' .. colour_off )
	    else
	        print( '  - No CPU hours allocated' )
	    end
	
	    if project_info['billing']['gpu_hours']['alloc'] > 0 then
	        local alloc = project_info['billing']['gpu_hours']['alloc']
	        local used = project_info['billing']['gpu_hours']['used']
	        local perc_used = 100 * used / alloc
	        local colour_on, colour_off = colour_thresholds( perc_used )
	        print( '  - GPU hours:       ' .. colour_on .. string.format( '%5.1f', perc_used ) .. '% used (' .. used .. ' of ' .. alloc .. ')' .. colour_off )
	    else
	        print( '  - No GPU hours allocated' )
	    end
	
	    if project_info['billing']['storage_hours']['alloc'] > 0 then
	        local alloc = project_info['billing']['storage_hours']['alloc']
	        local used = project_info['billing']['storage_hours']['used']
	        local perc_used = 100 * used / alloc
	        local colour_on, colour_off = colour_thresholds( perc_used )
	        print( '  - Storage TBhours: ' .. colour_on .. string.format( '%5.1f', perc_used ) .. '% used (' .. used .. ' of ' .. alloc .. ')' .. colour_off )
	    else
	        print( '  - No storage TBhours allocated' )
	    end
	
	    if project_info['billing']['qpu_secs']['alloc'] > 0 then
	        local alloc = project_info['billing']['qpu_secs']['alloc']
	        local used = project_info['billing']['qpu_secs']['used']
	        local perc_used = 100 * used / alloc
	        local colour_on, colour_off = colour_thresholds( perc_used )
	        print( '  - QPU seconds:     ' .. colour_on .. string.format( '%5.1f', perc_used ) .. '% used (' .. used .. ' of ' .. alloc .. ')' .. colour_off )
	    end
    
    end -- else-part check if there is an allocation.
    
    --
    -- List the project members
    --
    
    if project_info['members']  ~=  nil then
    
        print( '- Project members (by userid):' )
        
        local member_list = {}
        for member,_ in pairs( project_info['members'] ) do table.insert( member_list, member ) end
        table.sort( member_list )
        
        local user_table = get_user_table()
        
        for _,member in ipairs( member_list ) do
            if project_info['members'][member]['active'] then
                -- Active member, get GECOS information
                if user_table[member] == nil then
                    print( '  - ' .. member .. ' (active)' )
                else
                    print( '  - ' .. member .. ' - ' .. user_table[member] )
                end 
            else
                print( '  - ' .. member .. ' (inactive)' )
            end
        end
    
    end -- if project_info['members']  ~=  nil then

    print( )

end
