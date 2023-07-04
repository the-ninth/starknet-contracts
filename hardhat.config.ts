/** @type import('hardhat/config').HardhatUserConfig */

import "@shardlabs/starknet-hardhat-plugin";

module.exports = {
  starknet: {
    scarbCommand: "scarb",
    requestTimeout: 90_000, // 90s
    // network: "integrated-devnet", // Predefined networks include alpha-goerli, alpha-goerli2, alpha-mainnet and integrated-devnet.
    network: "alpha-goerli",
    venv: "~/cairo_venv",
    cairo1BinDir: "~/.cairo/target/release/",
  },
  paths: {
    // Defaults to "contracts" (the same as `paths.sources`).
    starknetSources: "contracts",

    // Defaults to "starknet-artifacts".
    // Has to be different from the value set in `paths.artifacts` (which is used by core Hardhat and has a default value of `artifacts`).
    starknetArtifacts: "starknet-artifacts",

    // Same purpose as the `--cairo-path` argument of the `starknet-compile-deprecated` command
    // Allows specifying the locations of imported files, if necessary.
    // cairoPaths: ["my/own/cairo-path1", "also/my/own/cairo-path2"],
  },
  networks: {
    devnet: { // this way you can also specify it with `--starknet-network devnet`
      url: "http://127.0.0.1:5050"
    },
    integratedDevnet: {
      url: "http://127.0.0.1:5050",
      // venv: "active" <- for the active virtual environment with installed starknet-devnet
      // venv: "path/to/venv" <- for env with installed starknet-devnet (created with e.g. `python -m venv path/to/venv`)
      venv: "~/cairo_venv",

      // use python or rust vm implementation
      // vmLang: "python" <- use python vm (default value)
      // vmLang: "rust" <- use rust vm
      // (rust vm is available out of the box using dockerized integrated-devnet)
      // (rustc and cairo-rs-py required using installed devnet)
      // read more here : https://0xspaceshard.github.io/starknet-devnet/docs/guide/run/#run-with-the-rust-implementation-of-cairo-vm
      vmLang: "python",

      // or specify Docker image tag
      // dockerizedVersion: "<DEVNET_VERSION>",

      // optional devnet CLI arguments, read more here: https://0xspaceshard.github.io/starknet-devnet/docs/guide/run
      args: [
        "--gas-price", "2000000000",
        // "--fork-network", "alpha-goerli"
      ],

      // stdout: "logs/stdout.log" <- dumps stdout to the file
      stdout: "STDOUT", // <- logs stdout to the terminal
      // stderr: "logs/stderr.log" <- dumps stderr to the file
      stderr: "STDERR"  // <- logs stderr to the terminal
    }
  }
};
