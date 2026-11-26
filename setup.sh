#!/usr/bin/env bash
# Standalone native installer; run with sudo bash setup.sh
set -Eeuo pipefail
umask 022
trap 'echo "[ERROR] Installation stopped at line $LINENO" >&2' ERR
IP=${LAB_IP:-192.168.36.72}
DOMAIN=portal.kementrian.co.id
BASE=/opt/ngfw-portal
. /etc/os-release
[[ "$ID" == ubuntu && ( "$VERSION_ID" == 24.04 || "$VERSION_ID" == 26.04 ) ]] || { echo 'Ubuntu 24.04 or 26.04 required'; exit 1; }
[[ $(id -u) == 0 ]] || { echo 'Root required'; exit 1; }
ip -4 -o addr show | grep -F " $IP/" >/dev/null || { echo "Assign $IP to a server interface first"; exit 1; }
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl openssl iproute2 nginx openssh-server vsftpd
if ! dpkg-query -W -f='${Status}' php5.6-fpm 2>/dev/null | grep -q 'install ok installed'; then
  keydeb=$(mktemp --suffix=.deb)
  curl --fail --silent --show-error --location https://packages.sury.org/debsuryorg-archive-keyring.deb -o "$keydeb"
  dpkg -i "$keydeb"
  rm -f "$keydeb"
  printf 'deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ %s main\n' "$VERSION_CODENAME" > /etc/apt/sources.list.d/ngfw-php.list
  apt-get update
  apt-cache show php5.6-fpm >/dev/null 2>&1 || { echo 'PHP 5.6 package unavailable for this release/architecture'; exit 1; }
fi
apt-get install -y php5.6-fpm php5.6-cli
systemctl enable --now ssh php5.6-fpm
systemctl start ssh
install -d -m 755 "$BASE" "$BASE/web" "$BASE/tls" "$BASE/ftp"
cd "$BASE"
cat > /etc/php/5.6/fpm/pool.d/ngfw-portal.conf <<'POOL'
[ngfw-portal]
user = www-data
group = www-data
listen = /run/php/ngfw-portal.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
pm = ondemand
pm.max_children = 5
php_admin_value[upload_max_filesize] = 1M
php_admin_value[post_max_size] = 2M
php_admin_flag[display_errors] = off
php_admin_flag[expose_php] = off
php_admin_value[disable_functions] = exec,passthru,shell_exec,system,proc_open,popen
POOL
php-fpm5.6 -t
systemctl restart php5.6-fpm
cat > nginx.conf <<'NGINX'
server {
    listen LAB_BIND_IP:80;
    listen LAB_BIND_IP:443 ssl;
    server_name portal.kementrian.co.id;
    ssl_certificate /opt/ngfw-portal/tls/cert.pem;
    ssl_certificate_key /opt/ngfw-portal/tls/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    root /opt/ngfw-portal/web;
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/ngfw-portal-error.log;
    index index.php;
    client_max_body_size 2m;
    add_header X-Training-Lab NGFW-local-only always;
    location / { try_files $uri $uri/ =404; }
    location ~ \.php$ {
        try_files $uri =404;
        include fastcgi.conf;
        fastcgi_pass unix:/run/php/ngfw-portal.sock;
    }
    location ~ /\. { deny all; }
}
NGINX
sed -i "s/LAB_BIND_IP/$IP/g" nginx.conf
if [[ ! -s tls/key.pem || ! -s tls/cert.pem ]] || ! openssl x509 -in tls/cert.pem -noout -checkip "$IP" | grep -q "does match"; then
 openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj "/CN=$DOMAIN" -addext "subjectAltName=DNS:$DOMAIN,IP:$IP" -keyout tls/key.pem -out tls/cert.pem
