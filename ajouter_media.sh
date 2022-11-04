#!/bin/bash
########################################################################
# Author: Fred (support@qo-op.com)
# Version: 1.0
# License: AGPL-3.0 (https://choosealicense.com/licenses/agpl-3.0/)
########################################################################
# SCRIPT INTERACTIF POUR AJOUTER UN FICHIER à ASTROPORT/TW
#
# 1. CAT: film, serie
# 2. TMDB: ID de la fiche sur https://www.themoviedb.org/
# 3. TITLE:  Titre de la vidéo
# 4. YEAR: Année de la vidéo
# 5. RES: Résolution 1080p, 4K, SD, 720, HD
# 6. SAISON: Pour les séries, c'est le numéro de saison.
# Pour un film, le champ SAISON est utilisé pour renseigner la Saga
# 7. GENRES: Action, Aventure, Fantastique, Animation, etc (choix multiple).
# 8. GROUPES: Stocker la clef IPNS du MEDIAKEY.
#
# https://github.com/Kodi-vStream/venom-xbmc-addons/wiki/Voir-et-partager-sa-biblioth%C3%A8que-priv%C3%A9e#d%C3%A9clarer-des-films
########################################################################
MY_PATH="`dirname \"$0\"`"              # relative
MY_PATH="`( cd \"$MY_PATH\" && pwd )`"  # absolutized and normalized
ME="${0##*/}"

########################################################################
[[ $(which ipfs) == "" ]] && echo "ERREUR! Installez ipfs" && echo "wget https://git.p2p.legal/axiom-team/astrXbian/raw/master/.install/ipfs_alone.sh -O /tmp/ipfs_install.sh && chmod +x /tmp/ipfs_install.sh && /tmp/ipfs_install.sh" && exit 1
[[ $(which zenity) == "" ]] && echo "ERREUR! Installez zenity" && echo "sudo apt install zenity" && exit 1
[[ $(which ffmpeg) == "" ]] && echo "ERREUR! Installez ffmpeg" && echo "sudo apt install ffmpeg" && exit 1
[[ $(which xdpyinfo) == "" ]] && echo "ERREUR! Installez x11-utils" && echo "sudo apt install x11-utils" && exit 1

# Check who is .current PLAYER
PLAYER=$(cat ~/.zen/game/players/.current/.player 2>/dev/null)
[[ $PLAYER == "" ]] && espeak "ERROR CONNECT YOUR PLAYER - EXIT" && exit 1
PSEUDO=$(cat ~/.zen/game/players/.current/.pseudo 2>/dev/null)
G1PUB=$(cat ~/.zen/game/players/.current/.g1pub 2>/dev/null)
[[ $G1PUB == "" ]] && espeak "ERROR NO G1 PUBLIC KEY FOUND - EXIT" && exit 1

PLAYERNS=$(cat ~/.zen/game/players/.current/.playerns 2>/dev/null) || ( echo "noplayerns" && exit 1 )

ASTRONAUTENS=$(ipfs key list -l | grep -w "${PLAYER}" | cut -d ' ' -f 1)
[[ $ASTRONAUTENS == "" ]] && echo "ASTRONAUTE manquant" && espeak "Astronaut Key Missing" && exit 1

MOATS=$(date -u +"%Y%m%d%H%M%S%4N")
IPFSNODEID=$(cat ~/.ipfs/config | jq -r .Identity.PeerID)
myIP=$(hostname -I | awk '{print $1}' | head -n 1)

URL="$1"
if [ $URL ]; then
    echo "URL: $URL"
    REVSOURCE="$(echo "$URL" | awk -F/ '{print $3}' | rev)_"
    [ ! $2 ] && IMPORT=$(zenity --entry --width 640 --title="$URL => Astroport" --text="Quel type de media voulez vous copier ?" --entry-text="Video" Page MP3 Web)
    [[ $IMPORT == "" ]] && espeak "No choice made. Exiting program" && exit 1
    [[ $IMPORT == "Video" ]] && IMPORT="Youtube"
    CHOICE="$IMPORT"
fi

# REMOVE GtkDialog errors for zenity
shopt -s expand_aliases
alias zenity='zenity 2> >(grep -v GtkDialog >&2)'

# GET SCREEN DIMENSIONS
screen=$(xdpyinfo | grep dimensions | sed -r 's/^[^0-9]*([0-9]+x[0-9]+).*$/\1/')
width=$(echo $screen | cut -d 'x' -f 1)
height=$(echo $screen | cut -d 'x' -f 2)
large=$((width-300))
haut=$((height-200))

########################################################################
## CADRE EXCEPTION COPIE PRIVE
# https://www.legifrance.gouv.fr/codes/article_lc/LEGIARTI000006278917/2008-12-11/
if [[ ! -f ~/.zen/game/players/.current/legal ]]; then
zenity --width ${large} --height=${haut} --text-info \
       --title="Action conforme avec le Code de la propriété intellectuelle" \
       --html \
       --url="https://fr.wikipedia.org/wiki/Droit_d%27auteur_en_France#Les_exceptions_au_droit_d%E2%80%99auteur" \
       --checkbox="J'ai lu et j'accepte les termes."

