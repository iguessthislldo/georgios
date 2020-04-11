set -e
cmd="tail --retry --follow"
file="tmp/serial.log"
$cmd $file || $cmd ../$file
