#!/bin/bash

domains=(ratodo.ru www.ratodo.ru)
rsa_key_size=4096
data_path="./certbot"
email="anton.ratnov@yandex.ru" # твоя почта
staging=1 # staging=1 — если хочешь потестить

GATEWAY_CONTAINER="gateway"
DC="docker compose -f /root/general/docker-compose-cd.yml"

echo ">> Проверка наличия данных"
if [ -d "$data_path/conf/live/${domains[0]}" ]; then
  read -p "Существующий сертификат найден. Перезаписать? (y/N): " decision
  if [ "$decision" != "Y" ] && [ "$decision" != "y" ]; then
    echo "Выход..."
    exit
  fi
fi

echo ">> Скачивание TLS параметров"
mkdir -p "$data_path/conf"
if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "$data_path/conf/ssl-dhparams.pem"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "$data_path/conf/options-ssl-nginx.conf"
fi

echo ">> Создание временного самоподписанного сертификата"
path="/etc/letsencrypt/live/${domains[0]}"
$DC run --rm --entrypoint "\
  mkdir -p $path && \
  openssl req -x509 -nodes -newkey rsa:${rsa_key_size} -days 1 \
    -keyout '$path/privkey.pem' \
    -out '$path/fullchain.pem' \
    -subj '/CN=localhost'" certbot

echo ">> Запуск nginx"
$DC up -d $GATEWAY_CONTAINER

echo ">> Удаление временного сертификата"
$DC run --rm --entrypoint "\
  rm -rf /etc/letsencrypt/live/${domains[0]} /etc/letsencrypt/live/${domains[0]}* && \
  rm -rf /etc/letsencrypt/archive/${domains[0]} /etc/letsencrypt/archive/${domains[0]}* && \
  rm -rf /etc/letsencrypt/renewal/${domains[0]}.conf /etc/letsencrypt/renewal/${domains[0]}*.conf" certbot

echo ">> Запрос Let's Encrypt сертификата"
domain_args=""
for domain in "${domains[@]}"; do
  domain_args="$domain_args -d $domain"
done

email_arg="--email $email"
[ $staging != "0" ] && staging_arg="--staging"

$DC run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    --cert-name ${domains[0]} \
    --force-renewal \
    $staging_arg \
    $email_arg \
    $domain_args \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --force-renewal" certbot

echo ">> Перезапуск nginx с новыми сертификатами"
$DC exec $GATEWAY_CONTAINER nginx -s reload
