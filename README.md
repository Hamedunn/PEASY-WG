# PEASY-WG

**PEASY-WG** اسکریپتی برای نصب خودکار **WireGuard VPN** روی اوبونتو 22.04 با پنل تحت وب برای مدیریت کلاینت‌ها و همگام‌سازی خودکار با GitHub.

## ویژگی‌ها
- نصب خودکار WireGuard و پیش‌نیازها.
- پیکربندی با DNSهای `10.202.10.10` و `10.202.10.11`.
- تولید کانفیگ کلاینت با QR کد.
- پنل تحت وب Flask برای مدیریت کلاینت‌ها.
- همگام‌سازی روزانه با GitHub.

## پیش‌نیازها
- اوبونتو 22.04
- دسترسی root یا sudo
- IP عمومی و اتصال اینترنت

## نصب
1. دانلود اسکریپت:
```bash
sudo apt update
wget https://raw.githubusercontent.com/Hamedunn/PEASY-WG/main/setup.sh
chmod +x setup.sh
