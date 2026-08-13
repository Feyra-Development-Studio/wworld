program wwwalk;
{ Ходилка по подземелью.

    wwwalk [--json out/dungeon.json] [--geometry scripts/geometry.R]
    wwwalk --dir out/csv
    wwwalk ... --script "sssdd>"

  По умолчанию читается основное хранилище — граф в JSON, и карта строится
  заново геометрией на R (значит, нужен Rscript). С флагом --dir берётся
  тестовая выгрузка CSV: там лежит готовый растр и R не нужен.

  Управление: WASD и QEZC, '>' и '<' на клетке лестницы, Esc — выход.
  --script прогоняет последовательность клавиш без ввода, для CI.

  Сборка с BearLibTerminal:
    fpc -dUSE_BLT -Fusrc/dungeon \
        -Futhird_party/bearlibterminal/Terminal/Include/Pascal \
        src/demo/wwwalk.pas }

{$MODE OBJFPC}{$H+}

uses
  SysUtils, wwCore, wwGrid, wwSource, wwViewer;

type
  TWwWalkApp = class
  private
    FJson, FGeometry, FCsvDir, FScript: string;
    procedure ParseArgs;
    function MakeSource: TWwMapSource;
  public
    constructor Create;
    function Run: Integer;
  end;

constructor TWwWalkApp.Create;
begin
  inherited Create;
  FJson := 'out/dungeon.json';
  FGeometry := 'scripts/geometry.R';
  FCsvDir := '';
  FScript := '';
end;

procedure TWwWalkApp.ParseArgs;
var
  i: Integer;
  a: string;
begin
  i := 1;
  while i <= ParamCount do
  begin
    a := ParamStr(i);
    if (a = '--json') and (i < ParamCount) then
    begin
      FJson := ParamStr(i + 1);
      Inc(i);
    end
    else if (a = '--dir') and (i < ParamCount) then
    begin
      FCsvDir := ParamStr(i + 1);
      Inc(i);
    end
    else if (a = '--geometry') and (i < ParamCount) then
    begin
      FGeometry := ParamStr(i + 1);
      Inc(i);
    end
    else if (a = '--script') and (i < ParamCount) then
    begin
      FScript := ParamStr(i + 1);
      Inc(i);
    end;
    Inc(i);
  end;
end;

function TWwWalkApp.MakeSource: TWwMapSource;
begin
  if FCsvDir <> '' then
    Result := TWwCsvSource.Create(FCsvDir)
  else
    Result := TWwJsonSource.Create(FJson, FGeometry);
end;

function TWwWalkApp.Run: Integer;
var
  source: TWwMapSource;
  viewer: TWwViewer;
begin
  ParseArgs;
  try
    source := MakeSource;
  except
    on E: Exception do
    begin
      Writeln('не удалось открыть подземелье: ', E.Message);
      Result := 2;
      Exit;
    end;
  end;
  Writeln('источник — ', source.Describe);

  {$IFDEF USE_BLT}
  viewer := TWwBltViewer.Create(source);
  {$ELSE}
  viewer := TWwConsoleViewer.Create(source);
  {$ENDIF}
  try
    if FScript <> '' then
      viewer.RunScript(FScript)
    else
      viewer.Run;
  finally
    viewer.Free;
  end;
  Result := 0;
end;

var
  App: TWwWalkApp;
begin
  App := TWwWalkApp.Create;
  try
    ExitCode := App.Run;
  finally
    App.Free;
  end;
end.
