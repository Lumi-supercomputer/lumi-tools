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

-   Project start- and end-related dates: In both the LUST and the user version of the files.

    -   `open_date`: Date/time of opening of the project, e.g., `20251031225126Z`

    -   `end_date`: Date/time at which compute ends, e.g., `20261031050000Z`

        Puhuri projects with an end time of 04:00 UTC are definitely closed early on on
        that day.

    -   `closed_date`: Date/time at which data access closes, e.g., `20270129050000Z`

-   Compute-related fields:

    -   `enabled_partitions`: A list of all partitions that a project can use. This is unfortunately
        not reset to an empty list if the project does not have an allocation anymore.

        Instead, there is also the structure `partition_access` with per partition a field `allowed`
        that is reset to false if the project has no longer access to a partition.So to print the partitions,
        it would be better to go through that list and to see which partitions are allowed.

-   Some LUST-only fields:

    -   `allocator_country`: lumi-be, lumi-ch, lumi-cz, lumi-dk, lumi-ee, 
        lumi-fi, lumi-is, lumi-ju, lumi-lust, lumi-lustt, lumi-nl, lumi-no, lumi-pl, 
        lumi-se, lumi-training, efp-lumi-c, efp-lumi-g
        
        lumi-lust and lumi-lustt have been used inconsistently in the past. lumi-training 
        is for new trainings.

    -   `is_softclosed`: Boolean, telling if a project is soft closed or not, which may point
        to issues with the account of the PI.

