program demo;
{ wworld — генерация подземелья и экспорт в CSV.

  Использование:
    demo [--seed N] [--levels N] [--out DIR] [--dump L]

  Каждый этаж выгружается отдельным листом csv/level_NN.csv.
  Генерация полностью детерминирована: одинаковый seed даёт побайтово
  одинаковые файлы на любой машине (ГПСЧ собственный, RTL Random не
  используется). }

{$MODE OBJFPC}{$H+}

uses
  SysUtils, wwCore, wwGrid, wwStruct, wwGenerator, wwCsv;

type
  TWwApp = class
  private
    FSeed: QWord;
    FLevels: Integer;
    FOutDir: string;
    FDumpLevel: Integer;
    procedure ParseArgs;
    procedure DumpAscii(ALevel: TWwLevel);
  public
    constructor Create;
    function Run: Integer;
  end;

constructor TWwApp.Create;
begin
  inherited Create;
  FSeed := 20260813;
  FLevels := 10;
  FOutDir := 'csv';
  FDumpLevel := 0;
end;

procedure TWwApp.ParseArgs;
var
  i: Integer;
  a: string;
begin
  i := 1;
  while i <= ParamCount do
  begin
    a := ParamStr(i);
    if (a = '--seed') and (i < ParamCount) then
    begin
      FSeed := StrToQWord(ParamStr(i + 1));
      Inc(i);
    end
    else if (a = '--levels') and (i < ParamCount) then
    begin
      FLevels := StrToInt(ParamStr(i + 1));
      Inc(i);
    end
    else if (a = '--out') and (i < ParamCount) then
    begin
      FOutDir := ParamStr(i + 1);
      Inc(i);
    end
    else if (a = '--dump') and (i < ParamCount) then
    begin
      FDumpLevel := StrToInt(ParamStr(i + 1));
      Inc(i);
    end;
    Inc(i);
  end;
end;

procedure TWwApp.DumpAscii(ALevel: TWwLevel);
var
  x, y: Integer;
  row: string;
begin
  for y := 0 to ALevel.Grid.H - 1 do
  begin
    row := '';
    for x := 0 to ALevel.Grid.W - 1 do
      case ALevel.Grid.CodeAt(x, y) of
        WW_ROCK: row := row + ' ';
        WW_WALL: row := row + '#';
        WW_ROOM: row := row + '.';
        WW_COR_MINOR: row := row + ':';
        WW_COR_SECOND: row := row + '=';
        WW_COR_MAIN: row := row + '%';
        WW_JUNCTION: row := row + '+';
        WW_FORK: row := row + '*';
        WW_STAIR_UP: row := row + '<';
        WW_STAIR_DOWN: row := row + '>';
      end;
    Writeln(row);
  end;
end;

function TWwApp.Run: Integer;
var
  gen: TWwGenerator;
  writer: TWwCsvWriter;
  lv: TWwLevel;
  i, failed: Integer;
begin
  ParseArgs;
  Writeln('wworld dungeon generator | seed=', FSeed, ' levels=', FLevels, ' out=', FOutDir);
  gen := TWwGenerator.Create;
  writer := TWwCsvWriter.Create(FOutDir);
  failed := 0;
  try
    for i := 1 to FLevels do
    begin
      lv := gen.Generate(i, FSeed);
      Writeln(gen.Report);
      if lv = nil then
      begin
        Inc(failed);
        Continue;
      end;
      writer.AddLevel(lv);
      if i = FDumpLevel then DumpAscii(lv);
      lv.Free;
    end;
    writer.Flush;
  finally
    writer.Free;
    gen.Free;
  end;
  if failed > 0 then
  begin
    Writeln('FAILED levels: ', failed);
    Result := 1;
  end
  else
  begin
    Writeln('ok: ', FLevels, ' levels written to ', FOutDir);
    Result := 0;
  end;
end;

var
  App: TWwApp;
begin
  App := TWwApp.Create;
  try
    ExitCode := App.Run;
  finally
    App.Free;
  end;
end.
