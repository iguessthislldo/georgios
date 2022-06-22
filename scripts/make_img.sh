set -e

input_path="$1"
filename="${input_path##*/}"
basename="${filename%.*}"
img="root/files/$basename.img"
width=700
convert -verbose "$input_path" -resize $width -depth 8 "rgba:$img"
# echo "made $img $(identify -ping -format '%[width]' "$input_path")"
echo "made $img $width"
rm -f disk.img
