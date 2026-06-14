#!/bin/sh

# Note: Arguments to this script
#  1: string - S3 bucket for your backup save files (required)
#  2: true|false - whether to use Satisfactory Experimental build (optional, default false)
S3_SAVE_BUCKET=$1
USE_EXPERIMENTAL_BUILD=${2-false}

# install steamcmd dependencies
# lib32gcc-s1 is the new name for lib32gcc1 on Ubuntu 22.04+
add-apt-repository multiverse -y
dpkg --add-architecture i386
apt-get update

# Needed to accept steam license without hangup
echo steam steam/question 'select' "I AGREE" | debconf-set-selections
echo steam steam/license note '' | debconf-set-selections

apt-get install -y unzip lib32gcc-s1 steamcmd

# install satisfactory: https://satisfactory.wiki.gg/wiki/Dedicated_servers
if [ "$USE_EXPERIMENTAL_BUILD" = "true" ]; then
    STEAM_INSTALL_SCRIPT="/usr/games/steamcmd +login anonymous +app_update 1690800 -beta experimental validate +quit"
else
    STEAM_INSTALL_SCRIPT="/usr/games/steamcmd +login anonymous +app_update 1690800 validate +quit"
fi

SATISFACTORY_PATH="/home/ubuntu/Steam/steamapps/common/SatisfactoryDedicatedServer"

# note, we are switching users because steam doesn't recommend running steamcmd as root
su - ubuntu -c "$STEAM_INSTALL_SCRIPT"

# enable as server so it stays up and start: https://satisfactory.wiki.gg/wiki/Dedicated_servers/Running_as_a_Service
cat << EOF > /etc/systemd/system/satisfactory.service
[Unit]
Description=Satisfactory dedicated server
Wants=network-online.target
After=syslog.target network.target nss-lookup.target network-online.target

[Service]
Environment="LD_LIBRARY_PATH=./linux64"
ExecStartPre=$STEAM_INSTALL_SCRIPT
ExecStart=$SATISFACTORY_PATH/FactoryServer.sh
User=ubuntu
Group=ubuntu
StandardOutput=journal
Restart=on-failure
KillSignal=SIGINT
WorkingDirectory=$SATISFACTORY_PATH

[Install]
WantedBy=multi-user.target
EOF
systemctl enable satisfactory
systemctl start satisfactory

# enable auto shutdown
cat << 'EOF' > /home/ubuntu/auto-shutdown.sh
#!/bin/sh

shutdownIdleMinutes=30
idleCheckFrequencySeconds=1

isIdle=0
while [ $isIdle -le 0 ]; do
    isIdle=1
    iterations=$((60 / $idleCheckFrequencySeconds * $shutdownIdleMinutes))
    while [ $iterations -gt 0 ]; do
        sleep $idleCheckFrequencySeconds
        connectionBytes=$(ss -lu | grep 777 | awk -F ' ' '{s+=$2} END {print s}')
        if [ ! -z $connectionBytes ] && [ $connectionBytes -gt 0 ]; then
            isIdle=0
        fi
        if [ $isIdle -le 0 ] && [ $(($iterations % 21)) -eq 0 ]; then
           echo "Activity detected, resetting shutdown timer to $shutdownIdleMinutes minutes."
           break
        fi
        iterations=$(($iterations-1))
    done
done

echo "No activity detected for $shutdownIdleMinutes minutes, shutting down."
sudo shutdown -h now
EOF
chmod +x /home/ubuntu/auto-shutdown.sh
chown ubuntu:ubuntu /home/ubuntu/auto-shutdown.sh

cat << 'EOF' > /etc/systemd/system/auto-shutdown.service
[Unit]
Description=Auto shutdown if no one is playing Satisfactory
After=syslog.target network.target nss-lookup.target network-online.target

[Service]
ExecStart=/home/ubuntu/auto-shutdown.sh
User=ubuntu
Group=ubuntu
StandardOutput=journal
Restart=on-failure
KillSignal=SIGINT
WorkingDirectory=/home/ubuntu

[Install]
WantedBy=multi-user.target
EOF
systemctl enable auto-shutdown
systemctl start auto-shutdown

# restore saves from S3 before first boot
SAVE_PATH="/home/ubuntu/Steam/steamapps/common/SatisfactoryDedicatedServer/FactoryGame/Saved/SaveGames/server"
mkdir -p "$SAVE_PATH"
chown -R ubuntu:ubuntu /home/ubuntu/.config
/usr/local/bin/aws s3 sync "s3://$S3_SAVE_BUCKET/server" "$SAVE_PATH"

# automated backups to s3 every 5 minutes
su - ubuntu -c "(crontab -l 2>/dev/null; echo \"*/5 * * * * /usr/local/bin/aws s3 sync $SAVE_PATH s3://$S3_SAVE_BUCKET/server\") | crontab -"
