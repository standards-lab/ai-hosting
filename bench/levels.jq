# Per-level figures from GuideLLM 0.8.1 result JSON, one table a file, judged by the purpose's
# floor: audio an RTFx median of at least 5, embed a mean of at least 4,300 prompt tok/s.
#
#   jq -r --arg purpose <audio|embed> -f bench/levels.jq <result.json>...
#
# See bench/README.md.

def pct($p):
  sort as $xs | ($xs | length) as $n
  | if $n == 0 then nan
    else (($n - 1) * $p) as $k | ($k | floor) as $lo | ([$lo + 1, $n - 1] | min) as $hi
    | $xs[$lo] + ($xs[$hi] - $xs[$lo]) * ($k - $lo)
    end;
def median: pct(0.5);

def fixed($d):
  if . == null then "-"
  elif isnan then "nan"
  else (if . < 0 then "-" else "" end) as $sign
    | (fabs * pow(10; $d)) as $y | ($y | floor) as $f | ($y - $f) as $r
    | (if $r > 0.5 then $f + 1 elif $r < 0.5 then $f elif ($f % 2) == 0 then $f else $f + 1 end
       | tostring) as $s
    | if $d == 0 then $sign + $s
      else ([range(0; $d + 1 - ($s | length))] | map("0") | join("") + $s) as $p
      | $sign + $p[:-$d] + "." + $p[-$d:]
      end
    end;

def name: input_filename | split("/") | last;

def level_name:
  .config.strategy
  | if .type_ == "concurrent" then .streams | tostring
    elif .type_ == "constant" or .type_ == "poisson" then "rate \(.rate | fixed(2))"
    else .type_ end;

def knee:
  (.conclusions // [])[] | (.initial.throughput // {})
  | "knee: \(.status) knee \(.knee) breakpoint \(.breakpoint_concurrency) saturation \(.saturation_concurrency) (\(.reason))";

def level($purpose):
  .metrics as $m | $m.request_totals as $rt
  | [.requests.successful[] | .request_end_time - .request_start_time] as $lat
  | [.requests.successful[] | select(.input_metrics.audio_seconds // 0 > 0)
     | .input_metrics.audio_seconds / (.request_end_time - .request_start_time)] as $rtfx
  | $m.prompt_tokens_per_second.successful.mean as $ptps
  | ($lat | median) as $latm
  | ((if $purpose == "audio" then ($rtfx | length) > 0 and ($rtfx | median) >= 5
     else $ptps >= 4300 end) and $rt.successful > 0) as $ok
  | [ level_name,
      "\($rt.successful)/\($rt.errored)/\($rt.incomplete)",
      ($m.requests_per_second.successful.mean | fixed(3)),
      ($m.time_to_first_token_ms.successful.median | fixed(0)),
      ($latm | fixed(2)),
      ($lat | pct(0.9) | fixed(2)),
      (if ($lat | length) > 0 then $lat | min | fixed(2) else "-" end),
      ($ptps | fixed(0)),
      (if ($rtfx | length) > 0
       then "\($rtfx | median | fixed(2)) | \($rtfx | min | fixed(2)) | \([$rtfx[] | select(. >= 5)] | length)/\($rtfx | length)"
       else "- | - | -" end),
      (.duration | fixed(0)),
      (if $ok then "meets" else "MISSES" end) ]
  | join(" | ");

def table($purpose):
  "## \(name)",
  knee,
  "level | ok/err/inc | req/s | TTFT med ms | lat med s | lat p90 s | lat min s | prompt tok/s | RTFx med | RTFx min | RTFx>=5 | dur s | floor",
  (.benchmarks[] | level($purpose));

$ARGS.named.purpose as $purpose
| if $purpose == "audio" or $purpose == "embed" then table($purpose)
  else error("purpose must be audio or embed") end
