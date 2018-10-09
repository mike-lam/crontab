FROM docker:latest
RUN apk add --no-cache bash

COPY cronjobs.sh /usr/local/bin/cronjobs.sh

# Create the log file to be able to run tail
RUN touch /var/log/cron.log

# Run the command on container startup
CMD ["/usr/local/bin/cronjobs.sh"]
