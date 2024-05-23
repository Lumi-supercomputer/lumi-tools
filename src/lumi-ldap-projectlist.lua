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
        '\nlumi-ldap-projectlist: List projects of a user or all projects (latter LUST only)\n\n' ..
        'Arguments:\n' ..
        '  -h/--help: Show this help and quit\n' ..
        '  -a/--all:  List all projects (LUST only)\n'
    )

end

-- -----------------------------------------------------------------------------
--
-- Function to clean up json code with problems that we have observed.
--
-- -----------------------------------------------------------------------------

function cleanup_json( json_in )

    -- Helper function from https://stackoverflow.com/questions/7983574/how-to-write-a-unicode-symbol-in-lua
    function utf8Char (decimal)
        if decimal < 128 then 
            return string.char(decimal)
        elseif decimal < 2048 then 
            local byte2 = (128 + (decimal % 64))
            local byte1 = (192 + math.floor(decimal / 64))
            return string.char(byte1, byte2)
        elseif decimal < 65536 then 
            local byte3 = (128 + (decimal % 64))
            decimal = math.floor(decimal / 64)
            local byte2 = (128 + (decimal % 64))
            local byte1 = (224 + math.floor(decimal / 64))
            return string.char(byte1, byte2, byte3)
        elseif decimal < 1114112 then
            local byte4 = (128 + (decimal % 64))
            decimal = math.floor(decimal / 64)
            local byte3 = (128 + (decimal % 64))
            decimal = math.floor(decimal / 64)
            local byte2 = (128 + (decimal % 64))
            local byte1 = (240 + math.floor(decimal / 64))
            return string.char(byte1, byte2, byte3, byte4)
        else
            return nil  -- Invalid Unicode code point
        end
    end

	local json_out = json_in

    -- Found a \" which is likely confusing in project_465000200 title.
    json_out = string.gsub( json_out, '\\"', '' )

    -- Search for UNICODE patterns '\\u%x%x%x%x' and convert to a character.
    local first, last = string.find( json_out, '\\u%x%x%x%x' )
    while first do 
    
        local charnum = tonumber( 'ox' .. string.sub( json_out, first+2, last ) )
        json_out = string.gsub( json_out, string.sub( json_out, first, last ), utf8Char( charnum ) )
        
        first, last = string.find( json_out, '\\u%x%x%x%x' )
    
    end
    
    return json_out


end  -- function cleanup_json



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

-- -----------------------------------------------------------------------------
--
-- Process the command line arguments
--
-- There are no command line arguments to process except for -h/--help and 
-- -a/--all and both cannot be used together.
--

local argctr = 1
local show_all = false

while ( argctr <= #arg )
do
    if ( arg[argctr] == '-h' or arg[argctr] == '--help' ) then
        print_help()
        os.exit( 0 )
    elseif ( arg[argctr] == '-a' or arg[argctr] == '--all' ) then
        show_all = true
        if debug then io.stderr:write( 'DEBUG: Found -a/--all argument.\n' ) end
    else
        io.stderr:write( 'Error: ' .. arg[argctr]  .. ' is an unrecognised argument.\n' )
        print_help()
        os.exit( 1 )
    end
    argctr = argctr + 1
end

-- -----------------------------------------------------------------------------
--
-- Get the list of projects to show
--

local project_list = {}

local cmd

if show_all then

    cmd = "/usr/bin/ls -1 /var/lib/project_info/lust |& " ..
          "grep -v 'Permission denied'"

else

    -- No arguments so we use the projects of the current user.
    
    local user_executing = os.getenv( 'USER' )
    
    cmd = "/usr/bin/getent group | /usr/bin/grep project_ | " ..
          "/usr/bin/sed -e 's/,/|/g' -e 's/:/|/g' -e 's/\\(.*\\)/\\1|/' | " ..
          "/usr/bin/grep '|" .. user_executing .. "|' | " ..
          "/usr/bin/cut -d'|' -f1"

end

fh = io.popen( cmd, 'r')
for line in fh:lines() do 
    table.insert( project_list, line )
    if debug then io.stderr:write( 'DEBUG: Adding ' .. line .. ' to the project list.\n' ) end
end
fh:close()

table.sort( project_list )

-- -----------------------------------------------------------------------------
--
-- Gather  and print information about all projects that should be listed.
--

local project_path = '/var/lib/project_info'
local first = true

for _,project in ipairs( project_list )
do

    if debug then io.stderr:write( 'Gathering information for project ' .. project .. '\n' ) end
    
    local project_postfix = project .. '/' .. project .. '.json'

    -- First try to open the lust version as that one contains more data.
    local project_file = project_path .. '/lust/' .. project_postfix
    if debug then io.stderr:write( 'Attempting to read information from ' ..  project_file .. '\n' ) end
    local fh = io.open( project_file, 'r' )
    if fh == nil then
        project_file = project_path .. '/users/' .. project_postfix
        if debug then io.stderr:write( 'Now attempting to read information from ' ..  project_file .. '\n' ) end
        fh = io.open( project_file, 'r' )
    end
    if fh == nil then 
        io.stderr:write( 'ERROR: You may not have sufficient rights to get information from project ' .. project .. 
                         ' or the project name is invalid.\n\n' )
        os.exit( 1 )
    end
    local project_info_str = fh:read( '*all' )
    fh:close()
    
    local project_info = json_decode( project_info_str )
    
    print( 'Decoding ' .. project_info_str )
    
    print( project .. ': ' .. (project_info['title'] or 'UNKNOWN') )

end
