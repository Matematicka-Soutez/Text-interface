program Exceptions;

{$codepage utf8}

uses
  Crt,
  Classes,
  SysUtils,
  HTTPDefs,
  fpHTTP,
  fpWeb,
  fphttpclient,
  fpjson,
  jsonparser,
  httpprotocol;

type
  PHistoryRecord = ^THistoryRecord;

  THistoryRecord = record
    Input, Output: string;
    Next: PHistoryRecord;
  end;

  TResponse = record
    StatusCode: integer;
    Body: TJSONData;
  end;

  TActionResult = record
    Team: TJSONData;
    Result: string;
  end;

  TTeamInputHistory = record
    Team: TJSONData;
    History: PHistoryRecord;
  end;


var
  GameCode, OrgKey: string;
  Teams: TJSONArray;
  IsAuthenticated: boolean;

  function QueryAPI(Method, Path: string; State: integer): TResponse;

  var
    HTTP: TFPHTTPClient;
    SS: TStringStream;

  begin
    try
      try
        HTTP := TFPHttpClient.Create(nil);
        SS := TStringStream.Create('');

        HTTP.AddHeader('Authorization', 'JWT ' + OrgKey);
        HTTP.AddHeader('Content-Type', 'application/json');
        if State <> 0 then
          HTTP.RequestBody := TStringStream.Create('{"state":' + IntToStr(State) + '}');

        HTTP.HTTPMethod(Method, 'https://game-mock.herokuapp.com/games/' +
          GameCode + Path, SS, [200, 201, 400, 401, 404, 500, 505]);

        //HTTP.RequestHeaders[3]

        Result.StatusCode := HTTP.ResponseStatusCode;
        Result.Body := GetJSON(SS.Datastring);
      except
        on E: Exception do
          //     WriteLn(E.Message);
      end;
    finally
      SS.Free;
      HTTP.Free;
    end;
  end;

  function AuthenticationCheck(): boolean;

  var
    Response: TResponse;

  begin
    Write('Enter gamecode: ');
    Readln(GameCode);
    GameCode := 'bgi63c';

    Write('Enter organizer key: ');
    Readln(OrgKey);
    OrgKey := 'bti34tbri8t34rtdbiq34tvdri6qb3t4vrdtiu4qv';

    Response := QueryAPI('GET', '/teams', 0);
    case Response.StatusCode of
      200:
      begin
        WriteLn('Success');
        Teams := TJSONArray(Response.Body);
        Result := True;
      end;
      401:
      begin
        WriteLn('Špatný klíč organizátora');
        Result := False;
      end;
      404:
      begin
        WriteLn('Špatný kód hry');
        Result := False;
      end;
      else
      begin
        WriteLn('Chyba serveru - můžete začít panikařit');
        Result := False;
      end;
    end;

  end;

  procedure PrintMoves(Moves: TJSONData);
  var
    Move: TJSONData;
    i: integer;
  begin
    WriteLn('Možné pohyby:');
    for i := 0 to Moves.Count - 1 do
    begin
      Move := Moves.FindPath('[' + i.ToString() + ']');
      WriteLn('    ' + IntToStr(Move.FindPath('id').AsQWord) + ') ' +
        Move.FindPath('name').AsString);
    end;

  end;

  procedure PrintTeam(Team: TJSONData);
  var
    Number, StateRecord, Name: string;
  begin
    Number := IntToStr(Team.FindPath('number').AsQWord);
    Name := Team.FindPath('name').AsString;
    StateRecord := Team.FindPath('stateRecord').AsString;
    WriteLn(Number + '. ' + Name);
    TextBackground(lightGreen);
    TextColor(White);
    WriteLn(' ' + StateRecord + ' ');
    TextBackground(Black);
    TextColor(White);
    PrintMoves(Team.FindPath('possibleMoves'));
  end;

  function ReverseMove(Team: TJSONData): TActionResult;
  var
    Id: string;
    Response: TResponse;
  begin
    Id := Team.FindPath('id').AsString;
    Response := QueryAPI('DELETE', '/teams/' + Id + '/state', 0);
    if Response.StatusCode <> 200 then
    begin
      Result.Result := 'POZOR!: Vrácení pohybu se nezdařilo.';
      Result.Team := Team;
    end
    else
    begin
      Result.Result := 'Success';
      Result.Team := Response.Body;
    end;
  end;

  procedure CheckMoveId(Team: TJSONData; MoveId: integer);
  var
    Moves: TJSONData;
    Possible: boolean;
    i: integer;
  begin
    Possible := False;
    Moves := Team.FindPath('possibleMoves');
    for i := 0 to Moves.Count - 1 do
    begin
      if Moves.FindPath('[' + i.ToString() + '].id').AsInteger = MoveId then
        Possible := True;
    end;
    if not Possible then
      raise EConvertError.Create('POZOR!: Neplatné číslo pohybu');
  end;

  function MoveTeam(Team: TJSONData; Move: string): TActionResult;
  var
    Number: string;
    Response: TResponse;
    MoveId: integer;
  begin
    Number := Team.FindPath('id').AsString;
    try
      MoveId := StrToInt(Move);
      CheckMoveId(Team, MoveId);
      Response := QueryAPI('POST', '/teams/' + Number + '/state', MoveId);
      if Response.StatusCode <> 200 then
      begin
        Result.Result := 'POZOR!: Zadání pohybu se nezdařilo.';
        Result.Team := Team;
      end
      else
      begin
        Result.Result := 'Success';
        Result.Team := Response.Body;
      end;
    except
      on E: EConvertError do
      begin
        Result.Result := 'POZOR!: Neplatné číslo pohybu';
        Result.Team := Team;
      end;
    end;

  end;

  function TeamNumberTranslate(TeamNumber: integer): integer;
  var
    Team: TJSONData;
    i: integer;
  begin
    Result := 0;
    for i := 0 to Teams.Count - 1 do
    begin
      Team := Teams.FindPath('[' + i.ToString() + ']');
      if Team.FindPath('number').AsInteger = TeamNumber then
      begin
        Result := Team.FindPath('id').AsInteger;
        Exit;
      end;
    end;
  end;

  procedure AppendHistoryRecord(var InputHistory: TTeamInputHistory;
    Action: string; ActionResult: TActionResult);
  var
    HistoryRecord, Current: PHistoryRecord;
  begin
    new(HistoryRecord);
    HistoryRecord^.Input := Action;
    HistoryRecord^.Output := ActionResult.Result;
    HistoryRecord^.Next := nil;
    if InputHistory.History = nil then
      InputHistory.History := HistoryRecord
    else
    begin
      Current := InputHistory.History;
      while Current^.Next <> nil do
      begin
        Current := Current^.Next;
      end;
      Current^.Next := HistoryRecord;
    end;
  end;

  procedure PrintInputHistory(HistoryRecord: PHistoryRecord);
  var
    Current: PHistoryRecord;
  begin
    Current := HistoryRecord;
    while Current <> nil do
    begin
      WriteLn('Zadej číslo pohybu: ' + Current^.Input);
      WriteLn(Current^.Output);
      Current := Current^.Next;
    end;
  end;

  procedure RedrawScreen(TeamInputHistory: TTeamInputHistory);
  begin
    clrscr;
    WriteLn('Zadej číslo týmu: ' + TeamInputHistory.Team.FindPath('number').AsString);
    PrintTeam(TeamInputHistory.Team);
    PrintInputHistory(TeamInputHistory.History);
  end;

  procedure ManageMoveInput(Team: TJSONData);
  var
    MoveInput: string;
    InputHistory: TTeamInputHistory;
    ActionResult: TActionResult;
  begin
    InputHistory.Team := Team;
    while True do
    begin
      Write('Zadej číslo pohybu: ');
      ReadLn(MoveInput);
      MoveInput := Upcase(Trim(MoveInput));
      case MoveInput of
        '':
          Exit;
        'R':
        begin
          ActionResult := ReverseMove(Team);
        end
        else
          ActionResult := MoveTeam(Team, MoveInput);
      end;
      InputHistory.Team := ActionResult.Team;
      AppendHistoryRecord(InputHistory, MoveInput, ActionResult);
      RedrawScreen(InputHistory);
    end;
  end;

  procedure ManageInput;
  var
    TeamNumber: integer;
    TeamResponse: TResponse;
  begin
    while True do
    begin
      clrscr;
      Write('Zadej číslo týmu: ');
      Readln(TeamNumber);

      TeamResponse := QueryAPI('GET', '/teams/' +
        IntToStr(TeamNumberTranslate(TeamNumber)), 0);
      if TeamResponse.StatusCode <> 200 then
      begin
        WriteLn('POZOR!: Neznámý tým');
        Continue;
      end;
      PrintTeam(TeamResponse.Body);
      ManageMoveInput(TeamResponse.Body);
    end;
  end;

begin
  IsAuthenticated := False;
  while not IsAuthenticated do
    IsAuthenticated := AuthenticationCheck();

  ManageInput();

  Readln;
  Readln;
end.
