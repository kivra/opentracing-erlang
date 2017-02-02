all: compile

compile:
		rebar3 compile

clean:
		rebar3 clean

eunit:
		rebar3 eunit

dialyze:
		rebar3 dialyzer

repl:
		rebar3 shell

ci:
		./rebar3 compile
		./rebar3 eunit
		./rebar3 dialyzer