case $? in
    0)
        echo "AUTORISATION COPIE PRIVE ASTROPORT OK !"
        echo "$G1PUB" > ~/.zen/game/players/.current/legal
    # next step
    ;;
    1)
        echo "Refus conditions"
        rm -f ~/.zen/game/players/.current/legal
        exit 1
    ;;
    -1)
        echo "Erreur."
        exit 1
    ;;
esac
fi

## DES/ACTIVATION ASTROPORT
if [[ $1 == "on" ]]; then
    STRAP=$(ipfs bootstrap)
    BOOT=$(zenity --entry --width 300 --title="Catégorie" --text="$STRAP Changez de Bootstrap" --entry-text="Aucun" astrXbian Public)
    [[ $BOOT == "Aucun" ]] && ipfs bootstrap rm --all
    [[ $BOOT == "astrXbian" ]] && for bootnode in $(cat ~/.zen/astrXbian/A_boostrap_nodes.txt | grep -Ev "#"); do ipfs bootstrap add $bootnode; done
    [[ $BOOT == "Public" ]] && for bootnode in $(cat ~/.zen/astrXbian/A_boostrap_public.txt | grep -Ev "#"); do ipfs bootstrap add $bootnode; done
    REP=$(~/.zen/Astroport.ONE/tools/cron_VRFY.sh ON) && zenity --warning --width 600 --text "$REP"
fi

## CHECK IF ASTROPORT/CRON/IPFS IS RUNNING
YOU=$(ps auxf --sort=+utime | grep -w ipfs | grep -v -E 'color=auto|grep' | tail -n 1 | cut -d " " -f 1)
[[ ! $YOU ]] &&  espeak "I P F S not running - EXIT" && exit 1

########################################################################
# CHOOSE CATEGORY (remove anime, not working!)
[[ $CHOICE == "" ]] && CHOICE=$(zenity --entry --width 300 --title="Catégorie" --text="Choisissez la catégorie de votre media" --entry-text="Vlog" Film Serie Youtube Video)
[[ $CHOICE == "" ]] && exit 1

# LOWER CARACTERS
CAT=$(echo "${CHOICE}" | awk '{print tolower($0)}')
# UPPER CARACTERS
CHOICE=$(echo "${CAT}" | awk '{print toupper($0)}')

PREFIX=$(echo "${CAT}" | head -c 1 | awk '{ print toupper($0) }' ) # ex: F, S, A, Y, M ... P W
[[ $PREFIX == "" ]] && exit 1

########################################################################
########################################################################
case ${CAT} in
########################################################################
# CASE ## ASTRONAUTE
#                  _                                             _
#   __ _ ___| |_ _ __ ___  _ __   __ _ _   _| |_ ___
#  / _` / __| __| '__/ _ \| '_ \ / _` | | | | __/ _ \
# | (_| \__ \ |_| | | (_) | | | | (_| | |_| | ||  __/
#  \__,_|___/\__|_|  \___/|_| |_|\__,_|\__,_|\__\___|
#
#
########################################################################
    vlog)

    espeak "vlog is video blogging"

    zenity --warning --width 300 --text "$PLAYER. Prêt à enregistrer votre video ?"

    ## RECORD WEBCAM VIDEO
    ~/.zen/Astroport.ONE/tools/vlc_webcam.sh


    exit 0
    ;;
########################################################################
# CASE ## YOUTUBE
#                   _         _
# _   _  ___  _   _| |_ _   _| |__   ___
#| | | |/ _ \| | | | __| | | | '_ \ / _ \
#| |_| | (_) | |_| | |_| |_| | |_) |  __/
# \__, |\___/ \__,_|\__|\__,_|_.__/ \___|
# |___/
########################################################################
    youtube)

    espeak "youtube : video copying"

YTURL="$URL"
[[ $YTURL == "" ]] && YTURL=$(zenity --entry --width 300 --title "Lien ou identifiant à copier" --text "Indiquez le lien (URL) ou l'ID de la vidéo" --entry-text="")
[[ $YTURL == "" ]] && exit 1

REVSOURCE="$(echo "$YTURL" | awk -F/ '{print $3}' | rev)_"

# Create TEMP directory to copy $YID_$TITLE.$FILE_EXT
YTEMP="$HOME/.zen/tmp/$(date -u +%s%N | cut -b1-13)"
mkdir -p ${YTEMP}

# youtube-dl $YTURL
echo "VIDEO $YTURL"

/usr/local/bin/youtube-dl -f '[ext=mp4]+best[height<=480]+[filesize<300M]' \
--no-playlist --write-info-json \
--no-mtime -o "${YTEMP}/%(id)s&%(title)s.%(ext)s" $YTURL

