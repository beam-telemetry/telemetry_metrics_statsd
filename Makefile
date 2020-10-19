.PHONY: test

test: test/inetrc
	ERL_INETRC="test/inetrc" mix test

test/inetrc:
	echo "{lookup, [file, native]}." > test/inetrc
	echo "{hosts_file, \"$(shell pwd)/test/hosts\"}." >> test/inetrc
