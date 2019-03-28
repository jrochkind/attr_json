#!/bin/bash
# Ensure all gems installed on start
bundle check || bundle install --jobs 3 --retry 20

# Finally call command issued to the docker service
exec "$@"
