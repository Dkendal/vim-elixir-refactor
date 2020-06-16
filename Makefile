ROOT=$(PWD)

all: clean build
	vim --headless -c UpdateRemotePlugins -c q

build: rplugin/elixir/refactor.ez

rplugin/elixir/refactor.ez: $(shell find ./refactor -type f)
	cd refactor; mix archive.build -o ${ROOT}/rplugin/elixir/refactor.ez

.PHONY: clean
clean:
	rm -f rplugin/elixir/refactor.ez
