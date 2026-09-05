set dotenv-load

export BUILD_DIR := "target"
unused_var := "nothing reads this"

alias b := build

# Compile the project.
[group: 'dev']
build:
    cargo build --release

[group: 'dev']
test: build
    cargo test

[group: 'release']
release version: test
    echo "releasing {{ version }} from {{ BUILD_DIR }}"
    echo {{ undefined_name() }}

fmt:
    just --fmt --unstable

deploy: missing_recipe
    echo deploy
