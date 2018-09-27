FROM ubuntu:latest

# Install cron
RUN apt-get update && apt-get -y install cron

COPY cronjobs.sh /usr/local/bin/cronjobs.sh

# Create the log file to be able to run tail
RUN touch /var/log/cron.log

# Setup cron job to run every minute
RUN (crontab -l ; echo "*/1 * * * * /usr/local/bin/cronjobs.sh") | crontab

# Run the command on container startup
CMD cron && tail -f /var/log/cron.log
