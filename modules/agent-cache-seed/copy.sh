#!/usr/bin/env bash
set -eu
home=$1
shift
die() {
  printf 'agent-cache-seed: %s\n' "$*" >&2
  exit 1
}
[ -d "$home" ] && [ ! -L "$home" ] || die "$home is not a real directory"
check_parents() {
  local dest=$1 path=$home part
  local -a parts
  IFS=/ read -ra parts <<<"${dest#"$home"/}"
  unset 'parts[-1]'
  for part in "${parts[@]}"; do
    path=$path/$part
    [ ! -L "$path" ] || die "$path is a symbolic link"
    if [ -e "$path" ] && [ ! -d "$path" ]; then die "$path is not a directory"; fi
  done
}
while [ "$#" -ge 2 ]; do
  from=$1
  to=$2
  shift 2
  case $to in
    "$home"/*) ;;
    *) die "$to is outside $home" ;;
  esac
  [ -e "$from" ] || continue
  [ -e "$to" ] && continue
  check_parents "$to"
  mkdir -p -- "${to%/*}"
  cp -a --reflink=auto -- "$from" "$to"
done
