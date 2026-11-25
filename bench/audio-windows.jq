# Groups consecutive clips, given as an array of sample counts, into windows of between $lo and $hi
# seconds at $rate samples a second, and prints the windows as one array, each window an array of
# clip indices. Windows don't overlap: a clip that would carry a window past $hi drops the
# window's first clip instead.
#
#   jq -c --argjson rate <hz> --argjson lo <s> --argjson hi <s> -f bench/audio-windows.jq
#
# See bench/README.md.

. as $samples | ($samples | length) as $n | ($lo * $rate) as $min | ($hi * $rate) as $max
| {start: 0, end: 0, sum: 0, out: []}
| until(.sum < $min and .end >= $n;
    if .sum >= $min and .sum <= $max then
      .out += [[range(.start; .end)]] | .start = .end | .sum = 0
    elif .sum > $max then
      .sum -= $samples[.start] | .start += 1
    else
      .sum += $samples[.end] | .end += 1
    end)
| .out
