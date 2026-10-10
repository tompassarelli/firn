run="$1"
tmux -L plato kill-session -t plato 2>/dev/null || true
tmux -L plato new-session -d -s plato -c "$HOME" -x 200 -y 50 "bash -l $run"
while tmux -L plato has-session -t plato 2>/dev/null; do sleep 5; done
