set -e

mke2fs -L '' -N 0 -O none -d root -r 1 -t ext2 ext2-test-disk.img 256k
