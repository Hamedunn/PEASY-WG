# PEASY-WG

A simple WireGuard VPN setup with a built-in web panel.  
راه‌اندازی ساده‌ی وی‌پی‌ان WireGuard با پنل تحت‌وب داخلی.

---

## ✨ Features | امکانات

- Automatic WireGuard and dependencies installation.  
  نصب خودکار WireGuard و تمام پیش‌نیازها.

- Server setup with DNS servers `10.202.10.10` and `10.202.10.11`.  
  پیکربندی سرور با DNSهای `10.202.10.10` و `10.202.10.11`.

- Client config generation with QR code.  
  تولید فایل پیکربندی کلاینت به‌همراه QR کد.

- Flask-based web panel for client management.  
  پنل تحت وب ساخته‌شده با Flask برای مدیریت کاربران.

- Daily GitHub repository synchronization.  
  هماهنگی روزانه با مخزن گیت‌هاب.

---

## 📋 Prerequisites | پیش‌نیازها

- Ubuntu 22.04  
  اوبونتو نسخه 22.04

- Root or sudo access  
  دسترسی روت یا sudo

- Public IP and internet connection  
  آی‌پی عمومی و اتصال به اینترنت

---

## ⚙️ Installation | نصب

1. Download and run the setup script:  
   اسکریپت نصب را دانلود و اجرا کنید:
```bash
sudo apt update
wget https://raw.githubusercontent.com/Hamedunn/PEASY-WG/main/setup.sh
chmod +x setup.sh
./setup.sh
