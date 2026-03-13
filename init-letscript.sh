#!/bin/bash

domains=(entergen.ru www.entergen.ru)
rsa_key_size=4096
data_path="./certbot"
email="anton.ratnov@yandex.ru" # твоя почта
staging=1 # staging=1 — если хочешь потестить

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
docker compose run --rm --entrypoint "\
  mkdir -p $path && \
  openssl req -x509 -nodes -newkey rsa:${rsa_key_size} -days 1 \
    -keyout '$path/privkey.pem' \
    -out '$path/fullchain.pem' \
    -subj '/CN=localhost'" certbot

echo ">> Запуск nginx"
docker compose up -d entergen-gateway

echo ">> Удаление временного сертификата"
docker compose run --rm --entrypoint "\
  rm -Rf /etc/letsencrypt/live/${domains[0]} && \
  rm -Rf /etc/letsencrypt/archive/${domains[0]} && \
  rm -Rf /etc/letsencrypt/renewal/${domains[0]}.conf" certbot

echo ">> Запрос Let's Encrypt сертификата"
domain_args=""
for domain in "${domains[@]}"; do
  domain_args="$domain_args -d $domain"
done

email_arg="--email $email"
[ $staging != "0" ] && staging_arg="--staging"

docker compose run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $staging_arg \
    $email_arg \
    $domain_args \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --force-renewal" certbot

echo ">> Перезапуск nginx с новыми сертификатами"
docker compose exec entergen-gateway nginx -s reload
