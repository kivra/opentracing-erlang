%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Zipkin tracer for OpenTracing
%%%
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration ===============================================
-module(zipkin_tracer).
-behavior(opentracing_tracer).
-behaviour(gen_server).

%%%_* Exports ==========================================================
%%%_ * API -------------------------------------------------------------
-export([start/1]).
-export([start_link/1]).
-export([drain/0]).
-export([stop/0]).
-export([finish_span/1]).
-export([extract/2]).
-export([inject/2]).

%% gen_server
-export([init/1]).
-export([terminate/2]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([code_change/3]).

%%%_* Macros ===========================================================
%% Spans are keps in a circular buffer and flushed to Zipkin once it reaches
%% `SPANS_THRESHOLD` or the next `tick` triggered by the `TICK_TIME` interval,
%% whatever comes first.
%% If for some reason an invalid HTTP-response is returned zipkin_tracer will
%% try to send the accumulated spans next time. It will continue to accumulate
%% Spans to a total of `MAX_SPANS_THRESHOLD` before evicting from the end of
%% the buffer.
%%
-define(TICK_TIME,           1000). % Tick-time in ms
-define(SPANS_THRESHOLD,     100).  % Number of Spans to accumulate before
                                    % flushing.
-define(MAX_SPANS_THRESHOLD, 100).  % Max Number of Spans to accumulate before
                                    % evicting
-define(http_options,    [ {timeout,         5000}
                         , {connect_timeout, 1000}
                         , {version,         "HTTP/1.1"} ]).
-define(options,         [ {body_format,     binary}
                         , {full_result,     false} ]).
-define(httpheaders,     [ {trace_id,  <<"x-b3-traceid">>}
                         , {span_id,   <<"x-b3-spanid">>}
                         , {parent_id, <<"x-b3-parentspanid">>}
                         , {sampled,   <<"x-b3-sampled">>}
                         ]).

%%%_* Code =============================================================
%%%_ * Types -----------------------------------------------------------
-record(s, { ip           = error('s.ip')   :: string()                 % Ip
           , port         = error('s.port') :: non_neg_integer()        % Port
           , tref         = error('s.tref') :: timer:tref()             % timer
           , spans        = []              :: list(opentracing:span()) % Spans
           , service_name = <<"unknown">>   :: list(opentracing:span()) % Name
           }).

%%%_ * API -------------------------------------------------------------
start(Args)       -> start_link(Args).
start_link(Args)  -> gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).
stop()            -> gen_server:call(?MODULE, stop).
drain()           -> gen_server:call(?MODULE, drain, infinity).

finish_span(Span) ->
  case opentracing:get_sampled(opentracing:span_ctx(Span)) of
    true  -> gen_server:cast(?MODULE, {finish_span, Span});
    false -> ok
  end.

extract(Format, Map) when is_map(Map) -> extract(Format, maps:to_list(Map));
extract(httpheaders, Headers)         ->
  ExtData = lists:map(fun({K, H}) ->
                        {K, to_span_data(assoc(Headers, H, undefined))}
                      end, ?httpheaders),
  case
    lists:filter(
      fun({parent_id, undefined}) -> false; % Optional
         ({_, undefined})         -> true;
         (_)                      -> false
      end,
      ExtData)
  of
    [] -> {ok, ExtData};
    _  -> {error, span_ctx_corrupted}
  end;
extract(_, _) ->
  {error, not_implemented}.

inject(SpanCtxData, httpheaders) ->
  {ok, lists:foldl(
         fun({K, H}, Acc) ->
           case assoc(SpanCtxData, K) of
             {error, notfound} -> Acc;
             {ok, undefined}   -> Acc;
             {ok, Val}         -> [{H, binary(Val)} | Acc]
           end
         end, [], ?httpheaders)};
inject(_, _) ->
  {error, not_implemented}.

