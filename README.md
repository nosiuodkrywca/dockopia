# dockopia
a short bash script for backing up docker compose services


WARNING: this is an experimental project and can be unpredictable. it offers only basic functionality.

dockopia does two things:

1. searches a specified -d directory for subdirectories with a docker-compose.yml file
2. stops containers, saves all images and data found to a -t target directory, then starts the containers back
