FROM ubuntu:24.04
RUN apt-get update 
RUN apt install software-properties-common ffmpeg curl yq jq procps bc -y

RUN add-apt-repository ppa:tomtomtom/yt-dlp
RUN apt-get update 
RUN apt install yt-dlp -y

VOLUME [ "/tasks", "/output"]
RUN mkdir app

COPY ./process.sh /app/process.sh
RUN chmod +x /app/process.sh

ENTRYPOINT [ "/app/process.sh" ]
