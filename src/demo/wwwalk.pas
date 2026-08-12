program wwwalk;
{ Ходилка по выгруженному подземелью.

    wwwalk [--dir csv] [--script "sssdd>"]

  По умолчанию — интерактивный терминальный режим. --script прогоняет
  последовательность клавиш без ввода (нужно для CI) и печатает итоговый
  экран. Сборка с BearLibTerminal:

    fpc -dUSE_BLT -Fusrc/dungeon \
        -Futhird_party/bearlibterminal/Terminal/Include/Pascal \
        src/demo/wwwalk.pas }

{$MODE OBJFPC}{$H+}

uses
  SysUtils, wwCore, wwGrid, wwCsv, wwViewer;

type
  TWwWalkApp = class
  private
    FDir: string;
    FScript: string;
    procedure ParseArgs;
  public
    constructor Create;
    procedure Run;
  end;

constructor TWwWalkApp.Create;
begin
  inherited Create;
  FDir := 'csv';
  FScript := '';
end;

procedure TWwWalkApp.ParseArgs;
var
  i: Integer;
begin
  i := 1;
  while i <= ParamCount do
  begin
    if (ParamStr(i) = '--dir') and (i < ParamCount) then
    begin
      FDir := ParamStr(i + 1);
      Inc(i);
    end
    else if (ParamStr(i) = '--script') and (i < ParamCount) then
    begin
      FScript := ParamStr(i + 1);
      Inc(i);
    end;
    Inc(i);
  end;
end;

procedure TWwWalkApp.Run;
var
  viewer: TWwViewer;
begin
  ParseArgs;
  {$IFDEF USE_BLT}
  viewer := TWwBltViewer.Create(FDir);
  {$ELSE}
  viewer := TWwConsoleViewer.Create(FDir);
  {$ENDIF}
  try
    if FScript <> '' then
      viewer.RunScript(FScript)
    else
      viewer.Run;
  finally
    viewer.Free;
  end;
end;

var
  App: TWwWalkApp;
begin
  App := TWwWalkApp.Create;
  try
    App.Run;
  finally
    App.Free;
  end;
end.
