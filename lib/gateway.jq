# agentgateway's config render, a jq module over the config template decoded to JSON (yq -o json
# 'explode(.)'): the validators of the key list and the overflow switches, and the render that
# fills the template with the rows, the keys, and the switches. Included by lib/gateway.sh. See
# docs/gateway.md.

include "profile";

# Whether the route is an alias's: its backend is an `ai` backend whose first group is the row.
def alias_route: .backends[0].ai != null;

# The key classes the template defines, one template key each.
def key_classes: [.gateways.consumer.apiKey.keys[].metadata.class];

# The aliases whose route has an Azure group, each of which the overflow switches turn on or off.
def switchable: [.routes[] | select(.backends[0].ai.groups | length > 1) | .name];

# The errors of the key list (keys.toml decoded to JSON), with the classes given: each [[keys]]
# entry holds a consumer, lowercase letters, digits, and hyphens; a class the template defines;
# and its key's SHA-256 hash as 64 lowercase hex digits; no consumer or hash is listed twice.
def key_errors($classes):
  (. // {}) as $doc
  | ($doc | unknown_keys(["keys"]; [])),
    (($doc.keys // []) as $keys
     | if ($keys | type) != "array" then problem(["keys"]; "an array of tables, [[keys]]")
       else
         ($keys | to_entries[] | .key as $i | .value as $key | ["keys", $i] as $path
          | if ($key | type) != "object" then problem($path; "a table")
            else
              ($key | unknown_keys(["consumer", "class", "sha256"]; $path)),
              (if ($key.consumer | type) != "string"
                  or ($key.consumer | test("^[a-z0-9][a-z0-9-]*$") | not) then
                 problem($path + ["consumer"]; "required, lowercase letters, digits, and hyphens")
               else empty end),
              (if $classes | index([$key.class]) | not then
                 problem($path + ["class"]; "required, one of \($classes | join(", "))")
               else empty end),
              (if ($key.sha256 | type) != "string" or ($key.sha256 | test("^[0-9a-f]{64}$") | not)
               then problem($path + ["sha256"]; "required, 64 lowercase hex digits")
               else empty end)
            end),
         ([$keys[] | objects | .consumer | strings] | group_by(.)[] | select(length > 1)
          | problem(["keys"]; "consumer \(.[0]) is listed more than once")),
         ([$keys[] | objects | .sha256 | strings] | group_by(.)[] | select(length > 1)
          | problem(["keys"]; "a hash is listed more than once"))
       end);

# The errors of the overflow switches (overflow.toml decoded to JSON), with the aliases given:
# exactly one switch an alias, each true or false.
def overflow_errors($aliases):
  (. // {}) as $doc
  | ($doc | keys_unsorted[] as $key | select($aliases | index([$key]) | not) | $key
     | problem([.]; "no alias with an Azure group; the switches are \($aliases | join(", "))")),
    ($aliases[] as $alias
     | if ($doc | has($alias) | not) then problem([$alias]; "required, true or false")
       elif ($doc[$alias] | type) != "boolean" then problem([$alias]; "true or false")
       else empty end);

# The errors of the rows (each class profile's rows, as {alias, port, model}) for the template's
# alias routes: each route's alias is one row's.
def row_errors($rows):
  .routes[] | select(alias_route) | .name as $alias
  | [$rows[] | select(.alias == $alias)] as $matches
  | if ($matches | length) == 0 then problem([$alias]; "no class profile has a row with this alias")
    elif ($matches | length) > 1 then problem([$alias]; "more than one class profile has this alias")
    else empty end;

# The rendered config: the template, each alias route's row provider at its host and its row's
# port, its /v1/models answer listing the alias with its row's model as root, and its Azure group
# dropped when the alias's switch is off; each host backend that names an alias, at that alias's
# row host and port; and one key a [[keys]] entry, its class's template key with the entry's hash
# and consumer.
def render($rows; $keys; $overflow):
  .gateways.consumer.apiKey.keys as $templates
  | .gateways.consumer.apiKey.keys = [
      ($keys // {}).keys // [] | .[] as $key
      | $templates[] | select(.metadata.class == $key.class)
      | .keyHash = "sha256:\($key.sha256)" | .metadata.name = $key.consumer
    ]
  | .routes |= map(
      if alias_route then
        .name as $alias
        | ($rows[] | select(.alias == $alias)) as $row
        | (.policies.directResponse.conditional[]
           | select(.condition == "request.path == \"/v1/models\"") | .body)
          = ({object: "list",
              data: [{id: $alias, object: "model", owned_by: "gateway", root: $row.model}]}
             | tojson)
        | .backends[0].ai.groups[0].providers[0].hostOverride += ":\($row.port)"
        | if ($overflow // {})[$alias] == false then .backends[0].ai.groups |= .[:1] else . end
      else . end)
  | ([.routes[] | select(alias_route)
      | {key: .name, value: .backends[0].ai.groups[0].providers[0].hostOverride}]
     | from_entries) as $hosts
  | .routes[].backends[] |= if has("host") then .host = $hosts[.host] else . end;
