# Make settings - @see https://tech.davis-hansson.com/p/make/
SHELL := bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

# Log levels
DEBUG := $(shell printf "\e[2D\e[35m")
INFO  := $(shell printf "\e[2D\e[36m🔵 ")
OK    := $(shell printf "\e[2D\e[32m🟢 ")
WARN  := $(shell printf "\e[2D\e[33m🟡 ")
ERROR := $(shell printf "\e[2D\e[31m🔴 ")
END   := $(shell printf "\e[0m")


.PHONY: default
default: help

## help - Print help message.
.PHONY: help
help: Makefile
	@echo "usage: make <target>"
	@sed -n 's/^##//p' $<

.PHONY: build
build: 
	swift build

.PHONY: test
test:
	swift test

## test-data
testDataDir := Tests/eppo/Resources/test-data/
tempDir := ${testDataDir}temp/
gitDataDir := ${tempDir}sdk-test-data/
branchName := main
githubRepoLink := https://github.com/Eppo-exp/sdk-test-data.git
.PHONY: test-data
test-data:
	rm -rf $(testDataDir)
	mkdir -p $(tempDir)
	git clone -b ${branchName} --depth 1 --single-branch ${githubRepoLink} ${gitDataDir}
	cp -r ${gitDataDir}/* ${testDataDir}
	rm -rf ${tempDir}
