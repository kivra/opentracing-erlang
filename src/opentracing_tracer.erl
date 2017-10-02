%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Erlang platform API for OpenTracing
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration ===============================================
-module(opentracing_tracer).

%%%_* Exports ==========================================================
%%%_* Types ------------------------------------------------------------
-export_type([carrier/0]).
-export_type([options/0]).
-export_type([serialize_format/0]).

%%%_* Types ============================================================
-type carrier()          :: any().
-type options()          :: list(proplists:proplist() | map()).
-type serialize_format() :: text_map | binary | httpheaders.

%%%_* Behaviour ========================================================
-callback start(options()) ->
  {ok, any()} | {error, atom}.

-callback finish_span(opentracing:span()) ->
  ok | {error, atom()}.

-callback inject(proplists:proplist(), serialize_format()) ->
  {ok, any()} | {error, atom()}.

-callback extract(serialize_format(), carrier()) ->
  {ok, opentracing:span_ctx()} | {error, atom()}.

%%%_* Editor ===========================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% vim: sw=2 ts=2 et
%%%
%%% End:
