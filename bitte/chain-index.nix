# Needed variables:
#   INDEX_STATE_DIR # Should persist if you don't want to wait for a full sync every time
#   NOMAD_ALLOC_DIR # With node socket in $NOMAD_ALLOC_DIR/node.sock
#   NOMAD_PORT_index
{ writeShellScriptBin, plutus-chain-index, coreutils, wait-for-socket, lib, network }:
writeShellScriptBin "entrypoint" ''
  set -eEuo pipefail

  export PATH="${lib.makeBinPath [ coreutils plutus-chain-index wait-for-socket ]}"

  mkdir -p "$INDEX_STATE_DIR"

  wait-for-socket "$NOMAD_ALLOC_DIR/node.sock"

  exec plutus-chain-index start-index --socket-path "$NOMAD_ALLOC_DIR"/node.sock --db-path "$INDEX_STATE_DIR/db.sqlite" --port "$NOMAD_PORT_index" --network-id ${toString network.magic}
''
