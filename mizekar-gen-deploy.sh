# در عمل
# پوشه رو کامل کپی کردم روی سرور در داخل پوشه nginx-proxy
# بعد روی سرور کپی کردم به داخل پوشه acme
# sudo cp -R ~/data/nginx-proxy/mizekar.site_ecc ~/data/nginx-proxy/acme/
# بعد داکر کامپوز رو اجرا کردم که نصب کنه سرتیفیکت رو
# docker compose up -d acme-arvan

# از سیستم محلی (Mac) - مستقیماً به پوشه certs
scp /Users/abooraja/.acme.sh/mizekar.site_ecc/fullchain.cer ubuntu@37.32.12.61:~/data/nginx-proxy/certs/mizekar.site.crt
scp /Users/abooraja/.acme.sh/mizekar.site_ecc/mizekar.site.key ubuntu@37.32.12.61:~/data/nginx-proxy/certs/mizekar.site.key

### مرحله 2: نصب روی سرور Ubuntu

# اتصال به سرور
ssh ubuntu@37.32.12.61

# تنظیم مجوزها
cd ~/data/nginx-proxy
sudo chmod 644 ./certs/mizekar.site.crt
sudo chmod 600 ./certs/mizekar.site.key
sudo chown root:root ./certs/mizekar.site.*

# راه‌اندازی مجدد container
docker-compose restart nginx-proxy
