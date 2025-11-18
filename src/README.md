# Some very incomplete technical information

## Data in the user information files

-   Location
    -   LUST version: `/var/lib/user_info/lust/<USER>/<USER>.json`
    -   User version: `/var/lib/user_info/users/<USER>/<USER>.json`

-   Fields are the same in both versions:

    ``` json
    {
    "name": "<USERID>",
    "uid": 10XXXXXX, -- or 327YYYYYY
    "gid": 10XXXXXX, -- or 327YYYYYY, but same as uid
    "gecos": "<Full name>",
    "is_banned": false,
    "is_active": true,
    "valid_compute_user": true,
    "home": "/users/<USERID>>",    
    "home_fs": "/pfs/lustrepZ/users",
    "home_real": "/pfs/lustrepZ/users/<USERID>>",
    "home_lpid": 1010XXXXXX, -- or 1327YYYYYY
    "home_quota": {
        "block_quota_used": 9645788,
        "block_quota_soft": 20971520,
        "block_quota_hard": 23068672,
        "inode_quota_used": 56073,
        "inode_quota_soft": 100000,
        "inode_quota_hard": 101000
    }
    }
    ```

## Data in the project information files

This is currently very incomplete as there is a lot of data in there.

-   Location:
    -   LUST version: `/var/lib/project_info/lust/project_<NUMBER>/project_<NUMBER>.json`
    -   User version: `/var/lib/project_info/users/project_<NUMBER>/project_<NUMBER>.json`

-   The user version contains a subset of the data of the LUST version

-   Project start- and end-related dates: Currently only in the LUST version, but we want
    this to change.

    -   `open_date`: Date/time of opening of the project, e.g., `20251031225126Z`

    -   `end_date`: Date/time at which compute ends, e.g., `20261031050000Z`

    -   `closed_date`: Date/time at which data access closes, e.g., `20270129050000Z`

-   Some LUST-only fields:

    -   `allocator_country`: lumi-be, lumi-ch, lumi-cz, lumi-dk, lumi-ee, 
        lumi-fi, lumi-is, lumi-ju, lumi-lust, lumi-lustt, lumi-nl, lumi-no, lumi-pl, 
        lumi-se, lumi-training
        
        lumi-lust and lumi-lustt have been used inconsistently in the past. lumi-training 
        is for new trainings.

