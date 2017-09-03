#!/bin/bash
clear
BASEDIR="${BASEDIR:-/srv/docker/official-builder/}"
echo "BASEDIR:$BASEDIR"
cd "$BASEDIR"

function check_prereqs()
{ ### check pre-requisittes
    local _baseImage=""
    if  [[ -z "$(which jq)" ]]; then
        whiptail --title "Missing Required File" --yesno "jq is required for this script to function.\nShould I install it for you?" 8 48 3>&1 1>&2 2>&3 || exit 1
        apt-get update
        apt-get install -y jq
    fi
    if  [[ -z "$(which pup)"  ]]; then
        cp tags/pup /usr/local/bin
    fi
    [[ $(grep -c zram /proc/swaps) = "0" ]] && ./zram.sh

    for _baseImage in "alpine" "rpi" "buildpack-deps" ; do
        check_baseImage $_baseImage
    done
    #./tags/parse.sh
}
function select_repo()
{
    cd "$BASEDIR"
    curl -s "https://api.github.com/users/docker-library/repos?per_page=1000" > docker-library.json
    jq -c '.[] | [{name,full_name}]' docker-library.json |grep -v -f excludes|grep -v -f todo.excludes |sed -f update.sed > names.json

    local _repoList=( $(jq -r '.[] | "\(.full_name) off"' names.json) )
    local _repo=""
    until [ ! $_repo = "" ]; do
        _repo=$(whiptail --title "Build Menu" --menu --noitem --separate-output "Choose Repository" 20 48 12 "${_repoList[@]}" 3>&1 1>&2 2>&3)||exit 1
    done
    [[ -f config ]] && rm config
    jq -e -r '.[] | select(.repo == "'"$_repo"'")' config.json > config 2>/dev/null
    if [[ "$?" = "0" ]]; then
        echo "$_repo"
    else
        rm config
    fi
}
function pull_repo()
{
    local _repo=$1
    if [[ "$_repo" = "" ]]; then
        echo "Repo name can not be empty"
        exit 3
    fi
    echo "Pulling Repo:$repo"
    [[ -d "$_repo" ]] && rm -rf "$_repo"
    mkdir -p "$_repo"
    git clone https://github.com/"$_repo".git "$_repo"||return 1;
    return 0
}
function check_baseImage()
{
    local _baseImage=${1//jessie/rpi}
    _baseImage=${_baseImage//debian:rpi/rpi-s6}
    local _msg="Building the image rather than pulling allows the timezone to be properly configured for your location.\n\nIt defaults to America/Chicago\n\nShould I build it for you?"
    if [[ "$(docker images -q whw3/"$_baseImage" 2> /dev/null)" == "" ]]; then
        case "$_baseImage" in
            alpine:3.4)
                whiptail --title "Invalid baseImage" --msgbox "alpine 3.4 will be upgraded to alpine 3.6." 8 48
                ;;
            alpine)
                ;&
            rpi)
                ;&
            buildpack-deps)
                whiptail --title "whw3/$_baseImage is a required base image." --yesno "$_msg" 14 50 3>&1 1>&2 2>&3|| return 1;
                pull_repo "whw3/$_baseImage"
                build_baseimage "whw3/$_baseImage"
                ;;
            *)
                _msg="This image is missing from your system\n\nShould I build it for you?"
                whiptail --title "whw3/$_baseImage" --yesno "$_msg" 14 50 3>&1 1>&2 2>&3 || return 2;
                local _repoName=$(echo "$_baseImage"|cut -d: -f1)
                local _tag=$(echo "$_baseImage"|cut -d: -f2)
                local _repo=$(jq  -r '.[] | select(.name == "'"$_repoName"'") | .full_name' names.json)
                pull_repo "$_repo"
                local _dockerfile=$(jq -c '.[]' ./tags/$_repoName.json | grep -w "$_tag" | jq -r '.name')
                build "$_repo" "$_dockerfile"
            ;;
        esac
    fi
    if [[ "$_baseImage" = "alpine:3.5" ]]; then
        _msg="Should I upgrade alpine3.5 to alpine3.6 for you?"
        whiptail --title "Upgrade Alpine" --yesno "$_msg" 8 56 3>&1 1>&2 2>&3
        use_A35="$?" #ignore lazy use of global_var
    fi

    return 0
}
function select_baseimage()
{
    local _repo=$1
    local _dockerfiles=$(find "$_repo" -name Dockerfile -exec grep "FROM" {} +\
        |grep -vF "onbuild"| grep -vF "wheezy"| grep -vF "stretch"| grep -vF "backports"\
        |grep -viF "microsoft"| grep -viF "windows"\
        |cut -d: -f2-|sort|uniq)
    local _A36only="$(jq -r '.[] | select(.repo == "'"$_repo"'")|.A36only' config.json)"

    if [[ "$_A36only" = "1" ]]; then
        _dockerfiles=$(echo "${_dockerfiles[@]}"|grep -v "alpine:3.4")
        _dockerfiles=$(echo "${_dockerfiles[@]}"|grep -v "alpine:3.5")
    fi
    _dockerfiles=($(echo "${_dockerfiles[@]}"|awk '{ print $2" \"\"\n"}'))

    local _baseImage=""
    until [ ! "$_baseImage" = "" ]; do
        _baseImage=$(whiptail --title "Build Menu" --noitem --menu "Select baseImage" 20 48 12 "${_dockerfiles[@]}" 3>&2 2>&1 1>&3)||exit 1;
    done;
    echo "$_baseImage"
}

