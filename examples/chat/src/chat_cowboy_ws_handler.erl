-module(chat_cowboy_ws_handler).

-export([init/3]).
-export([websocket_init/3]).
-export([websocket_handle/3]).
-export([websocket_info/3]).
-export([websocket_terminate/3]).

-define(CHATROOM_NAME, ?MODULE).
-define(TIMEOUT, 5 * 60 * 1000). % Innactivity Timeout

-record(state, {name, handler}).

%% API

init(_, _Req, _Opts) ->
  {upgrade, protocol, cowboy_websocket}.

websocket_init(_Type, Req, _Opts) ->
  % Create the handler from our custom callback
  Handler = ebus_proc:spawn_handler(fun chat_erlbus_handler:handle_msg/2, [self()]),
  Username = binary_to_list(element(1, cowboy_req:binding(username, Req))),
  ebus:sub(Handler, ?CHATROOM_NAME),
  ebus:sub(Handler, Username),
  ebus:pub(?CHATROOM_NAME, {list_to_binary("admin"), list_to_binary("=== " ++ Username ++ " Joined the ChatRoom! ===")}),
  {ok, Req, #state{name = get_name(Req), handler = Handler}, ?TIMEOUT}.

websocket_handle({text, Msg}, Req, State) ->
  ListInput = string:tokens(binary_to_list(Msg), ":"),
  {_, {Hour,Minute,_}} = erlang:localtime(),
  Time = integer_to_list(Hour) ++ "." ++ integer_to_list(Minute),
  case ListInput of
    [Pm, Pesan] -> ebus:sub(State#state.handler, Pm),
                   ebus:pub(Pm, {list_to_binary("[PM:" ++ Pm ++ "]-[" ++ Time ++ "]-" ++ binary_to_list(State#state.name)), list_to_binary(Pesan)}),
                   ebus:unsub(State#state.handler, Pm);
    [Pesan] -> ebus:pub(?CHATROOM_NAME, {list_to_binary("[Global]-[" ++ Time ++ "]-" ++ binary_to_list(State#state.name)), list_to_binary(Pesan)})
  end,
  {ok, Req, State};
websocket_handle(_Data, Req, State) ->
  {ok, Req, State}.

websocket_info({message_published, {Sender, Msg}}, Req, State) ->
  {reply, {text, jiffy:encode({[{sender, Sender}, {msg, Msg}]})}, Req, State};
websocket_info(_Info, Req, State) ->
  {ok, Req, State}.

websocket_terminate(_Reason, _Req, State) ->
  % Unsubscribe the handler
  ebus:unsub(State#state.handler, ?CHATROOM_NAME),
  ok.

%% Private methods

get_name(Req) ->
  {{Host, Port}, _} = cowboy_req:peer(Req),
  Username = element(1, cowboy_req:binding(username, Req)),
  Name = list_to_binary(string:join(["[", inet_parse:ntoa(Host),
    ":", io_lib:format("~p", [Port]), "]-[", binary_to_list(Username), "]"], "")),
  Name.
  