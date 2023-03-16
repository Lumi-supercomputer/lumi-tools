#! /bin/bash
# Exit on errors, exit when accessing undefined variables
set -o errexit
set -o nounset
#set -o xtrace


# Usage
function usage() {
    printf "This help script returns quota and allocation information about your workspaces\n"
    printf "\nIt takes no further arguments in its current implementation.\n\n"
    exit 0
}

while getopts "h" arg; do
    case "$arg" in
        h*)
            usage
            ;;
    esac
done


echo -e "\nQuota for your projects:"

lumi-quota

echo -e "\nStatus of your allocations:\n"

lumi-allocations

printf "\n"
