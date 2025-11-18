# LUA tricks that are usefull for this code

## Date function

-   See also [section 22.1 in the LUA manual](https://www.lua.org/pil/22.1.html)
    
-   Starting the format string with `!` gives Zulu time.
    
    This does not only work with the `*t` format string that returns a table, but also
    with other formatting that returns a string. E.g.,
    
    ```
    os.date('%Y%m%d%H%M%S' ), os.date('!%Y%m%d%H%M%SZ' )
    ```
