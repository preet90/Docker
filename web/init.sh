#!/bin/bash -l

echo "

----------------------------------------------------------------
   ____                   ______
  / __ \                 |  ____|
 | |  | |_ __   ___ _ __ | |__  _   _  ___  ___
 | |  | | '_ \ / _ \ '_ \|  __|| | | |/ _ \/ __|
 | |__| | |_) |  __/ | | | |___| |_| |  __/\__ \.
  \____/| .__/ \___|_| |_|______\__, |\___||___/
        | |                      __/ |
        |_|                     |___/

Openeyes is an AGPL v3 OpenSource Electronic Patient Record.
Brought to you by the Apperta Foundation (https://apperta.org/)
See the following urls for more info
- https://openeyes.org.uk/
- https://github.com/openeyes/openeyes
- https://github.com/appertafoundation/openeyes

----------------------------------------------------------------

"
export DEBIAN_FRONTEND=noninteractive

echo "Setting Timezone to ${TZ:-'Europe/London'}"
sudo timedatectl set-timezone ${TZ:-'Europe/London'} 2>/dev/null
[ $? = 1 ] && sudo ln -sf /usr/share/zoneinfo/${TZ:-Europe/London} /etc/localtime || :
sed -i "s|.*date.timezone =.*|date.timezone = ${TZ:-'Europe/London'}|" /etc/php/${PHP_VERSION}/apache2/php.ini 2>/dev/null || sed -i "s|.*date.timezone =.*|date.timezone = ${TZ:-'Europe/London'}|" /etc/php${PHP_VERSION}/apache2/php.ini
sed -i "s|^.*date.timezone =.*|date.timezone = ${TZ:-'Europe/London'}|" /etc/php/${PHP_VERSION}/cli/php.ini 2>/dev/null || sed -i "s|^.*date.timezone =.*|date.timezone = ${TZ:-'Europe/London'}|" /etc/php${PHP_VERSION}/cli/php.ini

# if we have mysql installed in the same image, then start the service
[ "$LOCAL_DB" == "TRUE" ] && service mysql start

# Set ssh key Can be done using a secret (SSH_PRIVATE_KEY), as an ENV variable (SSH_PRIVATE_KEY)
# Or by mounting your host .ssh folder to /root/.host-ssh
mkdir -p /root/.ssh /tmp/.ssh
idfilecontent="Host github.com\nStrictHostKeyChecking no"
[ -d /root/.host-ssh ] && rsync -av /root/.host-ssh/ /root/.ssh --exclude known_hosts --delete 2>/dev/null || :
[ ! -z ${SSH_PRIVATE_KEY} ] && { echo "${SSH_PRIVATE_KEY}" > /tmp/.ssh/id_rsa && echo -e "$idfilecontent\nIdentityFile /tmp/.ssh/id_rsa" > /root/.ssh/config; } || :
[ -f /run/secrets/SSH_PRIVATE_KEY ] && { cp /run/secrets/SSH_PRIVATE_KEY /tmp/.ssh/id_rsa; echo -e "$idfilecontent\nIdentityFile /tmp/.ssh/id_rsa" > /root/.ssh/config ; } || :
[ -d /root/.ssh ] && chmod 600 /root/.ssh/* || :
[ -d /tmp/.ssh ] && chmod 600 /tmp/.ssh/* || :

# Use docker secret as DB password, or fall back to environment variable
[ -f /run/secrets/DATABASE_PASS ] && dbpassword="$(</run/secrets/MYSQL_ROOT_PASSWORD)" || dbpassword=${MYSQL_ROOT_PASSWORD:-""}
[ ! -z $dbpassword ] && dbpassword="-p$dbpassword" || dbpassword="-p''" # Add -p to the beginning of the password (workaround for blank passwords)

# Test to see if database is accessible. If not we will rebuild it later
echo Testing Database: host=${DATABASE_HOST:-"localhost"} user=${MYSQL_SUPER_USER:-"openeyes"} name=${DATABASE_NAME:-"openeyes"}

db_pre_exist=$( ! mysql --host=${DATABASE_HOST:-'localhost'} -u $MYSQL_SUPER_USER "$dbpassword" -e 'use '"${DATABASE_NAME:-'openeyes'};")$?

# If no web files exist, check them out locally
if [ ! -d $WROOT/protected/modules/eyedraw/src ]; then
  ssh git@github.com -T
  [ "$?" == "1" ] && cloneroot="git@github.com:" || cloneroot="https://github.com/"
  [ -z "$GIT_ORG" ] && { [ "$cloneroot" == "https://" ] && gitroot="appertafoundation" || gitroot="openeyes";} || gitroot=$GIT_ORG

  # If openeyes files don't already exist then clone them
  [ ! -f $WROOT/protected/runtime/testme ] && { echo cloning "-b ${BUILD_BRANCH} $cloneroot${gitroot}/openeyes.git"; git clone -b ${BUILD_BRANCH} $cloneroot${gitroot}/openeyes.git $WROOT; } || :

  # run the standard installer script, do not overwrite database if it already exists
  initparams="--accept"
  [ "$db_pre_exist" == "1" ] && initparams="$initparams --preserve-database" || :
  $WROOT/protected/scripts/install-oe.sh ${BUILD_BRANCH} --accept $initparams
  # update db_pre_exist, as it will now exist and we don't want to overwrite it again!
  db_pre_exist=1
  echo "true" > /initialised.oe
fi

# If this is a new container (using existing git files), then we need to initialise the config
initparams="--no-checkout --accept --no-migrate"
[ "$db_pre_exist" == "1" ] && initparams="$initparams --preserve-database" || :
[ ! -f /initialised.oe ] && { $WROOT/protected/scripts/install-oe.sh $initparams  && echo "true" > /initialised.oe && db_pre_exist=1; } || :

if [ $db_pre_exist = 0 ]; then
    #If DB doesn't exist then create it - if ENV sample=demo, etc, then call oe-reset (--demo) --no-dependencies --no-migrate
    echo "Database host=${DATABASE_HOST:-'localhost'}; user=${MYSQL_SUPER_USER:-'openeyes'}; name=${DATABASE_NAME:-'openeyes'} was not fount. Creating a new db"
    [ "$USE_DEMO_DATA" = "TRUE" ] && resetparams="--demo" || resetparams=""
    $WROOT/protected/scripts/oe-reset.sh -b $BUILD_BRANCH $resetparams
fi

# Ensure .htaccess is set
if [ ! -f "$WROOT/.htaccess" ]; then
    echo Renaming .htaccess file
    mv $WROOT/.htaccess.sample $WROOT/.htaccess
    sudo chown www-data:www-data $WROOT/.htaccess
fi

# ensure index is set
if [ ! -f "$WROOT/index.php" ]; then
    echo Renaming index.php file
    mv $WROOT/index.example.php $WROOT/index.php
    sudo chown www-data:www-data $WROOT/index.php
fi

$WROOT/protected/scripts/set-profile.sh
echo "source /etc/profile.d/git-branch.sh" > ~/.bash_profile
source /etc/profile.d/git-branch.sh

[[ ! -d "$WROOT/node_modules" || ! -d "$WROOT/vendor/yiisoft" ]] && $WROOT/protected/scripts/oe-fix.sh || :


[[ -z $(git config --global user.name)  && ! -z $GIT_USER ]] && { git config --global user.name "$GIT_USER" && echo "git global user set to $GIT_USER"; } || :
[[ -z $(git config --global user.email) && ! -z $GIT_EMAIL ]] && { git config --global user.email "$GIT_EMAIL" && echo "git global email set to $GIT_EMAIL"; } || :

# Start apache
echo "Starting opeyes apache process..."
apachectl -DFOREGROUND
