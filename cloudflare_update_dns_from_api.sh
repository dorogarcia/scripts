#!/bin/bash
#
# https://doro.es/cloudflare-dynamic-dns-service/
#

# whatismyip_334234232429874928373947.php
# <?php
# echo $_SERVER['REMOTE_ADDR'];
# ?>

MY_IP=$(curl -s https://doro.es/whatismyip_334234232429874928373947.php?`date +%s`)

curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/asda4g2ert254753j427i8juj8t8gtyhhgu/dns_records/184a439fad0b0513678hx83a78d890a1" \
	-H "X-Auth-Email: my@email.com" \
	-H "X-Auth-Key:36181a8b6d4j5k7l8lwl297a76105a7ewv55467" \
	-H "Content-Type: application/json" \
	--data "{\"type\":\"A\",\"name\":\"testdinamicdns.doro.es\",\"content\":\"${MY_IP}\",\"ttl\":120,\"proxied\":false}"
