ARG BASE
FROM $BASE

# Install marmot
RUN curl -sL https://github.com/maxpert/marmot/releases/download/v0.8.6/marmot-v0.8.6-linux-amd64-static.tar.gz | tar -zxv marmot -C /usr/local/bin

# Install sqlite
RUN apt update && apt install -y sqlite3
