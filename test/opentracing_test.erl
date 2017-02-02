%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Tests for OpenTracing
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration ===============================================
-module(opentracing_test).

%%%_* Includes =========================================================
-include_lib("eunit/include/eunit.hrl").

%%%_* Code =============================================================
%%%_ * API -------------------------------------------------------------
opentracing_simple_test() ->
  {ok, noop_tracer} = opentracing:tracer(),
  {ok, Span}        = opentracing:start_span(noop_tracer, "root-span"),
  ok                = opentracing:finish_span(noop_tracer, Span).

opentracing_run_span_test() ->
  {ok, noop_tracer} = opentracing:tracer(),
  ok                = opentracing:run_span( noop_tracer
                                          , "root-fun-span"
                                          , fun(S) -> S end ),
  {ok, noop_tracer} = opentracing:tracer(),
  ok                = opentracing:run_span( noop_tracer
                                          , "root-fun-span"
                                          , fun(_) -> blah end ),
  {ok, noop_tracer} = opentracing:tracer(),
  {ok, Span}        = opentracing:start_span(noop_tracer, "root-span"),
  ok                =
    opentracing:run_span( noop_tracer
                        , "follows_from-root-fun-span"
                        , fun(_) -> blah end
                        , [{follows_from, opentracing:span_ctx(Span)}] ),
  ok                = opentracing:finish_span(noop_tracer, Span).

opentracing_ref_span_test() ->
  {ok, noop_tracer} = opentracing:tracer(),
  {ok, Span}        = opentracing:start_span(noop_tracer, "root-span"),
  {ok, Span2}       =
    opentracing:start_span( noop_tracer
                          , "child-span"
                          , [{child_of, opentracing:span_ctx(Span)}] ),
  {ok, Span3}       =
    opentracing:start_span( noop_tracer
                          , "follows_from-span"
                          , [{follows_from, opentracing:span_ctx(Span2)}] ),
  ?assertError(
     {case_clause, {false, false}},
     opentracing:start_span( noop_tracer
                           , "blah-span"
                           , [{blah, opentracing:span_ctx(Span2)}] ) ),
  ok                = opentracing:finish_span(noop_tracer, Span2),
  ok                = opentracing:finish_span(noop_tracer, Span3),
  ok                = opentracing:finish_span(noop_tracer, Span).

%%%_* Editor ===========================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% vim: sw=2 ts=2 et
%%%
%%% End:
