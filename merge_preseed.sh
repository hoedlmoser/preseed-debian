#!/bin/bash

set -e

HOST_NAME="${1:-unassigned-hostname}"
DOMAIN="${2:-unassigned-domain}"
ADD_CONFIG="${3:-none}"
PRESEED_FILE="${4:-preseed.cfg}"
USERNAME="${5:-tux}"
USER_FULLNAME="${6:-Tux Pinguin}"
DEBIAN_ISO="${7:-debian-11.2.0-amd64-netinst.iso}"
PUB_KEY_NAME="${8:-ansible}"

if [[ "${HOST_NAME}" == "unassigned-hostname" || "${DOMAIN}" == "unassigned-domain" ]]; then
  PRESEED_ISO="${DEBIAN_ISO%.iso}-preseed.iso"
else
  PRESEED_ISO="${DEBIAN_ISO%.iso}-preseed-${HOST_NAME}-${DOMAIN//./-}.iso"
fi

echo "merging preseed"
echo "host: ${HOST_NAME}.${DOMAIN}"
echo "addon config: ${ADD_CONFIG}"
echo "preseed: ${PRESEED_FILE}"
echo "username: ${USERNAME}"
echo "user fullname: ${USER_FULLNAME}"
echo "debian iso: ${DEBIAN_ISO}"
echo "pub key: ${PUB_KEY_NAME}"
echo "preseed iso: ${PRESEED_ISO}"

echo

if [ ! -f ${PUB_KEY_NAME}.pub ]; then
  ssh-keygen -C "${PUB_KEY_NAME}" -f ${PUB_KEY_NAME} -t ed25519 -N ''
fi;

if [ ! -f root-password-crypted ]; then
  pwgen --secure --symbols 64 1 | tee root-password | mkpasswd --stdin --method=sha-512 > root-password-crypted
  chmod go= root-password*
fi;
if [ ! -f user-password-crypted ]; then
  pwgen --secure --symbols 64 1 | tee user-password | mkpasswd --stdin --method=sha-512 > user-password-crypted
  chmod go= user-password*
fi;

if [ ! -f ${DEBIAN_ISO} ]; then
  wget https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/${DEBIAN_ISO}
fi;

tempdir=$(mktemp -d)
echo "tempdir: ${tempdir}"

pub_key=$(<${PUB_KEY_NAME}.pub)

root_password_crypted=$(<root-password-crypted)
user_password_crypted=$(<user-password-crypted)

volumeid=$(isoinfo -d -i ${DEBIAN_ISO} | sed -n 's/Volume id: //p')

xorriso -osirrox on -indev ${DEBIAN_ISO} -extract / ${tempdir}
chmod -R +w ${tempdir}

sed "s/<SSH_PUBLIC_KEY>/${pub_key}/g; \
     s/<HOST_NAME>/${HOST_NAME}/g; \
     s/<DOMAIN>/${DOMAIN}/g; \
     s/<ROOT_PASSWORD_CRYPTED>/${root_password_crypted}/g; \
     s/<USER_PASSWORD_CRYPTED>/${user_password_crypted}/g; \
     s/<USERNAME>/${USERNAME}/g; \
     s/<USER_FULLNAME>/${USER_FULLNAME}/g; \
" ${PRESEED_FILE} > ${tempdir}/preseed.cfg

if [ -f ${ADD_CONFIG} ]; then
  cat ${ADD_CONFIG} >> ${tempdir}/preseed.cfg
fi

my_pwd=$(pwd)
cd ${tempdir}

sed -i 's#timeout [0-9]\+#timeout 40#g' isolinux/isolinux.cfg
sed -i '1i set timeout=4' boot/grub/grub.cfg

gunzip install.amd/initrd.gz
echo preseed.cfg | cpio -H newc -o -A -F install.amd/initrd
gzip install.amd/initrd

gunzip install.amd/gtk/initrd.gz
echo preseed.cfg | cpio -H newc -o -A -F install.amd/gtk/initrd
gzip install.amd/gtk/initrd

find -follow -type f ! -name md5sum.txt -print0 | xargs -0 md5sum > md5sum.txt

cd ${my_pwd}

xorriso -as mkisofs -r -V "${volumeid}" \
        -o ${PRESEED_ISO} \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
	-b isolinux/isolinux.bin -c isolinux/boot.cat \
	-boot-load-size 4 -boot-info-table -no-emul-boot \
	-eltorito-alt-boot \
	-e boot/grub/efi.img \
	-no-emul-boot -isohybrid-gpt-basdat \
        ${tempdir}

#rm -rf ${tempdir}

