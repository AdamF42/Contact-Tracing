-module(utenti).
-export([main/0, list_handler/2, check_list/2, visit_place/2, actorDispatcher/0, require_test/2, utente/0, start/0]).
-import(utils, [sleep/1, set_subtract/2, take_random/2, check_service/1, make_probability/1]).

%%%%%%%%%%%%%%%%%%%% PROTOCOLLO DI MANTENIMENTO DELLA TOPOLOGIA (a) %%%%%%%%%%%%%%%%%%%%
main() ->
  PidServer = check_service(server),
  PidServer ! {ciao, da, utente, self()},
  link(PidServer),
  actorDispatcher().

actorDispatcher() ->
  process_flag(trap_exit, true),
  ActorListHandler = spawn_link(?MODULE, list_handler, [self(), []]),
  %io:format("[ActorDispatcher] User ~p ActorListHandler ~p ~n", [self(), ActorListHandler]),
  spawn_link(?MODULE, check_list, [ActorListHandler, self()]),
  %io:format("[ActorDispatcher] User ~p CheckList ~p ~n", [self(), CheckList]),
  ActorVisitPlace = spawn_link(?MODULE, visit_place, [ActorListHandler, self()]),
  %io:format("[ActorDispatcher] User ~p ActorVisitPlace ~p ~n", [self(), ActorVisitPlace]),
  ActorRequireTest = spawn_link(?MODULE, require_test, [self(), make_probability(25)]),
  %io:format("[ActorDispatcher] User ~p ActorRequireTest ~p ~n", [self(), ActorRequireTest]),
  %sleep(1000),
  dispatcher_loop(ActorListHandler, ActorRequireTest, ActorVisitPlace).

dispatcher_loop(ListHandler, RequiredTest, VisitPlace) ->
  receive
    {places, PIDLIST} ->
      ListHandler ! {get_list, self()},
      receive
        {list, L} ->
          R = set_subtract(PIDLIST, L),
          case length(L) of
            0 -> ListHandler ! {update_list, take_random(R, 3)};
            1 -> ListHandler ! {update_list, take_random(R, 2)};
            2 -> ListHandler ! {update_list, take_random(R, 1)};
            _ -> ok
          end
      end;
    {contact, PID} ->
      % check if PID is alive before linking
      case erlang:process_info(PID) == undefined of
        true -> io:format("[Dispatcher] ~p impossibile linkarsi a ~p~n", [self(), PID]);
        false ->
          link(PID),
          io:format("[Dispatcher] ~p linkato a ~p~n", [self(), PID])
      end;
    positive ->
      io:format("[Dispatcher] ~p sono positivo ~n", [self()]),
      exit(positive);
    negative ->
      io:format("[Dispatcher] ~p Sono negativo ~n", [self()]);
    {'EXIT', Sender, R} ->
      handle_exit_messages(R, self(), Sender)
  end,
  dispatcher_loop(ListHandler, RequiredTest, VisitPlace).

%%%%%%%%%%%%%%%%%%%% PROTOCOLLO DI MANTENIMENTO DELLA TOPOLOGIA (b) %%%%%%%%%%%%%%%%%%%%
list_handler(PidDispatcher, L) ->
  receive
    {get_list, Pid} ->
      Pid ! {list, L},
      list_handler(PidDispatcher, L);
    {update_list, L1} ->
      % monitor all places in L1
      [monitor(process, X) || X <- L1],
      list_handler(PidDispatcher, L1 ++ L);
  % messages from a dead place (DOWN)
    {'DOWN', _, process, Pid, _} ->
      global:send(server, {get_places, PidDispatcher}),
      list_handler(PidDispatcher, set_subtract(L, [Pid]))
  end.

handle_exit_messages(R, PidDispatcher, Pid) ->
  case R of
    quarantine ->
      io:format("[Dispatcher] ~p entro in quarantena ~n", [PidDispatcher]),
      exit(quarantine);
    positive ->
      io:format("[Dispatcher] ~p entro in quarantena ~n", [PidDispatcher]),
      exit(quarantine);
    _ ->
      io:format("[Dispatcher] ~p catturato evento: ~p da ~p ~n", [PidDispatcher, R, Pid]),
      exit(R)
  end.

%%%%%%%%%%%%%%%%%%%%% PROTOCOLLO DI MANTENIMENTO DELLA TOPOLOGIA (c, d) %%%%%%%%%%%%%%%%%%%%
check_list(ActorList, PidDispatcher) ->
  ActorList ! {get_list, self()},
  receive
    {list, L} ->
      case length(L) >= 3 of
        true -> ok;
        false ->
          global:send(server, {get_places, PidDispatcher})
      end
  end,
  sleep(10000),
  check_list(ActorList, PidDispatcher).

%%%%%%%%%%%%%%%%%%%%% PROTOCOLLO DI VISITA DEI LUOGHI %%%%%%%%%%%%%%%%%%%%
visit_place(ActorList, PidDispatcher) ->
  ActorList ! {get_list, self()},
  receive
    {list, L} ->
      case length(L) >= 1 of
        true ->
          REF = make_ref(),
          [LUOGO | _] = take_random(L, 1),
          LUOGO ! {begin_visit, PidDispatcher, REF},
          sleep(5000 + rand:uniform(5000)),
          LUOGO ! {end_visit, PidDispatcher, REF};
        false -> ok
      end,
      sleep(3000 + rand:uniform(2000)),
      visit_place(ActorList, PidDispatcher)
  end.

%%%%%%%%%%%%%%%%%%%% PROTOCOLLO DI TEST (a,b) %%%%%%%%%%%%%%%%%%%%
require_test(PidDispatcher, Probability) ->
  sleep(30000),
  case Probability() of
    1 ->
      PidOspedale = check_service(ospedale),
      PidOspedale ! {test_me, PidDispatcher};
    _ -> ok
  end,
  require_test(PidDispatcher, Probability).

utente() ->
  io:format("Io sono l'utente ~p~n", [self()]),
  main().

start() ->
  [spawn(fun utente/0) || _ <- lists:seq(1, 1000)].