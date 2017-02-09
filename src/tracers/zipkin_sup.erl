%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Zipkin tracer for OpenTracing
%%%
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration ===============================================
-module(zipkin_sup).
-behaviour(supervisor).

%%%_* Exports ==========================================================
%%%_ * API -------------------------------------------------------------
-export([start_link/0]).
-export([init/1]).

%%%_* Code =============================================================
%%%_ * API -------------------------------------------------------------
start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([])   -> init(application:get_all_env(opentracing));
init(Args) ->
  {ok, { {one_for_one, 4, 3600}
       , [worker_spec(zipkin_tracer, [Args], permanent)] }}.

%%%_* Private functions ================================================
worker_spec(M, A, Restart) ->
  {M, {M, start_link, A}, Restart, brutal_kill, worker, [M]}.

%%%_* Editor ===========================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% vim: sw=2 ts=2 et
%%%
%%% End:
