#!/bin/bash
_repo="nginxinc/docker-nginx"
_d="mainline/alpine/Dockerfile"
_name=$(jq  -r '.[] | select(.full_name == "'"$_repo"'") | .name' names.json)
_version="${_name^^}_VERSION"
eval $(grep "$_version" "$_repo/$_d"| grep ENV| sed -e 's/ENV/export/;s/$/"/;s/VERSION /VERSION="/')
_v=$(eval echo \$$_version)
echo "_v:$_v"
_tags=$(jq -c -r '.[]|select(.repo == "'"$_repo"'").dockerfiles[]|select(.name == "'"$_d"'")|.tags[] |"-t whw3/'"$_name":'\(.tag)"' config.json )
echo "TAGS:"$_tags|sed 's/\$_v/'"$_v"'/g'

