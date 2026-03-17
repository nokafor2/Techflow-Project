#!/bin/bash

CONTAINER="techflow-app"

IMAGE=$(docker inspect --format='{{.Config.Image}}' $CONTAINER)

echo "Current image: $IMAGE"

docker tag $IMAGE nokafor2/techflow-app:previous_stable
docker push nokafor2/techflow-app:previous_stable