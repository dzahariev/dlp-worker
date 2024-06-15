#! /bin/bash
TASKS_LOCATION="/tasks"
OUTPUT_LOCATION="/output"
TASKS_KIND="download"

get_next_task(){
    local tasksfolder=${1}
    local taskskind=${2}

    for filenamewithpath in "${tasksfolder}"/*; do
        filename="$(basename "$filenamewithpath")"
        extension="${filename##*.}"
        if  [[ "${extension}" == "json" ]]; then
            taskkind=$(cat ${filenamewithpath} | jq -r .kind)
            taskstatus=$(cat ${filenamewithpath} | jq -r .status)
            if  [[ "${taskkind}" == "${taskskind}" ]]; then
                if  [[ ! "${taskstatus}" == "done" ]]; then
                    echo "${filenamewithpath}"
                fi
            fi
        fi
    done
}

is_valid_json(){
    [[ $(echo ${1} | jq -e . &>/dev/null; echo $?) -eq 0 ]] && echo "true" || echo "false"
}

get_conversion_status(){
    local reportjson=${1}

    state="$(echo ${reportjson} | jq -r '.status')"
    if  [[ $state == "finished" ]]; then
        echo "done"
    else 
        if  [[ $state == "downloading" ]]; then
            echo "working"
        else
            echo "unknown"
        fi
    fi
}

get_conversion_progress(){
    local reportjson=${1}

    state="$(echo ${reportjson} | jq -r '.status')"
    if  [[ $state == "finished" ]]; then
        echo "100"
    else 
        if  [[ $state == "downloading" ]]; then
            downloaded_bytes=$(echo ${1} | jq -r .downloaded_bytes)
            total_bytes=$(echo ${1} | jq -r .total_bytes)
            progressfloat=$(echo "${downloaded_bytes}/${total_bytes}" | bc -l | xargs printf "%.2f")
            progressprcfloat=$( bc -l <<<"100*${progressfloat}" )
            progress_int=$(echo ${progressprcfloat} | bc -l | xargs printf "%.0f")
            echo "$progress_int"
        else
            echo "0"
        fi
    fi
}

update_task(){
    local taskfilename=${1}
    local taskstatus=${2}
    local taskprogress=${3}

    taskjson=$(cat ${taskfilename}) 
    taskjsonupdstatus=$(echo -E $taskjson | jq --arg vstatus $taskstatus '.status = $vstatus') 
    taskjsonupd=$(echo -E $taskjsonupdstatus | jq --arg vprogress $taskprogress '.progress = $vprogress') 
    echo -E "$taskjsonupd" > $taskfilename
}

process_exists(){
    pgrep -x ${1} >/dev/null && echo "true" || echo "false"
}

monitor_task(){
    local taskfilename=${1}
    local logfilename=${2}

    sleep 10 
    progressing=true
    while $progressing 
    do
        str=$(tail -1 $logfilename)
        lastreport=""
        flatline=$(echo -n $str | yq -oj eval)
        valid=$(is_valid_json  "$flatline")
        if  [[ "$valid" == "true" ]]; then
            lastreport=$flatline
        fi

        handbrakeprocessexists=$(process_exists "yt-dlp")
        conversionstatus=$(get_conversion_status "$lastreport")
        conversionprogress=$(get_conversion_progress "$lastreport")

        if  [[ $conversionstatus == "done" ]]; then
            update_task $taskfilename $conversionstatus $conversionprogress 
            rm -f $logfilename
            progressing=false
        else
            if  [[ $conversionstatus == "working" ]]; then
                update_task $taskfilename $conversionstatus $conversionprogress 
            else
                echo "Unknow: $lastreport"
            fi
        fi

        if  [[ $handbrakeprocessexists == "true" ]]; then
            echo "Process yt-dlp is started. Continue monitoring of the task."
        else
            echo "Process yt-dlp is not started. Stoping monitoring of the task."
            rm -f $logfilename
            progressing=false
        fi
        sleep 10 
    done
}

echo "Starting to watch the folder with tasks: $TASKS_LOCATION"

while true
do
    read -r TASK_TO_PROCESS <<< "$( get_next_task $TASKS_LOCATION $TASKS_KIND )"

    if [ -e "$TASK_TO_PROCESS" ]; then
        ID=$(cat $TASK_TO_PROCESS | jq -r .id)
        SOURCE=$(cat $TASK_TO_PROCESS | jq -r .source)
        PRESET=$(cat $TASK_TO_PROCESS | jq -r .preset)
        AUDIO_QUALITY=""
        VIDEO_QUALITY=""

        case $PRESET in

        MP3128)
            AUDIO_QUALITY="128K"
            ;;

        MP3192)
            AUDIO_QUALITY="192K"
            ;;

        MP3320)
            AUDIO_QUALITY="320K"
            ;;

        MP4480P)
            VIDEO_QUALITY="480"
            ;;

        MP4720P)
            VIDEO_QUALITY="720"
            ;;

        esac

        echo "Converting $SOURCE using preset $PRESET ..."
        yt-dlp --restrict-filenames -P $OUTPUT_LOCATION --newline --progress-template "download:%(progress)s" $SOURCE ${AUDIO_QUALITY:+"--extract-audio --audio-format mp3 --audio-quality $AUDIO_QUALITY"} ${VIDEO_QUALITY:+"-S res:$VIDEO_QUALITY,codec,br,ext:mp4"}  > ${ID}_enc.log &
        monitor_task $TASK_TO_PROCESS ${ID}_enc.log &
        wait
    else
        echo "There is no task for conversion in queue. Sleeping ..."
    fi

    sleep 10
done