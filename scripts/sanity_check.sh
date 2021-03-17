set -e

function pop {
    git stash pop
}

function do_or_pop {
    echo $@
    $@ || (echo "$@ failed" && pop && exit 1)
}

git clean --force -dX
git stash --keep-index --include-untracked
do_or_pop make test
do_or_pop make
pop
