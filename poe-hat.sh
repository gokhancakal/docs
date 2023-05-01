#!/bin/bash

# Install required packages I
apt update 
apt install -y python3-pip python3-venv python3-pil libatlas-base-dev raspi-config unzip

IS_I2C=`sudo raspi-config nonint get_i2c 1`
[ $IS_I2C -ne 0 ]&&sudo raspi-config nonint do_i2c 0

# create and activate venv 
[ -d /opt/python_base ] && rm -rf /opt/python_base
python3 -m venv /opt/python_base
source /opt/python_base/bin/activate

# Install required packages II
pip install RPi.GPIO smbus numpy pillow

# Cleanout artifacts if necesary
[ -d ~/PoE_HAT_B_code ] && rm -rf ~/PoE_HAT_B_code
[ -f ~/PoE_HAT_B_code.7z ] && rm -rf ~/PoE_HAT_B_code.7z

# Install Waveshare libraries and examples
wget https://www.waveshare.com/w/upload/8/8b/PoE_HAT_B_code.zip
unzip -o  PoE_HAT_B_code.zip -d .

# Move required parts to poe-hat directory
[ -d /opt/poe-hat ] && rm -rf /opt/poe-hat
mkdir -p /opt/poe-hat
chmod 777 -R /opt/poe-hat
mv PoE_HAT_B_code/python/examples/main.py /opt/poe-hat/
mv PoE_HAT_B_code/python/lib/waveshare_POE_HAT_B /opt/poe-hat/
mv PoE_HAT_B_code/python/readme_EN.txt /opt/poe-hat/PoE_HAT_B_readme.txt

# Cleanup
rm PoE_HAT_B_code.zip
rm -rf PoE_HAT_B_code
rm -f $0

# Create/Activate service
[ -d /etc/systemd/system/poe-hat.service ] && rm -rf /etc/systemd/system/poe-hat.service

PYTHON=`which python3 |head -n1`
cat <<EOF >poe-hat.service
[Unit]
Description=Poe Hat B
After=network.target
[Service]
Environment=systemd=true
ExecStart=${PYTHON} /opt/poe-hat/main.py
Restart=always
RestartSec=30
[Install]
WantedBy=multi-user.target
EOF

mv -f poe-hat.service /etc/systemd/system

systemctl daemon-reload
systemctl enable poe-hat.service --now
systemctl status poe-hat.service
