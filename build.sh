BASEDIR="/srv/docker/official-builder/"
cd $BASEDIR
clear
### check pre-requisittes
if  [[ "$(which jq)" = "" ]]; then
    whiptail --title "Missing Required File" --yesno "jq is required for this script to function.\nShould I install it for you?" 8 48 3>&1 1>&2 2>&3
    exitstatus=$?; if [ $exitstatus = 1 ]; then exit 1; fi
    apt-get update
    apt-get install -y jq
fi
[[ $(grep -c zram /proc/swaps) = "0" ]] && ./zram.sh

for IMG in "alpine" "rpi" "buildpack-deps" ; do
    if [[ "$(docker images -q whw3/$IMG 2> /dev/null)" == "" ]]; then
        MSG="Building the image rather than pulling allows the timezone to be properly configured for your location.\n\nIt defaults to America/Chicago\n\nShould I build it for you?"
        whiptail --title "whw3/$IMG is a required base image." --yesno "$MSG" 14 50 3>&1 1>&2 2>&3; exitstatus=$?; 
        if [ $exitstatus = 0 ]; then
            REPO="whw3/$IMG"
            [[ -d "$REPO" ]] && rm -rf "$REPO"
            mkdir -p "$REPO"
            git clone https://github.com/"$REPO".git "$REPO"
            [ -f TIMEZONE ] && cp TIMEZONE "$REPO"/TIMEZONE
            cd "$REPO"
            chmod 0700 ./build.sh
            export BASEDIR="$BASEDIR/$REPO" && ./build.sh
            export BASEDIR=${BASEDIR//$REPO/};
            cd "$BASEDIR"
            cp "$REPO"/TIMEZONE TIMEZONE
        fi
    fi
done

### update Library list ###
curl -s "https://api.github.com/users/docker-library/repos?per_page=1000" > docker-library.json
jq -c '.[] | [{name,full_name}]' docker-library.json |grep -v -f excludes |sed -f update.sed > names.json
REPO_LIST=( $(jq -r '.[] | "\(.full_name) [] off"' names.json) )
REPO=""
until [ ! $REPO = "" ]; do
    REPO=$(whiptail --title "Build Menu" --radiolist --separate-output "Choose Repository" 20 48 12 "${REPO_LIST[@]}" 3>&1 1>&2 2>&3)||exit 1
done
NAME=$(jq  -r '.[] | select(.full_name == "'"$REPO"'") | .name' names.json)
### pull repo ###
[[ -d  "$REPO" ]] && rm -rf "$REPO"
mkdir -p "$REPO"
git clone https://github.com/"$REPO".git "$REPO"
### patch ###

find "$REPO" -name Dockerfile -exec sed -i -f patch.sed {} +
if (jq -e -r '.[] | select(.name == "'"$NAME"'")|.patch[].value' config.json > patch 2>/dev/null) ; then
    find "$REPO" -name Dockerfile -exec sed -i -f patch {} +
fi
rm patch
### create BUILDLIST ###
if  (jq -e -r '.[] | select(.name == "'"$NAME"'")|.buildlist[].value' config.json > buildlist 2>/dev/null) ; then
    BUILDLIST=$(<buildlist)
else
    cd "$REPO"
    TARGET_LIST=( $(grep -R "FROM whw" --include 'Dockerfile' | cut -d: -f1| sort | awk '!/^ / && NF {print $1 " [] off"}') )
    BUILDLIST=$(whiptail --title "Build Menu" --checklist --separate-output "Select Dockerfiles " 18 78 12 "${TARGET_LIST[@]}" 3>&1 1>&2 2>&3)||exit 1
fi
[[ -f buildlist ]]  && rm buildlist
### build ###
for TARGET in $BUILDLIST; do
    cd "$BASEDIR/$REPO"
    echo "Buildiing ... "
    echo "$NAME:$TARGET";
    WORKDIR="${TARGET//\/Dockerfile/}"
    #echo "WORKDIR:$WORKDIR:"
    RELEASE=$(echo "$WORKDIR"| cut -d/ -f1)
    #echo "RELEASE:$RELEASE:"
    TAG="${WORKDIR//$RELEASE/}"
    TAG="${TAG//\//-}"
    #echo "TAG:$TAG:"
    if [[ "$TAG" = "" ]] ; then
        case "$NAME" in
            php)
                TAG="-cli"
            ;;
        esac
    fi
    echo "whw3/$NAME:$RELEASE$TAG"
    cd "$WORKDIR"
    #VERSION="${NAME^^}_VERSION"
    #echo "$PWD:$VERSION"
    #grep "$VERSION" Dockerfile| grep ENV| sed -e 's/ENV/export/;s/$/"/;s/VERSION /VERSION="/' > VERSION
    #. VERSION
    #jq -r '.[]| select(.name == "'$NAME'")|.dockerfile|.[]|select(.name =="'$TARGET'").tags[].tag' $BASEDIR/config.json > tags
#cat << EOF > options
#export RELEASE="v$RELEASE"
#export TAGS=(whw3/$NAME:$VERSION$TAG whw3/$NAME:$RELEASE$TAG)
#EOF
#    cat options
        
done
