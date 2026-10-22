#!/bin/sh
# 文字版试玩的一步（见 scripts/debug/agent_play.gd）。
# 用法：play.sh <会话目录> new <种子> [报名]   开局
#       play.sh <会话目录> <编号> [<编号>...]  依次点这些编号，只打出最后一屏
#       play.sh <会话目录>                     再看一遍当前这一屏
GODOT=/e/Godot/Godot_v4.7.2-stable_win64_console.exe
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
S="$1"; shift
if [ "$1" = "new" ]; then
  "$GODOT" --headless --fixed-fps 60 --path "$ROOT" -- --agent --session "$S" --new "$2" ${3:+--paper "$3"} 2>&1 | grep -Ev "^Godot Engine|ObjectDB instances|resources still in use|^   at: "
elif [ -n "$1" ]; then
  "$GODOT" --headless --fixed-fps 60 --path "$ROOT" -- --agent --session "$S" --do "$(echo "$*" | tr " " ",")" 2>&1 | grep -Ev "^Godot Engine|ObjectDB instances|resources still in use|^   at: "
else
  "$GODOT" --headless --fixed-fps 60 --path "$ROOT" -- --agent --session "$S" 2>&1 | grep -Ev "^Godot Engine|ObjectDB instances|resources still in use|^   at: "
fi
