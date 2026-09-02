#!/bin/bash

webserver_static() {
    echo "----------------------------------------------------------"
    echo "http://localhost:$2"
    echo "----------------------------------------------------------"
    echo

    docker run -v `realpath $1`:/usr/share/nginx/html -p $2:80 nginx
}

webserver_php() {
    echo "----------------------------------------------------------"
    echo "http://localhost:$2"
    echo "----------------------------------------------------------"
    echo

    docker run -v `realpath $1`:/var/www/html -p $2:80 php:7.4-apache
}
