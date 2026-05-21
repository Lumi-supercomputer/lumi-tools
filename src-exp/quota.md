# Getting quota

-   User quota:
    
    ```
    lfs quota -q -p $((1000000000 + $(id -u $USER) )) /users/$USER
    ```
    
-   Project directory:

    ```
    group=project_462000008
    lfs quota -q -p $(( 2000000000 + $(getent group $group | cut -d : -f3) )) /projappl/$group
    ```
    
    Note however that the result of `$(getent group $group | cut -d : -f3)` is just the numeric part
    of the project name, so this also works:
    
    ```
    group=project_462000008
    lfs quota -q -p $(( 2000000000 + ${group#project_} )) /projappl/$group
    ```

-   Scratch directory:

    ```
    group=project_462000008
    lfs quota -q -p $(( 3000000000 + ${group#project_} )) /scratch/$group
    ```

-   Flash directory

    ```
    group=project_462000008
    lfs quota -q -p $(( 3000000000 + ${group#project_} )) /flash/$group
    ```

