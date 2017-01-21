#!/bin/bash
#
# https://doro.es/certificado-lets-encrypt-autorenovable-pfsense/
#
# dg \4t doro.es
# 2016.12.18
#
# ssh-keygen -t rsa
# Copy public key to your PfSense user: System -> User Manager -> 'Your user' -> Authorized SSH Keys
# wget https://dl.eff.org/certbot-auto
# chmod a+x certbot-auto
# /root/certbot-auto
# /root/certbot-auto -d test1.doro.es -d test2.doro.es --agree-tos --text --email my@email.com --manual --preferred-challenges dns certonly
# echo "12 1 * * 1 root /bin/bash /root/cert-auto-pfsense-haproxy.sh">>/etc/crontab
#
# First time:
# ssh root@pfsense "chflags noschg /var/etc/haproxy/default_frontend.pem"
# cat /etc/letsencrypt/live/test1.doro.es/fullchain.pem /etc/letsencrypt/live/test1.doro.es/privkey.pem > /tmp/haproxy.pem; scp /tmp/haproxy.pem root@pfsense:/var/etc/haproxy/default_frontend.pem
# ssh root@pfsense "chflags schg /var/etc/haproxy/default_frontend.pem; pkill -7 haproxy; /usr/local/sbin/haproxy -f /var/etc/haproxy/haproxy.cfg -p /var/run/haproxy.pid -D"
#

RHOST=pfsense
DOMAIN=test1.doro.es
CERT=/etc/letsencrypt/live/${DOMAIN}/fullchain.pem
KEY=/etc/letsencrypt/live/${DOMAIN}/privkey.pem
TMP_FILE=/tmp/haproxy.pem
# default_frontend.pem is based in backend name: Services -> HAProxy -> backend -> 'backend name', i named 'default_backend'
PEM_FILE=default_frontend.pem
# Check md5 for running cert
NEW_MD5=$(md5sum ${CERT}|awk '{ print $1 }')
# Try to update
/root/certbot-auto renew --quiet
# Check md5 again
OLD_MD5=$(md5sum ${CERT}|awk '{ print $1 }')

# If certificate is updated, it will be copied to PfSense
if [ "$NEW_MD5" != "${OLD_MD5}" ]; then

	# PfSense overwrite certificates file when restart a process, so we have lock it to restart from shell without update cert manually from webgui
	# Unlock file
	ssh root@${RHOST} "chflags noschg /var/etc/haproxy/${PEM_FILE}"
	cat ${CERT} ${KEY} > ${TMP_FILE}
	scp ${TMP_FILE} root@${RHOST}:/var/etc/haproxy/${PEM_FILE}
	# Lock file
	ssh root@${RHOST} "chflags schg /var/etc/haproxy/${PEM_FILE}"
	ssh root@${RHOST} "pkill -7 haproxy; /usr/local/sbin/haproxy -f /var/etc/haproxy/haproxy.cfg -p /var/run/haproxy.pid -D"
fi