function create_buildlist()
{
    local _repo=$1
    local _baseImage=$2
    echo "Creating buildlist...";
    cd "$BASEDIR"
    if  [ !  "$(jq -e -r '.[] | select(.repo == "'"$_repo"'")|.buildlist[].value' config.json > buildlist 2>/dev/null)" = "0" ] ; then 
        echo "repo:$_repo"
        cd "$_repo"
        local _targets=( $(grep -R "FROM $_baseImage" --include 'Dockerfile' | cut -d: -f1| sort | awk '!/^ / && NF {print $1 " off"}') )
        local _buildlist=$(whiptail --title "Build Menu" --checklist --noitem --separate-output "$_repo" 20 78 12 "${_targets[@]}" 3>&1 1>&2 2>&3)||exit 1
        echo "${_buildlist[@]}" > buildlist
    fi
}
function build_baseimage()
{
    local _repo=$1

    cd  "$BASEDIR"
    [ -f TIMEZONE ] && cp TIMEZONE "$_repo"/TIMEZONE
    cd "$_repo"
    chmod 0700 ./build.sh
    export BASEDIR="$BASEDIR/$_repo" && ./build.sh
    export BASEDIR=${BASEDIR//$_repo/};
    cd "$BASEDIR"
    cp "$_repo"/TIMEZONE TIMEZONE
}
function patch_dockerfiles()
{ ### patch ###
    local _repo=$1
    echo "Patching:$_repo";
    find "$_repo" -name Dockerfile -exec sed -i -f patch.sed {} +
    if (jq -e -r '.[] | select(.repo == "'"$_repo"'")|.patch[].value' config.json > patch 2>/dev/null) ; then
        echo "Applying custom patch"
        find "$_repo" -name Dockerfile -exec sed -i -f patch {} +
    fi
    if [[ "$use_A35" = "1" ]]; then #ignore lazy use of global_var
        echo "s_alpine:latest_alpine:3.5_" > patch
        find "$_repo" -name Dockerfile -exec sed -i -f patch {} +
    fi
    rm patch
}
function get_tags()
{
    local _repo=$1
    local _d=$2
    local _name=$(jq  -r '.[] | select(.full_name == "'"$_repo"'") | .name' names.json)
    local _version="${_name^^}_VERSION"
    eval "$(grep "$_version" "$_repo/$_d"| grep ENV| sed -e 's/ENV/export/;s/$/"/;s/VERSION /VERSION="/')"
    local _v=$(eval echo "\$$_version")
    #echo "_v:$_v"
    local _tags=$(jq -c -r '.[]|select(.name == "'"$_d"'")|.tags[] |"-t whw3/'"$_name":'\(.tag)"' ./tags/$_name.json )
    echo $_tags|sed 's/\$_v/'"$_v"'/g'

}
function build()
{
    cd "$BASEDIR"
    local _repo_=$1
    local _dockerfile_=$2
    [[ "$_dockerfile_" = "Dockerfile" ]] && _dockerfile_="./$_dockerfile_"
    local _buildDir_="$_repo_/${_dockerfile_//\/Dockerfile/}"
    local _tags_=$(get_tags "$_repo_" "$_dockerfile_")
    patch_dockerfiles "$_repo_"
    #echo "bd:$_buildDir_:repo:$_repo_:Dockerfile:$_dockerfile_"
    echo "Building..."
    cd  "$_buildDir_"
    echo "PWD:$PWD"
    echo "docker build $_tags_ ."
    [[ -z "$_tags_" ]] && exit 3
    docker build $_tags_ .
}
### MAIN ###
check_prereqs
repo=$(select_repo)|| exit 1 ;
if [[ ! -f config ]]; then
    whiptail --title "Build Terminated" --msgbox "Repository unconfigured" 8 28
    exit 1;
fi
pull_repo "$repo" || exit 1 ;
baseImage=$(select_baseimage "$repo")|| exit 1 ;
echo "baseImage:$baseImage:"
check_baseImage "$baseImage"
create_buildlist "$repo" "$baseImage"
buildlist=$(<buildlist)
for target in $buildlist; do
    echo "TARGET:$target"
    build "$repo" "$target"
done
