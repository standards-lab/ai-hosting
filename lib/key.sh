#!/usr/bin/env bash
# The gateway's consumer keys, issued on the architect's laptop beside the consumers' checkouts:
# the issue that generates a consumer's key, writes it into the consumer repository's own
# age-encrypted fnox.toml through fnox, and writes only its SHA-256 hash and class into the key
# list, compose/agentgateway/keys.toml; the revoke that deletes a consumer's entry from the key
# list; and the list of the consumers holding one. The key list is the gateway's one record of
# issued keys, validated as the render validates it (hosting_gateway_keys in lib/gateway.sh), and
# no key is printed, put on a command line, or written to disk unencrypted. Sourced by
# lib/hosting.sh. See context/gateway.md.

# The variable a consumer's fnox.toml holds its key under.
HOSTING_KEY_VARIABLE=AI_GATEWAY_TOKEN

# Refuses a consumer name that isn't lowercase letters, digits, and hyphens, starting with a
# letter or digit, the form the key list holds.
hosting_key_consumer() {
  if [[ ! $1 =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "hosting: consumer '$1' is not lowercase letters, digits, and hyphens" >&2
    return 1
  fi
}

# Refuses a class the template given, decoded to JSON (hosting_gateway_template), defines no key
# for: hosting_key_class <class> <template>.
hosting_key_class() {
  local classes
  classes=$(hosting_gateway_jq 'key_classes | join(" ")' -r <<<"$2") || return
  if [[ " $classes " != *" $1 "* ]]; then
    echo "hosting: class '$1' is none of $classes" >&2
    return 1
  fi
}

# Prints the name of the one age provider of the fnox config at the path given, a consumer
# repository's fnox.toml, after refusing a path holding no file, a file that doesn't decode as
# TOML, and a config whose age providers aren't exactly one, since the key is encrypted to that
# provider's recipients.
hosting_key_provider() {
  local config providers
  if [[ ! -f $1 ]]; then
    echo "hosting: $1 is missing; a consumer repository commits its fnox.toml at its root" >&2
    return 1
  fi
  config=$(hosting_gateway_toml "$1" "$1") || return
  providers=$(jq -r '(.providers // {}) | objects | to_entries[]
    | select(.value | objects | .type == "age") | .key' <<<"$config") || return
  if [[ -z $providers || $providers == *$'\n'* ]]; then
    echo "hosting: $1 is no fnox config with exactly one age provider, which the key is" \
      "encrypted to" >&2
    return 1
  fi
  echo "$providers"
}

# Prints the description of the variable given in the fnox config at the path given, or nothing
# when it has none: hosting_key_description <path> <variable>.
hosting_key_description() {
  hosting_yq -p toml -o json '.' "$1" |
    jq -r --arg variable "$2" '.secrets[$variable].description? // empty | strings'
}

# Prints a new key: 32 bytes from /dev/urandom as 64 lowercase hex digits, the spike's format.
hosting_key_generate() {
  od -A n -v -t x1 -N 32 /dev/urandom | tr -d ' \n'
}

# Prints the SHA-256 hash of the key given as lowercase hex, agentgateway's hash of a presented
# key: of its exact characters, no newline. printf is a builtin, so the key reaches no command's
# arguments.
hosting_key_hash() {
  printf %s "$1" | sha256sum | cut -d ' ' -f 1
}

# Writes the key list given, the key list's JSON, to compose/agentgateway/keys.toml in place of
# the old one, keeping the old one's leading comment lines, once a copy validates against the template
# given (hosting_gateway_keys). Fails, removing the copy and leaving the key list as it was, when
# the copy is invalid: hosting_key_write <keys> <template>.
hosting_key_write() {
  local copy
  copy=$(mktemp "$HOSTING_GATEWAY/keys.toml.XXXXXX") || return
  chmod 644 "$copy"
  if {
    sed -n '/^#/!q; p' "$HOSTING_GATEWAY/keys.toml"
    jq -r '(.keys // [])[]
      | "\n[[keys]]\nconsumer = \"\(.consumer)\"\nclass = \"\(.class)\"\nsha256 = \"\(.sha256)\""' \
      <<<"$1"
  } >"$copy" && hosting_gateway_keys "$2" "$copy" >/dev/null; then
    mv "$copy" "$HOSTING_GATEWAY/keys.toml"
    return
  fi
  rm -f "$copy"
  return 1
}

# Issues the consumer given a key of the class given: validates the consumer's name, the class,
# the consumer repository's fnox.toml (hosting_key_provider), and the key list, refusing a
# consumer the list already holds unless rotate is given, and one it doesn't hold when it is;
# then generates the key (hosting_key_generate), writes it with fnox set, by stdin, into the
# repository's fnox.toml as AI_GATEWAY_TOKEN, encrypted to its age provider's recipients, and only
# then writes the key's hash and class into the key list, replacing the consumer's entry on a
# rotate. Gives the variable a description when it has none; fnox keeps one it has. Commits
# nothing: hosting_key_issue <consumer> <class> <repository> [rotate].
hosting_key_issue() {
  local consumer=$1 class=$2 repository=$3 rotate=${4:-} template keys held fnox provider
  local description key hash options=()
  hosting_key_consumer "$consumer" || return
  template=$(hosting_gateway_template) || return
  hosting_key_class "$class" "$template" || return
  if [[ ! -d $repository ]]; then
    echo "hosting: $repository is no directory; give the consumer repository's checkout" >&2
    return 1
  fi
  fnox=$(cd "$repository" && pwd)/fnox.toml
  provider=$(hosting_key_provider "$fnox") || return
  keys=$(hosting_gateway_keys "$template") || return
  held=$(jq --arg consumer "$consumer" '[(.keys // [])[] | select(.consumer == $consumer)]
    | length' <<<"$keys")
  if ((held > 0)) && [[ -z $rotate ]]; then
    echo "hosting: $consumer already holds a key; --rotate replaces it" >&2
    return 1
  fi
  if ((held == 0)) && [[ -n $rotate ]]; then
    echo "hosting: $consumer holds no key to rotate; issue one without --rotate" >&2
    return 1
  fi
  description=$(hosting_key_description "$fnox" "$HOSTING_KEY_VARIABLE") || return
  if [[ -z $description ]]; then
    description="The ai-hosting model gateway's API key for $consumer, which it presents to"
    description+=" the gateway on gb10-2 as a bearer token. The gateway's operator issues it with"
    description+=" \`hosting key issue\` in ai-hosting, which gives the gateway only its hash;"
    description+=" issue your own there for a gateway of your own."
    options=(--description "$description")
  fi
  key=$(hosting_key_generate) || return
  if [[ ! $key =~ ^[0-9a-f]{64}$ ]]; then
    echo "hosting: /dev/urandom gave no 32-byte key" >&2
    return 1
  fi
  hash=$(hosting_key_hash "$key") || return
  printf %s "$key" | fnox -c "$fnox" set --provider "$provider" "${options[@]}" \
    "$HOSTING_KEY_VARIABLE" >/dev/null || return
  keys=$(jq --arg consumer "$consumer" --arg class "$class" --arg sha256 "$hash" '
    (. // {}) | .keys = if any((.keys // [])[]; .consumer == $consumer)
            then [.keys[] | if .consumer == $consumer then .class = $class | .sha256 = $sha256
                            else . end]
            else (.keys // []) + [{consumer: $consumer, class: $class, sha256: $sha256}] end' \
    <<<"$keys") || return
  hosting_key_write "$keys" "$template"
}

# Revokes the consumer given's key: validates its name and the key list, refusing a consumer the
# list doesn't hold, then deletes its entry from the key list, which the gateway drops at the next
# hosting gateway render on gb10-2. Leaves the consumer's fnox.toml as it is, and commits nothing.
hosting_key_revoke() {
  local template keys
  hosting_key_consumer "$1" || return
  template=$(hosting_gateway_template) || return
  keys=$(hosting_gateway_keys "$template") || return
  if ! jq -e --arg consumer "$1" 'any((.keys // [])[]; .consumer == $consumer)' <<<"$keys" \
    >/dev/null; then
    echo "hosting: $1 holds no key" >&2
    return 1
  fi
  keys=$(jq --arg consumer "$1" '.keys |= map(select(.consumer != $consumer))' <<<"$keys") ||
    return
  hosting_key_write "$keys" "$template"
}

# Prints a table of the consumers the key list holds a hash for, each with its class, in the key
# list's order, or a line saying none does, after validating the key list.
hosting_key_list() {
  local keys
  keys=$(hosting_gateway_keys "$(hosting_gateway_template)") || return
  if jq -e '(.keys // []) | length == 0' <<<"$keys" >/dev/null; then
    echo "no consumer holds a key; hosting key issue issues one"
    return
  fi
  printf '%-24s %s\n' CONSUMER CLASS
  jq -r '.keys[] | [.consumer, .class] | @tsv' <<<"$keys" |
    while IFS=$'\t' read -r consumer class; do
      printf '%-24s %s\n' "$consumer" "$class"
    done
}
