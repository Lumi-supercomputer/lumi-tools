#!/bin/bash

# Exit on errors, exit when accessing undefined variables
set -o errexit
set -o nounset
#set -o xtrace

#----------------------------------------------------------------------
# Global variable declarations
#----------------------------------------------------------------------
# Set needed variables
# Lustre project id mappings offsets
declare -A offsets=( ["users"]="1000000000" \
                     ["projappl"]="2000000000" \
                     ["scratch"]="3000000000" \
                     ["flash"]="3000000000" \
                   )

# User specific values
username=$(whoami)
uid=$(id -u ${username})
homedir="/users/${username}"

# Active groups with scratch folder
active_groups=()

# Output formatting strings
desc_format="%-40s %8s/%-6s %8s/%s"
long_format="%-40s %8s %5s %5s %5s %5s %5s"

# Formatting used, default is desc, option -v sets this to long
formatting=desc

# Are we printing just a single project info (option -p)?
single_project=false

#----------------------------------------------------------------------
# Function declarations
#----------------------------------------------------------------------

# Usage
function usage() {
    echo "This help script is used to manage your workspaces"
    echo " $(basename $0)          : Shows your workspaces"
    echo " $(basename $0) -v       : Detailed quota information"
    echo " $(basename $0) -p prj   : Show quota of project prj"
    exit 0
}

# Quota query function
# Arguments: 1. Lustre project id
#            2. Directory
function quotaquery() {
    #echo "DEBUG quota_query calling lfs quota -q -p ${1} ${2}"
    local quota=$(lfs quota -q -p ${1} ${2} 2> /dev/null)
    if [[ "${quota[@]}" == *"errors happened"* ]]; then
        echo "${2}:  Errors while reading quota (permission denied?)"
        exit 1
    fi
    case "${formatting}" in
        desc)
            IFS=' '; local values=($quota); unset IFS
            printf "${desc_format}" \
                   ${2} \
                   $(numfmt --to si --from iec ${values[1]%\*}K) \
                   $(numfmt --to si --from iec ${values[2]%\*}K) \
                   $(numfmt --to si ${values[5]%\*}) \
                   $(numfmt --to si ${values[6]%\*})
            ;;
        long)
            IFS=' '; local values=($quota); unset IFS
            printf "${long_format}" \
                   ${values[0]} \
                   $(numfmt --to si --from iec ${values[1]%\*}K) \
                   $(numfmt --to si --from iec ${values[2]%\*}K) \
                   $(numfmt --to si --from iec ${values[3]%\*}K) \
                   $(numfmt --to si ${values[5]%\*}) \
                   $(numfmt --to si ${values[6]%\*}) \
                   $(numfmt --to si ${values[7]%\*})
            ;;
    esac
}

# Print separator line
function print_line() {
    case "${formatting}" in
        desc)
            echo "----------------------------------------------------------------------"
            ;;
        long)
            echo "-------------------------------------------------------------------------------"
    esac
}

# Print project quota
# Arguments: 1. disk area (scratch or projappl), these have to be also valid
#               keys in offsets array
#            2. project
function print_quota() {
    local gid=$(getent group ${2} | cut -d : -f3)
    if [[ -d "/${1}/${2}" ]]; then
        echo "$(quotaquery $(( ${gid} + ${offsets[${1}]} )) /${1}/${2})"
    fi
}

# Special version of the previous one for flash as it is no longer mounted on /flash
function print_quota2() {
    local gid=$(getent group ${3} | cut -d : -f3)

    if [[ -d "${2}/${1}/${3}" ]]; then
        echo "$(quotaquery $(( ${gid} + ${offsets[${1}]} )) ${2}/${1}/${3})"
    fi
}

# Print all active projects
# Arguments: 1... list of active projects
function print_projects() {
    for grp in "${@}"; do
        projectvolume=$(ls -l1 /projappl | grep $grp)
        projectvolume=${projectvolume#*pfs/}
        projectvolume=${projectvolume%/projappl/*}
        print_line
        echo "Project: ${grp}"
        echo "Project is hosted on $projectvolume"
        echo
        print_quota projappl ${grp}
        print_quota scratch ${grp}
        #echo "DEBUG Looking at flash for ${grp}"
        if [[ -d "/flash/${grp}" ]]; then
             print_quota flash ${grp}
        fi
        #print_quota2 flash /pfs/lustref1 ${grp}
        #echo "DEBUG End looking at flash for ${grp}"
    done
}

# Print home directory quota
function print_home() {
    uservolume=$(ls -l1 /users | grep $username)
    uservolume=${uservolume#*pfs/}
    uservolume=${uservolume%/users/*}
    print_line
    echo "Personal home folder"
    echo "Home folder is hosted on $uservolume"
    echo
    echo "$(quotaquery $(( ${uid} + ${offsets[users]} )) ${homedir} ${1})"
}

#----------------------------------------------------------------------
# Main script execution
#----------------------------------------------------------------------

# Fill in the active project info
my_groups=$(groups)
# DEBUG projects my_groups="ilvonens p_installation_spack project_2001659 project_2001981 project_2003573"

# Process arguments
while getopts "p:hv" arg; do
    case "$arg" in
        h*)
            usage
            ;;
        p)
            my_groups=(${OPTARG})
            single_project=true
            ;;
        v)
            formatting="long"
            ;;
    esac
done
shift $((OPTIND-1))

# Filter active projects, they should have /scratch folder
for g in ${my_groups}; do
    if [[ -d "/scratch/${g}" ]]; then
        active_groups+=(${g})
    fi
done

# Check that the -p argument is actually an active project
if [[ "${single_project:-false}" == "true" && ! -d "/scratch/${my_groups[0]}" ]]; then
    echo "${my_groups[@]} is not an active project with quota"
    exit 1
fi

# Print the description line
case "${formatting}" in
    desc)
        echo ;
        echo "Disk area                          Capacity(used/max)  Files(used/max)"
        ;;
    long)
        echo ;
        printf "${long_format}" "Filesystem" "Used" "Quota" "Limit" "Files" "Quota" "Limit"
        echo ;
        ;;
esac

# Print quota information for the home directory (unless -p is given)
if [[ "${single_project:-false}" == "false" ]];  then
    print_home desc
fi

# Print the information for the project(s)
print_projects "${active_groups[@]}"
print_line
