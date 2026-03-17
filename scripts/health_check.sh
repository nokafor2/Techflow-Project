#!/bin/bash

URL="http://localhost/health"
MAX_RETRIES=5

for i in $(seq 1 $MAX_RETRIES)
do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" $URL)

    if [ "$STATUS" == "200" ]; then
        echo "App is healthy"
        exit 0
    fi

    echo "Health check failed. Retry $i/$MAX_RETRIES"
    sleep 5
done

echo "Application failed health check"
exit 1