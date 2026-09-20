.PHONY: test lint

test:
	./tests/test-cli.sh
	./tests/test-homebrew.sh
	./tests/test-google-drive.sh
	./tests/test-ghostty.sh
	./tests/test-starship.sh
	./tests/test-dev-image.sh
	./tests/test-ssh.sh
	./tests/test-local-dev-tls.sh
	./tests/test-orbstack-docker-api.sh
	./tests/test-static.sh

lint:
	./tests/test-static.sh
