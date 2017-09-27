%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Erlang platform API for OpenTracing
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration ===============================================
-module(opentracing).

%%%_* Exports ==========================================================
%%%_ * API -------------------------------------------------------------
-export([tracer/0]).
-export([tracer/1]).
-export([inject/4]).
-export([extract/3]).
-export([start_span/2]).
-export([start_span/3]).
-export([run_span/3]).
-export([run_span/4]).
-export([start_span_from_context/3]).
-export([finish_span/2]).

%%%_ * Getter / Setters ------------------------------------------------
-export([span_ctx/1]).
-export([add_span_tag/3]).
-export([del_span_tag/2]).
-export([get_span_tags/1]).
-export([set_span_tags/2]).
-export([get_span_id/1]).
-export([get_span_kind/1]).
-export([get_sampled/1]).
-export([set_sampled/2]).
-export([get_parent_id/1]).
-export([get_trace_id/1]).
-export([get_operation/1]).
-export([get_timestamp/1]).
-export([get_duration/1]).

%%%_* Types ------------------------------------------------------------
-export_type([span/0]).
-export_type([options/0]).
-export_type([baggage/0]).
-export_type([span_tags/0]).
-export_type([timestamp/0]).

%%%_* Records ==========================================================
-record(s, { operation = error(operation) :: term()
           , ctx       = error(ctx)       :: span_ctx()
           , tracer    = error(tracer)    :: module()
           , start_ts  = error(start_ts)  :: non_neg_integer()
           , duration  = undefined        :: undefined | timestamp()
           , parent_id = undefined        :: parent_id()
           , kind      = server           :: span_kind()
           , tags      = maps:new()       :: span_tags()
           }).
-record(s_ctx, { trace_id = error(trace_id) :: trace_id()
               , span_id  = error(span_id)  :: span_id()
               , sampled  = false           :: boolean()
               , baggage  = maps:new()      :: baggage()
               }).

%%%_* Types ============================================================
-type span()             :: #s{}.
-type tracer()           :: module().
-type span_id()          :: non_neg_integer().
-type carrier()          :: opentracing_tracer:carrier().
-type options()          :: opentracing_tracer:options().
-type baggage()          :: map().
-type trace_id()         :: non_neg_integer().
-type span_ctx()         :: #s_ctx{}.
-type parent_id()        :: undefined | span_id().
-type span_kind()        :: client | server | resource.
-type operation()        :: binary() | string() | iolist().
-type span_tags()        :: map().
-type timestamp()        :: non_neg_integer().
-type serialize_format() :: opentracing_tracing:serialize_format().
-type span_reference()   :: {child_of, span()} | {follows_from, span()}.
-type span_options()     :: list(span_reference()).

%%%_* Code =============================================================
%%%_ * API -------------------------------------------------------------
%% @doc Start a new Noop tracer
-spec tracer() ->
  {ok, any()} | {error, atom()}.
tracer() ->
  tracer(noop_tracer).

%% @doc Start a new tracer implementing the Tracer API
-spec tracer(module()) ->
  {ok, any()} | {error, atom()}.
tracer(Tracer) ->
  tracer(Tracer, []).

-spec tracer(module(), options()) ->
  {ok, any()} | {error, atom()}.
tracer(Tracer, Options) ->
  Tracer:start(Options).

%% @doc Inject SpanCtx for over-the-wire serialization of data
-spec inject(module(), span_ctx(), serialize_format(), carrier()) ->
  {ok, span_ctx()} | {error, atom()}.
inject(Tracer, SpanCtx, Format, Carrier) ->
  Tracer:inject(SpanCtx, Format, Carrier).

%% @doc Extract SpanCtx from over-the-wire serialized data
-spec extract(module(), serialize_format(), carrier()) ->
  {ok, span_ctx()} | {error, atom()}.
extract(Tracer, Format, Carrier) ->
  Tracer:extract(Format, Carrier).

%% @doc Start a new root span
-spec start_span(tracer(), operation()) ->
  {ok, span()} | {error, atom()}.
start_span(Tracer, Operation) ->
  {ok, new_span(Tracer, Operation, undefined, new_ctx())}.

%% @doc Start a new child or followsfrom span
-spec start_span(tracer(), operation(), span_options()) ->
  {ok, span()} | {error, atom()}.