%%%_ * gen_server callbacks --------------------------------------------
init(Args) ->
  Ip          = assoc(Args, zipkin_ip,    "127.0.0.1"),
  Port        = assoc(Args, zipkin_port,  9411),
  TickTime    = assoc(Args, tick_time,    ?TICK_TIME),
  ServiceName = assoc(Args, service_name, <<"unknown">>),
  {ok, TRef}  = timer:send_interval(TickTime, tick),
  {ok, #s{ ip=Ip, port=Port, tref=TRef, service_name=ServiceName }}.

terminate(_Rsn, #s{tref=TRef}) -> {ok, cancel} = timer:cancel(TRef), ok.

handle_call(drain, _From, #s{tref=TRef, spans=SL} = S) ->
  _  = timer:cancel(TRef),
  ok = flush(tick),
  {reply, ok, S#s{spans=flush_spans(S, SL)}};
handle_call(stop, _From, S) ->
  {stop, stopped, ok, S}.

handle_cast({finish_span, Span}, #s{spans=SL} = S) ->
  {noreply, S#s{spans=maybe_flush_spans(S, [Span|SL])}}.

handle_info(tick, #s{spans=SL} = S) ->
  flush(tick),
  {noreply, S#s{spans=flush_spans(S, SL)}};
handle_info(_Info, State) ->
  {noreply, State}.

code_change(_OldVsn, S, _Extra) -> {ok, S}.

%%%_* Private functions ================================================
maybe_flush_spans(State, Spans) ->
  case length(Spans) > ?SPANS_THRESHOLD of
    true  -> flush_spans(State, Spans);  % Flush spans if above threshold
    false -> Spans
  end.

flush_spans(_, [])        -> [];
flush_spans(#s{ ip=Ip, port=Port, service_name=SName}, InputSpans) ->
  Spans = lists:sublist(InputSpans, ?MAX_SPANS_THRESHOLD),
  case send_spans(
         Ip,
         Port,
         lists:foldl(fun(S, Acc) -> [encode_span(SName,S)|Acc] end, [], Spans) )
  of
    ok         -> [];
    {error, R} -> io:format("Error: ~p~n", [R]), Spans
  end.

send_spans(Ip, Port, Spans) ->
  Req = { "http://"++Ip++":"++integer_to_list(Port)++"/api/v2/spans"
        , []
        , "application/json"
        , jsx:encode(lists:reverse(Spans)) },
  try httpc:request(post, Req, ?http_options, ?options) of
    {ok, {202, _}}          -> ok;
    {ok, {Status, Payload}} -> {error, {Status, Payload}};
    Error                   -> Error
  catch
    exit:{timeout, _} -> {error, timeout}
  end.

encode_span(ServiceName, Span) ->
  Ctx = opentracing:span_ctx(Span),
  lists:flatten(
    [ {<<"traceId">>,           encode_id(opentracing:get_trace_id(Ctx))}
    , {<<"id">>,                encode_id(opentracing:get_span_id(Ctx))}
    , {<<"name">>,              binary(opentracing:get_operation(Span))}
    , {<<"timestamp">>,         opentracing:get_timestamp(Span)}
    , {<<"duration">>,          opentracing:get_duration(Span)}
    , {<<"kind">>,              binary(opentracing:get_span_kind(Span))}
    , {<<"localEndpoint">>,     [ {<<"serviceName">>, ServiceName}
                                , {<<"ipv4">>,        local_ip_v4()}
                               %, {<<"port">>,        } TODO
                                ]}
    , case opentracing:get_parent_id(Span) of
        undefined -> [];
        ParentId  -> {<<"parentId">>, encode_id(ParentId)}
      end
    , case tags(Span) of
        []   -> [];
        Tags -> {<<"tags">>, Tags}
      end
    %, {<<"annotations">>,       annotations(ServiceName, Span)}
    ]).

tags(Span) ->
  lists:flatten(
    maps:fold(
      fun(<<"error">>, false, Acc) -> Acc;
         (Key, Value, Acc)         -> [{binary(Key), binary(Value)}|Acc]
      end,
      [],
      opentracing:get_span_tags(Span))).

%% Zipkin treats the presence of an error annotation as error, regardles
%% of `true` or `false`

local_ip_v4() ->
  {ok, Addrs} = inet:getifaddrs(),
  list_to_binary(
    inet_parse:ntoa(
      hd([ Addr || {_, Opts} <- Addrs, {addr, Addr} <- Opts,
                   size(Addr) == 4, Addr =/= {127,0,0,1}
         ]) ) ).

binary(I) when is_integer(I) -> binary(integer_to_binary(I));
binary(L) when is_list(L)    -> binary(list_to_binary(L));
binary(A) when is_atom(A)    -> binary(atom_to_list(A));
binary(B)                    -> B.

encode_id(Id) -> binary(string:to_lower(integer_to_list(Id, 16))).

flush(Msg) ->
  receive Msg -> flush(Msg)
  after   0   -> ok
  end.

assoc(L, K) ->
  case lists:keyfind(K, 1, L) of
    {K, V} -> {ok, V};
    false  -> {error, notfound}
  end.

assoc(KVs, K, Def) ->
  case assoc(KVs, K) of
    {ok, V}           -> V;
    {error, notfound} -> Def
  end.

to_span_data(<<"true">>)              -> true;
to_span_data(<<"false">>)             -> false;
to_span_data(Val) when is_binary(Val) -> binary_to_integer(Val);
to_span_data(Val)                     -> Val.

%%%_* Editor ===========================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% vim: sw=2 ts=2 et
%%%
%%% End:
