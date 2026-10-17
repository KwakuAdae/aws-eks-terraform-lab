#!/bin/sh
# Fill in which pod served the page and which version is running.
# POD_NAME comes from the Kubernetes Downward API; APP_VERSION is set by Terraform (2-app).
sed -e "s/__POD_NAME__/${POD_NAME:-local}/" \
    -e "s/__APP_VERSION__/${APP_VERSION:-dev}/" \
    /usr/share/nginx/html/index.html.tpl > /usr/share/nginx/html/index.html
exec nginx -g 'daemon off;'
