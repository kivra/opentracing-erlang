%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Zipkin tracer for OpenTracing
%%%
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-module(zipkin_app).
-behaviour(application).

%%%_* Exports ==========================================================
-export([start/2]).
-export([stop/1]).

%%%_* API ==============================================================
start(normal, _Args) ->
  zipkin_sup:start_link().

stop(_State) ->
  ok.

%%%_* Tests ============================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

basic_test() ->
  ok = application:start(opentracing),
  ok = application:stop(opentracing).

-endif.

%%%_* Emacs ============================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:
