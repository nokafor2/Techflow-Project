#!/bin/bash

CONTAINER="techflow-app"

IMAGE=$(docker inspect --format='{{.Config.Image}}' $CONTAINER)

echo "Current image: $IMAGE"

docker tag $IMAGE yourdockerhubusername/techflow-app:previous_stable
docker push yourdockerhubusername/techflow-app:previous_stable