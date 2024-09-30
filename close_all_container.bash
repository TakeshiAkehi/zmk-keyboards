SCRIPT_DIR=$(cd $(dirname $0); pwd)
cd $SCRIPT_DIR

for I in `ls keyboards`; do
    for C in `docker ps -f name=$I -q`; do
        docker stop $C
        docker remove $C
    done
done