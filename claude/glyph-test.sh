#!/bin/bash
# Renders candidate status-line glyph sets so you can see which ones your
# terminal draws correctly. Each glyph sits between pipes at a fixed column.
# If a right-hand pipe is pushed out of line, that glyph is double-width and
# will overlap neighbouring text (this is what broke the old countdown icon).

row() { printf '  %-18s |%s| |%s| |%s| |%s| |%s| |%s|\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7"; }

echo
echo "  Alignment ruler   |X| |X| |X| |X| |X| |X|      <- all pipes must line up"
echo "  ------------------------------------------------------------------"
row "A. plain text"   "pj" "br" "pr" "5h" "7d" "cx"
row "B. emoji"        "📁" "🌿" "🔀" "⏳" "📅" "🧠"
row "C. nerd font"    $'' $'' $'' $'' $'' $''
row "D. symbols"      "◆" "⑂" "◈" "◔" "▣" "▪"
row "E. arrows/dots"  "▸" "❯" "•" "◦" "▪" "▫"
echo
echo "  Progress bar characters (all should be single-width):"
printf '    blocks   |%s|\n' "████░░░░░░"
printf '    shaded   |%s|\n' "▓▓▓▓▒▒░░░░"
printf '    bars     |%s|\n' "▰▰▰▰▱▱▱▱▱▱"
printf '    ascii    |%s|\n' "####------"
echo
echo "  Sample line 3, three bar styles:"
printf '    5h %s 43%%  7d %s 86%%\n' "████░░░░░░" "█████████░"
printf '    5h %s 43%%  7d %s 86%%\n' "▰▰▰▰▱▱▱▱▱▱" "▰▰▰▰▰▰▰▰▰▱"
printf '    5h %s 43%%  7d %s 86%%\n' "####------" "#########-"
echo
