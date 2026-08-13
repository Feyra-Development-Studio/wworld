program demo;
{ wworld — генерация подземелья.

    demo [--seed N] [--levels N] [--out DIR] [--test] [--dump L] [--geometry PATH]

  По умолчанию пишется основное хранилище — DIR/dungeon.json: граф-инструкция
  подземелья (seed, спецификации форм комнат, осевые линии коридоров, узлы,
  связи, лестницы). Растр в нём не хранится: он выводим, его строит геометрия
  на R.

  С флагом --test дополнительно кладётся человекочитаемая выгрузка DIR/csv/
  (каждый этаж отдельным листом) и выполняется сверка обратной сборки: карта
  восстанавливается из записанного JSON и сравнивается с исходной клетка в
  клетку. Расхождение означает, что графа для восстановления не хватает, и
  прогон завершается с кодом 3. }

{$MODE OBJFPC}{$H+}

uses
  SysUtils, Classes, wwCore, wwGrid, wwStruct, wwGenerator, wwCsv, wwJson,
  wwRGeom, wwRebuild;

type
  TWwApp = class
  private
    FSeed: QWord;
    FLevels: Integer;
    FOutDir: string;
    FDumpLevel: Integer;
    FGeometry: string;
    FTest: Boolean;
    FFingerprints: TStringList;
    procedure ParseArgs;
    procedure DumpAscii(ALevel: TWwLevel);
    function JsonPath: string;
    function CsvDir: string;
    function VerifyRoundtrip(AGeom: TWwGeometryClient): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function Run: Integer;
  end;

constructor TWwApp.Create;
begin
  inherited Create;
  FSeed := 20260813;
  FLevels := 10;
  FOutDir := 'out';
  FDumpLevel := 0;
  FGeometry := 'scripts/geometry.R';
  FTest := False;
  FFingerprints := TStringList.Create;
end;

destructor TWwApp.Destroy;
begin
  FFingerprints.Free;
  inherited Destroy;
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
    else if (a = '--geometry') and (i < ParamCount) then
    begin
      FGeometry := ParamStr(i + 1);
      Inc(i);
    end
    else if (a = '--dump') and (i < ParamCount) then
    begin
      FDumpLevel := StrToInt(ParamStr(i + 1));
      Inc(i);
    end
    else if a = '--test' then
      FTest := True;
    Inc(i);
  end;
end;

function TWwApp.JsonPath: string;
begin
  Result := IncludeTrailingPathDelimiter(FOutDir) + 'dungeon.json';
end;

function TWwApp.CsvDir: string;
begin
  Result := IncludeTrailingPathDelimiter(FOutDir) + 'csv';
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

{ Сверка обратной сборки: JSON перечитывается с диска, карта строится заново
  и сравнивается с исходной. }
function TWwApp.VerifyRoundtrip(AGeom: TWwGeometryClient): Boolean;
var
  reader: TWwJsonReader;
  rebuilder: TWwRebuilder;
  lv: TWwLevel;
  i, bad, total: Integer;
begin
  bad := 0;
  total := 0;
  reader := TWwJsonReader.Create(JsonPath);
  rebuilder := TWwRebuilder.Create(AGeom);
  try
    total := reader.LevelCount;
    for i := 0 to total - 1 do
    begin
      lv := reader.LevelAt(i);
      try
        rebuilder.Rebuild(lv);
        if lv.Grid.AsText <> FFingerprints[i] then
        begin
          Writeln(Format('  этаж %d: восстановленная карта не совпала с исходной',
            [lv.Number]));
          Inc(bad);
        end;
      finally
        lv.Free;
      end;
    end;
  finally
    rebuilder.Free;
    reader.Free;
  end;
  if bad = 0 then
    Writeln(Format('обратная сборка из JSON: %d этажей совпали клетка в клетку',
      [total]));
  Result := bad = 0;
end;

function TWwApp.Run: Integer;
var
  gen: TWwGenerator;
  json: TWwJsonWriter;
  csv: TWwCsvWriter;
  lv: TWwLevel;
  i, failed: Integer;
begin
  ParseArgs;
  Writeln('wworld dungeon generator | seed=', FSeed, ' levels=', FLevels,
          ' out=', FOutDir, BoolToStr(FTest, ' [test]', ''));
  try
    gen := TWwGenerator.Create(FGeometry);
  except
    on E: Exception do
    begin
      Writeln('геометрия на R недоступна: ', E.Message);
      Writeln('нужен Rscript в PATH и файл ', FGeometry);
      Result := 2;
      Exit;
    end;
  end;

  json := TWwJsonWriter.Create(JsonPath, FSeed);
  csv := nil;
  if FTest then csv := TWwCsvWriter.Create(CsvDir);
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
      json.AddLevel(lv);
      if FTest then
      begin
        csv.AddLevel(lv);
        FFingerprints.Add(lv.Grid.AsText);
      end;
      if i = FDumpLevel then DumpAscii(lv);
      lv.Free;
    end;
    json.Flush;
    if FTest then csv.Flush;
  finally
    if csv <> nil then csv.Free;
    json.Free;
  end;

  Result := 0;
  if failed > 0 then
  begin
    Writeln('не сгенерировано этажей: ', failed);
    Result := 1;
  end
  else
  begin
    Writeln('записан граф: ', JsonPath);
    if FTest then
    begin
      Writeln('тестовая выгрузка: ', CsvDir);
      if not VerifyRoundtrip(gen.Geometry) then Result := 3;
    end;
  end;
  Writeln(Format('геометрия на R: запросов %d, из кеша %d',
    [gen.Geometry.Calls, gen.Geometry.CacheHits]));
  gen.Free;
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
