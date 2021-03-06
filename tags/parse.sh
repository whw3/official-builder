#!/bin/bash
#            {	"tags":[
#                   {"tag":"$_v-jessie"},{"tag":"2.4-jessie"},{"tag":"2-jessie"},{"tag":"jessie"},{"tag":"$_v"}
#               ],
#               "name":"2.4/jessie/Dockerfile"
#            },
function parse()
{
    local _name=$1
    echo -n "["
    local first="1"
    local newline="1"
    local tag
    local latest=$(jq '.[]|select(.name == "'$_name'")|.latest' latest)
    while read tag; do
        if [[ "$newline" = "1" ]]; then
            if [[ "$first" = "1" ]]; then
                echo "{"
                first="0"
            else
                echo ",{"
            fi
            echo -n "\"tags\":["
        fi
        if [[ $tag =~ .*Dockerfile.* ]]; then
            if [[ "$tag" = "$latest" ]]; then
                echo -n ",{\"tag\":\"latest\"}"
            fi
            echo "],"
            echo "\"name\":$tag"
            echo -n "}"
            newline="1"
        else 
            if [[ "$newline" = "1" ]]; then
                case $_name in
                    postgres)
                        _tag=$tag
                    ;;
                    *)
                        _tag=$(echo $tag| cut -d- -f2-)
                        _tag="\"\$_v-$_tag"
                        _v=${tag/_tag//}
                        _tag=$tag
                    ;;
                esac
                echo -n "{\"tag\":$_tag}"
                newline="0"
            else # prepend a comma to delimit tags
                case $_name in
                    postgres)
                    ;;
                    *)
                        [[ "$tag" = "$_v" ]] && tag="\$_v"
                    ;;
                esac
                echo -n ",{\"tag\":$tag}"
            fi
        fi
    done <"$_name.tags"
    echo "]"
}

### Begin Main ###
TAGS_DIR=$(cd "$( dirname "$0" )" && pwd)
# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.
verbose=0
SINGLE_TAG=''
while getopts "vft:" opt; do
    case "$opt" in
    v)  verbose=1
        ;;
    f)  echo "forcing pull of new tags"
        rm $TAGS_DIR/*.json
        ;;
    t)  SINGLE_TAG=$OPTARG
    esac
done
shift $((OPTIND-1))

[ "$1" = "--" ] && shift

echo "Checking Tags..."
cd "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
for name in $(jq -r '.[]|"\(.name)"' ../names.json); do
    if [[ -z $SINGLE_TAG ]]; then
        echo -n "$name : "
        update="0"
        if [[ ! -e "$name.json" ]]; then
            update="1"
        else
            if (( "$(date -r $name.json +%s)" <= "$(date -d 'now - 30 minutes' +%s)" )); then
                update="1"
            fi
        fi
    elif [[ "$SINGLE_TAG" != "$name" ]]; then
        continue;
    else
        echo -n "$name : "
        update="1"
    fi
    if [[ "$update" = "1" ]]; then
        echo -n "updating..."
        case $name in
            caddy)
                cat << EOF > $name.json
[{
"tags":[{"tag":"php"}],
"name":"php/Dockerfile"
},{
"tags":[{"tag":"latest"}],
"name":"./Dockerfile"
}]
EOF
            ;;
            *)
                curl -sS https://hub.docker.com/_/$name/| pup 'ul'| pup ':parent-of(:contains("Dockerfile"))'| pup 'a json{}'| jq  '.[].children[]|"\(.text)"'| grep -v "latest" > $name.tags
                parse $name > $name.json
                rm $name.tags                
            ;;
        esac
        case $name in
            mariadb)
            ;;
            postgres)
            ;;
            *)
                sed -i 's/[0-9]\+.[0-9]\+.[0-9]\+/$_v/g' $name.json
            ;;
        esac
    fi
    echo "ok"
done 
