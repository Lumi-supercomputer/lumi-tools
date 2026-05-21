#! /usr/bin/env lua

function readablezulu( zulustring )

    if ( zulustring == nil ) then
        return nil
    end

    local months = {'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'}

    local year, month, day, hour, min, sec

    year, month, day, hour, min, sec = string.match( zulustring, '(%d%d%d%d)(%d%d)(%d%d)(%d%d)(%d%d)(%d%d)Z' )

    year  = tonumber( year )
    month = tonumber( month )
    day   = tonumber( day )
    hour  = tonumber( hour )
    min   = tonumber( min )

    return string.format( '%2d %s %4d %02d:%02d UTC', day, months[month], year, hour, min )

end -- function printzulu

function get_current_zulu_time()

    local time = os.date("!*t")

    local timestring = string.format( "%d/%d/%d %d:%d:%d", 
        time['day'], time['month'], time['year'], 
        time['hour'], time['min'], time['sec'] )

    if time['isdst'] then
        timestring = timestring .. ', daylight saving time'
    else
        timestring = timestring .. ', no daylight saving time'
    end

    return timestring

end

-- Convert Zulu (UTC) time string to epoch seconds
function zulu_to_epoch(zulu)

    -- Parse Zulu string
    local y, m, d, H, M, S = zulu:match( '(%d%d%d%d)(%d%d)(%d%d)(%d%d)(%d%d)(%d%d)Z' )
    y, m, d, H, M, S = tonumber(y), tonumber(m), tonumber(d),
                       tonumber(H), tonumber(M), tonumber(S)

    -- Build time table
    local t = {year=y, month=m, day=d, hour=H, min=M, sec=S, isdst=false}

    -- os.time interprets as local time, so adjust to UTC
    local local_epoch = os.time(t)
    local utc_correction = math.tointeger( os.difftime( local_epoch, os.time( os.date( '!*t', local_epoch ) ) ) )
 
    return local_epoch + utc_correction

end


zulu = '20250701002826Z' ; zulur = readablezulu( zulu ) ; print( zulu .. ' :  ' .. zulur )
zulu = '20260331040000Z' ; zulur = readablezulu( zulu ) ; print( zulu .. ' :  ' .. zulur )
zulu = '20250929142159Z' ; zulur = readablezulu( zulu ) ; print( zulu .. ' :  ' .. zulur )
zulu = '20250930215157Z' ; zulur = readablezulu( zulu ) ; print( zulu .. ' :  ' .. zulur )
zulu = '20251014120929Z' ; zulur = readablezulu( zulu ) ; print( zulu .. ' :  ' .. zulur )
zulu = '20221201195744Z' ; zulur = readablezulu( zulu ) ; print( zulu .. ' :  ' .. zulur )
zulu = '20240113092309Z' ; zulur = readablezulu( zulu ) ; print( zulu .. ' :  ' .. zulur )
zulu = '20230131065609Z' ; zulur = readablezulu( zulu ) ; print( zulu .. ' :  ' .. zulur )
zulu = '20250501040000Z' ; zulur = readablezulu( zulu ) ; print( zulu .. ' :  ' .. zulur )
zulu = '20260529050000Z' ; zulur = readablezulu( zulu ) ; print( zulu .. ' :  ' .. zulur )

print( 'Zulu time detected: ' .. get_current_zulu_time() )

zulu = '20251118101010Z' -- A moment in winter time
ftime = { 
    year =  2025,
    month = 11,
    day =   18,
    hour =  12, -- Time in Finland for the zulu string above
    min =   10,
    sec =   10,
    isdst = false
}
zulu_to_epoch( zulu )
os.time( ftime )
zulu_to_epoch( zulu ) - os.time( ftime )

zulu = '20250909101010Z' -- A moment in winter time
ftime = { 
    year =  2025,
    month = 9,
    day =   9,
    hour =  13, -- Time in Finland for the zulu string above, it is daylight saving time at that day
    min =   10,
    sec =   10,
    isdst = true
}
zulu_to_epoch( zulu )
os.time( ftime )
zulu_to_epoch( zulu ) - os.time( ftime )
