%%%-------------------------------------------------------------------
%%% @author peguy
%%% @copyright (C) 2020, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 03. Feb 2020 17:27
%%%-------------------------------------------------------------------
-module(ring_mutex).
-author("peguy").

%% API
%% API
-export([start/3, starting_process/7, running_processes/6, mutex_acquire/1, mutex_release/1, mutex_loop/0]).

start(NbProcesses, NbMessages, Message) ->
  MasterProcess = self(),
  case (NbProcesses > 0) and (NbMessages >= 0) of
    true ->
      Mutex = spawn(ring_mutex, mutex_loop, []),
      StartProcess = spawn(ring_mutex, starting_process, [MasterProcess, undef, Mutex, NbMessages, NbProcesses - 1, undef, Message]),
      StartProcess ! {created};

    false->
      io:format("Big ERROR coming from the master process : arguments values(~w, ~w) not allowed~n", [NbMessages, NbProcesses])
  end,

  receive
    {Pid, stop_simul} ->
      io:format("Master process [~p] has just received from the first process [~p] the message '~w'~n", [self(), Pid, stop_simul]),
      done
  end.

% This function lock a mutex and works as follows:
% The mutex is locked when the calling process is the owner.
% Otherwise, If the mutex is already blocked and owned by another process,
% the calling process will be block until the mutex becomes available
mutex_acquire(Mutex) ->
  % Simulate the random access to enter the critical section
  RandNum = rand:uniform(3),
  % 1 chance out of 3 to request access
  case RandNum == 1 of
    true ->
      Mutex ! {need_lock, self()},
      receive
        {accessGranted} -> true
      end;
    false -> false
  end.

mutex_release(Mutex) ->
  Mutex ! {release_lock}.

% The main loop for the Mutex
mutex_loop() ->
  receive
  %---------------------------------------------
  % Keeps waiting until you received a request.
  % Once it receives a request from a given PID P,
  % grants access to p so that it can enter a CS
  % and waits for P to release the lock
  % (So that other process can enter the CS)
  %-------------------------------------------
    {need_lock, PidRequesting} ->
      io:format("Process [~p] requests access to the critical section~n", [PidRequesting]),
      PidRequesting ! {accessGranted},
      receive
        {release_lock} -> mutex_loop()
      end
  end.

starting_process(MasterProcess, Successor, Mutex, NbMessages, NbProcesses, _, Message) ->
  %-------------------------------------------------------------------------------
  % This is the very first spawned process which acts like a central process.
  % This process will send its pid through the ring
  % so that the last process know which is its next/successor process.
  %-------------------------------------------------------------------------------
  receive

    {created} ->
      self() ! {start_deployment},
      starting_process(MasterProcess, undefined, Mutex, NbMessages, NbProcesses, undefined, Message);

    {start_deployment} ->
      Next = spawn(ring_mutex, running_processes, [MasterProcess, self(), undefined, undefined, Mutex, NbProcesses - 1]),
      Next ! {keep_deploying},  % send a message to the next process my own pid and an atom.
      starting_process(MasterProcess, Next, Mutex, NbMessages, NbProcesses, undef, Message);

  %------------------------------------------------------------------------------------------
  %  When receiving a message "Successful deployment" from the very last process,
  %  this process sends an atom to itself, to start sending tokens/messages around the ring.
  %------------------------------------------------------------------------------------------
    {send_tokens} ->
      NewCounter = 0,
      self() ! {NewCounter, Message},
      starting_process(MasterProcess, Successor, Mutex, NbMessages, NbProcesses, NewCounter, Message);

    {NewCounter, Message} when NbMessages > 0 ->
      case mutex_acquire(Mutex) of
        true ->
          io:format("Process [~p] enters in the CS...~n", [self()]),
          timer:sleep(rand:uniform(20)), % simulate work in critical section
          mutex_release(Mutex),
          io:format("Process [~p] exits the CS...~n", [self()]);
        false ->
          io:format("Process [~p] could not get the lock to enter in the CS...~n", [self()])
      end,
      Successor ! {NewCounter + 1, Message},
      starting_process(MasterProcess, Successor, Mutex, NbMessages - 1, NbProcesses, NewCounter, Message);

  %----------------------------------------------------------------------------------------------------------
  % Send to the next process that there aren't any messages left to broadcast.
  % And then the first/starting process terminate itself when it receives a message from the last process!
  %----------------------------------------------------------------------------------------------------------
    {NewCounter, Message} when NbMessages =< 0 ->
      io:format("Process [~p] quits.~n", [self()]),
      Successor ! {stop},
      starting_process(MasterProcess, Successor, Mutex, NbMessages, NbProcesses, NewCounter, Message);

    {stop} ->
      MasterProcess ! {self(), stop_simul},
      finish
  end.


% We need to keep track of the first process (i.e., the central process PID) so that it does not keep running infinitely
running_processes(MasterProcess, StartProcess, Successor, Counter, Mutex, NbProcesses) ->

  receive
  % ---------------------
  % Phase 1: Deployment
  % ---------------------
    {keep_deploying} when NbProcesses > 0 ->
      Next = spawn(ring_mutex, running_processes, [MasterProcess, StartProcess, undefined, undefined, Mutex, NbProcesses - 1]),
      Next ! {keep_deploying},
      running_processes(MasterProcess, StartProcess, Next, undefined, Mutex, NbProcesses);

    {keep_deploying} when NbProcesses =:= 0 ->
      StartProcess ! {send_tokens},
      running_processes(MasterProcess, StartProcess, StartProcess, undefined, Mutex, NbProcesses);  % As it is the last process, its successor process is the starting process

  % -----------------------
  % Phase 2: Token activity
  % -----------------------
    {NewCounter, Message} ->
      case mutex_acquire(Mutex) of
        true ->
          io:format("Process [~p] enters in the CS...~n", [self()]),
          timer:sleep(rand:uniform(10)), % simulate work in critical section
          mutex_release(Mutex),
          io:format("Process [~p] exits the CS...~n", [self()]);
        false ->
          io:format("Process [~p] could not get the lock to enter in the CS...~n", [self()])
      end,
      Successor ! {NewCounter + 1, Message},
      running_processes(MasterProcess, StartProcess, Successor, NewCounter, Mutex, NbProcesses);

  % ---------------------
  % Phase 3: Termination
  % ---------------------
    {stop} ->
      io:format("Process [~p] quits.~n", [self()]),
      Successor ! {stop},
      finish
  end.
