%%%-------------------------------------------------------------------
%%% @author peguy
%%% @copyright (C) 2020, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 13. Oct 2020 14:40
%%%-------------------------------------------------------------------
-module(chandy_misra).
-author("peguy").

%% API
-export([start/0, deploy/0, cm/3]).

start() ->
  io:format("Deploying~n"),
  deploy(),
  io:format("Starting~n").

deploy() ->
  % Create network (use registered names for communication)
  register(a, spawn(?MODULE, cm, [{1, a}, {undefined, infinity}, [{b, 5}, {c, 1}, {e, 4}]])),
  register(b, spawn(?MODULE, cm, [{2, b}, {undefined, infinity}, []])),
  register(c, spawn(?MODULE, cm, [{3, c}, {undefined, infinity}, [{e, 2}, {d, 1}]])),
  register(d, spawn(?MODULE, cm, [{4, d}, {undefined, infinity}, [{f, 5}]])),
  register(e, spawn(?MODULE, cm, [{5, e}, {undefined, infinity}, [{b, 1}, {d, 5}]])),
  register(f, spawn(?MODULE, cm, [{6, f}, {undefined, infinity}, [{b, 6}, {g, 2}]])),
  register(g, spawn(?MODULE, cm, [{7, g}, {undefined, infinity}, [{d, 2}]])),
  % Start algorithm from source
  a ! start.

% Each process has an identifier (Id) and a name (Name).
% We use names instead of Erlang pids to simplify communication and have readable logs.
% Identifiers are used to mirror the original algorithm and identify the source (process 1).
% Neighbours denote successors, i.e., outgoing edges only, not incoming ones.

% Source (i=1)
cm({1, Name}, {Pred, D}, Neighbours) ->
  receive
  % Start
    start ->
      [Node ! {path, Name, Weight} || {Node, Weight} <- Neighbours],
      cm({1, Name}, {Pred, D}, Neighbours);

  % New path (cannot be shorter without negative cycles)
    {path, _, _} ->
      cm({1, Name}, {Pred, 0}, Neighbours)
  after 1000 ->
    % Exit
    unregister(Name),
    true
  end;

% Other node (i>1)
cm({Id, Name}, {Pred, D}, Neighbours) ->
  receive
  % New path (better than current)
    {path, Parent, ShortestPath} when ShortestPath < D ->
      [Node ! {path, Name, ShortestPath + Weight} || {Node, Weight} <- Neighbours],
      cm({Id, Name}, {Parent, ShortestPath}, Neighbours);
  % New path (not better than current)
    {path, _, _} ->
      cm({Id, Name}, {Pred, D}, Neighbours)
  after 1000 ->
    io:format("Shortest path at ~p is ~p via ~p~n", [Name, D, Pred]),
    unregister(Name),
    true
  end.
