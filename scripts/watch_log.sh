set -e
file="tmp/serial.log"
rm -f $file
tail --retry --follow $file
