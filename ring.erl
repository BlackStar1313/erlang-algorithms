%%%-------------------------------------------------------------------
%%% @author Njoyim Peguy
%%% @copyright (C) 2019, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 12. Oct 2019 4:27 PM
%%%-------------------------------------------------------------------
-module(ring).
-author("Njoyim Peguy").

%% API
-export([start/3, starting_process/6, running_processes/5, collectData/1]).

start(NbProcesses, NbMessages, Message) ->
  MasterProcess = self(),
  case (NbProcesses > 0) and (NbMessages >= 0) of
    true ->
      StartProcess = spawn(ring, starting_process, [MasterProcess, undef, NbMessages, NbProcesses - 1, undef, Message]),
      io:format("master process : [~p] has just created the starting process [~p]~n~n", [MasterProcess, StartProcess]),
      StartProcess ! {created},
      collectData(NbProcesses);

    false->
      io:format("Big ERROR coming from the master process : arguments values(~w, ~w) not allowed~n", [NbMessages, NbProcesses]),
      file:write_file("./tokenRing.txt", io_lib:fwrite("Big ERROR coming from the master process [~p] : args values(~w, ~w) not allowed~n", [MasterProcess, NbMessages, NbProcesses]), [append])
  end.

collectData(NbProcesses) ->
  case NbProcesses > 0 of
    true ->
      receive
        {Previous, Next, Counter} ->
          io:format("Master Process [~p] writes : Current process [~p], Next process [~w], Counter = ~w~n~n", [self(), Previous, Next, Counter]),
          file:write_file("./tokenRing.txt", io_lib:fwrite("Previous process [~w], Next process [~w], Counter = ~w~n", [Previous, Next, Counter]), [append]),
          collectData(NbProcesses - 1)
      end;

    false -> done
  end.


starting_process(MasterProcess, Successor, NbMessages, NbProcesses, Counter, Message) ->
  %-------------------------------------------------------------------------------
  % This is the very first spawned process which acts like a central process.
  % This process will send its pid through the ring
  % so that the last process know which is its next/successor process.
  %-------------------------------------------------------------------------------
  receive

    {created} ->
      self() ! {start_deployment},
      io:format("First process [~p] created! About to set up the rest of the ring.~n~n", [self()]),
      starting_process(MasterProcess, undef, NbMessages, NbProcesses, undef, Message);

    {start_deployment} ->
      Next = spawn(ring, running_processes, [MasterProcess, self(), undef, undefined, NbProcesses - 1]),
      Next ! {keep_deploying},  % send a message to the next process my own pid and an atom.
      io:format("Process [~p] has just created its successor process [~p]. Rremaining processes to go : ~w.~n", [self(), Next, NbProcesses]),
      starting_process(MasterProcess, Next, NbMessages, NbProcesses, undef, Message);

  %------------------------------------------------------------------------------------------
  %  When receiving a message "Successful deployment" from the very last process,
  %  this process sends an atom to itself, to start sending tokens/messages around the ring.
  %------------------------------------------------------------------------------------------
    {Last, SuccessfulDeployment, send_tokens} ->
      NewCounter = 0,
      self() ! {NewCounter, Message},
      io:format("starting process [~p] has just received the message ~p from the last process [~p].~nNow it can send messages around the ring if any.~n~n",
        [self(), SuccessfulDeployment, Last]),
      starting_process(MasterProcess, Successor, NbMessages, NbProcesses, NewCounter, Message);

    {NewCounter, Message} when NbMessages > 0 ->
      Successor ! {NewCounter + 1, Message},
      io:format("Sender Process [~p] forwards message '~w' to its successor process [~p]. Received counter value = ~w~n", [self(), Message, Successor, NewCounter]),
      starting_process(MasterProcess, Successor, NbMessages - 1, NbProcesses, NewCounter, Message);

  %----------------------------------------------------------------------------------------------------------
  % Send to the next process that there aren't any messages left to broadcast.
  % And then the first/starting process terminate itself when it receives a message from the last process!
  %----------------------------------------------------------------------------------------------------------
    {NewCounter, Message} when NbMessages =< 0 ->
      io:format("~nSender process [~p] forwards message '~w' to its successor process [~p]. Received counter value = ~w~n", [self(), stop, Successor, NewCounter]),
      io:format("Sender process [~p] will send later to the master process [~p] : [Pid = ~p, Next Pid = ~p, Counter value = ~p]~n~n", [self(), MasterProcess, self(), Successor, NewCounter]),
      Successor ! {stop},
      starting_process(MasterProcess, Successor, NbMessages, NbProcesses, NewCounter, Message);

    {stop} ->
      MasterProcess ! {self(), Successor, Counter},
      finish
  end.


% We need to keep track of the first process (i.e., the central process PID) so that it does not keep running infinitely
running_processes(MasterProcess, StartProcess, Successor, Counter, NbProcesses) ->
  receive
  % ---------------------
  % Phase 1: Deployment
  % ---------------------
    {keep_deploying} when NbProcesses > 0 ->
      Next = spawn(ring, running_processes, [MasterProcess, StartProcess, undefined, undefined, NbProcesses - 1]),
      Next ! {keep_deploying},
      io:format("Process [~p] has just created its successor process [~p]. Remaining processes to go : ~w.~n", [self(), Next, NbProcesses]),
      running_processes(MasterProcess, StartProcess, Next, undefined, NbProcesses);

    {keep_deploying} when NbProcesses =:= 0 ->
      io:format("Last process [~p] created but cannot create anymore!~n~n", [self()]),
      SuccessfulDeployment = "Successful deployment!",
      StartProcess ! {self(), SuccessfulDeployment, send_tokens},
      running_processes(MasterProcess, StartProcess, StartProcess, undefined, NbProcesses);  % As it is the last process, its successor process is the starting process

  % -----------------------
  % Phase 2: Token activity
  % -----------------------
    {NewCounter, Message} ->
      io:format("Sender Process [~p] forwards message '~w' to its successor process [~p]. Received counter value = ~w~n", [self(), Message, Successor, NewCounter]),
      Successor ! {NewCounter + 1, Message},
      running_processes(MasterProcess, StartProcess, Successor, NewCounter, NbProcesses);

  % ---------------------
  % Phase 3: Termination
  % ---------------------
    {stop} ->
      io:format("Sender Process [~p] forwards message '~w' to the next process [~p].~n", [self(), stop, Successor]),
      io:format("About to send to the master process [~p] : [Pid = ~p, Next Pid = ~p, Counter value = ~p]~n", [MasterProcess, self(), Successor, Counter]),
      MasterProcess ! {self(), Successor, Counter},
      Successor ! {stop},
      finish
  end.