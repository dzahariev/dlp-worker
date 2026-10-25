FROM ubuntu:24.04
RUN apt-get update 
RUN apt install ffmpeg curl yq jq procps bc -y

# Install latest yt-dlp release binary directly (apt/PPA versions lag behind upstream releases)
RUN curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp \
    && chmod a+rx /usr/local/bin/yt-dlp

VOLUME [ "/tasks", "/output"]
RUN mkdir app

COPY ./process.sh /app/process.sh
RUN chmod +x /app/process.sh

ENTRYPOINT [ "/app/process.sh" ]