# Get filename, extract ID, make destination dir and move copy.
YFILE=$(ls -S ${YTEMP} | head -n 1)
FILE_NAME="$(basename "${YFILE}")"
FILE_EXT="${FILE_NAME##*.}"

JSON_FILE=$(echo ${FILE_NAME} | sed "s/${FILE_EXT}/json/g")

YID=$(echo "${FILE_NAME}" | cut -d "&" -f 1)
YNAME=$(echo "${FILE_NAME}" | cut -d "&" -f 2- | sed "s/[(][^)]*[)]//g" | sed -e 's/[^A-Za-z0-9._-]/_/g' | sed -e 's/__/_/g' ) # Remove YoutubeID_ and (what is in perentheses)
[[ $(which detox) ]] && YNAME=$(echo "${FILE_NAME}" | cut -d "&" -f 2- | detox --inline)
MEDIAID="$REVSOURCE${YID}"
TITLE="${YNAME%.*}"
MEDIAKEY="YOUTUBE_${MEDIAID}"
## CORRECT PARAMETERS to Make Kodi compatible YASTRXBIAN FILE

[ ! $2 ] && GENRES=$(zenity --list --checklist --title="GENRE" --height=${haut} \
    --text="Choisissez le(s) genre(s) d'information(s) contenue(s) dans cette vidéo \"${TITLE}\" publiée sur OASIS" \
    --column="Use" \
    --column="Feature" \
    FALSE Savoir \
    FALSE Nature \
    FALSE Habiter \
    FALSE Nourrir \
    FALSE Deplacer \
    FALSE Guerir \
    FALSE Divertir \
    FALSE Musique \
    FALSE DIY \
    FALSE Science \
    FALSE Humain \
    FALSE Animal \
    TRUE Eveil \
    TRUE ${PLAYER// /-}) || GENRES="${PLAYER// /-}"

# FORMAT GENRES genre1|genre2|genre3

FILE_PATH="$HOME/astroport/youtube/$MEDIAID"
mkdir -p ${FILE_PATH} && mv -f ${YTEMP}/* ${FILE_PATH}/
# rename FILE_NAME to YNAME (URL clean)
mv "${FILE_PATH}/${FILE_NAME}" "${FILE_PATH}/${YNAME}" && FILE_NAME="${YNAME}"
# get & rename video.json
jsonfile=$(ls ${FILE_PATH}/*.json)
mv "${jsonfile}" "${FILE_PATH}/video.json"

FILE_RES=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "${FILE_PATH}/${FILE_NAME}" | cut -d "x" -f 2)
RES=${FILE_RES%?}0p

## CREATE "~/astroport/${CAT}/${MEDIAID}/ajouter_video.txt" and video.json
URLENCODE_FILE_NAME=$(echo ${FILE_NAME} | jq -Rr @uri)

## KEEPS KODI COMPATIBILITY (BROKEN astroport.py !! ) : TODO DEBUG
echo "youtube;${MEDIAID};$(date -u +%s%N | cut -b1-13);${TITLE};${SAISON};${GENRES};_IPNSKEY_;${RES};/ipfs/_IPFSREPFILEID_/$URLENCODE_FILE_NAME" > ~/astroport/${CAT}/${MEDIAID}/ajouter_video.txt

# _IPFSREPFILEID_ is replaced later

rm -Rf ${YTEMP}

    ;;

########################################################################
# CASE ## WEB
    web)

        espeak "web : clone web site. Please help debugging"

    ## wget current URL -> index.html ## TEST ## TEST httrack ??
        [[ ! $(which httrack) ]] && espeak "Plase install httrack software - EXIT" && \
                                                zenity --warning --width ${large} --text "Utilitaire de copie de site web absent.. Lancez la commande 'sudo apt install httrack'" && \
                                                exit 1

        echo "httrack --mirror $URL" # TODO : FOR NOW NOT WORKING
        FILE_NAME="index.html"
        REVSOURCE="$(echo "$URL" | rev | sha256sum | cut -d ' ' -f 1)_"; echo $REVSOURCE # URL="https://discuss.ipfs.io/t/limit-ipfs-get-command/3573/6"
        MEDIAID="$REVSOURCE" # MEDIAID=1252ff59950395070a0cc56bb058cbb1ccfd2f8d8a32476acaf472f62b14d97d_
        MEDIAKEY="WWW_${MEDIAID}" # MEDIAKEY=PAGE_1252ff59950395070a0cc56bb058cbb1ccfd2f8d8a32476acaf472f62b14d97d_
        FILE_PATH="$HOME/astroport/web/$MEDIAID";
        mkdir -p $FILE_PATH

        wget -mpck --user-agent="" -e robots=off --wait 1 "$URL" > ${FILE_PATH}/

        echo "web;${MEDIAID};$(date -u +%s%N | cut -b1-13);${TITLE};${SAISON};${GENRES};_IPNSKEY_;${RES};/ipfs/_IPFSREPFILEID_/$FILE_NAME" > ~/astroport/${CAT}/${MEDIAID}/ajouter_video.txt

        zenity --warning --width ${large} --text "Vérifiez que la copie de votre site se trouve bien dans ${FILE_PATH}/"

    ;;


########################################################################
# CASE ## PAGE
    page)

        espeak "page : convert into portable digital document"

    ## record one page to PDF
        [[ ! $(which chromium) ]] &&  zenity --warning --width ${large} --text "Utilitaire de copie de page web absent.. Lancez la commande 'sudo apt install chromium'" && exit 1
        cd /tmp/ && rm -f output.pdf
        chromium --headless --no-sandbox --print-to-pdf $URL

        TITLE=$(zenity --entry --width 480 --title "Titre" --text "Quel nom de fichier à donner à cette page ? " --entry-text="${URL}")
        [[ $TITLE == "" ]] && exit 1
        FILE_NAME="$(echo "${TITLE}" | detox --inline).pdf" ## TODO make it better

        MEDIAID="$REVSOURCE$(echo "${TITLE}" | detox --inline)"
        MEDIAKEY="PAGE_${MEDIAID}"
        FILE_PATH="$HOME/astroport/page/$MEDIAID"
        mkdir -p ${FILE_PATH} && mv output.pdf ${FILE_PATH}/${FILE_NAME}

        echo "page;${MEDIAID};$(date -u +%s%N | cut -b1-13);${TITLE};${SAISON};${GENRES};_IPNSKEY_;${RES};/ipfs/_IPFSREPFILEID_/$FILE_NAME" > ~/astroport/${CAT}/${MEDIAID}/ajouter_video.txt

    ;;

########################################################################
# CASE ## MP3
#                _____
# _ __ ___  _ __|___ /
#| '_ ` _ \| '_ \ |_ \
#| | | | | | |_) |__) |
#|_| |_| |_| .__/____/
#          |_|
########################################################################
    mp3)

        espeak "mp3 is music copying. Please help..."

zenity --warning --width 600 --text 'DEVELOPPER ZONE ONLY - https://git.p2p.legal'
exit 0

# Create TEMP directory
YTEMP="$HOME/.zen/tmp/$(date -u +%s%N | cut -b1-13)"
mkdir -p ${YTEMP}

artist=$(zenity --entry --width 400 --title "Extraction MP3 depuis Youtube" --text "Artiste recherché ou Lien Youtube" --entry-text="")
[[ $artist == "" ]] && exit 1

## CHECK if artist is LINK or ID
length=${#artist}
islink=$(echo "$artist" | grep "http")
if [[ ! $islink && $length != 11 ]]
then
    # Ask for song name
    song=$(zenity --entry --width 300 --title "Titre à chercher sur Youtube" --text "Titre recherché" --entry-text="")
    [[ $song == "" ]] && exit 1
else
    song=$(zenity --entry --width 300 --title "Confirmer ID" --text "Titre recherché (ou confirmer la saisie précédente)" --entry-text="$artist")
    [[ "$song" == "$artist" ]] && song=""
fi

# Download mp3 from 1st youtube search video result (--write-info-json)
/usr/local/bin/youtube-dl --default-search ytsearch1: \
--ignore-errors --no-mtime \
--embed-thumbnail --metadata-from-title "%(artist)s - %(title)s" --add-metadata \
--extract-audio --audio-format mp3 -o "${YTEMP}/%(id)s&%(title)s.%(ext)s" "$artist $song"

ls ${YTEMP}
# Get filename, extract ID, make destination dir and move copy.
YFILE=$(ls -t ${YTEMP} | head -n 1)
FILE_NAME="$(basename "${YFILE}")"
FILE_EXT="${FILE_NAME##*.}"

YID=$(echo "${FILE_NAME}" | cut -d "&" -f 1)
YNAME=$(echo "${FILE_NAME}" | cut -d "&" -f 2- | sed "s/[(][^)]*[)]//g" | sed -e 's/[^A-Za-z0-9._-]/_/g' | sed -e 's/__/_/g') # Remove YoutubeID_ and (what is in perentheses)
[[ $(which detox) ]] && YNAME="$(echo "${FILE_NAME}" | cut -d "&" -f 2- | detox --inline)"

[[ ! $islink && "$song" != "" ]] && FILE_PATH="$HOME/astroport/$CAT/$artist/_o-o_" \
|| FILE_PATH="$HOME/astroport/$CAT/${YID}"

mkdir -p "${FILE_PATH}" && mv -f ${YTEMP}/* "${FILE_PATH}/"
# Remove "&" from FILE_NAME rename to YNAME
mv "${FILE_PATH}/${FILE_NAME}" "${FILE_PATH}/${YNAME}" && FILE_NAME="${YNAME}"

MEDIAID="${YID}"
TITLE="${YNAME%.*}"
GENRES="[\"$PLAYER\"]"
GROUPES="_IPNSKEY_" # USE GROUPS TO  RECORD IPNS MEDIAKEY
MEDIAKEY="MP3_$MEDIAID"

rm -Rf ${YTEMP}
# zenity --warning --width ${large} --text "MP3 copié"
echo "~/.zen/Astroport.ONE/tools/new_mp3_in_astroport.sh \"${FILE_PATH}/\" \"${FILE_NAME}\""
~/.zen/Astroport.ONE/tools/new_mp3_in_astroport.sh "${FILE_PATH}/" "${FILE_NAME}" > /tmp/${CHOICE}_${MEDIAID}.log 2>&1

cat /tmp/${CHOICE}_${MEDIAID}.log

exit 0

    ;;

########################################################################
#   __ _ _
# / _(_) |_ __ ___
#| |_| | | '_ ` _ \
#|  _| | | | | | | |
#|_| |_|_|_| |_| |_| THE MOVIE DATABASE INDEX
#
########################################################################
    film | serie)

    espeak "thank you for sharing your best movies"

# SELECT FILE TO ADD TO ASTROPORT/KODI
FILE=$(zenity --file-selection --title="Sélectionner le fichier à ajouter")
echo "${FILE}"
[[ $FILE == "" ]] && exit 1

# Remove file extension to get file name => STITLE
FILE_PATH="$(dirname "${FILE}")"
FILE_NAME="$(basename "${FILE}")"
FILE_EXT="${FILE_NAME##*.}"
FILE_TITLE="${FILE_NAME%.*}"

# OPEN default browser and search TMDB
zenity --question --width 300 --text "Ouvrir https://www.themoviedb.org pou récupérer le numéro d'identification de $(echo ${FILE_TITLE} | sed 's/_/%20/g') ?"
[ $? == 0 ] && xdg-open "https://www.themoviedb.org/search?query=$(echo ${FILE_TITLE} | sed 's/_/%20/g')"

MEDIAID=$(zenity --entry --title="Identification TMDB" --text="Copiez le nom de la page du film. Ex: 301528-toy-story-4 pour une adresse https://www.themoviedb.org/movie/301528-toy-story-4)" --entry-text="")
[[ $MEDIAID == "" ]] && exit 1
CMED=$(echo $MEDIAID | cut -d '-' -f 1)
TMTL=$(echo $MEDIAID | cut -d '-' -f 2-) # contient la fin du nom de fichier tmdb (peut servir?)

if ! [[ "$CMED" =~ ^[0-9]+$ ]]
then
        zenity --warning --width ${large} --text "Vous devez renseigner un numéro! Merci de recommencer... Seules les vidéos référencées sur The Movie Database sont acceptées." && exit 1
fi
MEDIAID=$CMED
MEDIAKEY="TMDB_$MEDIAID"

# VIDEO TITLE
TITLE=$(zenity --entry --width 300 --title "Titre" --text "Indiquez le titre de la vidéo" --entry-text="${FILE_TITLE}")
[[ $TITLE == "" ]] && exit 1
TITLE=$(echo "${TITLE}" | sed "s/[(][^)]*[)]//g" | sed -e 's/;/_/g' ) # Clean TITLE (NO ;)

# VIDEO YEAR
YEAR=$(zenity --entry --width 300 --title "Année" --text "Indiquez année de la vidéo. Exemple: 1985" --entry-text="")

# VIDEO RESOLUTION
FILE_RES=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "${FILE}" | cut -d "x" -f 2)
RES=${FILE_RES%?}0p # Rounding. Replace last digit with 0
#RES=$(zenity --entry --width 300 --title="Résolution" --text="Résolution de la vidéo" --entry-text="${FILE_RES}" SD HD 4K 360p 480p 720p 1080p)

# VIDEO SEASON or SAGA
[[ "${CAT}" == "serie" ]] && SAISON=$(zenity --entry --width 300 --title "${CHOICE} Saison" --text "Indiquez SAISON et EPISODE. Exemple: S02E05" --entry-text="")
[[ "${CAT}" == "film" ]] && SAISON=$(zenity --entry --width 300 --title "${CHOICE} Saga" --text "Indiquez une SAGA (optionnel). Exemple: James Bond" --entry-text="")

# VIDEO GENRES
FILM_GENRES=$(zenity --list --checklist --title="GENRE" --height=${haut}\
    --text="Choisissez le(s) genre(s) de la vidéo \"${TITLE}\""\
    --column="Use"\
    --column="Feature"\
    FALSE '+18'\
    FALSE Action\
    FALSE Animation\
    FALSE 'Arts martiaux'\
    FALSE Aventure\
    FALSE Autre\
    FALSE Biographie\
    FALSE Biopic\
    FALSE Comedie\
    FALSE 'Comedie dramatique'\
    FALSE 'Comedie musicale'\
    FALSE Crime\
    FALSE Documentaire\
    FALSE Drame\
    FALSE Divers\
    FALSE Educatif\
    FALSE Enfant\
    FALSE 'Epouvante horreur'\
    FALSE Espionnage\
    FALSE Famille\
    FALSE Fantastique\
    FALSE Guerre\
    FALSE Histoire\
    FALSE Historique\
    FALSE Judiciaire\
    FALSE Opera\
    FALSE Medical\
    FALSE Musique\
    FALSE Mystere\
    FALSE Peplum\
    FALSE Policier\
    FALSE Romance\
    FALSE 'Science fiction'\
    FALSE Soap\
    FALSE Spectacle\
    FALSE Sport\
    FALSE Telefilm\
    FALSE Thriller\
    FALSE Western\
    TRUE ${PLAYER// /-})

# FORMAT GENRES ["genre1","genre2"] # USE  IF YOU ACTIVATE KODI COMPATIBILITY
GENRES="[\"$(echo ${FILM_GENRES} | sed s/\|/\",\"/g)\"]"

########################################################################
# Screen capture is used as thumbnail
########################################################################
if [[ $(echo $DISPLAY | cut -d ':' -f 1) == "" ]]; then
    zenity --warning --width 300 --text "Cliquez nous capturons votre écran comme vignette MEDIA"
    sleep 1
    import -window root /tmp/screen.png
fi

###################################
### MOVING FILE TO ~/astroport ####
###################################
mkdir -p ~/astroport/${CAT}/${MEDIAID}/
mv /tmp/screen.png ~/astroport/${CAT}/${MEDIAID}/screen.png

mv -f "${FILE_PATH}/${FILE_NAME}" "$HOME/astroport/${CAT}/${MEDIAID}/${TITLE}.${FILE_EXT}"

if [ $? == 0 ]; then
    zenity --warning --width ${large} --text "Votre fichier ~/astroport/${CAT}/${MEDIAID}/${TITLE}.${FILE_EXT} est prêt à embarquer. Cliquez sur OK, nous allons préparer son script d'ajout à Astroport..."
else
    zenity --warning --width ${large} --text "Impossible de déplacer votre fichier ${FILE_PATH}/${FILE_NAME} vers ~/astroport - EXIT -"
    exit 1
fi
FILE_NAME="${TITLE}.${FILE_EXT}"


## CREATE "~/astroport/${CAT}/${MEDIAID}/ajouter_video.txt"
URLENCODE_FILE_NAME=$(echo ${FILE_NAME} | jq -Rr @uri)
echo "${CAT};${MEDIAID};${YEAR};${TITLE};${SAISON};${GENRES};_IPNSKEY_;${RES};/ipfs/_IPFSREPFILEID_/$URLENCODE_FILE_NAME" > ~/astroport/${CAT}/${MEDIAID}/ajouter_video.txt
# _IPFSREPFILEID_ is replaced later

    ;;
#       _     _
#__   _(_) __| | ___  ___
#\ \ / / |/ _` |/ _ \/ _ \
# \ V /| | (_| |  __/ (_) |
#  \_/ |_|\__,_|\___|\___/
#                           TIMESTAMP INDEX

    video)

    espeak "Simply adds your personnal video in TW"

    zenity --warning --width 600 --text 'DEV ZONE - HELP US - REGISTER - https://git.p2p.legal'

    ## GENERAL MEDIAKEY for uploaded video. Title + Decription + hashtag + hashipfs
    # SELECT FILE TO ADD TO ASTROPORT/KODI
    FILE=$(zenity --file-selection --title="Sélectionner le fichier vidéo à ajouter")
    echo "${FILE}"
    [[ $FILE == "" ]] && exit 1

    # Remove file extension to get file name => STITLE
    FILE_PATH="$(dirname "${FILE}")"
    FILE_NAME="$(basename "${FILE}")"
    FILE_EXT="${FILE_NAME##*.}"
    FILE_TITLE="${FILE_NAME%.*}"
    # VIDEO TITLE
    TITLE=$(zenity --entry --width 300 --title "Titre" --text "Indiquez le titre de la vidéo" --entry-text="${FILE_TITLE}")
    [[ $TITLE == "" ]] && exit 1
    TITLE=$(echo "${TITLE}" | sed "s/[(][^)]*[)]//g" | sed -e 's/;/_/g' ) # Clean TITLE (NO ;)

    ## video_timestamp INDEX
    MEDIAID="$(date -u +%s%N | cut -b1-13)"
    mkdir -p ~/astroport/${CAT}/${MEDIAID}/
    MEDIAKEY="VIDEO_${MEDIAID}"

    ## CREATE SIMPLE JSON (REMOVE== it ?
    jq -n --arg ts "$MEDIAID" --arg title "$TITLE" --arg desc "$DESCRIPTION" --arg htag "$HASHTAG" '{"timestamp":$ts,"ipfs":"_IPFSREPFILEID_","ipns":"_IPNSKEY_","title":$title,"desc":$desc,"tag":$htag}' > ~/astroport/${CAT}/${MEDIAID}/video.json
    ## MOVE FILE TO IMPORT ZONE
    mv -f "${FILE_PATH}/${FILE_NAME}" "$HOME/astroport/${CAT}/${MEDIAID}/${TITLE}.${FILE_EXT}"
    FILE_NAME="${TITLE}.${FILE_EXT}"

    ;;

########################################################################
# CASE ## DEFAULT
########################################################################
    *)

    zenity --warning --width ${large} --text "Impossible d'interpréter votre commande $CAT"
    exit 1

    ;;

esac

## Extract thumbnail
MIME=$(file --mime-type -b $HOME/astroport/${CAT}/${MEDIAID}/${TITLE}.${FILE_EXT})

[[ $(echo $MIME | grep video) ]] && ffmpeg  -i $HOME/astroport/${CAT}/${MEDIAID}/${TITLE}.${FILE_EXT} -r 1/300 -vf scale=-1:120 -vcodec png $HOME/astroport/${CAT}/${MEDIAID}/thumbnail.png
[[ ! -f ~/astroport/${CAT}/${MEDIAID}/thumbnail.png ]] && echo "DEFAULT THUMBNAIL NEEDED"

########################################################################
# ADD $FILE to IPFS / ASTROPORT / KODI
echo "new_file_in_astroport.sh \"$HOME/astroport/${CAT}/${MEDIAID}/\" \"${FILE_NAME}\"" $3
[[ -f ~/astroport/${CAT}/${MEDIAID}/ajouter_video.txt ]] && cat ~/astroport/${CAT}/${MEDIAID}/ajouter_video.txt
# LOG NOISE # [[ -f ~/astroport/${CAT}/${MEDIAID}/video.json ]] && cat ~/astroport/${CAT}/${MEDIAID}/video.json
########################################################################
## CREATION DU FICHIER ~/astroport/Add_${MEDIAKEY}_script.sh
########################################################################
### AJOUT DANS IPFS  #######################################################
########################################################################
####################################new_file_in_astroport.sh##################
########################################################################
[[ "$CAT" == "film" || "$CAT" == "serie" ]] && CHOICE="TMDB"

timestamp=$(date -u +%s%N | cut -b1-13)

## OLD CODE !!! ADD TO ASTROPORT SCRIPT
## NOW CREATE TIDDLER INTO PLAYER TW

echo "MEDIAKEY=${MEDIAKEY}" > ~/astroport/Add_${MEDIAKEY}_script.sh

## ACTIVATE h265 conversion .?
#[[ $CHOICE == "TMDB" ]] && echo "echo \"Encoder ${FILE_NAME} en h265 avant import ? Tapez sur ENTER.. Sinon saisissez qqch avant...\"
#reponse=\$1
#[[ ! \$reponse ]] && read reponse
#if [[ ! \$reponse ]]; then
#    ffmpeg -i \"$HOME/astroport/${CAT}/${MEDIAID}/${FILE_NAME}\" -vcodec libx265 -crf 28 $HOME/astroport/${MEDIAID}.mp4
#    mv \"$HOME/astroport/${CAT}/${MEDIAID}/${FILE_NAME}\" \"$HOME/astroport/${CAT}/${MEDIAID}/${FILE_NAME}.old\"
#    mv $HOME/astroport/${MEDIAID}.mp4 \"$HOME/astroport/${CAT}/${MEDIAID}/${FILE_NAME}.mp4\"
#    ~/.zen/Astroport.ONE/tools/new_file_in_astroport.sh \"$HOME/astroport/${CAT}/${MEDIAID}/\" \"${FILE_NAME}.mp4\"
#else" >> ~/astroport/Add_${MEDIAKEY}_script.sh

# $3 is the G1PUB of the PLAYER
echo "~/.zen/Astroport.ONE/tools/new_file_in_astroport.sh \"$HOME/astroport/${CAT}/${MEDIAID}/\" \"${FILE_NAME}\" \"$G1PUB\"" >> ~/astroport/Add_${MEDIAKEY}_script.sh

#[[ $CHOICE == "TMDB" ]] && echo "fi" >> ~/astroport/Add_${MEDIAKEY}_script.sh

echo "rm -f /tmp/\${MEDIAKEY}.pass
rm -f /tmp/\${MEDIAKEY}.dunikey ## REMOVE KEYS
mv ~/astroport/Add_${MEDIAKEY}_script.sh \"$HOME/astroport/Done_${FILE_NAME}.sh\"
" >> ~/astroport/Add_${MEDIAKEY}_script.sh

chmod +x ~/astroport/Add_${MEDIAKEY}_script.sh

########################################################################
## USE PLAYER G1PUB AS MEDIA WALLET
MEDIAPUBKEY=$(cat ~/.zen/game/players/.current/.g1pub)
G1BALANCE=$(~/.zen/Astroport.ONE/tools/jaklis/jaklis.py balance -p $G1PUB)

########################################################################
echo "# ZENBALANCE for ${MEDIAKEY} , WALLET $MEDIAPUBKEY"
########################################################################
FILE_BSIZE=$(du -b "$HOME/astroport/${CAT}/${MEDIAID}/${FILE_NAME}" | awk '{print $1}')
FILE_SIZE=$(echo "${FILE_BSIZE}" | awk '{ split( "B KB MB GB TB PB" , v ); s=1; while( $1>1024 ){ $1/=1024; s++ } printf "%.2f %s", $1, v[s] }')

#G1BALANCE=$(~/.zen/Astroport.ONE/tools/jaklis/jaklis.py balance -p $G1PUB) && [[ "$G1BALANCE" == "null" ]] && G1BALANCE=0 || G1BALANCE=$(echo "$G1BALANCE" | cut -d '.' -f 1)
#if [[ $G1BALANCE -gt 0 ]]; then
#    [ ! $2 ] && G1AMOUNT=$(zenity --entry --width 400 --title "VIRER DE LA MONNAIE LIBRE AU MEDIAKEY (MAX $G1BALANCE)" --text "Combien de JUNE (G1) souhaitez-vous offrir à ce MEDIA ($FILE_SIZE)" --entry-text="")
#    [[ ! "$G1AMOUNT" =~ ^[0-9]+$ ]] && G1AMOUNT=0
#    ~/.zen/Astroport.ONE/tools/jaklis/jaklis.py -k ~/.zen/secret.dunikey pay -p ${MEDIAPUBKEY} -a $G1AMOUNT -c "#ASTROPORT:${MEDIAKEY} DON"
#    ZENBALANCE=$(echo "100 * $G1AMOUNT" | bc -l | cut -d '.' -f 1)
#else
    ZENBALANCE=0
#fi
########################################################################

zenity --warning --width 360 --text "(♥‿‿♥) $MEDIAKEY (ᵔ◡◡ᵔ)"

bash ~/astroport/Add_${MEDIAKEY}_script.sh "noh265"

zenity --warning --width 320 --text "Ajout à votre TW $PLAYER"


########################################################################
## ADD TIDDLER TO TW
########################################################################
echo "%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
## GETTING LAST TW via IPFS or HTTP GW
LIBRA=$(head -n 2 ~/.zen/Astroport.ONE/A_boostrap_nodes.txt | tail -n 1 | cut -d ' ' -f 2)
[[ $YOU ]] && echo "http://$myIP:8080/ipns/${ASTRONAUTENS} ($YOU)" && ipfs --timeout 6s cat  /ipns/${ASTRONAUTENS} > ~/.zen/tmp/ajouter_media.html
[[ ! -s ~/.zen/tmp/ajouter_media.html ]] && echo "$LIBRA/ipns/${ASTRONAUTENS}" && curl -m 6 -so ~/.zen/tmp/ajouter_media.html "$LIBRA/ipns/${ASTRONAUTENS}"
[[ ! -s ~/.zen/tmp/ajouter_media.html ]] && espeak "WARNING. impossible to find your TW online"
[[ ! -s ~/.zen/game/players/$PLAYER/ipfs/moa/index.html ]] &&  espeak "FATAL ERROR. No player TW copy found ! EXIT" && exit 1
echo "%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
[[ -s ~/.zen/tmp/ajouter_media.html ]] && cp -f ~/.zen/tmp/ajouter_media.html ~/.zen/game/players/$PLAYER/ipfs/moa/index.html && espeak "OK DONE"

###############################

    echo "Nouveau MEDIAKEY dans TW $PSEUDO / $PLAYER : http://$myIP:8080/ipns/$ASTRONAUTENS"
    tiddlywiki --verbose --load ~/.zen/game/players/$PLAYER/ipfs/moa/index.html \
                    --import ~/astroport/${CAT}/${MEDIAID}/${MEDIAKEY}.dragdrop.json "application/json" \
                    --output ~/.zen/tmp --render "$:/core/save/all" "newindex.html" "text/plain"


    if [[ -s ~/.zen/tmp/newindex.html ]]; then
        cp ~/.zen/tmp/newindex.html ~/.zen/game/players/$PLAYER/ipfs/moa/index.html
        [[ $DIFF ]] && cp   ~/.zen/game/players/$PLAYER/ipfs/moa/.chain \
                                        ~/.zen/game/players/$PLAYER/ipfs/moa/.chain.$(cat ~/.zen/game/players/$PLAYER/ipfs/moa/.moats)

        TW=$(ipfs add -Hq ~/.zen/game/players/$PLAYER/ipfs/moa/index.html | tail -n 1)
        ipfs name publish --allow-offline -t 72h --key=$PLAYER /ipfs/$TW

        [[ $DIFF ]] && echo $TW > ~/.zen/game/players/$PLAYER/ipfs/moa/.chain
        echo $MOATS > ~/.zen/game/players/$PLAYER/ipfs/moa/.moats

        echo "================================================"
        echo "$PLAYER : http://$myIP:8080/ipns/$ASTRONAUTENS"
        echo "================================================"
        echo
    fi

 espeak "Well done my friend. You are feeding the blob. Happy TW"

exit 0