start_span(Tracer, Operation, Options) ->
  SCtx =
    case { lists:keyfind(child_of, 1, Options)
         , lists:keyfind(follows_from, 1, Options) }
    of
      {{child_of, Ctx}, false}               -> Ctx;
      {false,           {follows_from, Ctx}} -> Ctx
    end,
  {ok, new_span(Tracer, Operation, undefined, new_ctx(SCtx#s_ctx.trace_id))}.

-spec run_span(tracer(), operation(), fun()) ->
  ok | {error, atom()}.
run_span(Tracer, Operation, Fun) ->
    {ok, Span} = start_span(Tracer, Operation),
    case Fun(Span) of
        #s{}=NewSpan -> finish_span(Tracer, NewSpan);
        _            -> finish_span(Tracer, Span)
    end.

-spec run_span(tracer(), operation(), fun(), span_options()) ->
  ok | {error, atom()}.
run_span(Tracer, Operation, Fun, Options) ->
    {ok, Span} = start_span(Tracer, Operation, Options),
    case Fun(Span) of
        #s{}=NewSpan -> finish_span(Tracer, NewSpan);
        _            -> finish_span(Tracer, Span)
    end.

%% @doc Start a new span from Ctx or if none is found a new root-span
-spec start_span_from_context(tracer(), any(), context:context()) ->
  {ok, {context:context(), span()}}.
start_span_from_context(Tracer, Operation, Ctx) ->
  {ok, NewSpan} =
    case context:get(Ctx, active_span) of
      {error, notfound} ->
        start_span(Tracer, Operation);
      {ok, Span}        ->
        SpanCtx = span_ctx(Span),
        {ok, new_span( Tracer
                     , Operation
                     , undefined
                     , new_ctx(get_trace_id(SpanCtx), get_sampled(SpanCtx))) }
    end,
  {ok, {context:set(Ctx, active_span, NewSpan), NewSpan}}.

%% @doc Report a span as finished to the Tracer
-spec finish_span(tracer(), span()) ->
  ok | {error, atom()}.
finish_span(Tracer, #s{start_ts = StartTs} = Span) ->
  Tracer:finish_span(Span#s{ duration = calc_duration(StartTs) }).

%%%_ * Getter / Setters ------------------------------------------------
%% @doc Return the Span Context from a Span
-spec span_ctx(span()) ->
  span_ctx().
span_ctx(#s{ ctx = SpanCtx }) ->
  SpanCtx.

%% @doc Get Tags from a Span
-spec get_span_tags(span()) ->
  span_tags().
get_span_tags(#s{ tags = Tags }) ->
  Tags.

%% @doc Set Tags on a Span
-spec set_span_tags(span(), span_tags()) ->
  span().
set_span_tags(Span, Tags) ->
  Span#s{ tags = Tags }.

%% @doc Add single Tag to a Span
-spec add_span_tag(span(), term(), term()) ->
  span().
add_span_tag(Span, Key, Value) ->
  Span#s{ tags = maps:put(Key, Value, get_span_tags(Span)) }.

%% @doc Del single Tag on a Span
-spec del_span_tag(span(), term()) ->
  span().
del_span_tag(Span, Key) ->
  Span#s{ tags = maps:remove(Key, get_span_tags(Span)) }.

%% @doc get trace-id from a Span
-spec get_trace_id(span_ctx()) ->
  trace_id().
get_trace_id(#s_ctx{ trace_id = TraceId}) ->
  TraceId.

%% @doc get span-id from a Span
-spec get_span_id(span_ctx()) ->
  span_id().
get_span_id(#s_ctx{ span_id = SpanId }) ->
  SpanId.

%% @doc get sampled from a Trace, if `true` this Trace should be sampled
-spec get_sampled(span_ctx()) ->
  boolean().
get_sampled(#s_ctx{ sampled = Sampled }) ->
  Sampled.

%% @doc set sampled on a Trace, if `true` this Trace should be sampled
-spec set_sampled(span(), boolean()) ->
  span().
set_sampled(#s{ ctx = SpanCtx } = Span, Bool) ->
  Span#s{ ctx = SpanCtx#s_ctx { sampled = Bool } }.

%% @doc get parent-id from a Span
-spec get_parent_id(span()) ->
  parent_id().
get_parent_id(#s{ parent_id = ParentId }) ->
  ParentId.

%% @doc get span-kind from a Span
-spec get_span_kind(span()) ->
  span_kind().
get_span_kind(#s{ kind = Kind }) ->
  Kind.

%% @doc get operation, i.e. name from a Span
-spec get_operation(span()) ->
  span_kind().
get_operation(#s{ operation = Operation }) ->
  Operation.

%% @doc get start timestamp in `ms` from a Span
-spec get_timestamp(span()) ->
  timestamp().
get_timestamp(#s{ start_ts = Timestamp }) ->
  Timestamp.

%% @doc get duration in `ms` from a Span
-spec get_duration(span()) ->
  timestamp().
get_duration(#s{ duration = Duration }) ->
  Duration.

%%%_* Private functions ================================================
%% @doc since we always time our spans we will round up to 1 microsecond if the
%%      span took less.
calc_duration(StartTs) ->
  case ts() - StartTs of
    0   -> 1;
    Val -> Val
  end.

ts() ->
  {MegaSecs, Secs, MicroSecs} = os:timestamp(),
  (MegaSecs * 1000000 + Secs) * 1000000 + MicroSecs.

new_ctx() ->
  new_ctx(generate_id()).

new_ctx(TraceId) ->
  new_ctx(TraceId, false).

new_ctx(TraceId, Sampled) ->
  #s_ctx{ trace_id = TraceId, span_id = generate_id(), sampled = Sampled }.

new_span(Tracer, Operation, ParentId, SpanCtx) ->
  #s{ tracer    = Tracer
    , operation = Operation
    , start_ts  = ts()
    , parent_id = ParentId
    , ctx       = SpanCtx }.

generate_id() ->
  rand:uniform(16#ffffffffffffffff).

%%%_* Editor ===========================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% vim: sw=2 ts=2 et
%%%
%%% End:
