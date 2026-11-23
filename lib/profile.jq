# The host-class profile's schema, a jq module over a profile decoded to JSON (yq -p toml -o json):
# its validator, profile_errors, which yields each error in the profile's order, and the fields
# hosting profile set edits. Included by lib/profile.sh. See classes/README.md.

# The keys each table of the profile defines.
def profile_keys: ["store", "rows"];
def row_keys: [
  "alias", "model", "container", "port", "image", "context", "card_context", "cap",
  "queue_limit", "fraction", "dims", "flags", "cap_reason", "context_reason", "fraction_reason",
  "flags_reason", "measured_vllm", "load", "origin", "sampling"
];
def load_keys: ["target", "source"];
def origin_keys: [
  "publisher", "origin", "origin_reason", "licence", "card_url", "base_model", "base_origin",
  "generation_config"
];
def sampling_keys: ["source", "temperature", "top_p", "top_k", "min_p"];

# The fields of a row hosting profile set edits, by their dotted key paths: every key but a table.
def settable_fields:
  (row_keys - ["load", "origin", "sampling"])
  + (load_keys | map("load." + .))
  + (origin_keys | map("origin." + .))
  + (sampling_keys | map("sampling." + .));

# The settable fields whose value is a number, and the one whose value is a list of words.
def number_fields: [
  "port", "context", "card_context", "cap", "queue_limit", "fraction", "dims",
  "sampling.temperature", "sampling.top_p", "sampling.top_k", "sampling.min_p"
];
def list_fields: ["flags"];

# The aliases a row may serve under.
def aliases: ["agent", "vision", "audio", "embedding"];

# The vllm serve flags the typed fields and the suite own, which a row's free flags may not set.
def owned_flags: [
  "--host", "--port", "--served-model-name", "--max-num-seqs", "--max-model-len",
  "--gpu-memory-utilization", "--max-num-queued-reqs", "--model", "--override-generation-config"
];

# The origin the organization restricts. See standards-lab/context/ai-strategy.md.
def restricted_origin: "China";

# The key path given as an array, written as TOML's dotted keys with [i] for an array index.
def key_path:
  reduce .[] as $part ("";
    if ($part | type) == "number" then "\(.)[\($part)]"
    elif . == "" then $part
    else "\(.).\($part)" end);

# One error, at the key path given.
def problem($path; $message): {path: $path, message: $message};

# Whether the input is a whole number.
def whole: type == "number" and . == floor;

# Whether the input holds whitespace or a character a shell reads as syntax.
def unsafe_word: test("[\\s'\"\\\\$`;&|<>(){}\\[\\]*?!#~]");

# The errors of each key of the input object that the keys given don't hold.
def unknown_keys($allowed; $prefix):
  keys_unsorted[] as $key
  | select($allowed | index([$key]) | not)
  | problem($prefix + [$key]; "not a key the schema defines");

# The errors of the input object's field given, by kind: text, a non-empty string; word, a
# non-empty string a command line carries as one argument; count, a positive integer; fraction, a
# number over 0 and at most 1; port, an integer from 1 to 65535; release, a vLLM release such as
# v0.33.0; path, an absolute path. A required field that is absent is an error; an optional one
# that is absent has none.
def field($prefix; $key; $kind; $required):
  ($prefix + [$key]) as $path
  | if has($key) | not then
      if $required then problem($path; "required") else empty end
    else .[$key] as $value
    | if $kind == "text" then
        if ($value | type) != "string" or $value == "" then
          problem($path; "required, a non-empty string") else empty end
      elif $kind == "word" or $kind == "path" then
        if ($value | type) != "string" or $value == "" then
          problem($path; "required, a non-empty string")
        elif $value | unsafe_word then
          problem($path; "\($value | tojson) holds whitespace or shell syntax")
        elif $kind == "path" and ($value | startswith("/") | not) then
          problem($path; "\($value | tojson) is not an absolute path")
        else empty end
      elif $kind == "count" then
        if ($value | whole | not) or $value < 1 then
          problem($path; "required, a positive integer") else empty end
      elif $kind == "fraction" then
        if ($value | type) != "number" or $value <= 0 then
          problem($path; "required, a number over 0")
        elif $value > 1 then problem($path; "\($value) is over 1")
        else empty end
      elif $kind == "port" then
        if ($value | whole | not) or $value < 1 or $value > 65535 then
          problem($path; "required, a port from 1 to 65535") else empty end
      elif $kind == "release" then
        if ($value | type) != "string" or ($value | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$") | not) then
          problem($path; "required, a vLLM release such as v0.33.0") else empty end
      else empty end
    end;

# The errors of the input, a table the schema requires at the path given: absent or not a table.
def table_error($path):
  if . == null then problem($path; "required")
  elif type != "object" then problem($path; "required, a table")
  else empty end;

# The errors of a row's free flags: not a list of words, a flag the typed fields or the suite own,
# and flags without their reason.
def flag_errors($prefix):
  if has("flags") | not then empty
  elif (.flags | type) != "array" then problem($prefix + ["flags"]; "a list of words")
  else
    (.flags | to_entries[]
      | ($prefix + ["flags", .key]) as $path
      | .value as $word
      | if ($word | type) != "string" or $word == "" then problem($path; "required, a non-empty string")
        elif $word | unsafe_word then problem($path; "\($word | tojson) holds whitespace or shell syntax")
        elif owned_flags | index([$word | split("=")[0]]) then
          problem($path; "\($word | split("=")[0]) is set by the profile's typed fields or the suite, not a free flag")
        else empty end),
    (if (.flags | length) > 0 then field($prefix; "flags_reason"; "text"; true) else empty end)
  end;

# The errors of a row's origin table: its fields, and an origin or base origin the organization
# restricts without its reason, or a reason on any other origin.
def origin_errors($prefix):
  (.origin | table_error($prefix + ["origin"])),
  (.origin | objects
    | ($prefix + ["origin"]) as $p
    | unknown_keys(origin_keys; $p),
      field($p; "publisher"; "text"; true),
      field($p; "origin"; "text"; true),
      field($p; "origin_reason"; "text"; false),
      field($p; "licence"; "text"; true),
      field($p; "card_url"; "text"; true),
      field($p; "base_model"; "word"; false),
      field($p; "base_origin"; "text"; false),
      field($p; "generation_config"; "text"; false),
      (if has("base_model") != has("base_origin") then
        problem($p + ["base_origin"]; "set with base_model, or neither") else empty end),
      (if .origin == restricted_origin or .base_origin == restricted_origin then
        if has("origin_reason") | not then
          problem($p + ["origin_reason"]; "required for a model whose origin or base origin is \(restricted_origin)")
        else empty end
      elif has("origin_reason") then
        problem($p + ["origin_reason"]; "only a model whose origin or base origin is \(restricted_origin) records why it was chosen")
      else empty end));

# The errors of a row's sampling override: its fields, a row whose checkpoint is its card
# publisher's, and a checkpoint of another publisher's model without a sampling override or a
# statement that its generation config matches the card's.
def sampling_errors($prefix):
  (.origin | if type == "object" then .base_model else null end) as $base
  | if has("sampling") then
      ($prefix + ["sampling"]) as $p
      | (.sampling | table_error($p)),
        (.sampling | objects
          | unknown_keys(sampling_keys; $p),
            field($p; "source"; "text"; true),
            (to_entries[] | select(.key != "source") | select(.value | type != "number")
              | problem($p + [.key]; "a number")),
            (if [keys[] | select(. != "source")] == [] then
              problem($p; "sets no value") else empty end)),
        (if $base == null then
          problem($p; "only a row whose checkpoint another publisher's card describes (origin.base_model) overrides its sampling")
        else empty end)
    elif $base != null and (.origin | has("generation_config") | not) then
      problem($prefix + ["origin", "generation_config"]; "required with base_model when the row sets no sampling")
    else empty end;

# The errors of one row, the input, at index $i.
def row_errors($i):
  ["rows", $i] as $prefix
  | if type != "object" then problem($prefix; "a table")
    else
      unknown_keys(row_keys; $prefix),
      field($prefix; "alias"; "word"; true),
      (.alias as $alias
        | if ($alias | type) == "string" and $alias != "" and (aliases | index([$alias]) | not) then
          problem($prefix + ["alias"]; "\($alias | tojson) is not one of \(aliases | join(", "))")
        else empty end),
      field($prefix; "model"; "word"; true),
      field($prefix; "container"; "word"; true),
      field($prefix; "port"; "port"; true),
      field($prefix; "image"; "word"; false),
      field($prefix; "context"; "count"; true),
      field($prefix; "card_context"; "count"; true),
      (if (.context | whole) and (.card_context | whole) and .context > .card_context then
        problem($prefix + ["context"]; "\(.context) is over the card's context, \(.card_context)")
      else empty end),
      field($prefix; "context_reason"; "text"; true),
      field($prefix; "cap"; "count"; true),
      field($prefix; "cap_reason"; "text"; true),
      field($prefix; "queue_limit"; "count"; false),
      (if (.queue_limit | whole) and (.cap | whole) and .queue_limit != 2 * .cap then
        problem($prefix + ["queue_limit"]; "\(.queue_limit) is not twice the cap, \(.cap)")
      else empty end),
      field($prefix; "fraction"; "fraction"; true),
      field($prefix; "fraction_reason"; "text"; true),
      (if .alias == "embedding" then field($prefix; "dims"; "count"; true)
      elif has("dims") then problem($prefix + ["dims"]; "only an embedding row has an output width")
      else empty end),
      flag_errors($prefix),
      field($prefix; "measured_vllm"; "release"; true),
      (.load | table_error($prefix + ["load"])),
      (.load | objects
        | unknown_keys(load_keys; $prefix + ["load"]),
          field($prefix + ["load"]; "target"; "text"; true),
          field($prefix + ["load"]; "source"; "text"; true)),
      origin_errors($prefix),
      sampling_errors($prefix)
    end;

# The errors of a value a later row repeats from an earlier one, for each field given.
def duplicate_errors:
  [.rows | arrays | to_entries[] | select(.value | type == "object")] as $rows
  | ("alias", "port", "container") as $key
  | [$rows[] | select(.value | has($key)) | {index: .key, value: .value[$key]}]
  | to_entries[] as $entry
  | first(.[:$entry.key][] | select(.value == $entry.value.value)) as $first
  | problem(["rows", $entry.value.index, $key]; "\($entry.value.value | tojson) is also rows[\($first.index)]'s");

# The errors of each string anywhere in the profile that holds an IP address or a MagicDNS name.
def host_identity_errors:
  paths(type == "string") as $path
  | getpath($path) as $value
  | if $value | test("(?<![0-9.])([0-9]{1,3}\\.){3}[0-9]{1,3}(?![0-9]|\\.[0-9])") then
      problem($path; "holds an IP address; a profile names no host")
    elif $value | test("(?<![0-9a-z:])[0-9a-f]{1,4}((:[0-9a-f]{1,4})*::|(:[0-9a-f]{1,4}){4,7}(?![0-9a-z:]))"; "i") then
      problem($path; "holds an IP address; a profile names no host")
    elif $value | test("\\.ts\\.net\\b"; "i") then
      problem($path; "holds a MagicDNS name; a profile names no host")
    else empty end;

# Every error of the profile, the input.
def profile_errors:
  unknown_keys(profile_keys; []),
  field([]; "store"; "path"; true),
  (if has("rows") | not then problem(["rows"]; "required, at least one row")
  elif (.rows | type) != "array" or (.rows | length) == 0 then
    problem(["rows"]; "required, at least one row")
  else .rows | to_entries[] | .key as $i | .value | row_errors($i) end),
  duplicate_errors,
  host_identity_errors;

