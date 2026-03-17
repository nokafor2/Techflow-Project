#!/bin/bash

IMAGE="yourdockerhubusername/techflow-app:previous_stable"

echo "Rolling back deployment..."

docker stop techflow-app || true
docker rm techflow-app || true

docker pull $IMAGE

docker run -d \
  --name techflow-app \
  -p 80:5000 \
  $IMAGE

sleep 5

STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/health)

if [ "$STATUS" == "200" ]; then
    echo "Rollback successful"
    exit 0
else
    echo "Rollback failed"
    exit 1
fi