fi
chmod 600 tls/key.pem
cat > web/index.php <<'PHP'
<?php
function h($s){return htmlspecialchars($s, ENT_QUOTES, 'UTF-8');}
function field($k,$method='GET'){ $a=$method==='POST'?$_POST:$_GET; return isset($a[$k])&&is_string($a[$k])?$a[$k]:''; }
$p=basename($_SERVER['SCRIPT_NAME']);
$menus=array('index.php'=>'Beranda','layanan.php'=>'Layanan','login.php'=>'Login Pegawai','search.php'=>'Pencarian','pengaduan.php'=>'Pengaduan','upload.php'=>'Unggah Dokumen','download.php'=>'Unduh Dokumen');
if($p==='download.php' && field('file')==='eicar'){
 $sample='X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*';
 header('Content-Type: application/octet-stream'); header('Content-Disposition: attachment; filename="eicar.com.txt"'); header('Content-Length: '.strlen($sample)); echo $sample; exit;
}
if($p==='download.php' && field('file')==='normal'){header('Content-Type: text/plain');header('Content-Disposition: attachment; filename="panduan.txt"');echo "Dokumen dummy portal layanan kementerian.\n";exit;}
?><!doctype html><html lang="id"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Portal Layanan Kementerian | Lab</title><style>
*{box-sizing:border-box}body{margin:0;font:16px Arial,sans-serif;background:#f1f5f9;color:#172a42}header{background:#102d50;color:white;padding:24px max(5%,calc((100% - 1100px)/2));}header small{color:#b9d4f5;letter-spacing:2px}nav{background:#fff;padding:16px 5%;display:flex;gap:18px;flex-wrap:wrap;border-bottom:1px solid #dbe4ee}nav a{color:#153e69;text-decoration:none;font-size:14px;font-weight:bold}main{max-width:1100px;margin:32px auto;padding:0 20px}.hero{background:#174a78;color:white;padding:35px;border-radius:12px}.panel{background:white;padding:28px;border:1px solid #dbe4ee;border-radius:10px;margin:20px 0}.tiles{display:flex;flex-wrap:wrap;gap:15px}.tiles a{flex:1;min-width:200px;padding:22px;background:white;border:1px solid #dbe4ee;border-radius:8px;color:#174a78;text-decoration:none}input,textarea{display:block;width:100%;max-width:540px;padding:12px;margin:9px 0 17px;border:1px solid #aebdcd;border-radius:5px}button,.btn{display:inline-block;background:#174a78;color:white;padding:12px 20px;border:0;border-radius:5px;text-decoration:none;cursor:pointer}.notice{background:#e8f2fc;padding:15px;overflow-wrap:anywhere}footer{padding:24px;text-align:center;color:#52657c;font-size:13px}h1{margin:10px 0}</style></head><body><header><small>SIMULASI LABORATORIUM • BUKAN SITUS RESMI</small><h1>Portal Layanan Kementerian</h1><div>Pusat informasi dan layanan administrasi digital</div></header><nav><?php foreach($menus as $url=>$label){echo '<a href="/'.$url.'">'.h($label).'</a>';} ?></nav><main>
<?php if($p==='index.php'){ ?><section class="hero"><h1>Layanan publik dalam satu portal</h1><p>Akses informasi, dokumen, dan layanan administrasi secara digital.</p></section><h2>Layanan utama</h2><div class="tiles"><?php foreach($menus as $url=>$label){if($url!== 'index.php')echo '<a href="/'.$url.'"><strong>'.h($label).'</strong><p>Akses layanan &rsaquo;</p></a>';} ?></div>
<?php }else{ ?><section class="panel"><h2><?php echo h(isset($menus[$p])?$menus[$p]:'Layanan'); ?></h2>
<?php if($p==='login.php'){ ?><form method="post"><label>Username<input name="username" required></label><label>Password<input name="password" type="password" required></label><button>Masuk</button></form><?php if($_SERVER['REQUEST_METHOD']==='POST')echo '<p class="notice">Simulasi login: kredensial tidak diverifikasi dan tidak disimpan.</p>'; ?>
<?php }elseif($p==='search.php'){ ?><form><label>Kata kunci<input name="q" value="<?php echo h(field('q')); ?>"></label><button>Cari</button></form><?php if(isset($_GET['q']))echo '<p class="notice">Hasil pencarian untuk: '.h(field('q')).' — Tidak ada dokumen yang cocok.</p>'; ?>
<?php }elseif($p==='pengaduan.php'){ ?><form method="post"><label>Nama<input name="nama" required></label><label>Pesan<textarea name="pesan" required></textarea></label><button>Kirim</button></form><?php if($_SERVER['REQUEST_METHOD']==='POST')echo '<p class="notice">Pengaduan dummy diterima; data tidak disimpan.</p>'; ?>
<?php }elseif($p==='upload.php'){ ?><form method="post" enctype="multipart/form-data"><label>Dokumen (maks. 1 MiB)<input type="file" name="file" required></label><button>Unggah</button></form><?php if(isset($_FILES['file'])){ $f=$_FILES['file'];if($f['error']===UPLOAD_ERR_OK && $f['size']<=1048576 && is_uploaded_file($f['tmp_name'])){echo '<p class="notice">Transfer diterima: '.h(basename($f['name'])).' ('.(int)$f['size'].' byte). File tidak disimpan atau dieksekusi.</p>';}else{http_response_code(400);echo '<p>Unggahan ditolak atau terlalu besar.</p>';}} ?>
<?php }elseif($p==='download.php'){ ?><p>Dokumen biasa dan file standar uji antivirus (EICAR, bukan malware aktif).</p><p><a class="btn" href="?file=normal">Unduh dokumen biasa</a></p><p><a class="btn" href="?file=eicar">Unduh EICAR</a></p>
<?php }else{ ?><p>Informasi layanan administrasi, surat menyurat, dan dokumen publik. Seluruh informasi bersifat fiktif.</p><?php } ?></section><?php } ?></main><footer>Portal dummy untuk pengujian NGFW • Local lab only</footer></body></html>
PHP
for page in layanan login search pengaduan upload download; do cp web/index.php "web/$page.php"; done
# Dedicated FTP configuration: anonymous read-only, local lab IP only.
chmod 755 "$BASE/ftp"
printf 'Dokumen FTP dummy untuk uji NGFW.\n' > "$BASE/ftp/panduan.txt"
if [[ ! -e /etc/vsftpd.conf.ngfw-backup ]]; then cp -a /etc/vsftpd.conf /etc/vsftpd.conf.ngfw-backup; fi
cat > /etc/vsftpd.conf <<CONF
listen=YES
listen_ipv6=NO
listen_address=$IP
anonymous_enable=YES
local_enable=NO
write_enable=NO
anon_root=$BASE/ftp
no_anon_password=YES
pasv_enable=YES
pasv_address=$IP
pasv_min_port=30000
pasv_max_port=30009
xferlog_enable=YES
secure_chroot_dir=/var/run/vsftpd/empty
CONF
systemctl enable vsftpd
systemctl restart vsftpd
install -m 644 nginx.conf /etc/nginx/sites-available/ngfw-portal
ln -sfn /etc/nginx/sites-available/ngfw-portal /etc/nginx/sites-enabled/ngfw-portal
# Disable only the stock default site on this dedicated training VM.
if [[ -L /etc/nginx/sites-enabled/default && $(readlink -f /etc/nginx/sites-enabled/default) == /etc/nginx/sites-available/default ]]; then
  unlink /etc/nginx/sites-enabled/default
fi
chown -R root:root "$BASE/web"
find "$BASE/web" -type f -exec chmod 644 {} +
nginx -t
if nginx -T 2>&1 | grep -i 'conflicting server name' | grep -F "$DOMAIN"; then
  echo '[ERROR] Duplicate portal virtual host. Disable the conflicting site before continuing.' >&2
  exit 1
fi
systemctl enable --now nginx
systemctl restart nginx
echo "[CHECK] Target HTTP: $DOMAIN -> $IP"
ss -ltn | grep -E ":(80|443)[[:space:]]" || true
echo '[CHECK] Validasi seluruh service dan endpoint'
for service in nginx php5.6-fpm ssh vsftpd; do
  systemctl is-active --quiet "$service"
  printf '[OK] %s aktif\n' "$service"
done
for page in index login search pengaduan upload download layanan; do
  php5.6 -l "$BASE/web/$page.php" >/dev/null
  if ! curl --noproxy '*' --max-time 15 --fail --silent --show-error --resolve "$DOMAIN:80:$IP" "http://$DOMAIN/$page.php" >/dev/null; then
    echo "[ERROR] HTTP /$page.php failed. Diagnostic information:"
    ls -ld "$BASE" "$BASE/web" "$BASE/web/$page.php"
    curl --noproxy '*' -si --max-time 10 --resolve "$DOMAIN:80:$IP" "http://$DOMAIN/$page.php" | head -c 2000 || true
    nginx -T 2>&1 | grep -E 'configuration file|server_name|listen |root |fastcgi_pass' || true
    tail -n 20 /var/log/nginx/ngfw-portal-error.log || true
    exit 1
  fi
  printf '[OK] HTTP /%s.php\n' "$page"
done
curl --noproxy '*' --max-time 15 --fail --silent --show-error --cacert "$BASE/tls/cert.pem" --resolve "$DOMAIN:443:$IP" "https://$DOMAIN/" >/dev/null
printf '[OK] HTTPS\n'
ss -ltn

printf '\nPortal: http://%s / https://%s\nLogs: tail -f /var/log/nginx/access.log\n' "$DOMAIN" "$DOMAIN"
php-fpm5.6 -v

