ARG BASE
FROM $BASE

# Install marmot
RUN mkdir -p /opt/spectrocloud/bin && \
    curl -sL https://github.com/maxpert/marmot/releases/download/v0.8.6/marmot-v0.8.6-linux-amd64-static.tar.gz | tar -zxv marmot && \
    install marmot -o root -g root -m 755 /opt/spectrocloud/bin/ && \
    rm -f marmot

# Install sqlite
RUN apt update && apt install -y sqlite3 less
