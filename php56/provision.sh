#!/usr/bin/env bash

DIR=`dirname $0`

# PACKAGE INSTALLATION
#
# Build a bash array to pass all of the packages we want to install to a single
# apt-get command. This avoids doing all the leg work each time a package is
# set to install. It also allows us to easily comment out or add single
# packages. We set the array as empty to begin with so that we can append
# individual packages to it as required.
apt_package_install_list=()

# Start with a bash array containing all packages we want to install in the
# virtual machine. We'll then loop through each of these and check individual
# status before adding them to the apt_package_install_list array.
apt_package_check_list=(

  # PHP5.6
  #
  # Our base packages for php5.6. As long as php5.6-fpm and php5.6-cli are
  # installed, there is no need to install the general php5.6 package, which
  # can sometimes install apache as a requirement.
  php5.6-fpm
  php5.6-cli

  # Common and dev packages for php
  php5.6-common
  php5.6-dev

  # Extra PHP modules that we find useful
  php5.6-imagick
  php5.6-memcache
  php5.6-memcached
  php5.6-bcmath
  php5.6-curl
  php5.6-gd
  php5.6-mbstring
  php5.6-mcrypt
  php5.6-mysql
  php5.6-imap
  php5.6-json
  php5.6-soap
  php5.6-ssh2
  php5.6-xdebug
  php5.6-xml
  php5.6-zip
)

### FUNCTIONS

network_detection() {
  # Network Detection
  #
  # Make an HTTP request to google.com to determine if outside access is available
  # to us. If 3 attempts with a timeout of 5 seconds are not successful, then we'll
  # skip a few things further in provisioning rather than create a bunch of errors.
  if [[ "$(wget --tries=3 --timeout=5 --spider --recursive --level=2 http://google.com 2>&1 | grep 'connected')" ]]; then
    echo "Network connection detected..."
    ping_result="Connected"
  else
    echo "Network connection not detected. Unable to reach google.com..."
    ping_result="Not Connected"
  fi
}

network_check() {
  network_detection
  if [[ ! "$ping_result" == "Connected" ]]; then
    echo -e "\nNo network connection available, skipping package installation"
    exit 0
  fi
}

not_installed() {
  dpkg -s "$1" 2>&1 | grep -q 'Version:'
  if [[ "$?" -eq 0 ]]; then
    apt-cache policy "$1" | grep 'Installed: (none)'
    return "$?"
  else
    return 0
  fi
}

print_pkg_info() {
  local pkg="$1"
  local pkg_version="$2"
  local space_count
  local pack_space_count
  local real_space

  space_count="$(( 20 - ${#pkg} ))" #11
  pack_space_count="$(( 30 - ${#pkg_version} ))"
  real_space="$(( space_count + pack_space_count + ${#pkg_version} ))"
  printf " * $pkg %${real_space}.${#pkg_version}s ${pkg_version}\n"
}

package_check() {
  # Loop through each of our packages that should be installed on the system. If
  # not yet installed, it should be added to the array of packages to install.
  local pkg
  local pkg_version

  for pkg in "${apt_package_check_list[@]}"; do
    if not_installed "${pkg}"; then
      echo " *" "$pkg" [not installed]
      apt_package_install_list+=($pkg)
    else
      pkg_version=$(dpkg -s "${pkg}" 2>&1 | grep 'Version:' | cut -d " " -f 2)
      print_pkg_info "$pkg" "$pkg_version"
    fi
  done
}

package_install() {
  package_check

  if [[ ${#apt_package_install_list[@]} = 0 ]]; then
    echo -e "No apt packages to install.\n"
  else

    # Apply the PHP signing key
    apt-key adv --quiet --keyserver "hkp://keyserver.ubuntu.com:80" --recv-key E5267A6C 2>&1 | grep "gpg:"
    apt-key export E5267A6C | apt-key add -

    # Update all of the package references before installing anything
    echo "Running apt-get update..."
    apt-get -y update

    # Install required packages
    echo "Installing apt-get packages..."
    apt-get -y install ${apt_package_install_list[@]}

    # Remove unnecessary packages
    echo "Removing unnecessary packages..."
    apt-get autoremove -y

    # Clean up apt caches
    apt-get clean
  fi
}

configure() {
  # Copy nginx configuration from local
  cp "${DIR}/php5.6-upstream.conf" "/etc/nginx/upstreams/php56.conf"

  # Copy php-fpm configuration from local
  cp "${DIR}/php5.6-fpm.conf" "/etc/php/5.6/fpm/php-fpm.conf"
  cp "${DIR}/php5.6-www.conf" "/etc/php/5.6/fpm/pool.d/www.conf"
  cp "${DIR}/php5.6-custom.ini" "/etc/php/5.6/fpm/conf.d/php-custom.ini"
  cp "/srv/config/php-config/opcache.ini" "/etc/php/5.6/fpm/conf.d/opcache.ini"
  cp "/srv/config/php-config/xdebug.ini" "/etc/php/5.6/mods-available/xdebug.ini"

  echo " * Copied ${DIR}/php5.6-fpm.conf                   to /etc/php/5.6/fpm/php-fpm.conf"
  echo " * Copied ${DIR}/php5.6-www.conf                   to /etc/php/5.6/fpm/pool.d/www.conf"
  echo " * Copied ${DIR}/php5.6-custom.ini                 to /etc/php/5.6/fpm/conf.d/php-custom.ini"
  echo " * Copied /srv/config/php-config/opcache.ini       to /etc/php/5.6/fpm/conf.d/opcache.ini"
  echo " * Copied /srv/config/php-config/xdebug.ini        to /etc/php/5.6/mods-available/xdebug.ini"

  service php5.6-fpm restart
}

network_check
package_install
configure
