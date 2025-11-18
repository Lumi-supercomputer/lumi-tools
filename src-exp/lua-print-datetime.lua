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
