dest=$HOME/backups/nexus
mkdir -p "$dest"
rsync -a -e 'ssh -T -o BatchMode=yes' --include='*.age' --exclude='*' nexus:/var/lib/nexus-backup/ "$dest/"
find "$dest" -maxdepth 1 -name '*.age' -mtime +35 -delete
ssh -T -o BatchMode=yes nexus "date -u +%Y-%m-%dT%H:%M:%SZ > /var/lib/nexus-backup/last-pull"
echo "nexus-pull: $(find "$dest" -maxdepth 1 -name '*.age' | wc -l) archives in $dest"
