FROM mcr.microsoft.com/mssql/server:2022-latest
USER root
WORKDIR /init
COPY sql /init/sql
COPY docker/db-init/init.sh /init/init.sh
RUN chmod +x /init/init.sh
ENTRYPOINT ["/init/init.sh"]
