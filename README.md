# official-builder
This repo UNSTABLE !!!
Consider it a work in progress
### Assumptions
* home for docker build images is ***/srv/docker***

To build the image(s) run ***/srv/docker/official-builder/build.sh***
```
mkdir -p /srv/docker
cd /srv/docker
git clone https://github.com/whw3/official-builder.git
cd official-builder
chmod 0700 build.sh
./build.sh
```
