#!/bin/sh -ex

# Script to build custom nginx rpm
# Example use:
# MANAGE_DEPS=false DISABLE_SUDO=1 MANAGE_REPO=false TEST_INSTALL=no ./nginx-build.sh

MANAGE_REPO=${MANAGE_REPO:-yes}
MANAGE_DEPS=${MANAGE_DEPS:-yes}
TEST_INSTALL=${TEST_INSTALL:-yes}

SUDO=sudo
if [[ "$DISABLE_SUDO" == "1" ]]; then
  SUDO=''
fi

#Clean up old nginx builds
$SUDO rm -rf ~/rpmbuild/RPMS/*/nginx-*.rpm

if [[ "$MANAGE_DEPS" == "yes" ]]; then
    #Install required packages for building
    $SUDO yum install -y \
        rpm-build \
        rpmdevtools \
        yum-utils \
        mercurial \
        git \
        wget
fi

#Install source RPM for Nginx
pushd ~

if [[ "$MANAGE_REPO" == "yes" ]]; then
  echo """[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/centos/6/SRPMS/
gpgcheck=0
enabled=1""" >> nginx.repo
sudo mv nginx.repo /etc/yum.repos.d/
fi

yumdownloader --source nginx
$SUDO rpm -ihv nginx*.src.rpm
popd


function fetch_module {
  if [[ ! -d $1 ]]; then
    git clone $2 $3 $4
  else
    pushd $1
    git pull origin
    popd
  fi
}


#Get various add-on modules for Nginx
pushd ~/rpmbuild/SOURCES

# Fancy Index module
fetch_module ngx-fancyindex http://github.com/aperezdc/ngx-fancyindex.git -b v0.3.4

# Headers-More module
fetch_module headers-more-nginx-module http://github.com/agentzh/headers-more-nginx-module.git -b v0.25

# AJP module
fetch_module nginx_ajp_module http://github.com/yaoweibin/nginx_ajp_module.git -b v0.3.0

# LDAP authentication module
fetch_module nginx-auth-ldap https://github.com/kvspb/nginx-auth-ldap.git

# Shibboleth module
fetch_module nginx-http-shibboleth https://github.com/nginx-shib/nginx-http-shibboleth.git

popd

# Obtain a location for the patches, either from /vagrant
# or cloned from GitHub (if run stand-alone).
if [ -d '/vagrant' ]; then
    patch_dir='/vagrant'
else
    if [[ -e nginx-eresearch.patch ]]; then
        patch_dir='.'
    else
        patch_dir=`mktemp`
        git clone https://github.com/jcu-eresearch/nginx-custom-build.git $patch_dir
    fi
fi
cp $patch_dir/nginx-eresearch.patch ~/rpmbuild/SPECS/
cp $patch_dir/nginx-xslt-html-parser.patch ~/rpmbuild/SOURCES/

# Remove temp directory if not Vagrant or local
if ! [ -d '/vagrant' ] && [ "$patch_dir" != '.' ]; then
    rm -rf $patch_dir
fi

#Prep and patch the Nginx specfile for the RPMs
pushd ~/rpmbuild/SPECS
patch -p1 < nginx-eresearch.patch
spectool -g -R nginx.spec
if [[ "$MANAGE_DEPS" == "yes" ]]; then
  yum-builddep -y nginx.spec
else
  echo "Warning: Skipped installing nginx.spec dependencies, make sure you've installed those via 'sudo yum-builddep $PWD/nginx.spec'"
fi
rpmbuild -ba nginx.spec

if [[ "$TEST_INSTALL" == "yes" ]]; then
  #Test installation and check output
  sudo yum remove -y nginx nginx-devel
  sudo yum install -y ~/rpmbuild/RPMS/*/nginx-*.rpm
  nginx -V
fi
