#! /usr/bin/env lua

function get_quota( type, name, id )

    local offsets = {
        user =    1000000000,
        project = 2000000000,
        scratch = 3000000000,
        flash =   3000000000,
    }

    local dir
    local lfsid

    if ( type == 'user' ) then

        lfsid = tonumber( id ) + offsets['user']
        dir = '/users/' .. name

    elseif ( type == 'project' ) or ( type == 'scratch' ) or (type == 'flash') then

        lfsid = tonumber( name:match('project_([%d]+)') ) + offsets[type]
        
        if ( type == 'project' ) then
            dir = '/projappl/' .. name
        else
            dir = '/' .. type .. '/' .. name
        end

    else
        -- Should not happen, the first argument is illegal.
        return nil
    end

    local cmd = string.format( 'lfs quota -q -p %d %s', lfsid, dir )
    -- print( cmd )
    
    local handle = io.popen( cmd, 'r')
    local lfsquota = handle:read("*a")
    handle:close()

    local values = {}
    for w in string.gmatch( lfsquota, '%S+' ) do
        table.insert( values, w )
    end

    return tonumber( values[2] ), tonumber( values[3] ), tonumber( values[4] ), 
           tonumber( values[6] ), tonumber( values[7] ), tonumber( values[8] )

end -- function get_quota

get_quota( 'user', 'kurtlust', '10012026' )

get_quota( 'project', 'project_462000008' )
get_quota( 'scratch', 'project_462000008' )
get_quota( 'flash',   'project_462000008' )
