set -e

input_path="$1"
shift
resize_width="$1"
shift || true

filename="${input_path##*/}"
basename="${filename%.*}"
img="root/files/$basename.img"
tmp="tmp/to-img.bmp"

width="$(identify -ping -format '%[width]' "$input_path")"
if [ -z "$resize_width" ]
then
    if [ $width -gt 700 ]
    then
        resize_width=700
    fi
fi

args=""
if [ ! -z "$resize_width" ]
then
    width="$resize_width"
    args="-resize $width"
fi

convert -verbose "$input_path" $args "bmp:$tmp"
height="$(identify -ping -format '%[height]' "$tmp")"

convert -verbose "$tmp" -depth 8 "rgba:$img"

python3 <<EOF
with open('$img', 'br+') as file:
    content = file.read()
    file.seek(0)
    w = int($width).to_bytes(4, 'little')
    h = int($height).to_bytes(4, 'little')
    file.write(w + h + content)
EOF

echo "made $img"

rm -f disk.img
