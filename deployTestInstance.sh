#!/bin/bash

#################################################################################################
# This script is designed to be called with a commit ID and a mode string (either ISSUE or PR). #
# It will then take that, clone the repo, check out the commit or PR, and configure and start   #
# the app based on that.                                                                        #
#################################################################################################


# 1. Spawn a new link via port numbers
#  ie ->
#     - PR #25 requesting a demo server on staging, server should return a link: yacs.duckdns.org:25
#     - PR #1000 requesting a demo server on staging, server should return a link: yacs.duckdns.org:1000

# 1.1 Update nginx.conf to open/supply the links for demo server.
# 1.1.1
#     - Map the port number to :80
#         ie: PR #25 is using :25. YOu have to tell NGINX that port 25 is linked to yacs_web-25's 443 port.


# 2. Auto-destroy demo servers that have been running for at least 24 hours

# 3. Rename each docker container for each PR
#    - PR #25 -> all docker container names should have *-25. 

# Requires packages: docker, docker-compose, procmail, git, sed, tac, potentially others depending on your distro

echo "Starting deployTestInstance.sh Script..."


#######################
# Argument Validation #
#######################

# Name the variables
ID=$1
MODE=$2

# Make sure exactly 2 arguments are passed
if [ $# -ne 2 ]; then
  # 2 args not passed, see if 1 was
  if [ $# -ne 1 ]; then
    # 1 arg was not passed
    echo "Invalid Number Of Arguments Specified, Aborting."; exit 1
  else
    # 1 arg was passed, use compatibility mode
    echo "1 Argument specified, running in compatibility mode"
    MODE="ISSUE"
  fi
fi

# Validate MODE and ID (depending on MODE)
if [ "${MODE}" = "ISSUE" ]; then

   # Only allow a-z, 0-9 in commit IDs
  if [[ "${ID}" =~ [^abcdefghijklmnopqrstuvwxyz0123456789] ]]; then
      echo "Invalid Commit ID, Aborting."; exit 1
  fi

elif [ "${MODE}" = "PR" ]; then

  # Only allow 0-9 in PR Numbers
  if [[ "${ID}" =~ [^0123456789] ]]; then
      echo "Invalid PR Number, Aborting."; exit 1
  fi

else
  echo "Invalid Mode Specified, Aborting."; exit 1
fi

echo "Arguments Validated."



#####################
# Exclusivity Check #
#####################

function finish {
  # Remove lock files
  echo "Trapped EXIT, removing lockfiles"
  rm -f ~/deployTestInstance.lock
  rm -f ~/deployTestInstance-"${ID}".lock
}
trap finish EXIT

# Try to acquire a lock every 5 seconds, not continuing until then.
# Given that this normally is run by GitHub, this should end up terminated by them if it never gets a lock
echo "Acquiring unique lock..."

# Acquire unique lock so that we can have parallel builds that don't interfere with each other
lockfile -5 ~/deployTestInstance-"${ID}".lock
echo "Unique lock acquired"



###############
# Basic Setup #
###############

# Echo out what we're doing
echo "Creating instance for commit/PR '${ID}'"

# Enter the folder to spin up an instance
cd ~/CICD_TestInstances || { echo "Test Instances Folder Missing, Aborting."; exit 1; }

# If for some reason this job was being rerun, we'll want to delete the old folder. We don't care if it fails of course
rm -rf "${ID}"

# Create a folder for this instance
echo "Creating folder for this instance"
mkdir "${ID}"

# Enter it
cd "${ID}" || { echo "Commit Folder Missing, Aborting."; exit 1; }

# Clone the repo
echo "Cloning repo"
git clone https://github.com/YACS-RCOS/yacs.n || { echo "Repo Cloning Failed, Aborting."; exit 1; }

# Enter it
cd yacs.n || { echo "Repo Folder Missing, Aborting."; exit 1; }

# Checkout depending on mode
if [ "${MODE}" = "ISSUE" ]; then
  # Checkout the commit
  echo "Checking out commit"
  git checkout "${ID}" || { echo "Commit Checkout Failed, Aborting."; exit 1; }

elif [ "${MODE}" = "PR" ]; then
  # Checkout the PR
  echo "Checking out PR"

  # Configure remotes to allow checking out PR merge commits
  # See: https://gist.github.com/piscisaureus/3342247

  # Add remote URL
  sed -i '/fetch = +refs\/heads\/\*:refs\/remotes\/origin\/\*/a \\tfetch = +refs\/pull\/*\/head:refs\/remotes\/origin\/pr\/*' .git/config || { echo "PR Checkout Failed at SED, Aborting."; exit 1; }

  # Pull PR
  git fetch origin "refs/pull/${ID}/head:pr/${ID}" || { echo "PR Checkout Failed at FETCH, Aborting."; exit 1; }

  # Checkout PR
  git checkout "pr/${ID}" || { echo "PR Checkout Failed and CHECKOUT, Aborting."; exit 1; }

fi



############################
# Configure Instance Setup #
############################

# Docker
# Configure port

# Acquire global lock for this next part
lockfile -5 ~/deployTestInstance.lock

# Collect a port
PORT="$(bash ~/CI-CD/getPort.sh "$ID")"

# Make sure the port isn't 0
if [ "${PORT}" -eq "0" ]; then
   echo "No ports available, Aborting.";
   exit 1
fi

echo "Acquired port ${PORT}"

# Unlock for now
rm -f ~/deployTestInstance.lock

# Store our commit ID in the port file for use in cleanup tasks
echo "${ID}" > "${HOME}/dev-site-ports/${PORT}"

# Write into docker compose file
sed -i "s/7655:80/${PORT}:80/g" docker-compose.yml  || { echo "Docker SED Failed, Aborting."; exit 1; }

# Add newlines to docker-compose.yml to fix issue with tac breaking
{ echo ""; echo ""; echo ""; } >> docker-compose.yml

# Delete other port mappings (temporary until they're removed in the real code)
tac docker-compose.yml | sed "/3000:3000/I,+1 d" | tac > docker-compose.yml.new || { echo "Docker SED Failed, Aborting."; exit 1; }
mv docker-compose.yml.new docker-compose.yml || { echo "Docker SED Failed, Aborting."; exit 1; }
tac docker-compose.yml | sed "/3001:3001/I,+1 d" | tac > docker-compose.yml.new || { echo "Docker SED Failed, Aborting."; exit 1; }
mv docker-compose.yml.new docker-compose.yml || { echo "Docker SED Failed, Aborting."; exit 1; }
tac docker-compose.yml | sed "/3002:3000/I,+1 d" | tac > docker-compose.yml.new || { echo "Docker SED Failed, Aborting."; exit 1; }
mv docker-compose.yml.new docker-compose.yml || { echo "Docker SED Failed, Aborting."; exit 1; }
tac docker-compose.yml | sed "/27017:27017/I,+1 d" | tac > docker-compose.yml.new || { echo "Docker SED Failed, Aborting."; exit 1; }
mv docker-compose.yml.new docker-compose.yml || { echo "Docker SED Failed, Aborting."; exit 1; }

# Done configuring docker environment variables
echo "Docker environment variables configured"

# We're done configuring
echo "Configuring environment variables complete"

#############################
# Create and Start instance #
#############################

# Pull the latest images
echo "Pulling latest Docker images"
docker pull node:current-alpine
docker pull python:3.8-slim
docker pull postgres:12-alpine
docker pull nginx:latest

# Build containers
echo "Building containers for instance"
docker-compose -p "${ID}" build --parallel || { echo "Docker-Compose Build Failed, Aborting."; exit 1; }

# Just in case this is a rerun, try to shut down / reset previous containers
echo "Attempting to stop any previous containers"
docker-compose -p "${ID}" down
echo "Attempting to clear any previous container's data"
docker volume rm "${ID}_yacs_postgres_data"

# Start the new instance
echo "Starting instance"
docker-compose -p "${ID}" up -d || { echo "Docker-Compose Up Failed, Aborting."; exit 1; }  # deploy 2 of the repo's main docker-compose.yml using -f

# We're done!
echo "Instance is now running"

######################
# Configure Dev Site #
######################

# Talk about it
echo "Configuring dev site"

# Copy example configuration file
cp ~/PollBuddy.app/webserver/conf.d/TEMPLATE.conf.ignore "${HOME}/dev-site-configs/${ID}.conf" || { echo "Template NGINX Config Copy Failed, Aborting."; exit 1; }

# Edit configuration file
sed -i "s/TEMPLATE_COMMITID/${ID}/g" "${HOME}/dev-site-configs/${ID}.conf"  || { echo "NGINX SED Failed, Aborting."; exit 1; }
sed -i "s/TEMPLATE_PORT/${PORT}/g" "${HOME}/dev-site-configs/${ID}.conf"  || { echo "NGINX SED Failed, Aborting."; exit 1; }

# We're done!
echo "Dev site configured"

####################
# Restart Dev Site #
####################

# Talk about it
echo "Restarting dev site"

# Acquire the lock again
lockfile -5 ~/deployTestInstance.lock

# Move over to the website folder
cd ~/yacs.n/ || { echo "CD to yacs.n Folder Failed, Aborting."; exit 1; }

# Restart dev site (instance configs are bind mounted, so we just need to restart nginx)
docker-compose restart

# We're done!
echo "Dev site restarted"

##########
# Finish #
##########

# We're done!
echo "Deployment completed successfully!"
echo "Deploy Link: https://yacs.duckdns.org:${PORT}"


exit 0